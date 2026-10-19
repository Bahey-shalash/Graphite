#!/usr/bin/env python3
"""Reference reader for Notability notes (.note, session format 9), as described in Docs/Notability-format.md.

Reads a note straight from its ZIP archive, with the standard library only, and prints what it found: the paper and
page geometry, the curves, shapes, pictures, typed text, imported PDF pages and recordings with their stroke timing,
and every archive class or key this reader does not know. It exists to check the format description against more notes and newer Notability versions, and to give the
Swift parsers (import checklist, phase 2) expected values to test against. It is not Graphite's importer.

Every size read from the file is checked before it is used, so a damaged or hostile archive fails with an error
message instead of exhausting memory.

Usage:
  python3 scripts/notability-reader.py NOTE.note               summary and unknown keys
  python3 scripts/notability-reader.py NOTE.note --page 2      the curves, shapes and pictures on that page as JSON
  python3 scripts/notability-reader.py NOTE.note --text        the typed text and its runs as JSON
  python3 scripts/notability-reader.py NOTE.note --recordings  the recordings and the timing of each curve as JSON
"""
import argparse
import array
import json
import plistlib
import re
import sys
import xml.parsers.expat
import zipfile

SUPPORTED_SESSION_FORMAT = 9
MAXIMUM_ENTRY_BYTES = 512 * 1024 * 1024
MAXIMUM_OBJECT_DEPTH = 64
PEN_STYLE = 3
HIGHLIGHTER_STYLE = 4
UUID_BYTES = 16
# Page size in PDF points of Notability's own PDF export, per paperSize. Letter is "Letter (Optimized)", 16:21; the
# A4 size was seen only for a note made from an imported A4 PDF. Other sizes are reported as unknown.
EXPORT_PAGE_POINTS = {"letter": (612.0, 803.25), "a4": (595.2756, 842.7541)}
# Every export seen draws the document's x = 0 this far from the page's left edge.
EXPORT_LEFT_INSET_POINTS = 15.9375

KNOWN_SESSION_KEYS = {
    "$cls", "name", "packagePath", "subject", "tags", "creationDate", "isReadOnly", "sessionFormatVersion",
    "richText", "contentPlaybackEventManager", "NBNoteTakingSessionDocumentPaperLayoutModelKey",
    "NBNoteTakingSessionIsHighlighterBehindTextKey", "NBNoteTakingSessionHandwritingLanguageKey",
    "NBNoteTakingSessionMinorVersionNumberKey", "NBNoteTakingSessionLastUsedFontKey",
    "kNBNoteTakingSessionNoteLinkStoreKey", "NBPaperMinorVersionNumber", "NBPaperMajorVersionNumber",
    "NBNoteTakingSessionAllowHighlighterConversionKey", "NBNoteTakingSessionBundleVersionNumberKey",
}
KNOWN_RICH_TEXT_KEYS = {
    "$cls", "formatVersion", "formattedStringTextAlignmentKey", "attributedString", "NBAttributedBackingString",
    "Handwriting Overlay", "reflowState", "didBecomeReflowable", "pdfFiles", "mediaObjects",
    "recordingTimestampString", "pageLayoutArray",
}
KNOWN_PICTURE_KEYS = {
    "$cls", "UUID", "assetsIdKey", "captionFieldText", "captionFontColor", "captionFontColorCrossPlatform",
    "captionFontName", "captionFontSize", "captionIsUnderlined", "cornerMode", "documentContentOrigin",
    "documentOrigin", "figure", "handwritingZIndecesKey", "indexable", "isCaptionEnabled", "isFlippedHorizontal",
    "isFlippedVertical", "locked", "maxDimension", "minDimension", "rotationDegrees", "textWrapMode",
    "unscaledContentSize", "zIndex",
}
KNOWN_TEXT_ATTRIBUTE_KEYS = {"NSStrikethrough", "NSUnderline", "line-spacing", "NSBaselineOffset", "checklist-checked"}
KNOWN_SHAPE_KEYS = {"appearance", "startPt", "endPt", "controlPoint1", "rect", "uuid", "options"}
KNOWN_PAGE_LAYOUT_KEYS = {
    "kPageLayoutPDFIsOriginalPageKey", "kPageLayoutPDFPageNumberKey", "kPageLayoutPageIsBookmarkedKey",
    "kPageLayoutPDFFileNameKey", "kPageLayoutDocumentPageNumberKey", "kPageLayoutPDFFileKey",
}
KNOWN_INK_KEYS = {
    "$cls", "numcurves", "numpoints", "numfractionalwidths", "curvesnumpoints", "curvespoints", "curveswidth",
    "curvescolors", "curvesstyles", "curveUUIDs", "options", "curvesfractionalwidths", "curvesforces",
    "curvesaltitudeangles", "curvesazimuthunitvector", "groupsArrays", "bezierPathsDataDictionary", "shapes",
}
CONTAINER_CLASSES = {
    "NSArray": "list", "NSMutableArray": "list", "NSSet": "list", "NSMutableSet": "list", "NSOrderedSet": "list",
    "NSDictionary": "dictionary", "NSMutableDictionary": "dictionary",
}


class FormatError(Exception):
    """The file does not match the format this reader knows."""


def parse_property_list(property_list_bytes, name):
    """A binary or XML property list; a damaged one is a FormatError naming the file."""
    try:
        return plistlib.loads(property_list_bytes)
    except (plistlib.InvalidFileException, xml.parsers.expat.ExpatError, LookupError, ValueError) as error:
        raise FormatError(f"{name} is not a readable property list ({error})") from None


class KeyedArchive:
    """Resolves an NSKeyedArchiver (or GLKeyedArchiver) object graph into plain values, cycles cut."""

    def __init__(self, archive_bytes):
        archive = parse_property_list(archive_bytes, "keyed archive")
        if not isinstance(archive, dict) or archive.get("$archiver") not in ("NSKeyedArchiver", "GLKeyedArchiver"):
            raise FormatError("not a keyed archive")
        self.objects, self.top = archive["$objects"], archive["$top"]

    def class_name(self, archived_object):
        class_reference = archived_object.get("$class")
        if not isinstance(class_reference, plistlib.UID) or class_reference.data >= len(self.objects):
            raise FormatError("object without a valid class")
        return self.objects[class_reference.data].get("$classname", "")

    def resolve_root(self):
        """Notability's session archive names its root '$0'; NSKeyedArchiver's default is 'root'."""
        if "$0" not in self.top and "root" not in self.top:
            raise FormatError("archive has no root object")
        return self.resolve(self.top.get("$0", self.top.get("root")))

    def resolve(self, reference, visiting=frozenset(), depth=0):
        if depth > MAXIMUM_OBJECT_DEPTH:
            raise FormatError("object graph nested too deeply")
        if isinstance(reference, plistlib.UID):
            if reference.data >= len(self.objects):
                raise FormatError("reference past the end of the object table")
            if reference.data in visiting:
                return {"$cycle": reference.data}
            visiting = visiting | {reference.data}
            archived_object = self.objects[reference.data]
        else:
            archived_object = reference
        if archived_object == "$null":
            return None
        if not isinstance(archived_object, dict):
            return archived_object
        class_name = self.class_name(archived_object)

        def resolve_child(child):
            return self.resolve(child, visiting, depth + 1)

        container = CONTAINER_CLASSES.get(class_name)
        if container == "list":
            return [resolve_child(member) for member in archived_object.get("NS.objects", [])]
        if container == "dictionary":
            return {resolve_child(key): resolve_child(member)
                    for key, member in zip(archived_object.get("NS.keys", []), archived_object.get("NS.objects", []))}
        if class_name in ("NSString", "NSMutableString"):
            return archived_object.get("NS.string") or archived_object.get("NS.bytes", b"").decode("utf-8")
        if class_name in ("NSData", "NSMutableData"):
            return archived_object["NS.data"]
        if class_name == "NSDate":
            return {"seconds_since_2001": archived_object["NS.time"]}
        if class_name == "NSUUID":
            return archived_object["NS.uuidbytes"].hex()
        resolved = {"$cls": class_name}
        for key, member in archived_object.items():
            if key != "$class":
                resolved[key] = resolve_child(member)
        return resolved


def numbers_from_string(geometry_string):
    """'{{0, 0}, {520, 304}}' or '{-13.6, 1815.0}' -> its numbers."""
    return [float(number) for number in re.findall(r"-?\d+(?:\.\d+)?(?:e-?\d+)?", geometry_string or "")]


def packed(buffer, type_code, expected_count, name):
    values = array.array(type_code)
    if len(buffer) != expected_count * values.itemsize:
        raise FormatError(f"{name}: {len(buffer)} bytes, expected {expected_count} values of {values.itemsize} bytes")
    values.frombytes(buffer)
    if sys.byteorder != "little":
        values.byteswap()
    return values


class NotabilityNote:
    def __init__(self, note_path):
        self.archive = zipfile.ZipFile(note_path)
        self.unknown = {}
        folders = {name.split("/", 1)[0] for name in self.archive.namelist() if "/" in name}
        if len(folders) != 1:
            raise FormatError("expected one top-level folder")
        self.folder = folders.pop()
        self.session = KeyedArchive(self.entry("Session.plist")).resolve_root()
        self.check_keys("session keys", self.session, KNOWN_SESSION_KEYS)
        if self.session.get("sessionFormatVersion") != SUPPORTED_SESSION_FORMAT:
            self.note_unknown("session format", self.session.get("sessionFormatVersion"))
        rich_text = self.session["richText"]
        self.check_keys("rich text keys", rich_text, KNOWN_RICH_TEXT_KEYS)
        self.paper = self.session["NBNoteTakingSessionDocumentPaperLayoutModelKey"]["documentPaperAttributes"]
        self.page_width = self.read_page_width(rich_text["reflowState"])
        ink = rich_text["Handwriting Overlay"]["SpatialHash"]
        self.check_keys("ink keys", ink, KNOWN_INK_KEYS)
        self.curves = self.read_curves(ink)
        self.shapes = self.read_shapes(ink.get("shapes"))
        self.pictures = [self.read_picture(media) for media in rich_text["mediaObjects"]]
        self.typed_text = self.read_text(rich_text["attributedString"])
        self.pdf_pages = [self.read_pdf_page(layout) for layout in rich_text.get("pageLayoutArray") or []]
        self.recordings = self.read_recordings()
        self.playback_events = self.read_playback_events(self.session["contentPlaybackEventManager"])

    def entry(self, name):
        path = f"{self.folder}/{name}"
        try:
            information = self.archive.getinfo(path)
        except KeyError:
            raise FormatError(f"{path} is missing") from None
        if information.file_size > MAXIMUM_ENTRY_BYTES:
            raise FormatError(f"{path} is larger than {MAXIMUM_ENTRY_BYTES} bytes")
        return self.archive.read(information)

    def note_unknown(self, where, what):
        self.unknown.setdefault(where, set()).add(what)

    def check_keys(self, where, archived_object, known_keys):
        for key in set(archived_object) - known_keys:
            self.note_unknown(where, key)

    def read_page_width(self, reflow_state):
        """Width of a page in document units: stored for a locked layout, absent for a reflowable one."""
        if "pageWidthInDocumentCoordsKey" in reflow_state:
            return float(reflow_state["pageWidthInDocumentCoordsKey"])
        locked = re.fullmatch(r"lockedWidth:([\d.]+):.*", self.paper.get("paperSizingBehavior") or "")
        if locked:
            return float(locked.group(1))
        if reflow_state.get("$cls") != "NBReflowStateReflowable":
            self.note_unknown("reflow states", reflow_state.get("$cls"))
        return None

    def read_curves(self, ink):
        curve_count, point_count, knot_count = ink["numcurves"], ink["numpoints"], ink["numfractionalwidths"]
        points_per_curve = packed(ink["curvesnumpoints"], "I", curve_count, "curvesnumpoints")
        if sum(points_per_curve) != point_count:
            raise FormatError("curvesnumpoints does not add up to numpoints")
        if any(count % 3 != 1 for count in points_per_curve):
            raise FormatError("a curve's point count is not 3k + 1")
        if sum((count - 1) // 3 + 1 for count in points_per_curve) != knot_count:
            raise FormatError("knot count does not match numfractionalwidths")
        coordinates = packed(ink["curvespoints"], "f", 2 * point_count, "curvespoints")
        widths = packed(ink["curveswidth"], "f", curve_count, "curveswidth")
        colors = packed(ink["curvescolors"], "B", 4 * curve_count, "curvescolors")
        styles = packed(ink["curvesstyles"], "B", curve_count, "curvesstyles")
        width_factors = packed(ink["curvesfractionalwidths"], "f", knot_count, "curvesfractionalwidths")
        forces = packed(ink["curvesforces"], "f", knot_count, "curvesforces")
        uuids = packed(ink["curveUUIDs"], "B", UUID_BYTES * curve_count, "curveUUIDs")
        curves, point_index, knot_index = [], 0, 0
        for curve_index in range(curve_count):
            count = points_per_curve[curve_index]
            knots = (count - 1) // 3 + 1
            style = styles[curve_index]
            if style not in (PEN_STYLE, HIGHLIGHTER_STYLE):
                self.note_unknown("curve styles", style)
            curves.append({
                "points": [(coordinates[2 * index], coordinates[2 * index + 1]) for index in range(point_index, point_index + count)],
                "width": widths[curve_index], "color": tuple(colors[4 * curve_index:4 * curve_index + 4]),
                "is_highlighter": style == HIGHLIGHTER_STYLE,
                "width_factors": list(width_factors[knot_index:knot_index + knots]),
                "forces": list(forces[knot_index:knot_index + knots]),
                "uuid": bytes(uuids[UUID_BYTES * curve_index:UUID_BYTES * (curve_index + 1)]).hex(),
            })
            point_index += count
            knot_index += knots
        return curves

    def read_shapes(self, shapes_plist):
        if not shapes_plist:
            return []
        shapes = parse_property_list(shapes_plist, "shapes")
        if not isinstance(shapes, dict):
            raise FormatError("shapes is not a dictionary")
        shape_list, kinds, indices = shapes.get("shapes", []), shapes.get("kinds", []), shapes.get("indices", [])
        if not len(shape_list) == len(kinds) == len(indices):
            raise FormatError("shape arrays differ in length")
        for kind in set(kinds) - {"line"}:
            self.note_unknown("shape kinds", kind)
        for shape in shape_list:
            self.check_keys("shape keys", shape, KNOWN_SHAPE_KEYS)
        return [{"kind": kind, "drawn_before_curve": index, "start": shape.get("startPt"), "end": shape.get("endPt"),
                 "quadratic_control_point": shape.get("controlPoint1"),
                 "width": shape["appearance"].get("strokeWidth"), "color": shape["appearance"]["strokeColor"]["rgba"],
                 "is_dashed": "dashStyle" in shape["appearance"]}
                for shape, kind, index in zip(shape_list, kinds, indices)]

    def read_picture(self, media):
        if media.get("$cls") != "ImageMediaObject":
            self.note_unknown("media classes", media.get("$cls"))
        self.check_keys("picture keys", media, KNOWN_PICTURE_KEYS)
        figure = media["figure"]
        size = numbers_from_string(media["unscaledContentSize"])
        crop = numbers_from_string(figure["FigureCropRectKey"])
        if len(size) != 2 or len(crop) != 4 or crop[2] <= 0:
            raise FormatError("picture size or crop is not a size and a rectangle")
        return {"file": figure["FigureBackgroundObjectKey"]["kImageObjectSnapshotKey"]["relativePath"],
                "origin": numbers_from_string(media["documentOrigin"]), "size": size,
                "rotation_radians_clockwise_about_centre": media["rotationDegrees"], "z_index": media["zIndex"],
                "crop_in_image_pixels": crop, "units_per_image_pixel": size[0] / crop[2],
                "is_flipped_horizontally": media.get("isFlippedHorizontal", False),
                "is_flipped_vertically": media.get("isFlippedVertical", False)}

    def read_text(self, attributed_string):
        text = attributed_string.get("stringKey") or ""
        utf16_length = len(text.encode("utf-16-le")) // 2
        runs = []
        for run in attributed_string.get("subRangesKey") or []:
            location, length = (int(number) for number in numbers_from_string(run.get("subRangeRangeKey")))
            if location < 0 or length < 0 or location + length > utf16_length:
                raise FormatError("text run outside the text (runs count UTF-16 units)")
            other_attributes = run.get("subRangeOtherAttributesKey") or {}
            self.check_keys("text attribute keys", other_attributes, KNOWN_TEXT_ATTRIBUTE_KEYS)
            font = run.get("subRangeFontKey") or {}
            color = run.get("subRangeColorCrossPlatformKey")
            runs.append({"location": location, "length": length, "font_name": font.get("NSFontNameAttribute"),
                         "font_size": font.get("NSFontSizeAttribute"),
                         "color": [float(component) for component in color.split(",")] if color else None,
                         "is_underlined": bool(other_attributes.get("NSUnderline")),
                         "is_struck_through": bool(other_attributes.get("NSStrikethrough")),
                         "line_spacing": other_attributes.get("line-spacing"),
                         "baseline_offset": other_attributes.get("NSBaselineOffset")})
        return {"text": text, "runs": runs}

    def read_pdf_page(self, layout):
        self.check_keys("page layout keys", layout, KNOWN_PAGE_LAYOUT_KEYS)
        return {"document_page": layout.get("kPageLayoutDocumentPageNumberKey"),
                "pdf_file": "PDFs/" + layout.get("kPageLayoutPDFFileNameKey", ""),
                "pdf_page": layout.get("kPageLayoutPDFPageNumberKey"),
                "is_bookmarked": layout.get("kPageLayoutPageIsBookmarkedKey", False)}

    def read_recordings(self):
        try:
            library_bytes = self.entry("Recordings/library.plist")
        except FormatError:
            return []
        library = parse_property_list(library_bytes, "Recordings/library.plist")
        if not isinstance(library, dict) or not isinstance(library.get("recordings") or {}, dict):
            raise FormatError("Recordings/library.plist has no recordings dictionary")
        recordings = []
        for identifier, recording in sorted((library.get("recordings") or {}).items(), key=lambda entry: str(entry[0])):
            if not isinstance(recording, dict):
                raise FormatError(f"recording {identifier} is not a dictionary")
            recordings.append({"identifier": recording.get("identifier"), "file": "Recordings/" + recording.get("filepath", ""),
                               "duration_seconds": recording.get("duration"), "name": recording.get("name")})
        return recordings

    def read_playback_events(self, event_manager):
        """One event per timed curve: its UUID, the recording, the time from the recording's start and how long it took."""
        count = event_manager.get("NBCPTimeManagerSOANumEventsKey", 0)
        uuids = packed(event_manager.get("NBCPTimeManagerSOAEventUUIDsKey", b""), "B", UUID_BYTES * count, "event UUIDs")
        timestamps = packed(event_manager.get("NBCPTimeManagerSOATimestampsKey", b""), "f", count, "event timestamps")
        recording_identifiers = packed(event_manager.get("NBCPTimeManagerSOARecordingIDsKey", b""), "I", count, "event recordings")
        durations = packed(event_manager.get("NBCPTimeManagerSOADurationsKey", b""), "f", count, "event durations")
        curve_by_uuid = {curve["uuid"]: index for index, curve in enumerate(self.curves)}
        events = []
        for event_index in range(count):
            uuid = bytes(uuids[UUID_BYTES * event_index:UUID_BYTES * (event_index + 1)]).hex()
            if uuid not in curve_by_uuid:
                self.note_unknown("playback events", "event UUID that is not a curve")
            events.append({"curve_index": curve_by_uuid.get(uuid), "recording": recording_identifiers[event_index],
                           "seconds_from_recording_start": timestamps[event_index],
                           "duration_seconds": durations[event_index]})
        return events

    def export_page_points(self):
        size = EXPORT_PAGE_POINTS.get(self.paper.get("paperSize"))
        if size is None:
            self.note_unknown("paper sizes", self.paper.get("paperSize"))
            return None
        return size[::-1] if self.paper.get("paperOrientation") == "landscape" else size

    def points_per_unit(self):
        size = self.export_page_points()
        return size[0] / self.page_width if size and self.page_width else None

    def page_height(self):
        size, scale = self.export_page_points(), self.points_per_unit()
        return size[1] / scale if scale else None

    def page_of(self, vertical_position):
        height = self.page_height()
        if height is None:
            raise FormatError("the page size is not known for this note")
        return int(vertical_position // height) + 1


def summary(note):
    lowest = max([max(y for _, y in curve["points"]) for curve in note.curves] +
                 [picture["origin"][1] + picture["size"][1] for picture in note.pictures] + [0])
    highlighter_count = sum(curve["is_highlighter"] for curve in note.curves)
    paper = (f"paper: {note.paper.get('paperIdentifier')}, {note.paper.get('paperSize')} {note.paper.get('paperOrientation')}, "
             f"lines {note.paper.get('lineStyle2')}, sizing {note.paper.get('paperSizingBehavior')}")
    if note.points_per_unit():
        geometry = (f"page: {note.page_width:.2f} x {note.page_height():.2f} units, {note.points_per_unit():.5f} points per unit; "
                    f"pages reached by content: {note.page_of(lowest)}")
    else:
        geometry = "page: width not stored (reflowable note) or paper size unknown; pages not computed"
    lines = [
        f"session format: {note.session.get('sessionFormatVersion')}, Notability {note.session.get('NBNoteTakingSessionBundleVersionNumberKey')}",
        paper, geometry,
        f"curves: {len(note.curves)} ({highlighter_count} highlighter), shapes: {len(note.shapes)}, pictures: {len(note.pictures)}",
        f"typed text: {len(note.typed_text['text'])} characters in {len(note.typed_text['runs'])} runs, "
        f"PDF pages: {len(note.pdf_pages)}, recordings: {len(note.recordings)}, timed curves: {len(note.playback_events)}",
    ]
    for where, what in sorted(note.unknown.items()):
        lines.append(f"unknown {where}: {sorted(what, key=str)}")
    if not note.unknown:
        lines.append("unknown: nothing")
    return "\n".join(lines)


def page_content(note, page_number):
    def on_page(vertical_positions):
        return any(note.page_of(position) == page_number for position in vertical_positions)
    return {
        "curves": [curve for curve in note.curves if on_page(y for _, y in curve["points"])],
        "shapes": [shape for shape in note.shapes if on_page([shape["start"][1], shape["end"][1]])],
        "pictures": [picture for picture in note.pictures if on_page([picture["origin"][1], picture["origin"][1] + picture["size"][1]])],
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("note", help="a .note file")
    parser.add_argument("--page", type=int, help="print what is on this page (from 1) as JSON")
    parser.add_argument("--text", action="store_true", help="print the typed text and its runs as JSON")
    parser.add_argument("--recordings", action="store_true", help="print the recordings and curve timing as JSON")
    arguments = parser.parse_args()
    try:
        note = NotabilityNote(arguments.note)
        if arguments.page is not None:
            print(json.dumps(page_content(note, arguments.page), indent=1))
        elif arguments.text:
            print(json.dumps(note.typed_text, indent=1))
        elif arguments.recordings:
            print(json.dumps({"recordings": note.recordings, "events": note.playback_events}, indent=1))
        else:
            print(summary(note))
        return 0
    except (FormatError, zipfile.BadZipFile, KeyError, TypeError, ValueError, UnicodeDecodeError) as error:
        print(f"cannot read {arguments.note}: {type(error).__name__}: {error}", file=sys.stderr)
        return 1
    except (AttributeError, IndexError) as error:
        # An archive object of the wrong type where the format has a dictionary, string or list.
        print(f"cannot read {arguments.note}: unexpected structure ({type(error).__name__}: {error})", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())

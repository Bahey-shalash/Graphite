#!/usr/bin/env python3
"""Reference reader for Notability notes (.note, session format 9), as described in Docs/Notability-format.md.

Reads a note straight from its ZIP archive, with the standard library only, and prints what it found: the paper,
the pages the ink reaches, the curves, shapes and pictures, and every archive class or key this reader does not
know. It exists to check the format description against more notes and newer Notability versions, and to give the
Swift parsers (import checklist, phase 2) expected values to test against. It is not Graphite's importer.

Every size read from the file is checked before it is used, so a damaged or hostile archive fails with an error
message instead of exhausting memory.

Usage:
  python3 scripts/notability-reader.py NOTE.note               summary and unknown keys
  python3 scripts/notability-reader.py NOTE.note --page 2      the curves, shapes and pictures on that page as JSON
"""
import argparse
import array
import json
import plistlib
import re
import sys
import zipfile

SUPPORTED_SESSION_FORMAT = 9
MAXIMUM_ENTRY_BYTES = 512 * 1024 * 1024
MAXIMUM_OBJECT_DEPTH = 64
PEN_STYLE = 3
HIGHLIGHTER_STYLE = 4
PAPER_INCHES = {"letter": (8.5, 11.0), "legal": (8.5, 14.0), "a4": (210 / 25.4, 297 / 25.4)}
POINTS_PER_INCH = 72

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


class KeyedArchive:
    """Resolves an NSKeyedArchiver (or GLKeyedArchiver) object graph into plain values, cycles cut."""

    def __init__(self, archive_bytes):
        archive = plistlib.loads(archive_bytes)
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
        self.page_width = rich_text["reflowState"]["pageWidthInDocumentCoordsKey"]
        ink = rich_text["Handwriting Overlay"]["SpatialHash"]
        self.check_keys("ink keys", ink, KNOWN_INK_KEYS)
        self.curves = self.read_curves(ink)
        self.shapes = self.read_shapes(ink.get("shapes"))
        self.pictures = [self.read_picture(media) for media in rich_text["mediaObjects"]]
        self.typed_text = rich_text["attributedString"]["stringKey"]
        self.pdf_files = rich_text["pdfFiles"]

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
            })
            point_index += count
            knot_index += knots
        return curves

    def read_shapes(self, shapes_plist):
        if not shapes_plist:
            return []
        shapes = plistlib.loads(shapes_plist)
        shape_list, kinds, indices = shapes.get("shapes", []), shapes.get("kinds", []), shapes.get("indices", [])
        if not len(shape_list) == len(kinds) == len(indices):
            raise FormatError("shape arrays differ in length")
        for kind in set(kinds) - {"line"}:
            self.note_unknown("shape kinds", kind)
        return [{"kind": kind, "drawn_before_curve": index, "start": shape.get("startPt"), "end": shape.get("endPt"),
                 "width": shape["appearance"].get("strokeWidth"), "color": shape["appearance"]["strokeColor"]["rgba"],
                 "is_dashed": "dashStyle" in shape["appearance"]}
                for shape, kind, index in zip(shape_list, kinds, indices)]

    def read_picture(self, media):
        if media.get("$cls") != "ImageMediaObject":
            self.note_unknown("media classes", media.get("$cls"))
        figure = media["figure"]
        return {"file": figure["FigureBackgroundObjectKey"]["kImageObjectSnapshotKey"]["relativePath"],
                "origin": numbers_from_string(media["documentOrigin"]), "size": numbers_from_string(media["unscaledContentSize"]),
                "rotation_degrees": media["rotationDegrees"], "z_index": media["zIndex"],
                "crop": numbers_from_string(figure["FigureCropRectKey"])}

    def page_height(self):
        width_inches, height_inches = PAPER_INCHES.get(self.paper.get("paperSize"), PAPER_INCHES["letter"])
        if self.paper.get("paperSize") not in PAPER_INCHES:
            self.note_unknown("paper sizes", self.paper.get("paperSize"))
        if self.paper.get("paperOrientation") == "landscape":
            width_inches, height_inches = height_inches, width_inches
        return self.page_width * height_inches / width_inches

    def points_per_unit(self):
        width_inches, height_inches = PAPER_INCHES.get(self.paper.get("paperSize"), PAPER_INCHES["letter"])
        if self.paper.get("paperOrientation") == "landscape":
            width_inches = height_inches
        return width_inches * POINTS_PER_INCH / self.page_width

    def page_of(self, vertical_position):
        return int(vertical_position // self.page_height()) + 1


def summary(note):
    lowest = max([max(y for _, y in curve["points"]) for curve in note.curves] +
                 [picture["origin"][1] + picture["size"][1] for picture in note.pictures] + [0])
    page_count = note.page_of(lowest)
    highlighter_count = sum(curve["is_highlighter"] for curve in note.curves)
    lines = [
        f"session format: {note.session.get('sessionFormatVersion')}, Notability {note.session.get('NBNoteTakingSessionBundleVersionNumberKey')}",
        f"paper: {note.paper.get('paperIdentifier')}, {note.paper.get('paperSize')} {note.paper.get('paperOrientation')}, "
        f"lines {note.paper.get('lineStyle2')}, {note.page_width:.1f} units wide ({note.points_per_unit():.4f} points per unit)",
        f"pages reached by content: {page_count} of {note.page_height():.1f} units",
        f"curves: {len(note.curves)} ({highlighter_count} highlighter), shapes: {len(note.shapes)}, pictures: {len(note.pictures)}",
        f"typed text: {len(note.typed_text)} characters, PDFs: {len(note.pdf_files)}",
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
    arguments = parser.parse_args()
    try:
        note = NotabilityNote(arguments.note)
        if arguments.page is None:
            print(summary(note))
        else:
            print(json.dumps(page_content(note, arguments.page), indent=1))
        return 0
    except (FormatError, zipfile.BadZipFile, plistlib.InvalidFileException, KeyError, TypeError, ValueError, UnicodeDecodeError) as error:
        print(f"cannot read {arguments.note}: {type(error).__name__}: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())

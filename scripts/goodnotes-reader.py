#!/usr/bin/env python3
"""Reference reader for Goodnotes notebooks (.goodnotes, schemas 24, 25, 26 and 35), as described in
Docs/Goodnotes-format.md.

Reads a notebook straight from its ZIP archive, with the standard library only, and prints what it found: the
title, each page in order with its size, paper and elements, bookmarks, outline entries and recordings, and every
record kind or field this reader does not know. It exists to check the format description against more notebooks
and newer Goodnotes versions, and to give the Swift parsers (import checklist, phase 2) expected values to test
against. It is not Graphite's importer.

Every size read from the file is checked before it is used, so a damaged or hostile archive fails with an error
message instead of exhausting memory.

Usage:
  python3 scripts/goodnotes-reader.py NOTEBOOK.goodnotes              summary and unknown fields
  python3 scripts/goodnotes-reader.py NOTEBOOK.goodnotes --page 3     that page's elements as JSON
"""
import argparse
import json
import struct
import sys
import zipfile

SUPPORTED_SCHEMA_VERSIONS = {24, 25, 26, 35}
MAXIMUM_ENTRY_BYTES = 512 * 1024 * 1024
MAXIMUM_DECODED_STROKE_BYTES = 64 * 1024 * 1024
MAXIMUM_VARINT_BYTES = 10
GOODNOTES_UNITS_PER_POINT = 11 / 6
FLICKS_PER_SECOND = 705_600_000
UNSET_TEXT_ATTRIBUTE = -404.0

EVENT_DOCUMENT_CREATED = 30
EVENT_DOCUMENT_RENAMED = 31
EVENT_ATTACHMENT = 6
EVENT_PAPER = 2
EVENT_PAGE_CREATED = 54
EVENT_PAGE_PAPER_CHANGED = 3
EVENT_PAGE_MOVED = 55
EVENT_PAGE_DELETED = 56
EVENT_PAGE_BOOKMARKED = 57
EVENT_PAGE_FLAG = 63
EVENT_OUTLINE_ENTRY = 62
EVENT_LAYER_MEMBERS = 106
EVENT_RECORDING = 160
EVENT_RECORDING_DELETED = 163
KNOWN_EVENT_KINDS = {2, 3, 6, 10, 30, 31, 33, 34, 54, 55, 56, 57, 62, 63, 102, 103, 104, 105, 106, 160, 163}

BODY_PICTURE = 1
BODY_STROKE = 7
BODY_RICH_TEXT_BOX = 8
BODY_FILL = 9
BODY_TEXT_ELEMENT = 12
BODY_STICKY_NOTE = 20
BODY_TEXT_BOX = 21
POSITION_FIELD_BY_BODY = {BODY_STROKE: 7, BODY_PICTURE: 5, BODY_FILL: 3, BODY_RICH_TEXT_BOX: 5,
                          BODY_TEXT_ELEMENT: 13, BODY_STICKY_NOTE: 7, BODY_TEXT_BOX: 7}
KNOWN_FIELDS_BY_BODY = {
    BODY_STROKE: {1, 2, 3, 4, 5, 6, 7, 9, 14, 15, 20, 21},
    BODY_PICTURE: {1, 2, 3, 4, 5, 6, 7, 14, 15, 18},
    BODY_FILL: {1, 2, 3, 4, 5, 6, 7, 14, 15, 18},
    BODY_RICH_TEXT_BOX: {1, 2, 3, 4, 5, 6, 7, 9, 10, 14, 15, 18, 19, 20, 21, 27},
    BODY_TEXT_ELEMENT: {1, 2, 3, 13, 15, 25, 26, 27, 28},
    BODY_STICKY_NOTE: {1, 2, 3, 7, 20, 21, 30, 31, 32, 33, 40, 41},
    BODY_TEXT_BOX: {1, 2, 3, 7, 9, 20, 21, 22, 30, 31, 32, 33},
}
KNOWN_HEADER_FIELDS = {1, 2, 3, 4, 6, 7, 8, 9, 10, 14, 16}
KNOWN_SHAPE_FIELDS = {1, 2, 3, 4, 5, 15}

CONSTANT_WIDTH_PATH_FORMAT = "vuA(v)A(S(uu))A(S(uuuu))vA(f)"
VARIABLE_WIDTH_PATH_FORMAT = "vA(v)A(u)A(u)A(v)A(v)A(u)A(u)A(u)A(u)A(v)"
OLDER_VARIABLE_WIDTH_PATH_FORMAT = "vuA(v)A(u)A(u)A(v)A(v)A(u)A(u)A(u)A(u)A(v)"
PENCIL_PATH_FORMAT = "vuA(v)A(S(uuuuu))A(S(uuuuuuuuuuu))A(S(uu))A(v)A(S(uu))A(S(uuuu))A(u)"
PATH_CODE_START = 0
PATH_CODE_CURVE = 1
CENTRE_LINE_START_CODES = {0, 4}
CENTRE_LINE_CURVE_CODES = {1, 5}
OUTLINE_COMMANDS = {0: "move", 2: "cubic", 3: "round_cap", 6: "flat_cap"}
OLDER_OUTLINE_COMMANDS = {2: "move", 4: "cubic"}
INK_NAMES = {0: "ball pen", 1: "fountain pen, brush pen or tape", 4: "older variable-width ink", 5: "pencil"}


class FormatError(Exception):
    """The file does not match the format this reader knows."""


# Protocol Buffers wire format, without a schema.

def read_varint(buffer, offset):
    value, shift = 0, 0
    for byte_count in range(MAXIMUM_VARINT_BYTES):
        if offset >= len(buffer):
            raise FormatError("varint runs past the end of its message")
        byte = buffer[offset]
        offset += 1
        value |= (byte & 0x7F) << shift
        if not byte & 0x80:
            return value, offset
        shift += 7
    raise FormatError("varint longer than ten bytes")


def parse_message(buffer):
    """A message as a list of (field number, wire type, value): integers for varints, bytes otherwise."""
    fields, offset = [], 0
    while offset < len(buffer):
        key, offset = read_varint(buffer, offset)
        field_number, wire_type = key >> 3, key & 7
        if field_number == 0:
            raise FormatError("field number 0")
        if wire_type == 0:
            value, offset = read_varint(buffer, offset)
        elif wire_type in (1, 5):
            length = 8 if wire_type == 1 else 4
            if offset + length > len(buffer):
                raise FormatError("fixed-size field runs past the end of its message")
            value, offset = buffer[offset:offset + length], offset + length
        elif wire_type == 2:
            length, offset = read_varint(buffer, offset)
            if offset + length > len(buffer):
                raise FormatError("length-delimited field runs past the end of its message")
            value, offset = buffer[offset:offset + length], offset + length
        else:
            raise FormatError(f"unsupported wire type {wire_type}")
        fields.append((field_number, wire_type, value))
    return fields


def message_fields(buffer):
    """A message as {field number: [values]}, keeping repeated fields in order."""
    if buffer is not None and not isinstance(buffer, bytes):
        raise FormatError("a message field holds a number")
    fields = {}
    for field_number, _, value in parse_message(buffer or b""):
        fields.setdefault(field_number, []).append(value)
    return fields


def last(fields, field_number, default=None):
    return fields[field_number][-1] if field_number in fields else default


def length_prefixed_messages(buffer):
    offset = 0
    while offset < len(buffer):
        length, offset = read_varint(buffer, offset)
        if offset + length > len(buffer):
            raise FormatError("record runs past the end of its file")
        yield buffer[offset:offset + length]
        offset += length


def float32(buffer):
    if not buffer:
        return 0.0
    if not isinstance(buffer, bytes) or len(buffer) != 4:
        raise FormatError("a float field has the wrong wire type")
    return struct.unpack("<f", buffer)[0]


def float32_from_bits(bits):
    return struct.unpack("<f", struct.pack("<I", bits))[0]


def text(buffer):
    if buffer is None:
        return ""
    if not isinstance(buffer, bytes):
        raise FormatError("a string field holds a number")
    return buffer.decode("utf-8")


def point(buffer):
    fields = message_fields(buffer)
    return (float32(last(fields, 1)), float32(last(fields, 2)))


def color(buffer):
    fields = message_fields(buffer)
    return tuple(float32(last(fields, component)) for component in (1, 2, 3, 4))


def clock(buffer):
    """{1: counter, 2: replica} -> (counter, replica)."""
    fields = message_fields(buffer)
    return (last(fields, 1, 0), last(fields, 2, 0))


def register(buffer):
    """A last-writer-wins register {1: value, 2: clock} -> (value or None, clock)."""
    fields = message_fields(buffer)
    return (last(fields, 1), clock(last(fields, 2)))


def layer_identifier(page_identifier):
    """A page's ink layer: the page UUID with 1 added to its last byte, without carry."""
    return f"{page_identifier[:-2]}{(int(page_identifier[-2:], 16) + 1) % 256:02X}"


# Apple Compression framework LZ4 framing, and the tpl serialisation inside it.

def decode_lz4_block(source, decoded_size):
    destination = bytearray()
    offset = 0
    while offset < len(source):
        token = source[offset]
        offset += 1
        literal_length = token >> 4
        if literal_length == 15:
            while True:
                if offset >= len(source):
                    raise FormatError("LZ4 literal length runs past the block")
                extra = source[offset]
                offset += 1
                literal_length += extra
                if extra != 255:
                    break
        if offset + literal_length > len(source) or len(destination) + literal_length > decoded_size:
            raise FormatError("LZ4 literals run past the block or its declared size")
        destination += source[offset:offset + literal_length]
        offset += literal_length
        if offset >= len(source):
            break
        if offset + 2 > len(source):
            raise FormatError("LZ4 match offset runs past the block")
        match_distance = source[offset] | (source[offset + 1] << 8)
        offset += 2
        match_length = token & 15
        if match_length == 15:
            while True:
                if offset >= len(source):
                    raise FormatError("LZ4 match length runs past the block")
                extra = source[offset]
                offset += 1
                match_length += extra
                if extra != 255:
                    break
        match_length += 4
        match_start = len(destination) - match_distance
        if match_distance == 0 or match_start < 0 or len(destination) + match_length > decoded_size:
            raise FormatError("LZ4 match outside the decoded data or its declared size")
        for copied_index in range(match_length):
            destination.append(destination[match_start + copied_index])
    if len(destination) != decoded_size:
        raise FormatError(f"LZ4 block decoded to {len(destination)} bytes, declared {decoded_size}")
    return bytes(destination)


def decode_apple_lz4(buffer):
    """Blocks of 'bv41' (LZ4) or 'bv4-' (stored), ended by 'bv4$'."""
    decoded, offset = bytearray(), 0
    while offset + 4 <= len(buffer):
        magic = buffer[offset:offset + 4]
        if magic == b"bv4$":
            return bytes(decoded)
        if magic == b"bv41":
            decoded_size, encoded_size = struct.unpack_from("<II", buffer, offset + 4)
            block_start = offset + 12
            next_offset = block_start + encoded_size
        elif magic == b"bv4-":
            decoded_size, = struct.unpack_from("<I", buffer, offset + 4)
            encoded_size = decoded_size
            block_start = offset + 8
            next_offset = block_start + decoded_size
        else:
            raise FormatError(f"unknown compression block {magic!r}")
        if next_offset > len(buffer) or len(decoded) + decoded_size > MAXIMUM_DECODED_STROKE_BYTES:
            raise FormatError("compression block runs past its field or exceeds the size limit")
        block = buffer[block_start:next_offset]
        decoded += decode_lz4_block(block, decoded_size) if magic == b"bv41" else block
        offset = next_offset
    raise FormatError("compressed stroke has no end marker")


TPL_SCALAR_FORMATS = {"c": "B", "i": "i", "u": "I", "j": "h", "v": "H", "I": "q", "U": "Q", "f": "d"}


def parse_tpl_format(format_string, offset=0):
    """'vA(S(uu))' -> ['v', ('A', [('S', ['u', 'u'])])]."""
    tree = []
    while offset < len(format_string):
        character = format_string[offset]
        if character in "AS":
            if format_string[offset + 1:offset + 2] != "(":
                raise FormatError(f"tpl format {format_string!r}: '(' expected")
            children, offset = parse_tpl_format(format_string, offset + 2)
            tree.append((character, children))
        elif character == ")":
            return tree, offset + 1
        elif character in TPL_SCALAR_FORMATS:
            tree.append(character)
            offset += 1
        else:
            raise FormatError(f"tpl format {format_string!r}: unsupported type {character!r}")
    return tree, offset


class TplImage:
    """A tpl image: 'tpl', flags, total size, NUL-terminated format string, then the values."""

    def __init__(self, buffer):
        if buffer[:3] != b"tpl" or len(buffer) < 9:
            raise FormatError("stroke path is not a tpl image")
        if buffer[3] & 1:
            raise FormatError("big-endian tpl image")
        end_of_format = buffer.find(b"\0", 8)
        if end_of_format < 0:
            raise FormatError("tpl format string is not terminated")
        self.format_string = buffer[8:end_of_format].decode("ascii")
        self.buffer, self.offset = buffer, end_of_format + 1

    def read_scalar(self, character):
        code = TPL_SCALAR_FORMATS[character]
        size = struct.calcsize("<" + code)
        if self.offset + size > len(self.buffer):
            raise FormatError("tpl value runs past the image")
        value, = struct.unpack_from("<" + code, self.buffer, self.offset)
        self.offset += size
        return value

    def read_tree(self, tree):
        values = []
        for node in tree:
            if isinstance(node, tuple) and node[0] == "S":
                values.append(tuple(self.read_tree(node[1])))
            elif isinstance(node, tuple):
                count = self.read_scalar("u")
                if count * 2 > len(self.buffer) - self.offset:
                    raise FormatError("tpl array longer than the image")
                children = node[1]
                values.append([self.read_tree(children)[0] if len(children) == 1 else self.read_tree(children) for _ in range(count)])
            else:
                values.append(self.read_scalar(node))
        return values

    def read(self):
        tree, _ = parse_tpl_format(self.format_string)
        values = self.read_tree(tree)
        if self.offset != len(self.buffer):
            raise FormatError(f"{len(self.buffer) - self.offset} bytes left after the tpl values")
        return values


# Rich text inside text boxes and sticky notes.

def text_attributes(buffer):
    """Run or default attributes: colour (3), link (4), font (30), size in Goodnotes units (40); -404 means unset."""
    fields = message_fields(buffer)
    size = float32(last(fields, 40)) if 40 in fields else None
    return {"color": color(last(fields, 3)) if 3 in fields else None, "link": text(last(fields, 4)) or None,
            "font": text(last(fields, 30)) or None,
            "size_units": None if size is None or size == UNSET_TEXT_ATTRIBUTE else size}


def rich_text(container_buffer):
    """{1: {2: compressed rich text, 3: hash, 4: 1}, 5: {1: default attributes}} -> text, runs and defaults."""
    container = message_fields(container_buffer)
    content = message_fields(last(container, 1))
    defaults = message_fields(last(container, 5))
    body = message_fields(last(message_fields(decode_apple_lz4(last(content, 2))), 1)) if 2 in content else {}
    return {"text": text(last(body, 1)), "runs": [text_attributes(run) for run in body.get(2, [])],
            "defaults": text_attributes(last(defaults, 1)) if 1 in defaults else None}


# The notebook.

class GoodnotesNotebook:
    def __init__(self, archive_path):
        self.archive = zipfile.ZipFile(archive_path)
        self.unknown = {}
        self.title = None
        self.attachments, self.papers, self.pages, self.layer_members = {}, {}, {}, {}
        self.outline_entries, self.recordings, self.deleted_recordings, self.flagged_pages = [], {}, set(), set()
        schema = message_fields(self.entry("schema.pb"))
        self.schema_version = last(schema, 1)
        if self.schema_version not in SUPPORTED_SCHEMA_VERSIONS:
            self.note_unknown("schema version", self.schema_version)
        for record in length_prefixed_messages(self.entry("index.events.pb")):
            self.apply_event(record)

    def entry(self, name):
        try:
            information = self.archive.getinfo(name)
        except KeyError:
            return b""
        if information.file_size > MAXIMUM_ENTRY_BYTES:
            raise FormatError(f"{name} is larger than {MAXIMUM_ENTRY_BYTES} bytes")
        return self.archive.read(information)

    def note_unknown(self, where, what):
        self.unknown.setdefault(where, set()).add(what)

    def update_register(self, target, key, new_register):
        """Last writer wins: the higher counter, or the later record when counters are equal."""
        value, version = new_register
        if key not in target or version[0] >= target[key][1][0]:
            target[key] = (value, version)

    def apply_event(self, record):
        top = parse_message(record)
        if not top:
            raise FormatError("empty event record")
        entity = text(top[0][2])
        bodies = [field for field in top[1:]]
        if len(bodies) != 1:
            raise FormatError(f"event for {entity} has {len(bodies)} bodies")
        kind, _, body = bodies[0]
        fields = message_fields(body)
        if kind == EVENT_DOCUMENT_CREATED or kind == EVENT_DOCUMENT_RENAMED:
            title = {} if self.title is None else {"title": self.title}
            self.update_register(title, "title", register(last(fields, 2)))
            self.title = title["title"]
        elif kind == EVENT_ATTACHMENT:
            page_count = message_fields(last(fields, 12))
            self.attachments[entity] = {"file": text(last(fields, 2)), "bytes": last(fields, 5),
                                        "pdf_page_count": last(page_count, 2)}
        elif kind == EVENT_PAPER:
            width, height = point(last(fields, 8))
            self.papers[entity] = {"attachment": text(last(fields, 4)), "pdf_page": last(fields, 5, 1),
                                   "width_points": width / GOODNOTES_UNITS_PER_POINT,
                                   "height_points": height / GOODNOTES_UNITS_PER_POINT,
                                   "template": text(last(fields, 9))}
        elif kind in (EVENT_PAGE_CREATED, EVENT_PAGE_PAPER_CHANGED, EVENT_PAGE_MOVED, EVENT_PAGE_DELETED, EVENT_PAGE_BOOKMARKED):
            self.apply_page_event(kind, entity, fields)
        elif kind == EVENT_PAGE_FLAG:
            self.flagged_pages.add(entity)
        elif kind == EVENT_OUTLINE_ENTRY:
            self.outline_entries.append({"title": text(last(fields, 5)), "order_key": text(last(fields, 6)),
                                         "point": point(last(message_fields(last(fields, 3)), 1)),
                                         "target": text(last(fields, 2))})
        elif kind == EVENT_LAYER_MEMBERS:
            self.layer_members[entity] = [text(register(member)[0]) for member in fields.get(2, [])]
        elif kind == EVENT_RECORDING:
            self.apply_recording(entity, fields)
        elif kind == EVENT_RECORDING_DELETED:
            self.deleted_recordings.add(entity)
        elif kind not in KNOWN_EVENT_KINDS:
            self.note_unknown("event kinds", kind)

    def apply_page_event(self, kind, entity, fields):
        """Created (54) and paper changed (3) carry the paper in 3; moved (55) a new position in 3; created a
        position in 4; deleted (56) and bookmarked (57) a register whose value 1 means yes."""
        page = self.pages.setdefault(entity, {"id": entity})
        if kind in (EVENT_PAGE_CREATED, EVENT_PAGE_PAPER_CHANGED) and 3 in fields:
            self.update_register(page, "paper", register(last(fields, 3)))
        if kind == EVENT_PAGE_CREATED and 4 in fields:
            self.update_register(page, "position", register(last(fields, 4)))
        if kind == EVENT_PAGE_MOVED and 3 in fields:
            self.update_register(page, "position", register(last(fields, 3)))
        if kind == EVENT_PAGE_DELETED:
            self.update_register(page, "deleted", register(last(fields, 3)))
        if kind == EVENT_PAGE_BOOKMARKED:
            self.update_register(page, "bookmarked", register(last(fields, 3)))

    def apply_recording(self, entity, fields):
        """Audio attachment (2), duration (4) and, per element written during it, its time from the start (5)."""
        timings = []
        for timing in message_fields(last(fields, 5)).get(1, []):
            timing_fields = message_fields(timing)
            moment = message_fields(last(timing_fields, 2))
            timings.append({"element": text(last(timing_fields, 1)), "seconds": last(moment, 1, 0) / FLICKS_PER_SECOND,
                            "page": text(last(moment, 2))})
        attachment = self.attachments.get(text(last(fields, 2)), {})
        self.recordings[entity] = {"file": attachment.get("file"), "seconds": last(fields, 4, 0) / FLICKS_PER_SECOND,
                                   "element_timings": timings}

    def ordered_pages(self):
        pages = [page for page in self.pages.values()
                 if page.get("position", (None,))[0] is not None and page.get("deleted", (None,))[0] != 1]
        return sorted(pages, key=lambda page: (page["position"][0], page["id"]))

    def page_paper(self, page):
        return self.papers.get(text(page["paper"][0])) if "paper" in page else None

    def elements(self, page):
        """The page's elements that are not erased, in drawing order. The layer file is authoritative: the member
        list (kind 106) is absent from some notebooks."""
        layer = layer_identifier(page["id"])
        headers, bodies = {}, {}
        for record in length_prefixed_messages(self.entry(f"notes/{layer}")):
            top = parse_message(record)
            if not top:
                raise FormatError(f"empty record in layer {layer}")
            if top[0][0] == 1 and len(top) > 1:
                fields = message_fields(record)
                for field_number in set(fields) - KNOWN_HEADER_FIELDS:
                    self.note_unknown("element header fields", field_number)
                headers[text(last(fields, 1))] = {"erased": last(fields, 3) == 1, "order_id": text(last(fields, 6))}
            else:
                kind, _, body = top[0]
                fields = message_fields(body)
                bodies[text(last(fields, 1))] = (kind, fields)
        members = set(self.layer_members[layer]) if layer in self.layer_members else None
        elements = []
        for element_identifier, (kind, fields) in bodies.items():
            header = headers.get(element_identifier)
            if header is None:
                self.note_unknown("elements", "body without header")
                continue
            if members is not None and (header["order_id"] or element_identifier) not in members:
                self.note_unknown("elements", "element missing from the layer's member list")
            if header["erased"]:
                continue
            element = self.element(element_identifier, kind, fields)
            if element is not None:
                element["position"] = clock(last(message_fields(last(fields, POSITION_FIELD_BY_BODY[kind])), 1))
                elements.append(element)
        return sorted(elements, key=lambda element: element["position"])

    def element(self, element_identifier, kind, fields):
        if kind not in KNOWN_FIELDS_BY_BODY:
            self.note_unknown("element kinds", kind)
            return None
        for field_number in set(fields) - KNOWN_FIELDS_BY_BODY[kind]:
            self.note_unknown(f"element kind {kind} fields", field_number)
        if kind == BODY_STROKE:
            return self.stroke(element_identifier, fields)
        if kind == BODY_PICTURE:
            return self.picture(element_identifier, fields)
        if kind == BODY_FILL:
            return {"id": element_identifier, "type": "fill", "color": color(last(fields, 7)),
                    "shape": self.shape(last(fields, 4)) if 4 in fields else None,
                    "outline_strokes": [text(stroke) for stroke in fields.get(5, [])],
                    "offset": point(last(fields, 6)) if last(fields, 6) else (0.0, 0.0)}
        if kind == BODY_TEXT_BOX:
            return self.text_box(element_identifier, fields)
        if kind == BODY_STICKY_NOTE:
            placement = message_fields(last(fields, 20))
            size = message_fields(last(message_fields(last(fields, 21)), 2))
            return {"id": element_identifier, "type": "sticky_note", "origin": point(last(placement, 1)),
                    "size": (float32(last(size, 1)), float32(last(size, 2))), "paper_color": color(last(fields, 30)),
                    "rich_text": rich_text(last(fields, 31)), "author": text(last(fields, 33))}
        if kind == BODY_RICH_TEXT_BOX:
            frame, text_frame = (message_fields(last(fields, number)) for number in (2, 3))
            return {"id": element_identifier, "type": "rtf_text_box",
                    "frame": (point(last(frame, 1)), point(last(frame, 2))),
                    "text_frame": (point(last(text_frame, 1)), point(last(text_frame, 2))),
                    "rtf": text(last(fields, 6))}
        return {"id": element_identifier, "type": "rtf_text_element", "rtf": text(last(fields, 3))}

    def picture(self, element_identifier, fields):
        bounds = message_fields(last(fields, 2))
        placement = message_fields(last(fields, 3))
        attachment = self.attachments.get(text(last(fields, 4)), {})
        return {"id": element_identifier, "type": "picture", "file": attachment.get("file"),
                "bounding_box": (point(last(bounds, 1)), point(last(bounds, 2))),
                "center": point(last(placement, 1)), "size": point(last(placement, 2)),
                "rotation_radians": float32(last(placement, 3)), "sticker_flag": last(fields, 6)}

    def text_box(self, element_identifier, fields):
        placement = message_fields(last(fields, 20))
        layout = message_fields(last(fields, 32))
        insets = message_fields(last(layout, 10))
        return {"id": element_identifier, "type": "text_box", "origin": point(last(placement, 1)),
                "scale": float32(last(placement, 3)) if 3 in placement else 1.0,
                "size": point(last(layout, 2)) if 2 in layout else None,
                "insets": tuple(float32(last(insets, side)) for side in (1, 2, 3, 4)) if 10 in layout else None,
                "rich_text": rich_text(last(fields, 32))}

    def stroke(self, element_identifier, fields):
        image = TplImage(decode_apple_lz4(last(fields, 2)))
        values = image.read()
        stroke = {"id": element_identifier, "type": "stroke", "ink": last(fields, 3, 0),
                  "ink_name": INK_NAMES.get(last(fields, 3, 0)), "color": color(last(fields, 4)),
                  "is_highlighter": last(fields, 5) == 1, "is_tape": bool(last(fields, 20)),
                  "offset": point(last(fields, 6)) if last(fields, 6) else (0.0, 0.0),
                  "shape": self.shape(last(fields, 9)) if last(fields, 9) else None, "path_format": image.format_string}
        if image.format_string == CONSTANT_WIDTH_PATH_FORMAT:
            stroke.update(self.constant_width_path(element_identifier, values))
        elif image.format_string == VARIABLE_WIDTH_PATH_FORMAT:
            stroke.update(self.variable_width_path(element_identifier, values, is_older_layout=False))
        elif image.format_string == OLDER_VARIABLE_WIDTH_PATH_FORMAT:
            stroke.update(self.variable_width_path(element_identifier, [values[0]] + values[2:], is_older_layout=True))
            stroke["width"] = float32_from_bits(values[1])
        elif image.format_string == PENCIL_PATH_FORMAT:
            stroke.update(self.pencil_path(element_identifier, values))
        else:
            self.note_unknown("stroke path formats", image.format_string)
            return None
        return stroke

    def constant_width_path(self, element_identifier, values):
        version, width_bits, codes, starts, curves, flag, dash = values
        if version != 2 or flag != 1:
            self.note_unknown("stroke path header", (version, flag))
        subpaths, start_index, curve_index = [], 0, 0
        for code in codes:
            if code == PATH_CODE_START and start_index < len(starts):
                start_x, start_y = starts[start_index]
                subpaths.append({"start": (float32_from_bits(start_x), float32_from_bits(start_y)), "quadratic_curves": []})
                start_index += 1
            elif code == PATH_CODE_CURVE and subpaths and curve_index < len(curves):
                subpaths[-1]["quadratic_curves"].append(tuple(float32_from_bits(bits) for bits in curves[curve_index]))
                curve_index += 1
            else:
                raise FormatError(f"stroke {element_identifier}: path code {code} out of place")
        dash_pattern = [struct.unpack("<2f", struct.pack("<d", value))[0] for value in dash]
        return {"width": float32_from_bits(width_bits), "subpaths": subpaths, "dash_pattern": dash_pattern}

    def variable_width_path(self, element_identifier, values, is_older_layout):
        """A centre line with a width at each point, and the outline Goodnotes fills, one closed shape per segment."""
        (version, codes, start, curves, outline_command_counts, outline_codes, outline_starts, _,
         outline_points, cap_records, _) = values
        start = [float32_from_bits(bits) for bits in start]
        curves = [float32_from_bits(bits) for bits in curves]
        outline_starts = [float32_from_bits(bits) for bits in outline_starts]
        outline_points = [float32_from_bits(bits) for bits in outline_points]
        cap_records = [float32_from_bits(bits) for bits in cap_records]
        segment_count = len(outline_command_counts)
        centre_line = None
        if not is_older_layout and codes:
            if codes[0] not in CENTRE_LINE_START_CODES or any(code not in CENTRE_LINE_CURVE_CODES for code in codes[1:]):
                raise FormatError(f"stroke {element_identifier}: centre line codes {sorted(set(codes))}")
            curve_size = len(curves) // max(1, len(codes) - 1)
            if curve_size < 6 or curve_size * (len(codes) - 1) != len(curves):
                raise FormatError(f"stroke {element_identifier}: centre line curves do not divide evenly")
            centre_line = {"start": tuple(start[:3]), "quadratic_curves": [
                {"control": tuple(curves[index * curve_size:index * curve_size + 3]),
                 "end": tuple(curves[index * curve_size + 3:index * curve_size + 6])} for index in range(len(codes) - 1)]}
        commands = OLDER_OUTLINE_COMMANDS if is_older_layout else OUTLINE_COMMANDS
        cap_record_size = len(cap_records) // (2 * segment_count) if segment_count else 0
        outline, point_index, start_index, caps_in_segment = [], 0, 0, 0
        for code in outline_codes:
            command = commands.get(code)
            if command == "move":
                if 2 * start_index + 2 > len(outline_starts):
                    raise FormatError(f"stroke {element_identifier}: outline starts run out")
                outline.append([("move", outline_starts[2 * start_index], outline_starts[2 * start_index + 1])])
                start_index += 1
                caps_in_segment = 0
            elif command == "cubic" and outline:
                if point_index + 6 > len(outline_points):
                    raise FormatError(f"stroke {element_identifier}: outline points run out")
                outline[-1].append(("cubic",) + tuple(outline_points[point_index:point_index + 6]))
                point_index += 6
            elif command in ("round_cap", "flat_cap") and outline and cap_record_size >= 2:
                record_start = ((start_index - 1) * 2 + min(caps_in_segment, 1)) * cap_record_size
                if record_start + 2 > len(cap_records):
                    raise FormatError(f"stroke {element_identifier}: cap records run out")
                outline[-1].append((command,) + tuple(cap_records[record_start:record_start + 2]))
                caps_in_segment += 1
            else:
                raise FormatError(f"stroke {element_identifier}: outline code {code} out of place")
        return {"width": None, "tpl_version": version, "centre_line": centre_line, "outline": outline}

    def pencil_path(self, element_identifier, values):
        """Quadratic curves whose points carry x, y and three more numbers, and a 32-bit value first in each curve."""
        version, width_bits, codes, starts, curves = values[:5]
        for leftover in values[5:]:
            if leftover:
                self.note_unknown("pencil path", "non-empty trailing array")
        subpaths, start_index, curve_index = [], 0, 0
        for code in codes:
            if code == PATH_CODE_START and start_index < len(starts):
                numbers = [float32_from_bits(bits) for bits in starts[start_index]]
                subpaths.append({"start": tuple(numbers[:2]), "start_extra": tuple(numbers[2:]), "quadratic_curves": []})
                start_index += 1
            elif code == PATH_CODE_CURVE and subpaths and curve_index < len(curves):
                numbers = [float32_from_bits(bits) for bits in curves[curve_index][1:]]
                subpaths[-1]["quadratic_curves"].append({"control": tuple(numbers[:2]), "control_extra": tuple(numbers[2:5]),
                                                         "end": tuple(numbers[5:7]), "end_extra": tuple(numbers[7:10]),
                                                         "leading_value": curves[curve_index][0]})
                curve_index += 1
            else:
                raise FormatError(f"stroke {element_identifier}: pencil path code {code} out of place")
        return {"width": float32_from_bits(width_bits), "tpl_version": version, "subpaths": subpaths}

    def shape(self, buffer):
        fields = message_fields(buffer)
        for field_number in set(fields) - KNOWN_SHAPE_FIELDS:
            self.note_unknown("shape fields", field_number)
        shape = {"width": float32(last(fields, 15)) if 15 in fields else None}
        if 1 in fields:
            shape.update(kind="polyline", points=[point(member) for member in message_fields(last(fields, 1)).get(1, [])])
        elif 2 in fields:
            geometry = message_fields(last(fields, 2))
            shape.update(kind="three_points", points=[point(last(geometry, number)) for number in (1, 2, 3)])
        elif 3 in fields or 4 in fields:
            geometry = message_fields(last(fields, 3 if 3 in fields else 4))
            shape.update(kind="ellipse", center=point(last(geometry, 1)), radii=point(last(geometry, 2)),
                         angle_radians=float32(last(geometry, 3)) if 3 in geometry else 0.0)
        return shape


def summary(notebook):
    lines = [f"title: {text(notebook.title[0]) if notebook.title else ''}", f"schema version: {notebook.schema_version}"]
    for page_number, page in enumerate(notebook.ordered_pages(), start=1):
        paper = notebook.page_paper(page) or {}
        counts = {}
        for element in notebook.elements(page):
            kind = element["type"] if element["type"] != "stroke" else f"stroke ({element['ink_name'] or element['ink']})"
            counts[kind] = counts.get(kind, 0) + 1
        attachment = notebook.attachments.get(paper.get("attachment"), {})
        background = f"PDF page {paper.get('pdf_page')} of {attachment.get('file')}"
        bookmark = ", bookmarked" if page.get("bookmarked", (None,))[0] == 1 else ""
        lines.append(f"page {page_number}: {paper.get('width_points', 0):.2f} x {paper.get('height_points', 0):.2f} points, "
                     f"{background}, template {paper.get('template') or 'none'}{bookmark}, elements {counts}")
    deleted_pages = sum(1 for page in notebook.pages.values() if page.get("deleted", (None,))[0] == 1)
    if deleted_pages:
        lines.append(f"deleted pages left out: {deleted_pages}")
    for entry in sorted(notebook.outline_entries, key=lambda entry: entry["order_key"]):
        lines.append(f"outline entry: {entry['title']!r}")
    for identifier, recording in notebook.recordings.items():
        if identifier in notebook.deleted_recordings:
            continue
        times = sorted(timing["seconds"] for timing in recording["element_timings"])
        span = f", from {times[0]:.1f} s to {times[-1]:.1f} s" if times else ""
        lines.append(f"recording: {recording['file']}, {recording['seconds']:.1f} s, {len(times)} element timings{span}")
    if notebook.flagged_pages:
        lines.append(f"pages with flag 63 (meaning unknown): {len(notebook.flagged_pages)}")
    for where, what in sorted(notebook.unknown.items()):
        lines.append(f"unknown {where}: {sorted(what, key=str)}")
    if not notebook.unknown:
        lines.append("unknown: nothing")
    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("notebook", help="a .goodnotes file")
    parser.add_argument("--page", type=int, help="print this page's elements (from 1) as JSON")
    arguments = parser.parse_args()
    try:
        notebook = GoodnotesNotebook(arguments.notebook)
        if arguments.page is None:
            print(summary(notebook))
            return 0
        pages = notebook.ordered_pages()
        if not 1 <= arguments.page <= len(pages):
            print(f"the notebook has {len(pages)} pages", file=sys.stderr)
            return 2
        print(json.dumps(notebook.elements(pages[arguments.page - 1]), indent=1))
        return 0
    except (FormatError, zipfile.BadZipFile, struct.error, UnicodeDecodeError, ValueError) as error:
        print(f"cannot read {arguments.notebook}: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())

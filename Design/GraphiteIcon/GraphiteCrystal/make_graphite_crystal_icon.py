"""Draws Graphite's app icon, a graphite crystal, and writes the app's icon presets.

Usage, from the repository root: python3 -I Design/GraphiteIcon/GraphiteCrystal/make_graphite_crystal_icon.py

For each preset it writes an Icon Composer document, App/Icons/<name>.icon (icon.json and
one SVG per facet, so the system draws the glass, highlights and shadows itself), and the
Settings preview, App/IconPreviews.xcassets/AppIconPreview<color>.imageset/Artwork.png (the
crystal alone on a transparent background, as Settings draws it on the pearl background).

The crystal is a hexagonal column with a long point above and a short one below, seen with
one face toward the viewer and a little from above, leaning to the right; light comes from
the upper left. The presets differ in the sheen of the front facets.
"""
import json
import math
import os

import numpy
from PIL import Image, ImageDraw

CANVAS_SIZE = 1024
PREVIEW_SIZE = 1254
SUPERSAMPLING = 2
CENTER = (512.0, 512.0)
LEAN_DEGREES = 20.0
TARGET_HEIGHT = 830.0

COLUMN_HALF_WIDTH = 170.0
SIDE_FACE_WIDTH = 85.0
PERSPECTIVE_DROP = 26.0
SHOULDER_HEIGHT = 400.0
BASE_HEIGHT = 640.0
UPPER_APEX = (512.0, 90.0)
LOWER_APEX = (512.0, 830.0)

# Light and dark ends of each facet's gradient, top to bottom, for the facets every preset shares.
STEEL_FACETS = {
    "TipLeft": ("#EEF2F7", "#B4BFCC"),
    "TipRight": ("#5A6472", "#3A414C"),
    "ColumnLeft": ("#AEB8C5", "#6B7583"),
    "ColumnRight": ("#2F353E", "#1B1F25"),
    "PointLeft": ("#6C7684", "#454D59"),
    "PointFront": ("#323944", "#20252C"),
    "PointRight": ("#1E2228", "#121519"),
}

# Each preset's sheen: the upper point's front facet and the column's front face. Charcoal
# also darkens the steel facets.
PRESETS = [
    {"document": "AppIcon", "preview": "Blue", "group": "Graphite crystal, ink blue sheen",
     "TipFront": ("#9CC0FA", "#2D5DA1"), "ColumnFront": ("#4F6A93", "#2C3442"), "steel_darkening": 0.0},
    {"document": "AppIconRed", "preview": "Red", "group": "Graphite crystal, red sheen",
     "TipFront": ("#F7B0B5", "#C9434D"), "ColumnFront": ("#93525A", "#3A2B30"), "steel_darkening": 0.0},
    {"document": "AppIconBlack", "preview": "Black", "group": "Graphite crystal, steel",
     "TipFront": ("#C7CDD5", "#59616D"), "ColumnFront": ("#4D5664", "#2C323B"), "steel_darkening": 0.0},
    {"document": "AppIconCharcoal", "preview": "Charcoal", "group": "Graphite crystal, charcoal",
     "TipFront": ("#9AA1AB", "#3A4049"), "ColumnFront": ("#3A414C", "#1F2329"), "steel_darkening": 0.28},
    {"document": "AppIconBlueGraphite", "preview": "BlueGraphite", "group": "Graphite crystal, blue graphite sheen",
     "TipFront": ("#B5C4D6", "#3B4D60"), "ColumnFront": ("#55667A", "#2B333D"), "steel_darkening": 0.0},
]

FACET_ORDER = ["TipFront", "TipLeft", "TipRight", "ColumnLeft", "ColumnFront", "ColumnRight", "PointLeft", "PointFront", "PointRight"]
FACET_NAMES = {
    "TipFront": "Upper point, front", "TipLeft": "Upper point, left", "TipRight": "Upper point, right",
    "ColumnLeft": "Column, left", "ColumnFront": "Column, front", "ColumnRight": "Column, right",
    "PointLeft": "Lower point, left", "PointFront": "Lower point, front", "PointRight": "Lower point, right",
}

# The pearl background of the default appearance and its dark counterpart, as Icon Composer gradients.
BACKGROUND_FILLS = [
    {"value": {"linear-gradient": ["srgb:0.96471,0.97255,0.98431,1.00000", "srgb:0.83922,0.86667,0.90196,1.00000"]}},
    {"appearance": "dark", "value": {"linear-gradient": ["srgb:0.18039,0.20784,0.25098,1.00000", "srgb:0.07059,0.08235,0.10196,1.00000"]}},
]


def lean(point):
    angle = math.radians(LEAN_DEGREES)
    offset_x, offset_y = point[0] - CENTER[0], point[1] - CENTER[1]
    return (CENTER[0] + offset_x * math.cos(angle) - offset_y * math.sin(angle),
            CENTER[1] + offset_x * math.sin(angle) + offset_y * math.cos(angle))


def ring(height):
    """The four visible corners of the hexagon at one height, left to right; the near ones sit lower."""
    left_edge = CENTER[0] - COLUMN_HALF_WIDTH
    right_edge = CENTER[0] + COLUMN_HALF_WIDTH
    return [(left_edge, height), (left_edge + SIDE_FACE_WIDTH, height + PERSPECTIVE_DROP),
            (right_edge - SIDE_FACE_WIDTH, height + PERSPECTIVE_DROP), (right_edge, height)]


SHOULDER = ring(SHOULDER_HEIGHT)
BASE = ring(BASE_HEIGHT)
FACET_CORNERS = {
    "TipLeft": [SHOULDER[0], SHOULDER[1], UPPER_APEX],
    "TipFront": [SHOULDER[1], SHOULDER[2], UPPER_APEX],
    "TipRight": [SHOULDER[2], SHOULDER[3], UPPER_APEX],
    "ColumnLeft": [SHOULDER[0], SHOULDER[1], BASE[1], BASE[0]],
    "ColumnFront": [SHOULDER[1], SHOULDER[2], BASE[2], BASE[1]],
    "ColumnRight": [SHOULDER[2], SHOULDER[3], BASE[3], BASE[2]],
    "PointLeft": [BASE[0], BASE[1], LOWER_APEX],
    "PointFront": [BASE[1], BASE[2], LOWER_APEX],
    "PointRight": [BASE[2], BASE[3], LOWER_APEX],
}

# Leaning moves the crystal off center; it is placed and scaled so its bounding box is centered.
_leaned_corners = [lean(corner) for corners in FACET_CORNERS.values() for corner in corners]
_minimum_x = min(x for x, _ in _leaned_corners)
_maximum_x = max(x for x, _ in _leaned_corners)
_minimum_y = min(y for _, y in _leaned_corners)
_maximum_y = max(y for _, y in _leaned_corners)
FIT_SCALE = TARGET_HEIGHT / (_maximum_y - _minimum_y)
FIT_OFFSET = (CENTER[0] - (_minimum_x + _maximum_x) / 2 * FIT_SCALE, CENTER[1] - (_minimum_y + _maximum_y) / 2 * FIT_SCALE)


def placed(point):
    leaned = lean(point)
    return (leaned[0] * FIT_SCALE + FIT_OFFSET[0], leaned[1] * FIT_SCALE + FIT_OFFSET[1])


def hex_components(hex_color):
    return tuple(int(hex_color[index:index + 2], 16) for index in (1, 3, 5))


def darkened(hex_color, darkening):
    return "#%02X%02X%02X" % tuple(round(component * (1 - darkening)) for component in hex_components(hex_color))


def facet_colors(preset):
    colors = {name: (darkened(light, preset["steel_darkening"]), darkened(dark, preset["steel_darkening"]))
              for name, (light, dark) in STEEL_FACETS.items()}
    colors["TipFront"] = preset["TipFront"]
    colors["ColumnFront"] = preset["ColumnFront"]
    return colors


def gradient_ends(corners):
    """The facet's highest and lowest corners, which its gradient runs between."""
    placed_corners = [placed(corner) for corner in corners]
    return min(placed_corners, key=lambda point: point[1]), max(placed_corners, key=lambda point: point[1])


def facet_svg(corners, light_color, dark_color):
    placed_corners = [placed(corner) for corner in corners]
    path = "M " + " L ".join(f"{x:.1f} {y:.1f}" for x, y in placed_corners) + " Z"
    top, bottom = gradient_ends(corners)
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{CANVAS_SIZE}" height="{CANVAS_SIZE}" viewBox="0 0 {CANVAS_SIZE} {CANVAS_SIZE}">'
            f'<defs><linearGradient id="facet" gradientUnits="userSpaceOnUse" x1="{top[0]:.1f}" y1="{top[1]:.1f}" x2="{bottom[0]:.1f}" y2="{bottom[1]:.1f}">'
            f'<stop offset="0" stop-color="{light_color}"/><stop offset="1" stop-color="{dark_color}"/></linearGradient></defs>'
            f'<path d="{path}" fill="url(#facet)"/></svg>')


def icon_description(preset):
    return {
        "features": ["specular-location"],
        "fill-specializations": BACKGROUND_FILLS,
        "groups": [{
            "name": preset["group"],
            "lighting": "combined",
            "specular": "outside",
            "shadow": {"kind": "neutral", "opacity": 0.3},
            "translucency": {"enabled": True, "value": 0.1},
            "layers": [{"image-name": f"{facet}.svg", "name": FACET_NAMES[facet]} for facet in FACET_ORDER],
        }],
        "supported-platforms": {"squares": "shared"},
    }


def render_preview(colors):
    """The crystal alone, antialiased by drawing it larger and scaling it down."""
    drawing_size = PREVIEW_SIZE * SUPERSAMPLING
    scale = drawing_size / CANVAS_SIZE
    column_positions, row_positions = numpy.meshgrid(numpy.arange(drawing_size), numpy.arange(drawing_size))
    preview = numpy.zeros((drawing_size, drawing_size, 4), dtype=numpy.float64)
    for facet in FACET_ORDER:
        corners = FACET_CORNERS[facet]
        polygon = [(x * scale, y * scale) for x, y in (placed(corner) for corner in corners)]
        mask_image = Image.new("L", (drawing_size, drawing_size), 0)
        ImageDraw.Draw(mask_image).polygon(polygon, fill=255)
        is_inside = numpy.asarray(mask_image) > 0
        top, bottom = gradient_ends(corners)
        direction = ((bottom[0] - top[0]) * scale, (bottom[1] - top[1]) * scale)
        length_squared = direction[0] ** 2 + direction[1] ** 2
        position = ((column_positions - top[0] * scale) * direction[0] + (row_positions - top[1] * scale) * direction[1]) / length_squared
        position = numpy.clip(position, 0.0, 1.0)[..., None]
        light, dark = (numpy.array(hex_components(color), dtype=numpy.float64) for color in colors[facet])
        facet_color = light + (dark - light) * position
        preview[is_inside, :3] = facet_color[is_inside]
        preview[is_inside, 3] = 255
    image = Image.fromarray(preview.round().astype(numpy.uint8), "RGBA")
    return image.resize((PREVIEW_SIZE, PREVIEW_SIZE), Image.LANCZOS)


def main():
    for preset in PRESETS:
        colors = facet_colors(preset)
        document_directory = os.path.join("App", "Icons", preset["document"] + ".icon")
        assets_directory = os.path.join(document_directory, "Assets")
        os.makedirs(assets_directory, exist_ok=True)
        for leftover in os.listdir(assets_directory):
            os.remove(os.path.join(assets_directory, leftover))
        for facet in FACET_ORDER:
            light_color, dark_color = colors[facet]
            with open(os.path.join(assets_directory, f"{facet}.svg"), "w") as facet_file:
                facet_file.write(facet_svg(FACET_CORNERS[facet], light_color, dark_color))
        with open(os.path.join(document_directory, "icon.json"), "w") as description_file:
            json.dump(icon_description(preset), description_file, indent=2)
            description_file.write("\n")
        preview_directory = os.path.join("App", "IconPreviews.xcassets", f"AppIconPreview{preset['preview']}.imageset")
        render_preview(colors).save(os.path.join(preview_directory, "Artwork.png"), optimize=True)
        print("wrote", document_directory, "and its preview")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Counts that the reference readers find in every Goodnotes and Notability sample under a folder, as JSON.

The Swift readers' sample tests (GoodnotesNotebookReaderSampleTests, NotabilityNoteReaderSampleTests in
Tests/GraphiteCoreTests) compare their own counts with these, file by file. The samples are personal notebooks and are
never in the repository: the owner extracts them from the local `samples/import-formats` branch (see
Tests/GraphiteCoreTests/NotebookImportFixtures/NotebookImportSamples.swift). The output holds numbers and the names of
unknown-field categories only, keyed by each sample's path relative to the folder.

What is counted, per sample:
  Goodnotes  pages (in order, deleted left out), strokes, points (on each stroke's path: per subpath its start and two
             points per quadratic curve; a varying-width stroke's centre line the same; the older varying-width ink
             none, as its centre line is not decoded), pictures, text boxes (newer and older), fills, sticky notes,
             RTF text elements, outline segments of varying-width strokes, bookmarked pages, outline entries,
             recordings that were not deleted, the schema version and the unknown categories.
  Notability curves, points, highlighter curves, shapes, pictures, text runs, text length in UTF-16 units, PDF pages,
             recordings, timed curves, pages reached by content (none when the page height is not known) and the
             unknown categories.

Usage:
  python3 scripts/import-reference-counts.py SAMPLES_FOLDER > counts.json
"""
import importlib.util
import json
import os
import sys

# Loading the readers as modules must leave no __pycache__ folder in scripts/.
sys.dont_write_bytecode = True
SCRIPTS_FOLDER = os.path.dirname(os.path.abspath(__file__))


def load_reader(file_name, module_name):
    specification = importlib.util.spec_from_file_location(module_name, os.path.join(SCRIPTS_FOLDER, file_name))
    module = importlib.util.module_from_spec(specification)
    specification.loader.exec_module(module)
    return module


goodnotes_reader = load_reader("goodnotes-reader.py", "goodnotes_reader")
notability_reader = load_reader("notability-reader.py", "notability_reader")


def stroke_point_count(stroke):
    if "subpaths" in stroke:
        return sum(1 + 2 * len(subpath["quadratic_curves"]) for subpath in stroke["subpaths"])
    centre_line = stroke.get("centre_line")
    return 1 + 2 * len(centre_line["quadratic_curves"]) if centre_line else 0


def goodnotes_counts(path):
    notebook = goodnotes_reader.GoodnotesNotebook(path)
    counts = dict.fromkeys(["pages", "strokes", "points", "pictures", "text_boxes", "fills", "sticky_notes",
                            "rtf_text_elements", "outline_segments", "bookmarked_pages"], 0)
    element_counter = {"picture": "pictures", "text_box": "text_boxes", "rtf_text_box": "text_boxes", "fill": "fills",
                       "sticky_note": "sticky_notes", "rtf_text_element": "rtf_text_elements"}
    for page in notebook.ordered_pages():
        counts["pages"] += 1
        counts["bookmarked_pages"] += int(page.get("bookmarked", (None,))[0] == 1)
        for element in notebook.elements(page):
            if element["type"] == "stroke":
                counts["strokes"] += 1
                counts["points"] += stroke_point_count(element)
                counts["outline_segments"] += len(element.get("outline") or [])
            else:
                counts[element_counter[element["type"]]] += 1
    counts["outline_entries"] = len(notebook.outline_entries)
    counts["recordings"] = sum(1 for identifier in notebook.recordings if identifier not in notebook.deleted_recordings)
    counts["schema_version"] = notebook.schema_version
    counts["unknown"] = sorted(notebook.unknown)
    return counts


def notability_counts(path):
    note = notability_reader.NotabilityNote(path)
    lowest = max([max(y for _, y in curve["points"]) for curve in note.curves] +
                 [picture["origin"][1] + picture["size"][1] for picture in note.pictures] + [0])
    return {"curves": len(note.curves), "points": sum(len(curve["points"]) for curve in note.curves),
            "highlighter_curves": sum(curve["is_highlighter"] for curve in note.curves), "shapes": len(note.shapes),
            "pictures": len(note.pictures), "text_runs": len(note.typed_text["runs"]),
            "text_utf16_units": len(note.typed_text["text"].encode("utf-16-le")) // 2, "pdf_pages": len(note.pdf_pages),
            "recordings": len(note.recordings), "timed_curves": len(note.playback_events),
            "pages": note.page_of(lowest) if note.points_per_unit() else None, "unknown": sorted(note.unknown)}


def main():
    if len(sys.argv) != 2:
        print(__doc__.strip().splitlines()[-1].strip(), file=sys.stderr)
        return 2
    samples_folder = sys.argv[1]
    counts_by_sample = {}
    for folder, _, file_names in os.walk(samples_folder):
        for file_name in sorted(file_names):
            path = os.path.join(folder, file_name)
            if file_name.endswith(".goodnotes"):
                counts_by_sample[os.path.relpath(path, samples_folder)] = goodnotes_counts(path)
            elif file_name.endswith(".note"):
                counts_by_sample[os.path.relpath(path, samples_folder)] = notability_counts(path)
    print(json.dumps(counts_by_sample, indent=1, sort_keys=True))
    return 0


if __name__ == "__main__":
    sys.exit(main())

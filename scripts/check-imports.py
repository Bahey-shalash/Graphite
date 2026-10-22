#!/usr/bin/env python3
"""The import rules of Docs/solid/rewrite-foundations.md section 3.2 and 3.3, applied to today's module folders.

Today's modules are the folders under Sources/ (GraphiteCore, GraphiteIndex, GraphiteApple, GraphiteVoices,
GraphitePostgreSQLMirror, GraphiteUI, GraphiteBenchmarks) and the app target (App/*.swift). Each module has a row below, taken from the section 3.2 table:
the Graphite modules it may import and the frameworks it may import. The script reads the `import` lines of every Swift
file (comments and strings removed) and reports:

  * a Graphite module imported by a module whose row does not list it ("nothing imports a module above it"; for example
    GraphiteCore importing GraphiteIndex, or any module importing GraphiteUI);
  * a framework imported by a module whose row does not list it (GraphiteCore imports no UI or platform framework beyond
    Foundation, CoreGraphics, CryptoKit, zlib, Synchronization, Markdown and Yams; MLX only in GraphiteVoices, GRDB only
    in GraphiteIndex, Markdown and Yams only in GraphiteCore);
  * a dependency in Package.swift that the module's row does not allow;
  * a Graphite module imported by a standalone package under Packages/ (section 3.5: a package knows nothing of Graphite);
  * target-state confinement inside GraphiteUI, which is one module today: how many of its files import GraphiteIndex
    (features never import the index, section 3.3 rule 3), Textual (only the editor and rendering modules), WebKit (only
    plugins) and MapKit (only Bases and the graph and map views). These counts only go down as the feature modules are cut.

Today's violations are recorded in scripts/import-baselines.json, one count per `<module> imports <name>`. The script
fails when a count rises or a new violation appears; the baseline only goes down. The rows are data at the top of this
file: a framework the table does not list but a module legitimately needs is added to its row in the same commit that
explains it in rewrite-foundations.md section 3.2.

Usage:
  python3 scripts/check-imports.py                check against scripts/import-baselines.json (exit 1 on a new violation)
  python3 scripts/check-imports.py --list         print every violation with its files, then check
  python3 scripts/check-imports.py --record       lower the baselines to today's counts (creates the file when it is missing)
  python3 scripts/check-imports.py --strict       also fail when a count is below its baseline (stale baseline)
  python3 scripts/check-imports.py --root <path>  check another checkout (default: the repository)
"""
import argparse
import datetime
import json
import os
import re
import subprocess
import sys
from collections import defaultdict

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from graphite_source_scanning import REPOSITORY_ROOT, SourceTree  # noqa: E402

BASELINE_PATH = os.path.join("scripts", "import-baselines.json")

# Frameworks the Core row lists that carry no I/O and no UI: every module may use them (section 3.2, row GraphiteCore).
FOUNDATIONAL_FRAMEWORKS = {"Foundation", "CoreGraphics", "CryptoKit", "zlib", "Synchronization"}
# Language and logging runtime that every module except GraphiteCore uses (not in the table; an interpretation, listed here).
RUNTIME_FRAMEWORKS = {"Swift", "Observation", "os", "OSLog"}

# Standalone packages under Packages/ (section 3.5): they know nothing of Graphite, so every module may import them, and
# none of them may import a Graphite module.
STANDALONE_PACKAGES = {"NotebookImport"}

# Section 3.2 rows for today's modules. "modules" are Graphite modules it may import; "frameworks" are the system and
# third-party frameworks it may import beyond FOUNDATIONAL_FRAMEWORKS and RUNTIME_FRAMEWORKS. `prefixes` allow a family.
MODULE_ROWS = {
    "GraphiteCore": {
        "folders": ["Sources/GraphiteCore"],
        "modules": set(),
        "frameworks": {"Markdown", "Yams"},
        "allows_runtime": False,
    },
    "GraphiteIndex": {
        "folders": ["Sources/GraphiteIndex"],
        "modules": {"GraphiteCore"},
        "frameworks": {"GRDB"},
        "allows_runtime": True,
    },
    "GraphiteApple": {
        "folders": ["Sources/GraphiteApple"],
        "modules": {"GraphiteCore"},
        "frameworks": {"UIKit", "AppKit", "PDFKit", "PencilKit", "AVFoundation", "Vision", "Security", "MetricKit", "ImageIO",
                       "CoreText", "CoreImage", "QuickLookThumbnailing", "UniformTypeIdentifiers"},
        "allows_runtime": True,
    },
    "GraphiteVoices": {
        "folders": ["Sources/GraphiteVoices"],
        "modules": {"GraphiteCore", "GraphiteApple"},
        "frameworks": set(),
        "framework_prefixes": ("MLX",),
        "allows_runtime": True,
    },
    "GraphitePostgreSQLMirror": {
        # The PostgreSQL Mirror core plugin: a one-way copy of the index into a PostgreSQL database (section 3.2, added 2026-10-22).
        "folders": ["Sources/GraphitePostgreSQLMirror"],
        "modules": {"GraphiteCore", "GraphiteIndex"},
        "frameworks": {"PostgresNIO"},
        "allows_runtime": True,
    },
    "GraphiteUI": {
        "folders": ["Sources/GraphiteUI"],
        "modules": {"GraphiteCore", "GraphiteIndex", "GraphiteApple", "GraphiteVoices", "GraphitePostgreSQLMirror"},
        "frameworks": {"SwiftUI", "UIKit", "AppKit", "Textual", "PDFKit", "PencilKit", "WebKit", "MapKit", "AVFoundation", "MediaPlayer",
                       "VisionKit", "PhotosUI", "UniformTypeIdentifiers"},
        "allows_runtime": True,
    },
    "GraphiteBenchmarks": {
        "folders": ["Sources/GraphiteBenchmarks"],
        "modules": {"GraphiteCore", "GraphiteIndex", "GraphiteVoices"},
        "frameworks": set(),
        "allows_runtime": True,
    },
    "App": {
        # The composition root imports every module above it, never the benchmark tool (section 3.2, rows App target and GraphiteBenchmarks).
        "folders": ["App"],
        "exclude_folders": ["App/Tests"],
        "modules": {"GraphiteCore", "GraphiteIndex", "GraphiteApple", "GraphiteVoices", "GraphiteUI"},
        "frameworks": {"SwiftUI", "UIKit", "AppKit"},
        "allows_runtime": True,
    },
}
GRAPHITE_MODULES = {name for name in MODULE_ROWS if name != "App"}

# Target-state confinement inside GraphiteUI (section 3.3 rules 3 and 5): the module names that only some feature modules may import.
CONFINED_IN_INTERFACE_MODULE = {
    "GraphiteIndex": "features never import the index (3.3 rule 3)",
    "Textual": "only GraphiteMarkdownRendering and GraphiteMarkdownEditing (3.3 rule 5)",
    "WebKit": "only GraphitePlugins (3.3 rule 5)",
    "MapKit": "only GraphiteBases and GraphiteGraphAndMap (3.3 rule 5)",
}

# Reviewed exceptions to the confinement: files of GraphiteUI that are composition, not a feature, and so may name what they
# build. Each moves to the composition root (section 4.2) with Phase 2.
COMPOSITION_FILES_IN_INTERFACE_MODULE = {
    "Sources/GraphiteUI/ProcessServices.swift": {
        "GraphiteIndex": "the process services hold the registry of each open vault's index, shared by its windows "
                         "(decision 12; Docs/Multiple-windows-todo.md)",
    },
}

IMPORT_PATTERN = re.compile(
    r"^[ \t]*(?:@\w+(?:\([^)\n]*\))?[ \t]+)*(?:(?:public|internal|package|private|fileprivate)[ \t]+)?import[ \t]+"
    r"(?:(?:class|struct|enum|protocol|typealias|func|var|let)[ \t]+)?([A-Za-z_]\w*)", re.MULTILINE)


def imported_modules(file):
    """The top-level module names imported by a file (`import UIKit.UIGestureRecognizerSubclass` is UIKit)."""
    return sorted(set(IMPORT_PATTERN.findall(file.stripped_text)))


def framework_is_allowed(row, name):
    if name in FOUNDATIONAL_FRAMEWORKS or name in STANDALONE_PACKAGES or name in row["frameworks"]:
        return True
    if row.get("allows_runtime") and name in RUNTIME_FRAMEWORKS:
        return True
    return any(name.startswith(prefix) for prefix in row.get("framework_prefixes", ()))


def collect_violations(tree):
    """{key: [files]} for every import the section 3.2 rows do not allow, plus the Package.swift dependencies and UI confinement."""
    violations = defaultdict(list)
    for module, row in MODULE_ROWS.items():
        files = tree.files(row["folders"], exclude_directories=row.get("exclude_folders", ()))
        for file in files:
            for name in imported_modules(file):
                if name == module:
                    continue
                if name in GRAPHITE_MODULES:
                    if name not in row["modules"]:
                        violations[f"{module} imports {name}"].append(file.relative_path)
                elif not framework_is_allowed(row, name):
                    violations[f"{module} imports {name}"].append(file.relative_path)
            if module == "GraphiteUI":
                for name, why in CONFINED_IN_INTERFACE_MODULE.items():
                    if name in COMPOSITION_FILES_IN_INTERFACE_MODULE.get(file.relative_path, {}):
                        continue
                    if name in imported_modules(file):
                        violations[f"target-state: GraphiteUI files import {name} ({why})"].append(file.relative_path)
    for file in tree.files(["Packages"]):
        for name in imported_modules(file):
            if name in GRAPHITE_MODULES:
                violations[f"Packages imports {name} (a standalone package knows nothing of Graphite, 3.5)"].append(file.relative_path)
    for key, files in package_dependency_violations(tree.root).items():
        violations[key].extend(files)
    return violations


def package_dependency_violations(root):
    """Package.swift lists exactly the dependencies of a row (3.3 rule 1): report a Graphite module a target lists beyond its row."""
    violations = defaultdict(list)
    path = os.path.join(root, "Package.swift")
    if not os.path.exists(path):
        return violations
    with open(path, encoding="utf-8") as handle:
        text = handle.read()
    for match in re.finditer(r'\.(?:target|executableTarget)\(\s*name:\s*"(\w+)"\s*,\s*dependencies:\s*\[(.*?)\]', text, re.DOTALL):
        target, dependencies = match.group(1), match.group(2)
        row = MODULE_ROWS.get(target)
        if row is None:
            continue
        for dependency in re.findall(r'"(Graphite\w+)"', dependencies):
            if dependency in GRAPHITE_MODULES and dependency not in row["modules"]:
                violations[f"Package.swift: {target} depends on {dependency}"].append("Package.swift")
    return violations


def load_baselines(path):
    if not os.path.exists(path):
        return None
    with open(path, encoding="utf-8") as handle:
        return json.load(handle).get("violations", {})


def current_revision(root):
    try:
        return subprocess.run(["git", "-C", root, "rev-parse", "--short", "HEAD"], capture_output=True, text=True, check=True).stdout.strip()
    except (OSError, subprocess.CalledProcessError):
        return "unknown"


def write_baselines(path, root, counts):
    document = {
        "schemaVersion": 1,
        "comment": "Import violations of Docs/solid/rewrite-foundations.md section 3.2 and 3.3 at today's module folders: one count of files per `<module> imports <name>`. They only go down. Lower them with `python3 scripts/check-imports.py --record`.",
        "recordedOn": datetime.date.today().isoformat(),
        "recordedAtRevision": current_revision(root) + " plus the working tree",
        "violations": dict(sorted(counts.items())),
    }
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as handle:
        json.dump(document, handle, indent=2)
        handle.write("\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--root", default=REPOSITORY_ROOT)
    parser.add_argument("--list", action="store_true", help="print every violation with its files")
    parser.add_argument("--record", action="store_true", help="lower baselines to today's counts (creates the file when missing)")
    parser.add_argument("--allow-raise", action="store_true", help="with --record: also raise or add a baseline (a reviewed exception only)")
    parser.add_argument("--strict", action="store_true", help="fail when a count is below its baseline too")
    arguments = parser.parse_args()

    tree = SourceTree(arguments.root)
    violations = collect_violations(tree)
    counts = {key: len(sorted(set(files))) for key, files in violations.items()}
    baseline_path = os.path.join(arguments.root, BASELINE_PATH)
    baselines = load_baselines(baseline_path)

    if arguments.list:
        for key in sorted(violations):
            print(f"{key}: {counts[key]}")
            for path in sorted(set(violations[key])):
                print(f"    {path}")

    if arguments.record:
        if baselines is None:
            merged = dict(counts)
        else:
            merged = {}
            for key, count in counts.items():
                if key in baselines:
                    merged[key] = min(baselines[key], count) if not arguments.allow_raise else count
                elif arguments.allow_raise:
                    merged[key] = count
        write_baselines(baseline_path, arguments.root, merged)
        print(f"recorded {len(merged)} violation baselines in {BASELINE_PATH}")
        return 0

    if baselines is None:
        print(f"FAIL no {BASELINE_PATH}: run `python3 scripts/check-imports.py --record` once and commit it")
        return 1

    failures = 0
    stale = 0
    for key in sorted(set(counts) | set(baselines)):
        count = counts.get(key, 0)
        baseline = baselines.get(key, 0)
        if count > baseline:
            failures += 1
            files = sorted(set(violations[key]))
            shown = ", ".join(files[:6]) + (f", and {len(files) - 6} more" if len(files) > 6 else "")
            print(f"FAIL  {key}: {count} file(s), baseline {baseline}: {shown}")
        elif count < baseline:
            stale += 1
            if arguments.strict:
                failures += 1
            print(f"{'FAIL' if arguments.strict else 'LOWER'}  {key}: {count} file(s), baseline {baseline}: run --record to lower it")
    total_files = sum(counts.values())
    print(f"{len(counts)} violation kinds in {total_files} file imports today; {len(baselines)} baselined.")
    if failures:
        print("\nFix the import (the section 3.2 row says what each module may import), or, for a framework the table "
              "leaves out on purpose, extend the row in scripts/check-imports.py together with section 3.2 of "
              "Docs/solid/rewrite-foundations.md. A baseline only goes down: after fixing run "
              "`python3 scripts/check-imports.py --record`.")
    elif stale:
        print(f"{stale} baseline(s) are above today's count: run `python3 scripts/check-imports.py --record` and commit {BASELINE_PATH}.")
    else:
        print("every module imports only what its row allows, up to the recorded baseline.")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())

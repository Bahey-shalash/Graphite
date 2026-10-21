#!/usr/bin/env python3
"""Check that every priority 1 and 2 invariant row is pinned by a test that exists.

Reads Docs/solid/invariants.md. A row of a priority 1 or 2 prefix (persisted formats and
keys, security) passes when one of these holds:
  - the "Pinned by tests" table lists it as Pinned or Partly pinned, and every test class it
    names is declared under Tests/ or App/Tests/ (or every runtime test file it names exists);
  - it is struck through (retired or fixed), and the table pins it, or it names no state;
  - it is not in the table and its Test idea names at least one existing test class or test
    file ("Existing ..."; a test idea may also name the class a later phase renames it to).
A row whose state is "Needs a seam", or that still starts its Test idea with "No test today."
and is not in the table, fails. Partly pinned rows are listed with what they leave unpinned.
Whether the tests pass is CI's job; this script checks that each pin exists.

Usage: python3 scripts/check-invariant-pins.py [--verbose]
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
INVARIANTS = ROOT / "Docs" / "solid" / "invariants.md"
TEST_FOLDERS = [ROOT / "Tests", ROOT / "App" / "Tests"]
RUNTIME_TESTS = ROOT / "Tests" / "CommunityPluginRuntimeTests" / "tests"
PRIORITY_PREFIXES = ["M", "ST", "OB", "D", "NM", "IX", "PL", "EX", "SEC"]
ROW = re.compile(r"^\| (~~)?([A-Z]+)-(\d+)(~~)? \| (.*)$")
PIN_ROW = re.compile(r"^\| ([A-Z]+-\d+) \| ([^|]+) \| ([^|]*) \| (.*)\|\s*$")
TEST_CLASS_NAME = re.compile(r"\b([A-Z][A-Za-z0-9]+Tests)\b")
RUNTIME_TEST_FILE = re.compile(r"\b([a-z0-9-]+\.test\.js)\b")


def declared_test_classes():
    names = set()
    declaration = re.compile(r"^\s*(?:final\s+|@MainActor\s+|private\s+)*class\s+([A-Za-z0-9_]+)\s*:", re.MULTILINE)
    for folder in TEST_FOLDERS:
        for path in folder.rglob("*.swift"):
            names.update(declaration.findall(path.read_text(encoding="utf-8", errors="replace")))
            names.add(path.stem)  # a document may name a test file that holds several classes
    return names


def main():
    verbose = "--verbose" in sys.argv[1:]
    text = INVARIANTS.read_text(encoding="utf-8")
    body, _, after = text.partition("\n## Pinned by tests\n")
    pin_section = after.split("\n## Rows with no test today", 1)[0]

    rows = {}
    for line in body.splitlines():
        match = ROW.match(line)
        if match and match.group(2) in PRIORITY_PREFIXES:
            identifier = f"{match.group(2)}-{match.group(3)}"
            rows[identifier] = line

    pins = {}
    for line in pin_section.splitlines():
        match = PIN_ROW.match(line)
        if match:
            pins[match.group(1)] = (match.group(2).strip(), match.group(3).strip(), match.group(4).strip())

    classes = declared_test_classes()
    failures, partial = [], []
    for identifier, line in sorted(rows.items()):
        struck = line.startswith(f"| ~~{identifier}")
        if identifier in pins:
            state, tests, gap = pins[identifier]
            if state not in ("Pinned", "Partly pinned"):
                failures.append(f"{identifier}: {state} ({gap or tests})")
                continue
            named_classes = TEST_CLASS_NAME.findall(tests)
            named_files = RUNTIME_TEST_FILE.findall(tests)
            if not named_classes and not named_files:
                failures.append(f"{identifier}: {state} but names no test class")
                continue
            missing = [name for name in named_classes if name not in classes]
            missing += [name for name in named_files if not (RUNTIME_TESTS / name).exists()]
            if missing:
                failures.append(f"{identifier}: names tests that do not exist: {', '.join(missing)}")
            elif state == "Partly pinned":
                partial.append(f"{identifier}: {gap}")
            continue
        cells = [cell.strip() for cell in line.split("|")]
        test_idea = cells[4] if len(cells) > 4 else ""
        if struck or not test_idea.startswith("**No test today.**"):
            named_classes = TEST_CLASS_NAME.findall(test_idea)
            if named_classes and not any(name in classes for name in named_classes):
                failures.append(f"{identifier}: its test idea names no test that exists: {', '.join(named_classes)}")
            continue
        failures.append(f"{identifier}: no test today")

    print(f"{len(rows)} priority 1 and 2 rows: {len(rows) - len(failures)} pinned "
          f"({len(partial)} of them in part), {len(failures)} not pinned.")
    if verbose:
        for entry in partial:
            print(f"  partly pinned  {entry}")
    for entry in failures:
        print(f"  not pinned     {entry}")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())

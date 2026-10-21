#!/usr/bin/env python3
"""Check that every defect of the audit's "Fix before the cleanup starts" list has a regression test.

Reads the defect IDs of that section of Docs/solid/defects.md and the table "Regression tests of
the audit's defects" of Docs/Coverage.md. Every listed defect needs a row, and every row's test
must exist:
  - a Swift test `Class.testMethod` is a `func testMethod(` in a file under Tests/ or App/Tests/
    that declares `class Class`;
  - a runtime test `name.test.js: title` is a test of that title in
    Tests/CommunityPluginRuntimeTests/tests/name.test.js.
Whether the tests pass is CI's job (the package, hosted and Node jobs run them).

Usage: python3 scripts/check-defect-tests.py
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
DEFECTS = ROOT / "Docs" / "solid" / "defects.md"
COVERAGE = ROOT / "Docs" / "Coverage.md"
TEST_FOLDERS = [ROOT / "Tests", ROOT / "App" / "Tests"]
RUNTIME_TESTS = ROOT / "Tests" / "CommunityPluginRuntimeTests" / "tests"
DEFECT_ID = re.compile(r"^\| \[?(BUG-[A-Z]+-[A-Z]?\d+)")
TABLE_ROW = re.compile(r"^\| (BUG-[A-Z]+-[A-Z]?\d+) \| ([^|]+) \| `([^`]+)` \|\s*$")
SWIFT_TEST = re.compile(r"^([A-Za-z0-9_]+)\.(test[A-Za-z0-9_]+)$")
RUNTIME_TEST = re.compile(r"^([a-z0-9-]+\.test\.js): (.+)$")


def section(text, heading):
    start = text.index(f"\n## {heading}\n")
    end = text.find("\n## ", start + 1)
    return text[start:end if end != -1 else len(text)]


def swift_test_exists(class_name, method_name, sources):
    declaration = re.compile(rf"\bclass\s+{re.escape(class_name)}\s*:")
    method = re.compile(rf"\bfunc\s+{re.escape(method_name)}\s*\(")
    return any(declaration.search(source) and method.search(source) for source in sources)


def runtime_test_exists(file_name, title):
    path = RUNTIME_TESTS / file_name
    if not path.exists():
        return False
    source = path.read_text(encoding="utf-8")
    return any(f"test({quote}{title.replace(quote, chr(92) + quote)}{quote}" in source for quote in "'\"`")


def main():
    required = []
    for line in section(DEFECTS.read_text(encoding="utf-8"), "Fix before the cleanup starts").splitlines():
        match = DEFECT_ID.match(line)
        if match and match.group(1) not in required:
            required.append(match.group(1))

    rows = {}
    for line in section(COVERAGE.read_text(encoding="utf-8"), "Regression tests of the audit's defects").splitlines():
        match = TABLE_ROW.match(line)
        if match:
            rows.setdefault(match.group(1), []).append(match.group(3))

    sources = [path.read_text(encoding="utf-8", errors="replace")
               for folder in TEST_FOLDERS for path in folder.rglob("*.swift")]
    failures = [f"{defect}: no row in Docs/Coverage.md" for defect in required if defect not in rows]
    for defect, tests in sorted(rows.items()):
        for test in tests:
            swift = SWIFT_TEST.match(test)
            runtime = RUNTIME_TEST.match(test)
            if swift and swift_test_exists(swift.group(1), swift.group(2), sources):
                continue
            if runtime and runtime_test_exists(runtime.group(1), runtime.group(2)):
                continue
            failures.append(f"{defect}: the test {test} does not exist")

    print(f"{len(required)} defects to fix before the cleanup; {len(rows)} defects with a regression test row; "
          f"{len(failures)} problems.")
    for failure in failures:
        print(f"  {failure}")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())

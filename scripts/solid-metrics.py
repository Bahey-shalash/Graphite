#!/usr/bin/env python3
"""Reproduce the measurements in Docs/solid/metrics.md.

Production Swift is Sources/**/*.swift plus App/GraphiteApp.swift; test Swift is Tests/** and App/Tests/**.
Code lines and pattern counts use the comment- and string-stripping of scripts/size-report.py, so a
pattern inside a comment or a string literal is not counted. Prints Markdown tables.

Usage: python3 scripts/solid-metrics.py [--root <checkout>]
"""
import argparse
import collections
import importlib.util
import os
import re

HERE = os.path.dirname(os.path.abspath(__file__))
specification = importlib.util.spec_from_file_location("size_report", os.path.join(HERE, "size-report.py"))
size_report = importlib.util.module_from_spec(specification)
specification.loader.exec_module(size_report)

PATTERNS = [
    ("try?", r"\btry\?"),
    ("try!", r"\btry!"),
    ("empty catch block", r"catch\s*(\w+\s*)?\{\s*\}"),
    ("sleep (Task.sleep, sleep, usleep)", r"Task\.sleep|\bsleep\(|usleep\(|Thread\.sleep"),
    ("DispatchQueue asyncAfter", r"asyncAfter\("),
    ("uses of .shared", r"\.shared\b"),
    ("static let/var shared declarations", r"static\s+(let|var)\s+shared\b"),
    ("static var", r"\bstatic\s+var\b"),
    ("nonisolated(unsafe)", r"nonisolated\(unsafe\)"),
    ("@unchecked Sendable", r"@unchecked\s+Sendable"),
    ("MainActor.assumeIsolated", r"assumeIsolated"),
    ("Date() and Date.now", r"\bDate\(\)|\bDate\.now\b"),
    ("other clock reads", r"CFAbsoluteTimeGetCurrent|systemUptime|DispatchTime\.now|ContinuousClock|SuspendingClock"),
    ("UserDefaults", r"\bUserDefaults\b"),
    ("FileManager.default", r"FileManager\.default"),
    ("URLSession", r"\bURLSession\b"),
    ("NotificationCenter.default", r"NotificationCenter\.default"),
    ("default: in a switch", r"^\s*default\s*:"),
    ("[String: Any]", r"\[String\s*:\s*Any\??\]"),
    ("unstructured Task { } and Task.detached", r"\bTask\s*(\(priority[^)]*\))?\s*\{|Task\.detached"),
    ("DispatchQueue.main", r"DispatchQueue\.main"),
    ("fatalError / preconditionFailure", r"fatalError\(|preconditionFailure\("),
    ("#if os(...)", r"#if\s+os\(|#elseif\s+os\("),
]
TEST_PATTERNS = [
    ("sleeps", r"Task\.sleep|usleep|Thread\.sleep|\bsleep\("),
    ("UserDefaults.standard", r"UserDefaults\.standard"),
    ("XCTest functions", r"func test[A-Z0-9_]\w*\("),
]


def swift_files(root, directories, include_tests):
    for directory in directories:
        for folder, folders, files in os.walk(os.path.join(root, directory)):
            if not include_tests:
                folders[:] = [name for name in folders if name != "Tests"]
            for name in sorted(files):
                if name.endswith(".swift"):
                    yield os.path.relpath(os.path.join(folder, name), root)


def module_of(relative):
    parts = relative.split(os.sep)
    if parts[0] in ("Sources", "Tests") and len(parts) > 2:
        return "/".join(parts[:2])
    if parts[0] == "App" and len(parts) > 2:
        return "App/Tests"
    return parts[0] if parts[0] == "App" else "(root)"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", default=os.path.dirname(HERE))
    root = parser.parse_args().root
    production = [path for path in swift_files(root, ("Sources", "App"), False)]
    tests = [path for path in swift_files(root, ("Tests", "App/Tests"), True)]
    inventory = collections.defaultdict(lambda: [0, 0, 0])
    pattern_counts = collections.Counter()
    for relative in production + tests:
        text = open(os.path.join(root, relative), encoding="utf-8", errors="replace").read()
        stripped = size_report.strip_comments_and_strings(text)
        row = inventory[module_of(relative)]
        row[0] += 1
        row[1] += text.count("\n") + (0 if text.endswith("\n") or not text else 1)
        row[2] += sum(1 for line in stripped.split("\n") if line.strip())
        if relative in production:
            for name, pattern in PATTERNS:
                pattern_counts[name] += len(re.findall(pattern, stripped, re.M))
        else:
            for name, pattern in TEST_PATTERNS:
                pattern_counts[(module_of(relative), name)] += len(re.findall(pattern, text, re.M))
    print("| Module | Files | Physical lines | Code lines |\n| --- | ---: | ---: | ---: |")
    for module, (files, physical, code) in sorted(inventory.items(), key=lambda item: -item[1][2]):
        print(f"| `{module}` | {files} | {physical:,} | {code:,} |")
    print("\n| Pattern (production Swift) | Count | Regular expression |\n| --- | ---: | --- |")
    for name, pattern in PATTERNS:
        print(f"| {name} | {pattern_counts[name]} | `{pattern.replace('|', chr(92) + '|')}` |")
    print("\n| Test module | Sleeps | UserDefaults.standard | XCTest functions |\n| --- | ---: | ---: | ---: |")
    for module in sorted({key[0] for key in pattern_counts if isinstance(key, tuple)}):
        print(f"| `{module}` | " + " | ".join(str(pattern_counts[(module, name)]) for name, _ in TEST_PATTERNS) + " |")


if __name__ == "__main__":
    main()

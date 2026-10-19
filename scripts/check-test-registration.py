#!/usr/bin/env python3
"""Fail when a test file would never run: tests are discovered, not registered (testing.md TR 1, section 4.8 `registration-check`).

Two checks, both over files that contain a `func test` method:

  * Package tests: a file under Tests/<Folder>/ runs only if Package.swift declares a `.testTarget(name: "<Folder>")`
    (SwiftPM finds files by folder, so the folder must be declared once).
  * Hosted tests: a file under App/Tests/ runs only if the hosted target `GraphiteIntegrationTests` in
    Graphite.xcodeproj takes the folder as a synchronized group, or lists the file in a target membership exception.

The hosted check reads the project text (groups, synchronized root groups and the target's `fileSystemSynchronizedGroups`),
so it needs no Xcode. Exit status 0 when every test file is registered, 1 otherwise.

Usage:
  python3 scripts/check-test-registration.py [--root <path>]
"""
import argparse
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from graphite_source_scanning import REPOSITORY_ROOT, SourceTree  # noqa: E402

HOSTED_TARGET_NAME = "GraphiteIntegrationTests"
TEST_METHOD_PATTERN = re.compile(r"\bfunc\s+test\w*\s*\(")


def files_with_test_methods(tree, directory):
    return [file for file in tree.files([directory]) if TEST_METHOD_PATTERN.search(file.stripped_text)]


def declared_package_test_targets(root):
    """{folder: target name} for each `.testTarget(name:)` of Package.swift (one declaration per statement start)."""
    with open(os.path.join(root, "Package.swift"), encoding="utf-8") as handle:
        text = handle.read()
    declared = {}
    for statement in re.split(r"(?=\.(?:testTarget|target|executableTarget|binaryTarget|plugin)\()", text):
        match = re.match(r'\.testTarget\(\s*name:\s*"(\w+)"', statement)
        if match:
            path = re.search(r'path:\s*"([^"]+)"', statement)
            declared[path.group(1) if path else f"Tests/{match.group(1)}"] = match.group(1)
    return declared


def project_blocks(text, section_isa):
    """{identifier: block text} of every object with the given `isa` in a project file."""
    blocks = {}
    for match in re.finditer(r"^\t\t(\w{24})(?: /\*.*?\*/)? = \{(.*?)^\t\t\};", text, re.DOTALL | re.MULTILINE):
        if f"isa = {section_isa};" in match.group(2):
            blocks[match.group(1)] = match.group(2)
    return blocks


def hosted_synchronized_folders_and_exceptions(root):
    """(set of folders taken by the hosted target, set of file paths named in its membership exceptions)."""
    with open(os.path.join(root, "Graphite.xcodeproj", "project.pbxproj"), encoding="utf-8") as handle:
        text = handle.read()
    groups = project_blocks(text, "PBXGroup")
    synchronized = project_blocks(text, "PBXFileSystemSynchronizedRootGroup")
    exceptions = project_blocks(text, "PBXFileSystemSynchronizedBuildFileExceptionSet")
    targets = project_blocks(text, "PBXNativeTarget")
    hosted = next((block for block in targets.values() if f"name = {HOSTED_TARGET_NAME};" in block), None)
    if hosted is None:
        return set(), set()
    listed = re.search(r"fileSystemSynchronizedGroups = \((.*?)\);", hosted, re.DOTALL)
    group_identifiers = re.findall(r"\b(\w{24})\b", listed.group(1)) if listed else []

    def folder_of(identifier):
        block = synchronized.get(identifier) or groups.get(identifier)
        path = re.search(r"\bpath = \"?([^;\"]+)\"?;", block or "")
        parts = [path.group(1)] if path else []
        for parent_identifier, parent in groups.items():
            children = re.search(r"children = \((.*?)\);", parent, re.DOTALL)
            if children and identifier in children.group(1) and parent_identifier != identifier:
                return folder_of(parent_identifier) + parts
        return parts

    folders = {"/".join(folder_of(identifier)) for identifier in group_identifiers if identifier in synchronized}
    excluded = set()
    for identifier in group_identifiers:
        block = synchronized.get(identifier, "")
        for exception_identifier in re.findall(r"\b(\w{24})\b", re.search(r"exceptions = \((.*?)\);", block, re.DOTALL).group(1) if "exceptions = (" in block else ""):
            exception = exceptions.get(exception_identifier, "")
            if f"target = " in exception:
                members = re.search(r"membershipExceptions = \((.*?)\);", exception, re.DOTALL)
                for name in re.findall(r"([^\s,()]+)", members.group(1) if members else ""):
                    excluded.add("/".join(folder_of(identifier) + [name]))
    return folders, excluded


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--root", default=REPOSITORY_ROOT)
    arguments = parser.parse_args()
    tree = SourceTree(arguments.root)
    problems = 0

    declared = declared_package_test_targets(arguments.root)
    package_files = files_with_test_methods(tree, "Tests")
    unregistered_folders = {}
    for file in package_files:
        folder = os.path.dirname(file.relative_path).split(os.sep)
        folder_path = "/".join(folder[:2])
        if folder_path not in declared:
            unregistered_folders.setdefault(folder_path, []).append(file.relative_path)
    for folder_path, files in sorted(unregistered_folders.items()):
        print(f"FAIL {folder_path}: {len(files)} file(s) with test methods, but Package.swift declares no .testTarget for it (first: {files[0]})")
        problems += 1
    print(f"package tests: {len(package_files)} files with test methods in {len(declared)} declared test targets")

    folders, excluded = hosted_synchronized_folders_and_exceptions(arguments.root)
    hosted_files = files_with_test_methods(tree, "App/Tests")
    for file in hosted_files:
        path = file.relative_path.replace(os.sep, "/")
        inside_synchronized_folder = any(path.startswith(folder + "/") for folder in folders)
        if not inside_synchronized_folder or path in excluded:
            print(f"FAIL {path}: not a member of {HOSTED_TARGET_NAME} (its folder is not a synchronized group of the target, or the file is excluded)")
            problems += 1
    print(f"hosted tests: {len(hosted_files)} files with test methods; {HOSTED_TARGET_NAME} synchronizes {sorted(folders) or 'no folder'}")
    if problems:
        print(f"\n{problems} problem(s): a test file that no target compiles never runs. Declare the Package test target, or take the folder as a synchronized group of {HOSTED_TARGET_NAME}.")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())

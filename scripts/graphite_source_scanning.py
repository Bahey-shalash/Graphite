"""Shared reading of Graphite's Swift sources for scripts/check-rules.py and scripts/check-imports.py.

Counting is done on text with comments and string contents removed, so a rule name quoted in a comment or a
string literal never counts. The stripping is `strip_comments_and_strings` of scripts/size-report.py, loaded
from that file so the two scripts cannot disagree about what a code line is.
"""
import importlib.util
import os
import re

SCRIPTS_DIRECTORY = os.path.dirname(os.path.abspath(__file__))
REPOSITORY_ROOT = os.path.dirname(SCRIPTS_DIRECTORY)

PRODUCTION_DIRECTORIES = ("Sources", "App")
TEST_DIRECTORIES = ("Tests", "App/Tests")
IGNORED_DIRECTORY_NAMES = {".build", ".swiftpm", "node_modules", "DerivedData", "test_vault", "BaseSampleVault", "built"}
# iCloud writes "Name 2.swift" beside a file it could not merge; such a copy breaks the build and is not source.
CONFLICT_COPY_PATTERN = re.compile(r" \d+\.swift$")


def load_size_report_module():
    """Import scripts/size-report.py (its file name has a hyphen, so `import` cannot name it)."""
    specification = importlib.util.spec_from_file_location("graphite_size_report", os.path.join(SCRIPTS_DIRECTORY, "size-report.py"))
    module = importlib.util.module_from_spec(specification)
    specification.loader.exec_module(module)
    return module


SIZE_REPORT = load_size_report_module()
strip_comments_and_strings = SIZE_REPORT.strip_comments_and_strings
TYPE_PATTERN = SIZE_REPORT.TYPE_PATTERN
MEMBER_KEYWORDS_AFTER_CLASS = SIZE_REPORT.MEMBER_KEYWORDS_AFTER_CLASS
matching_brace = SIZE_REPORT.matching_brace


def comment_line_numbers(text):
    """Return the 1-based numbers of the lines that carry a comment (line, block or documentation comment).

    A `//` or `/*` inside a string literal is not a comment. The scan mirrors `strip_comments_and_strings`:
    nested block comments, multi-line strings and raw strings (`#"..."#`) are followed; interpolated code
    inside a string is not scanned for comments, which is accurate for the code this repository has.
    """
    lines_with_comments = set()
    line_number = 1
    index = 0
    length = len(text)
    while index < length:
        character = text[index]
        if character == "\n":
            line_number += 1
            index += 1
            continue
        if text.startswith("//", index):
            lines_with_comments.add(line_number)
            end = text.find("\n", index)
            index = length if end == -1 else end
            continue
        if text.startswith("/*", index):
            depth = 0
            lines_with_comments.add(line_number)
            while index < length:
                if text.startswith("/*", index):
                    depth += 1
                    index += 2
                elif text.startswith("*/", index):
                    depth -= 1
                    index += 2
                    if depth == 0:
                        break
                else:
                    if text[index] == "\n":
                        line_number += 1
                        lines_with_comments.add(line_number)
                    index += 1
            continue
        if character == '"' or (character == "#" and re.match(r'#+"', text[index:index + 8])):
            hash_count = 0
            while index < length and text[index] == "#":
                hash_count += 1
                index += 1
            is_multiline = text.startswith('"""', index)
            delimiter = '"""' if is_multiline else '"'
            index += len(delimiter)
            closing = delimiter + "#" * hash_count
            while index < length:
                if hash_count == 0 and text[index] == "\\" and index + 1 < length:
                    index += 2
                    continue
                if text.startswith(closing, index):
                    index += len(closing)
                    break
                if text[index] == "\n":
                    line_number += 1
                    if not is_multiline:
                        break
                index += 1
            continue
        index += 1
    return lines_with_comments


class SwiftFile:
    """One Swift file: its raw text, the text without comments and strings, and lazily the comment lines."""

    def __init__(self, root, relative_path):
        self.relative_path = relative_path
        with open(os.path.join(root, relative_path), encoding="utf-8", errors="replace") as handle:
            self.raw_text = handle.read()
        self.stripped_text = strip_comments_and_strings(self.raw_text)
        self._comment_lines = None
        self._type_ranges = None

    @property
    def comment_lines(self):
        if self._comment_lines is None:
            self._comment_lines = comment_line_numbers(self.raw_text)
        return self._comment_lines

    @property
    def code_line_count(self):
        return sum(1 for line in self.stripped_text.split("\n") if line.strip())

    def line_number_at(self, index):
        return self.stripped_text.count("\n", 0, index) + 1

    def raw_line(self, line_number):
        lines = self.raw_text.split("\n")
        return lines[line_number - 1] if 0 < line_number <= len(lines) else ""

    def enclosing_type_name(self, index):
        """The innermost type (class, struct, enum, actor, protocol or extension) whose braces contain `index`."""
        if self._type_ranges is None:
            ranges = []
            for match in TYPE_PATTERN.finditer(self.stripped_text):
                keyword, name = match.groups()
                if keyword == "class" and name in MEMBER_KEYWORDS_AFTER_CLASS:
                    continue
                brace = self.stripped_text.find("{", match.end())
                between = self.stripped_text[match.end():brace] if brace != -1 else ""
                if brace == -1 or ";" in between or "}" in between:
                    continue
                ranges.append((brace, matching_brace(self.stripped_text, brace), name.split(".")[-1], match.start()))
            self._type_ranges = ranges
        containing = [item for item in self._type_ranges if item[0] < index <= item[1]]
        if not containing:
            return None
        return max(containing, key=lambda item: item[0])[2]

    def declared_type_name_before(self, index):
        """The name of the last type declaration that starts before `index` (for `final class Name: @unchecked Sendable`)."""
        names = [match.group(2) for match in TYPE_PATTERN.finditer(self.stripped_text, 0, index)
                 if not (match.group(1) == "class" and match.group(2) in MEMBER_KEYWORDS_AFTER_CLASS)]
        return names[-1].split(".")[-1] if names else None


def swift_file_paths(root, directories, exclude_directories=()):
    """Sorted relative paths of the Swift files under `directories` (conflict copies and fixture folders skipped)."""
    paths = []
    excluded = tuple(os.path.normpath(directory) for directory in exclude_directories)
    for directory in directories:
        base = os.path.join(root, directory)
        for folder, folders, files in os.walk(base):
            relative_folder = os.path.relpath(folder, root)
            folders[:] = sorted(name for name in folders if name not in IGNORED_DIRECTORY_NAMES
                                and os.path.normpath(os.path.join(relative_folder, name)) not in excluded)
            for name in sorted(files):
                if name.endswith(".swift") and not CONFLICT_COPY_PATTERN.search(name):
                    paths.append(os.path.join(relative_folder, name))
    return sorted(set(paths))


class SourceTree:
    """Lazily reads and caches the Swift files of a checkout."""

    def __init__(self, root=REPOSITORY_ROOT):
        self.root = root
        self._files = {}

    def file(self, relative_path):
        if relative_path not in self._files:
            self._files[relative_path] = SwiftFile(self.root, relative_path)
        return self._files[relative_path]

    def files(self, directories, exclude_directories=()):
        return [self.file(path) for path in swift_file_paths(self.root, directories, exclude_directories)]

    def production_files(self):
        return self.files(PRODUCTION_DIRECTORIES, exclude_directories=("App/Tests",))

    def test_files(self):
        return self.files(TEST_DIRECTORIES)

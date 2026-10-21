#!/usr/bin/env python3
"""Report Swift files, types and functions whose size asks for a design review.

Counts code lines: physical lines left after removing comments (line and nested block comments),
string-literal contents (single-line, multi-line and raw strings; interpolated code is kept) and blank
lines. Declarations are found by brace matching on that stripped text:

  file      the whole file
  Type      every block named Type in the file (its declaration plus same-file extensions), summed
  Type.f    a func / init / deinit / subscript / computed property (including SwiftUI `body`);
            nested functions count inside their owner; overloads with one name count as their largest

Thresholds (code lines):  function 40, strong reason from 80;  type 300, strong reason from 600;
                          file 400, strong reason from 500; 1,000 is a structural smell.

An item over its first threshold needs a row in Docs/solid/size-review.md. The script lists every item
over a threshold that has no row, or that grew by more than a fifth since its row was written, and
exits with status 1 while any are left (status 0 when none are). Sizes ask a question; they never force
a split (see Docs/solid/size-review.md).

Usage:
  python3 scripts/size-report.py                 check Sources/, App/ and Packages/ against the register
  python3 scripts/size-report.py --all           also print items that have a current row
  python3 scripts/size-report.py --list          print every item over a threshold, register or not
  python3 scripts/size-report.py --root <path>   measure another checkout (default: the repository)
"""
import argparse
import os
import re
import sys

FUNCTION_THRESHOLD, FUNCTION_STRONG = 40, 80
TYPE_THRESHOLD, TYPE_STRONG = 300, 600
FILE_THRESHOLD, FILE_STRONG, FILE_SMELL = 400, 500, 1000
ALLOWED_GROWTH = 1.2
SCANNED_DIRECTORIES = ("Sources", "App", "Packages")
REGISTER = os.path.join("Docs", "solid", "size-review.md")


def strip_comments_and_strings(text):
    """Return text with comments removed and string contents dropped; newlines are preserved."""
    output = []
    index = 0
    length = len(text)
    while index < length:
        character = text[index]
        if text.startswith("//", index):
            end = text.find("\n", index)
            index = length if end == -1 else end
            continue
        if text.startswith("/*", index):
            depth = 0
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
                        output.append("\n")
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
            output.append('""')
            while index < length:
                if hash_count == 0 and text[index] == "\\" and index + 1 < length:
                    if text[index + 1] == "(":
                        index += 2
                        depth = 1
                        while index < length and depth > 0:
                            if text[index] == "(":
                                depth += 1
                            elif text[index] == ")":
                                depth -= 1
                            if depth > 0:
                                output.append(text[index])
                            index += 1
                        continue
                    index += 2
                    continue
                if text.startswith(closing, index):
                    index += len(closing)
                    break
                if text[index] == "\n":
                    output.append("\n")
                    if not is_multiline:
                        break
                index += 1
            continue
        output.append(character)
        index += 1
    return "".join(output)


TYPE_PATTERN = re.compile(r"\b(class|struct|enum|actor|protocol|extension)\s+([A-Za-z_][\w.]*)")
FUNCTION_PATTERN = re.compile(r"\b(func\s+([^\s(<]+)|init[?!]?\s*[(<]|deinit\b|subscript\s*[(<])")
COMPUTED_PROPERTY_PATTERN = re.compile(r"\bvar\s+([A-Za-z_]\w*)\s*:[^=\n{]*\{")
DECLARATION_KEYWORDS = re.compile(
    r"\b(func|init|var|let|case|subscript|extension|struct|class|enum|actor|protocol|typealias)\b")
MEMBER_KEYWORDS_AFTER_CLASS = {"func", "var", "let", "override", "private", "public", "final", "subscript"}


def matching_brace(stripped, open_index):
    depth = 0
    for index in range(open_index, len(stripped)):
        if stripped[index] == "{":
            depth += 1
        elif stripped[index] == "}":
            depth -= 1
            if depth == 0:
                return index
    return len(stripped) - 1


def measure(text):
    """Return (file code lines, {type name: code lines}, {Type.function: code lines})."""
    stripped = strip_comments_and_strings(text)
    lines = stripped.split("\n")
    is_code = [bool(line.strip()) for line in lines]
    line_starts = [0]
    for line in lines[:-1]:
        line_starts.append(line_starts[-1] + len(line) + 1)

    def line_number(index):
        low, high = 0, len(line_starts) - 1
        while low < high:
            middle = (low + high + 1) // 2
            if line_starts[middle] <= index:
                low = middle
            else:
                high = middle - 1
        return low

    def code_lines_between(start_index, end_index):
        return sum(1 for number in range(line_number(start_index), line_number(end_index) + 1) if is_code[number])

    declarations = []
    for match in TYPE_PATTERN.finditer(stripped):
        keyword, name = match.groups()
        if keyword == "class" and name in MEMBER_KEYWORDS_AFTER_CLASS:
            continue
        brace = stripped.find("{", match.end())
        if brace == -1 or ";" in stripped[match.end():brace] or "}" in stripped[match.end():brace]:
            continue
        declarations.append(("type", name.split(".")[-1], match.start(), brace, matching_brace(stripped, brace)))
    for pattern in (FUNCTION_PATTERN, COMPUTED_PROPERTY_PATTERN):
        for match in pattern.finditer(stripped):
            if pattern is FUNCTION_PATTERN:
                raw = match.group(1)
                name = match.group(2) if raw.startswith("func") else (
                    "init" if raw.startswith("init") else ("deinit" if raw.startswith("deinit") else "subscript"))
                search_from = match.end()
            else:
                name = match.group(1)
                search_from = match.end() - 1
            brace = stripped.find("{", search_from)
            if brace == -1:
                continue
            between = stripped[match.end():brace]
            if pattern is FUNCTION_PATTERN and ("}" in between or DECLARATION_KEYWORDS.search(between)):
                continue  # a requirement without a body
            declarations.append(("function", name, match.start(), brace, matching_brace(stripped, brace)))

    types = [item for item in declarations if item[0] == "type"]
    functions = [item for item in declarations if item[0] == "function"]
    type_sizes, function_sizes = {}, {}
    for kind, name, start, brace, close in types:
        type_sizes[name] = type_sizes.get(name, 0) + code_lines_between(start, close)
    for kind, name, start, brace, close in functions:
        if any(other_brace < brace and close <= other_close
               for _, _, _, other_brace, other_close in functions if other_brace != brace):
            continue  # nested function, counted inside its owner
        owners = [item for item in types if item[3] < brace and close <= item[4]]
        owner = max(owners, key=lambda item: item[3])[1] if owners else None
        qualified = f"{owner}.{name}" if owner else name
        function_sizes[qualified] = max(function_sizes.get(qualified, 0), code_lines_between(start, close))
    return sum(is_code), type_sizes, function_sizes


def read_register(path):
    """Return {(file, declaration): code lines at review} from the register table."""
    rows = {}
    if not os.path.exists(path):
        return rows
    for line in open(path, encoding="utf-8"):
        cells = [cell.strip() for cell in line.strip().strip("|").split("|")]
        if len(cells) < 4 or not line.lstrip().startswith("|"):
            continue
        file_cell, declaration_cell, lines_cell = (cell.strip("` ") for cell in cells[:3])
        if not file_cell.endswith(".swift"):
            continue
        digits = lines_cell.replace(",", "")
        if digits.isdigit():
            rows[(file_cell, declaration_cell)] = int(digits)
    return rows


def items_over_threshold(root):
    items = []
    for directory in SCANNED_DIRECTORIES:
        for folder, folders, files in os.walk(os.path.join(root, directory)):
            folders[:] = [name for name in folders if name not in (".build", "Tests")]
            for name in sorted(files):
                if not name.endswith(".swift"):
                    continue
                path = os.path.join(folder, name)
                relative = os.path.relpath(path, root)
                file_lines, type_sizes, function_sizes = measure(open(path, encoding="utf-8", errors="replace").read())
                if file_lines > FILE_THRESHOLD:
                    level = "smell" if file_lines > FILE_SMELL else ("strong" if file_lines > FILE_STRONG else "review")
                    items.append((relative, "(file)", file_lines, "file", level))
                for type_name, size in type_sizes.items():
                    if size > TYPE_THRESHOLD:
                        items.append((relative, type_name, size, "type", "strong" if size > TYPE_STRONG else "review"))
                for function_name, size in function_sizes.items():
                    if size > FUNCTION_THRESHOLD:
                        items.append((relative, function_name, size, "function",
                                      "strong" if size > FUNCTION_STRONG else "review"))
    return items


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--root", default=os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    parser.add_argument("--all", action="store_true", help="also print items with a current register row")
    parser.add_argument("--list", action="store_true", help="print every item over a threshold and exit 0")
    arguments = parser.parse_args()
    register = read_register(os.path.join(arguments.root, REGISTER))
    items = items_over_threshold(arguments.root)
    items.sort(key=lambda item: (-item[2], item[0], item[1]))
    if arguments.list:
        for relative, declaration, size, kind, level in items:
            print(f"{size:6}  {kind:8} {level:6}  {relative}  {declaration}")
        print(f"{len(items)} items over a threshold")
        return 0
    unreviewed, grown, current = [], [], []
    for item in items:
        relative, declaration, size = item[:3]
        reviewed = register.get((relative, declaration))
        if reviewed is None:
            unreviewed.append(item)
        elif size > reviewed * ALLOWED_GROWTH:
            grown.append(item + (reviewed,))
        else:
            current.append(item + (reviewed,))
    for relative, declaration, size, kind, level in unreviewed:
        print(f"NO REVIEW   {size:6}  {kind:8} {level:6}  {relative}  {declaration}")
    for relative, declaration, size, kind, level, reviewed in grown:
        print(f"GREW        {size:6}  {kind:8} {level:6}  {relative}  {declaration}  (reviewed at {reviewed})")
    if arguments.all:
        for relative, declaration, size, kind, level, reviewed in current:
            print(f"reviewed    {size:6}  {kind:8} {level:6}  {relative}  {declaration}  (reviewed at {reviewed})")
    print(f"{len(items)} items over a threshold: {len(current)} reviewed, {len(unreviewed)} without a review row, "
          f"{len(grown)} grew by more than a fifth since review.")
    return 1 if unreviewed or grown else 0


if __name__ == "__main__":
    sys.exit(main())

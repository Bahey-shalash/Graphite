#!/usr/bin/env python3
"""The ratchet of Docs/solid/rewrite-foundations.md section 12.2: counts what the rules forbid and fails when a count rises.

Each gate is a grep or count taken from the "how to check" of a rule in Docs/solid/principles/ or Docs/solid/testing.md.
Counts are taken on Swift text with comments and string contents removed (the `strip_comments_and_strings` of
scripts/size-report.py), so a word in a comment or a string never counts. Today's counts are recorded in
scripts/rule-baselines.json. A baseline only goes down: the script fails when a gate's count is above its baseline,
and a count below the baseline asks for the baseline to be lowered so that the gain cannot be lost.

Statics and concurrency escapes are different: the rules say they may appear only on a reviewed list, so those gates
count the hits that are not on scripts/allowed-statics.txt or scripts/allowed-concurrency-escapes.txt. Their baselines
are 0 and a new site fails until a reviewer adds a line with its reason.

Usage:
  python3 scripts/check-rules.py                 check every gate against scripts/rule-baselines.json (exit 1 on a rise)
  python3 scripts/check-rules.py --strict        also fail when a count is below its baseline (the baseline is stale)
  python3 scripts/check-rules.py --record        lower every baseline to today's count; add gates that have none
  python3 scripts/check-rules.py --show <gate>   list the hits of one gate (path:line), then check as usual
  python3 scripts/check-rules.py --coverage      check that every SRP/OCP/LSP/ISP/DIP/CC/TR rule is in a Sources cell of
                                                 rewrite-foundations.md section 11 (exit 1 when one is missing)
  python3 scripts/check-rules.py --test-log <file>   only compare the skipped-test count of a `swift test` or `xcodebuild test` log
                                                 with the entry of "skippedTestsBaselines" named like the log file (swift-test.log, hosted-ipad.log; exit 1 when it rose)
  python3 scripts/check-rules.py --root <path>   check another checkout (default: the repository)

To lower a baseline: remove the hits (python3 scripts/check-rules.py --show <gate> lists them), then run --record and
commit scripts/rule-baselines.json with the change. To raise one (a reviewed exception only) use --record --allow-raise.
"""
import argparse
import datetime
import glob
import json
import os
import re
import subprocess
import sys
from collections import namedtuple

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from graphite_source_scanning import (REPOSITORY_ROOT, SourceTree, matching_brace, TYPE_PATTERN,  # noqa: E402
                                      MEMBER_KEYWORDS_AFTER_CLASS)

BASELINE_PATH = os.path.join("scripts", "rule-baselines.json")
STATICS_ALLOW_LIST_PATH = os.path.join("scripts", "allowed-statics.txt")
ESCAPES_ALLOW_LIST_PATH = os.path.join("scripts", "allowed-concurrency-escapes.txt")
FOUNDATIONS_PATH = os.path.join("Docs", "solid", "rewrite-foundations.md")
TESTING_PATH = os.path.join("Docs", "solid", "testing.md")
PRINCIPLES_GLOB = os.path.join("Docs", "solid", "principles", "*.md")
FILE_LINE_SMELL = 1000
LONG_LINE_LENGTH = 160

Hit = namedtuple("Hit", "path line text key")
GateResult = namedtuple("GateResult", "hits allow_listed all_hits")


class Gate:
    """One rule check: a name, where its rule is written, and a function from the source tree to its hits."""

    def __init__(self, name, rule, description, collect, allow_list_path=None):
        self.name = name
        self.rule = rule
        self.description = description
        self.collect = collect
        self.allow_list_path = allow_list_path


# ---------------------------------------------------------------------------------------------------------------------
# Hit collectors
# ---------------------------------------------------------------------------------------------------------------------

def pattern_hits(files, pattern, flags=0):
    """One hit per match of `pattern` in the stripped text of each file."""
    compiled = re.compile(pattern, flags)
    hits = []
    for file in files:
        for match in compiled.finditer(file.stripped_text):
            line_number = file.line_number_at(match.start())
            hits.append(Hit(file.relative_path, line_number, file.raw_line(line_number).strip(), None))
    return hits


def pattern_line_hits(files, pattern):
    """One hit per line that matches `pattern` (a line with two matches counts once, as `grep -c` does)."""
    compiled = re.compile(pattern)
    hits = []
    for file in files:
        for line_number, line in enumerate(file.stripped_text.split("\n"), start=1):
            if compiled.search(line):
                hits.append(Hit(file.relative_path, line_number, file.raw_line(line_number).strip(), None))
    return hits


def files_matching_pattern(files, pattern):
    """One hit per file whose stripped text matches `pattern` (the count is files, not matches)."""
    compiled = re.compile(pattern)
    hits = []
    for file in files:
        match = compiled.search(file.stripped_text)
        if match:
            line_number = file.line_number_at(match.start())
            hits.append(Hit(file.relative_path, line_number, file.raw_line(line_number).strip(), None))
    return hits


# `try?` as a keyword, not the end of a name such as `Entry?` or `Geometry?`.
OPTIONAL_TRY = re.compile(r"\btry\?")


def uncommented_try_hits(files):
    """`try?` on a line without any comment: the rule asks every best-effort `try?` to say why failure is harmless."""
    hits = []
    for file in files:
        for line_number, line in enumerate(file.stripped_text.split("\n"), start=1):
            if OPTIONAL_TRY.search(line) and line_number not in file.comment_lines:
                hits.append(Hit(file.relative_path, line_number, file.raw_line(line_number).strip(), None))
    return hits


def oversized_file_hits(files):
    hits = []
    for file in files:
        if file.code_line_count > FILE_LINE_SMELL:
            hits.append(Hit(file.relative_path, 1, f"{file.code_line_count} code lines", None))
    return hits


def overlong_line_hits(files):
    hits = []
    for file in files:
        for line_number, line in enumerate(file.raw_text.split("\n"), start=1):
            if len(line) > LONG_LINE_LENGTH:
                hits.append(Hit(file.relative_path, line_number, f"{len(line)} characters", None))
    return hits


def round_named_test_file_hits(files):
    hits = []
    for file in files:
        name = os.path.basename(file.relative_path)
        if re.search(r"Fix|Regression|Handoff", name):
            hits.append(Hit(file.relative_path, 1, name, None))
    return hits


# `enum Name: String, StaticPatternSet` (any access level), the sets FR-62's one test must compile.
STATIC_PATTERN_SET = re.compile(r"\benum\s+(\w+)\s*:\s*String\s*,\s*StaticPatternSet\b")


def untested_static_pattern_set_hits(tree):
    """`StaticPatternSet` conformers under Sources/ whose name no `StaticPatternTests.swift` under Tests/ mentions."""
    tested_text = "\n".join(file.stripped_text for file in tree.files(["Tests"])
                             if os.path.basename(file.relative_path) == "StaticPatternTests.swift")
    hits = []
    for file in tree.files(["Sources"]):
        for match in STATIC_PATTERN_SET.finditer(file.stripped_text):
            if not re.search(r"\b" + re.escape(match.group(1)) + r"\b", tested_text):
                line_number = file.line_number_at(match.start())
                hits.append(Hit(file.relative_path, line_number, file.raw_line(line_number).strip(), None))
    return hits


def own_enum_case_sets(files):
    """{enum name: set of case names} for every enum declared in `files` (names shared by two enums keep both sets)."""
    case_sets = []
    for file in files:
        text = file.stripped_text
        for match in TYPE_PATTERN.finditer(text):
            if match.group(1) != "enum":
                continue
            brace = text.find("{", match.end())
            if brace == -1:
                continue
            close = matching_brace(text, brace)
            cases = set()
            depth = 0
            index = brace + 1
            line_start = True
            while index < close:
                character = text[index]
                if character == "{":
                    depth += 1
                elif character == "}":
                    depth -= 1
                elif character == "\n":
                    line_start = True
                    index += 1
                    continue
                if depth == 0 and line_start:
                    declaration = re.match(r"[ \t]*(?:(?:indirect|private|fileprivate|internal|public)\s+)*case\s+", text[index:index + 200])
                    if declaration:
                        end_of_line = text.find("\n", index)
                        label = text[index + declaration.end():end_of_line]
                        while label.rstrip().endswith(",") and end_of_line != -1 and end_of_line < close:
                            next_end = text.find("\n", end_of_line + 1)
                            label += text[end_of_line + 1:next_end]
                            end_of_line = next_end
                        parenthesis_depth = 0
                        current = ""
                        for label_character in label + ",":
                            if label_character == "(":
                                parenthesis_depth += 1
                            elif label_character == ")":
                                parenthesis_depth -= 1
                            if label_character == "," and parenthesis_depth == 0:
                                name = re.match(r"\s*(\w+)", current)
                                if name:
                                    cases.add(name.group(1))
                                current = ""
                            else:
                                current += label_character
                if not character.isspace():
                    line_start = False
                index += 1
            if cases:
                case_sets.append(cases)
    return case_sets


def default_over_own_enum_hits(files):
    """`default:` of a `switch` whose case labels are all `.case` patterns of one enum declared under Sources (FR-18).

    The subject's type is not known without a compiler, so a switch counts when every label is a leading-dot pattern
    and all the case names belong to one enum declared in this repository. A framework enum that shares its case
    names with an own enum is over-counted; the ratchet is for the direction, and the exact list is in --show.
    """
    case_sets = own_enum_case_sets(files)
    hits = []
    for file in files:
        text = file.stripped_text
        if "default" not in text:
            continue
        depths = []
        depth = 0
        for character in text:
            if character == "{":
                depth += 1
            depths.append(depth)
            if character == "}":
                depth -= 1
        for match in re.finditer(r"(?<![.\w])switch\b", text):
            index = match.end()
            parenthesis_depth = 0
            while index < len(text):
                character = text[index]
                if character in "([":
                    parenthesis_depth += 1
                elif character in ")]":
                    parenthesis_depth -= 1
                elif character == "{" and parenthesis_depth == 0:
                    break
                index += 1
            if index >= len(text):
                continue
            body_depth = depths[index]
            close = matching_brace(text, index)
            labels = []
            default_positions = []
            for label in re.finditer(r"^[ \t]*(case\b|default\s*:)", text[index + 1:close], re.MULTILINE):
                position = index + 1 + label.start(1)
                if depths[position] != body_depth:
                    continue
                if label.group(1).startswith("default"):
                    default_positions.append(position)
                    continue
                parenthesis_depth = 0
                colon = position + 4
                while colon < close:
                    character = text[colon]
                    if character in "([":
                        parenthesis_depth += 1
                    elif character in ")]":
                        parenthesis_depth -= 1
                    elif character == ":" and parenthesis_depth == 0:
                        break
                    colon += 1
                labels.append(text[position + 4:colon])
            if not default_positions or not labels:
                continue
            case_names = set()
            is_enum_switch = True
            for label_text in labels:
                parenthesis_depth = 0
                current = ""
                for character in label_text + ",":
                    if character in "([":
                        parenthesis_depth += 1
                    elif character in ")]":
                        parenthesis_depth -= 1
                    if character == "," and parenthesis_depth == 0:
                        pattern = re.sub(r"\s+where\b.*$", "", current.strip(), flags=re.DOTALL)
                        name = re.match(r"(?:let\s+|var\s+)?(?:[A-Z]\w*)?\.(\w+)", pattern)
                        if not name:
                            is_enum_switch = False
                            break
                        case_names.add(name.group(1))
                        current = ""
                    else:
                        current += character
                if not is_enum_switch:
                    break
            if is_enum_switch and any(case_names <= cases for cases in case_sets):
                position = default_positions[0]
                line_number = file.line_number_at(position)
                hits.append(Hit(file.relative_path, line_number, file.raw_line(line_number).strip(), None))
    return hits


def static_declarations(file):
    """Yield (match start, kind, name, remainder) for each `static let/var` declaration in a file."""
    for match in re.finditer(r"\bstatic\s+(?:weak\s+|unowned\s+)?(let|var)\s+(\w+)([^\n]*)", file.stripped_text):
        yield match.start(), match.group(1), match.group(2), match.group(3), match.end()


def is_stored_variable(file, remainder, end_index):
    """True when a `static var` holds a value (stored), false when it is computed (has a body before any `=`)."""
    equals = remainder.find("=")
    brace = remainder.find("{")
    if brace == -1 and equals == -1:
        following = file.stripped_text[end_index:end_index + 200].lstrip()
        return not following.startswith("{")
    if brace == -1:
        return True
    return equals != -1 and equals < brace


LOCK_OR_CACHE_INITIALIZER = re.compile(r"=\s*(?:Mutex|NSCache|OSAllocatedUnfairLock|NSLock|NSRecursiveLock)\b")


def static_hits(files, wanted):
    """Hits for `wanted` in {"shared", "mutable"}: `static let/var shared`, or a stored `static var` / lock or cache `static let`."""
    hits = []
    for file in files:
        for start, kind, name, remainder, end_index in static_declarations(file):
            if wanted == "shared":
                matches = name == "shared"
            else:
                matches = name != "shared" and (
                    (kind == "var" and is_stored_variable(file, remainder, end_index))
                    or (kind == "let" and LOCK_OR_CACHE_INITIALIZER.search(remainder)))
            if matches:
                owner = file.enclosing_type_name(start) or "-"
                line_number = file.line_number_at(start)
                hits.append(Hit(file.relative_path, line_number, file.raw_line(line_number).strip(), f"{owner}.{name}"))
    return hits


def escape_sites(files):
    """Every `@unchecked Sendable`, `nonisolated(unsafe)` and `assumeIsolated` site, with its allow-list key."""
    sites = []
    for file in files:
        text = file.stripped_text
        for match in re.finditer(r"@unchecked\s+Sendable", text):
            key = file.declared_type_name_before(match.start()) or "-"
            sites.append((file, match.start(), "unchecked-sendable", key))
        for match in re.finditer(r"nonisolated\(unsafe\)\s+(?:(?:private|fileprivate|internal|public|static|final|lazy)\s+)*(?:var|let)\s+(\w+)", text):
            sites.append((file, match.start(), "nonisolated-unsafe", match.group(1)))
        for match in re.finditer(r"\bassumeIsolated\b", text):
            sites.append((file, match.start(), "assume-isolated", "assumeIsolated"))
    return sites


def escape_hits(files, kind):
    hits = []
    for file, start, site_kind, key in escape_sites(files):
        if site_kind == kind:
            line_number = file.line_number_at(start)
            hits.append(Hit(file.relative_path, line_number, file.raw_line(line_number).strip(), key))
    return hits


def uncommented_escape_hits(files):
    """Escapes with no comment on their line, on the line after, or in the comment and attribute lines directly above."""
    hits = []
    for file, start, site_kind, key in escape_sites(files):
        line_number = file.line_number_at(start)
        lines = file.raw_text.split("\n")
        if line_number in file.comment_lines or (line_number + 1) in file.comment_lines:
            continue
        above = line_number - 1
        found_comment = False
        while above >= 1:
            stripped_line = lines[above - 1].strip()
            if above in file.comment_lines:
                found_comment = True
                break
            if not stripped_line.startswith("@"):
                break
            above -= 1
        if not found_comment:
            hits.append(Hit(file.relative_path, line_number, lines[line_number - 1].strip(), key))
    return hits


# ---------------------------------------------------------------------------------------------------------------------
# Allow-lists
# ---------------------------------------------------------------------------------------------------------------------

def read_allow_list(path):
    """{(file, key): permitted site count} from lines `path key [xN]  # reason`."""
    entries = {}
    if not os.path.exists(path):
        return entries
    for line_number, line in enumerate(open(path, encoding="utf-8"), start=1):
        content = line.split("#", 1)[0].strip()
        if not content:
            continue
        tokens = content.split()
        if len(tokens) < 2 or "#" not in line:
            raise SystemExit(f"{path}:{line_number}: an entry is `<file> <key> [xN]  # <reason>`; the reason is mandatory")
        permitted = 1
        if len(tokens) > 2:
            if not re.fullmatch(r"x\d+", tokens[2]):
                raise SystemExit(f"{path}:{line_number}: the third token must be a count such as x3, not {tokens[2]!r}")
            permitted = int(tokens[2][1:])
        entries[(tokens[0], tokens[1])] = permitted
    return entries


def apply_allow_list(hits, entries):
    """Split hits into those outside the list, the number it excuses, and entries that match nothing any more."""
    remaining = dict(entries)
    unlisted = []
    excused = 0
    for hit in hits:
        entry = (hit.path, hit.key)
        if remaining.get(entry, 0) > 0:
            remaining[entry] -= 1
            excused += 1
        else:
            unlisted.append(hit)
    hits_by_entry = {}
    for hit in hits:
        hits_by_entry[(hit.path, hit.key)] = hits_by_entry.get((hit.path, hit.key), 0) + 1
    stale = sorted(entry for entry, permitted in entries.items() if hits_by_entry.get(entry, 0) < permitted)
    return unlisted, excused, stale


# ---------------------------------------------------------------------------------------------------------------------
# The gates
# ---------------------------------------------------------------------------------------------------------------------

def build_gates():
    production = lambda tree: tree.production_files()
    tests = lambda tree: tree.test_files()
    interface_files = lambda tree: tree.files(["Sources/GraphiteUI"])
    core_files = lambda tree: tree.files(["Sources/GraphiteCore"])
    gates = [
        # Silent failure (clean-code 472 to 496, LSP 5, FR-58 to FR-60)
        Gate("try-uncommented", "CC 1, FR-58", "`try?` on a line with no comment saying why failure is harmless (production)",
             lambda tree: uncommented_try_hits(production(tree))),
        Gate("empty-catch", "CC 1, FR-58", "`catch { }` with an empty body (production)",
             lambda tree: pattern_hits(production(tree), r"\bcatch\b(?:\s+(?:let\s+)?\w+)?\s*\{\s*\}")),
        Gate("try-force", "CC 29, FR-71", "`try!` (production)",
             lambda tree: pattern_hits(production(tree), r"\btry!")),
        Gate("constant-pattern-try", "CC 5, FR-62", "`try?`/`try!` on `NSRegularExpression` (constant patterns need a compile-once helper)",
             lambda tree: pattern_hits(production(tree), r"\btry[?!]\s+NSRegularExpression")),
        Gate("static-pattern-sets-tested", "CC 5, FR-62", "`StaticPatternSet` conformers under Sources/ that no `StaticPatternTests.swift` under Tests/ compiles",
             untested_static_pattern_set_hits),
        Gate("graphite-error-prose", "CC 6, FR-63", "`.unavailable(\"`, `.invalidFile(\"`, `.oversized(\"` with a string literal (errors are values, one presenter words them)",
             lambda tree: pattern_hits(production(tree), r"\.(?:unavailable|invalidFile|oversized)\(\s*\"\"")),
        Gate("localized-description-in-ui", "CC 7, FR-64", "`localizedDescription` in Sources/GraphiteUI (presenter and Logger only)",
             lambda tree: pattern_hits(interface_files(tree), r"\blocalizedDescription\b")),
        # Concurrency and time (clean-code 506, 510, 590; DIP 8)
        Gate("task-sleep-in-sources", "CC 9, FR-65", "`Task.sleep` in production code (primitives and listed exceptions only)",
             lambda tree: pattern_hits(production(tree), r"\bTask\.sleep\b")),
        Gate("async-after-in-sources", "CC 9, FR-65", "`asyncAfter` in production code",
             lambda tree: pattern_hits(production(tree), r"\basyncAfter\b")),
        Gate("ambient-time-and-randomness", "DIP 8, FR-50", "`Date()`, `Date.now`, `.now`, `systemUptime`, `TimeZone.current`, `Calendar.current`, `randomElement()` (take `now` as a parameter)",
             lambda tree: pattern_hits(production(tree), r"\bDate\(\)|\bDate\.now\b|=\s*\.now\b|\bContinuousClock\.now\b|\bsystemUptime\b|\bTimeZone\.current\b|\bCalendar\.current\b|\brandomElement\(\)")),
        Gate("concurrency-escapes-unlisted", "CC 28, FR-70", "`@unchecked Sendable`, `nonisolated(unsafe)`, `assumeIsolated` outside scripts/allowed-concurrency-escapes.txt",
             lambda tree: [hit for kind in ("unchecked-sendable", "nonisolated-unsafe", "assume-isolated") for hit in escape_hits(production(tree), kind)],
             allow_list_path=ESCAPES_ALLOW_LIST_PATH),
        Gate("concurrency-escapes-without-comment", "CC 28, FR-70", "a concurrency escape with no comment on, below or directly above its line",
             lambda tree: uncommented_escape_hits(production(tree))),
        # Singletons, statics and device state (DIP 1 to 5, FR-46 to FR-52)
        Gate("shared-singletons", "FR-48", "`static let/var shared` outside scripts/allowed-statics.txt",
             lambda tree: static_hits(production(tree), "shared"), allow_list_path=STATICS_ALLOW_LIST_PATH),
        Gate("mutable-statics", "FR-48", "a stored `static var`, or a `static let` holding a Mutex, NSCache or lock, outside scripts/allowed-statics.txt",
             lambda tree: static_hits(production(tree), "mutable"), allow_list_path=STATICS_ALLOW_LIST_PATH),
        Gate("user-defaults-standard-in-sources", "DIP 5, FR-73", "`UserDefaults.standard` in production code",
             lambda tree: pattern_hits(production(tree), r"\bUserDefaults\.standard\b")),
        Gate("app-storage-literals", "CC 20, FR-73", "`@AppStorage(\"literal key\")` (keys come from the typed registry)",
             lambda tree: pattern_hits(production(tree), r"@AppStorage\(\s*\"\"")),
        Gate("defaults-key-literals", "CC 20, FR-73", "`forKey: \"…\"`, `suiteName: \"…\"` and `Notification.Name(\"…\")` literals outside the registry",
             lambda tree: pattern_hits(production(tree), r"\b(?:forKey|suiteName):\s*\"\"|Notification\.Name\(\s*\"\"")),
        Gate("workspace-model-stored", "FR-02", "`let/var name: WorkspaceModel` or `= WorkspaceModel(` stored declarations",
             lambda tree: pattern_hits(production(tree), r"\b(?:let|var)\s+\w+\s*(?::\s*WorkspaceModel\b|=\s*WorkspaceModel\()")),
        Gate("workspace-model-parameters", "FR-02", "`name: WorkspaceModel` parameters",
             lambda tree: pattern_hits(production(tree), r"\b\w+\s*:\s*WorkspaceModel\??\s*[,)]")),
        # Layering (DIP 9, DIP 13)
        Gate("core-io", "DIP 9, FR-51, FR-54", "GraphiteCore files that use FileManager, URLSession, keychain, file coordination or Application Support",
             lambda tree: files_matching_pattern(core_files(tree), r"\b(?:FileManager|URLSession|NSFileCoordinator|SecItem\w*)\b|\bapplicationSupportDirectory\b")),
        # Types and data (ISP 13, CC 12, CC 13)
        Gate("untyped-dictionaries", "ISP 13, FR-44", "`[String: Any]` and `-> Any` (boundary adapters only)",
             lambda tree: pattern_hits(production(tree), r"\[\s*String\s*:\s*Any\??\s*\]|->\s*Any\b")),
        Gate("document-parsing", "CC 16, FR-68", "`Document(parsing` (one parse owner)",
             lambda tree: pattern_hits(production(tree), r"\bDocument\(parsing\b")),
        Gate("hash-value-identity", "CC 21, FR-28", "`hashValue` (never an identity or a key)",
             lambda tree: pattern_hits(production(tree), r"\bhashValue\b")),
        Gate("default-over-own-enum", "FR-18", "`default:` in a `switch` over an enum declared in this repository (approximated; see the function)",
             lambda tree: default_over_own_enum_hits(production(tree))),
        # Size and style (CC 1000-line smell, line length 160)
        Gate("files-over-1000-code-lines", "CC 27, FR-77", "production files over 1,000 code lines (a structural smell)",
             lambda tree: oversized_file_hits(production(tree))),
        Gate("lines-over-160-characters", "CC 17, FR-76", "production lines over 160 characters",
             lambda tree: overlong_line_hits(production(tree))),
        # Tests (testing.md section 6)
        Gate("wait-until-copies", "CC 31, FR-85", "`func waitUntil` declarations in Tests and App/Tests (one shared helper)",
             lambda tree: pattern_hits(tests(tree), r"\bfunc\s+waitUntil\b")),
        Gate("task-sleep-in-tests", "TR 8, FR-89", "`Task.sleep` in Tests and App/Tests (await the task or advance the clock)",
             lambda tree: pattern_hits(tests(tree), r"\bTask\.sleep\b")),
        Gate("blocking-sleep-in-tests", "TR 8, FR-89", "`Thread.sleep`, `usleep(`, `sleep(` in Tests and App/Tests",
             lambda tree: pattern_hits(tests(tree), r"\bThread\.sleep\b|\busleep\(|(?<![\w.])(?<!func )sleep\(")),
        Gate("user-defaults-standard-in-tests", "TR 9, FR-90", "`UserDefaults.standard` in Tests and App/Tests (isolated suites)",
             lambda tree: pattern_hits(tests(tree), r"\bUserDefaults\.standard\b")),
        Gate("temporary-directory-in-tests", "TR 10, FR-85", "direct `temporaryDirectory` in tests (use TemporaryVault)",
             lambda tree: pattern_hits(tests(tree), r"\.temporaryDirectory\b|\bNSTemporaryDirectory\b")),
        Gate("localized-description-in-tests", "TR 11, FR-91", "`localizedDescription` in tests (assert typed errors)",
             lambda tree: pattern_hits(tests(tree), r"\blocalizedDescription\b")),
        Gate("file-path-in-tests", "TR 12, FR-91", "`#filePath`/`#file` in tests (read resources through the module bundle)",
             lambda tree: pattern_hits(tests(tree), r"(?<!StaticString = )(?:#filePath\b|#file\b)")),
        Gate("xct-skip-count", "TR 14, FR-93", "`XCTSkip`, `XCTSkipIf`, `XCTSkipUnless` uses (a skip names a missing platform capability; the count never rises)",
             lambda tree: pattern_hits(tests(tree), r"\bXCTSkip\w*\b")),
        Gate("audible-output-in-tests", "TR 14, FR-93", "tests that can play to the speakers (`output: .speakers`, `AVSpeechSynthesizer(`, `AVAudioPlayer(`, `AVAudioEngine(`, `AVPlayer(`, `NSSound`; a test run is silent, `AudioOutputRoute`)",
             lambda tree: pattern_hits(tests(tree), r"output:\s*\.speakers\b|\bAVSpeechSynthesizer\(|\bAVAudioPlayer\(|\bAVAudioEngine\(|\bAVPlayer\(|\bNSSound\b|\bAudioServicesPlay\w*")),
        Gate("visible-window-in-tests", "TR 14, FR-93", "tests that show a window on the developer's screen (`window.orderFront(`, `makeKeyAndOrderFront(`, `orderFrontRegardless(`; use `showInvisibly()`)",
             lambda tree: pattern_hits(tests(tree), r"\b\w+\.(?:orderFront|makeKeyAndOrderFront|orderFrontRegardless)\(")),
        Gate("test-round-names", "TR 2, FR-83", "test files named `Fix`, `Regression` or `Handoff` (name the file after the type it pins)",
             lambda tree: round_named_test_file_hits(tests(tree))),
    ]
    return gates


# ---------------------------------------------------------------------------------------------------------------------
# Running and recording
# ---------------------------------------------------------------------------------------------------------------------

def evaluate_gate(gate, tree):
    hits = gate.collect(tree)
    if gate.allow_list_path is None:
        return GateResult(hits, 0, hits)
    entries = read_allow_list(os.path.join(tree.root, gate.allow_list_path))
    unlisted, excused, _stale = apply_allow_list(hits, entries)
    return GateResult(unlisted, excused, hits)


def evaluate_all(tree, gates):
    """Evaluate each gate once."""
    return {gate.name: evaluate_gate(gate, tree) for gate in gates}


def stale_entries_by_list(gates, results, tree):
    """An allow-list entry is stale when no gate that reads the list matched it any more."""
    stale_by_list = {}
    for gate in gates:
        if gate.allow_list_path is None:
            continue
        entries = read_allow_list(os.path.join(tree.root, gate.allow_list_path))
        used = set()
        for sharing_gate in gates:
            if sharing_gate.allow_list_path == gate.allow_list_path:
                for hit in results[sharing_gate.name].all_hits:
                    used.add((hit.path, hit.key))
        stale_by_list[gate.allow_list_path] = sorted(entry for entry in entries if entry not in used)
    return stale_by_list


def load_baselines(path):
    if not os.path.exists(path):
        return {}
    with open(path, encoding="utf-8") as handle:
        return json.load(handle).get("gates", {})


def current_revision(root):
    try:
        return subprocess.run(["git", "-C", root, "rev-parse", "--short", "HEAD"], capture_output=True, text=True, check=True).stdout.strip()
    except (OSError, subprocess.CalledProcessError):
        return "unknown"


def write_baselines(path, root, counts, test_log_baselines):
    document = {
        "schemaVersion": 1,
        "comment": "Counts of what the rules forbid; they only go down. Lower them with `python3 scripts/check-rules.py --record`. See Docs/solid/rewrite-foundations.md section 12.2.",
        "recordedOn": datetime.date.today().isoformat(),
        "recordedAtRevision": current_revision(root) + " plus the working tree",
        "gates": dict(sorted(counts.items())),
    }
    document.update(test_log_baselines)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as handle:
        json.dump(document, handle, indent=2)
        handle.write("\n")


def run_checks(arguments):
    tree = SourceTree(arguments.root)
    gates = build_gates()
    baseline_path = os.path.join(arguments.root, BASELINE_PATH)
    baselines = load_baselines(baseline_path)
    results = evaluate_all(tree, gates)
    counts = {name: len(result.hits) for name, result in results.items()}

    if arguments.show:
        names = [gate.name for gate in gates]
        if arguments.show not in results:
            print(f"unknown gate {arguments.show!r}; gates: {', '.join(names)}", file=sys.stderr)
            return 2
        for hit in results[arguments.show].hits:
            print(f"{hit.path}:{hit.line}: {hit.text}" + (f"  [{hit.key}]" if hit.key else ""))

    if arguments.record:
        merged = dict(baselines)
        for name, count in counts.items():
            if name not in merged or count < merged[name] or arguments.allow_raise:
                merged[name] = count
        previous = json.load(open(baseline_path, encoding="utf-8")) if os.path.exists(baseline_path) else {}
        carried = {key: previous[key] for key in previous if key in ("skippedTestsBaselines",)}
        write_baselines(baseline_path, arguments.root, merged, carried)
        print(f"recorded {len(merged)} baselines in {BASELINE_PATH}")
        for name in sorted(merged):
            note = "" if merged[name] == counts.get(name) else f"  (today {counts.get(name)}, baseline kept)"
            print(f"  {name:42} {merged[name]}{note}")
        return 0

    failures = 0
    stale = 0
    width = max(len(gate.name) for gate in gates)
    for gate in gates:
        result = results[gate.name]
        count = len(result.hits)
        baseline = baselines.get(gate.name)
        listed = f" ({result.allow_listed} on {os.path.basename(gate.allow_list_path)})" if gate.allow_list_path else ""
        if baseline is None:
            status = "FAIL"
            failures += 1
            detail = f"{count}{listed}: no baseline recorded (run --record)"
        elif count > baseline:
            status = "FAIL"
            failures += 1
            detail = f"{count}{listed} is above its baseline {baseline}: {gate.description} [{gate.rule}]"
        elif count < baseline:
            status = "LOWER" if not arguments.strict else "FAIL"
            if arguments.strict:
                failures += 1
            stale += 1
            detail = f"{count}{listed} is below its baseline {baseline}: run --record to lower it"
        else:
            status = "ok"
            detail = f"{count}{listed}"
        print(f"{status:5} {gate.name:{width}}  {detail}")
    stale_lists = stale_entries_by_list(gates, results, tree)
    for path, entries in stale_lists.items():
        for entry in entries:
            print(f"note  {path}: {entry[0]} {entry[1]} matches nothing any more; remove the line")
    if failures:
        print(f"\n{failures} gate(s) failed. Fix the hits (python3 scripts/check-rules.py --show <gate> lists them). "
              "A baseline only goes down: after fixing, `python3 scripts/check-rules.py --record` lowers it; "
              "a reviewed exception for a static or an escape is a line with a reason in its allow-list.")
    elif stale:
        print(f"\n{stale} gate(s) are below their baseline: run `python3 scripts/check-rules.py --record` and commit {BASELINE_PATH}.")
    else:
        print(f"\nall {len(gates)} gates at their baselines.")
    return 1 if failures else 0


def check_test_log(arguments, baseline_path):
    """Compare the skipped-test count of a test log with its baseline. The count is the number of distinct tests with a
    "Test Case '-[Class test]' skipped" line, which `swift test --parallel --verbose` and `xcodebuild test` both print (a
    parallel run without --verbose prints none); a log with no such line falls back to the last XCTest summary line
    ("Executed N tests, with M tests skipped and K failures")."""
    with open(arguments.test_log, encoding="utf-8", errors="replace") as handle:
        text = handle.read()
    results = {}
    for name, outcome in re.findall(r"Test Case '(-\[[^\]]+\])' (passed|failed|skipped)", text):
        # A test that is retried or listed twice counts once, with the last outcome.
        results[name] = outcome
    if results:
        executed = len(results)
        skipped = sum(1 for outcome in results.values() if outcome == "skipped")
    else:
        totals = re.findall(r"Executed (\d+) tests?, with (?:(\d+) tests? skipped and )?(\d+) failures?", text)
        if not totals:
            print("FAIL test log: no test result line and no XCTest summary line found; the skip count cannot be checked")
            return 1
        executed = int(totals[-1][0])
        skipped = int(totals[-1][1] or 0)
    # One baseline per job: the packages and the iPad simulator skip different tests. The key is the log's file name.
    job = os.path.splitext(os.path.basename(arguments.test_log))[0]
    baselines = {}
    if os.path.exists(baseline_path):
        baselines = json.load(open(baseline_path, encoding="utf-8")).get("skippedTestsBaselines", {})
    baseline = baselines.get(job)
    if baseline is None:
        print(f"test log {job}: {skipped} skipped of {executed}; no baseline recorded yet. Add \"{job}\": {skipped} to \"skippedTestsBaselines\" in {BASELINE_PATH} after the first green CI run.")
        return 0
    if skipped > baseline:
        print(f"FAIL test log: {skipped} skipped tests, above the baseline {baseline} (a skip names a missing platform capability, TR 14)")
        return 1
    print(f"ok    test log: {skipped} skipped tests (baseline {baseline})")
    return 0


# ---------------------------------------------------------------------------------------------------------------------
# --coverage
# ---------------------------------------------------------------------------------------------------------------------

RULE_TOKEN = re.compile(r"\b(SRP|OCP|LSP|ISP|DIP|CC|TR) (\d+)\b")
SOURCE_RULE_PREFIXES = ("SRP", "OCP", "LSP", "ISP", "DIP", "CC", "TR")


def defined_source_rules(root):
    """Every `**SRP n`, `**OCP n` ... in the principle documents and `**TR n` in testing.md."""
    defined = set()
    definition = re.compile(r"^\*\*(SRP|OCP|LSP|ISP|DIP|CC|TR) (\d+)(?=[ .—–:\-*])", re.MULTILINE)
    paths = sorted(glob.glob(os.path.join(root, PRINCIPLES_GLOB))) + [os.path.join(root, TESTING_PATH)]
    for path in paths:
        with open(path, encoding="utf-8") as handle:
            for match in definition.finditer(handle.read()):
                defined.add((match.group(1), int(match.group(2))))
    return defined


def rule_rows_of_section_eleven(root):
    """{FR number: set of source rules in its Sources cell} for the rule tables of section 11, and the coverage table's pairs."""
    with open(os.path.join(root, FOUNDATIONS_PATH), encoding="utf-8") as handle:
        lines = handle.read().split("\n")
    start = next(index for index, line in enumerate(lines) if line.startswith("## 11."))
    coverage_start = next(index for index, line in enumerate(lines) if line.startswith("### Coverage of the source rules"))
    end = next(index for index, line in enumerate(lines) if index > coverage_start and line.startswith("### Review checklist"))
    rows = {}
    for line in lines[start:coverage_start]:
        match = re.match(r"^\| \*\*FR-(\d+)\*\* \|", line)
        if match:
            sources_cell = line.rstrip().rstrip("|").rsplit("|", 1)[1]
            rows[int(match.group(1))] = {(token[0], int(token[1])) for token in RULE_TOKEN.findall(sources_cell)}
    landed = {}
    for line in lines[coverage_start:end]:
        cells = [cell.strip() for cell in line.strip().strip("|").split("|")]
        for position in range(0, len(cells) - 1, 2):
            token = RULE_TOKEN.search(cells[position])
            if token and line.startswith("|") and cells[position].startswith("`"):
                landed[(token.group(1), int(token.group(2)))] = {int(number) for number in re.findall(r"FR-(\d+)", cells[position + 1])}
    return rows, landed


def run_coverage(arguments):
    defined = defined_source_rules(arguments.root)
    rows, landed = rule_rows_of_section_eleven(arguments.root)
    cited = set()
    for sources in rows.values():
        cited |= sources
    problems = 0
    print("source rules defined in the principle documents and testing.md:")
    for prefix in SOURCE_RULE_PREFIXES:
        numbers = sorted(number for name, number in defined if name == prefix)
        gaps = [number for number in range(1, (numbers[-1] if numbers else 0) + 1) if number not in numbers]
        print(f"  {prefix:3} {len(numbers):3} rules" + (f"  (numbers missing from the documents: {gaps})" if gaps else ""))
        if gaps:
            problems += 1
    missing = sorted(defined - cited, key=lambda rule: (SOURCE_RULE_PREFIXES.index(rule[0]), rule[1]))
    undefined = sorted(cited - defined, key=lambda rule: (SOURCE_RULE_PREFIXES.index(rule[0]), rule[1]))
    for prefix, number in missing:
        print(f"FAIL {prefix} {number} appears in no Sources cell of section 11")
        problems += 1
    for prefix, number in undefined:
        print(f"FAIL {prefix} {number} is cited in a Sources cell but no document defines it")
        problems += 1
    disagreements = 0
    for rule in sorted(defined, key=lambda rule: (SOURCE_RULE_PREFIXES.index(rule[0]), rule[1])):
        citing = {number for number, sources in rows.items() if rule in sources}
        if rule in landed and landed[rule] != citing:
            print(f"note  {rule[0]} {rule[1]}: the coverage table says {sorted(landed[rule])}, the Sources cells say {sorted(citing)}")
            disagreements += 1
        if rule not in landed:
            print(f"note  {rule[0]} {rule[1]} has no row in the coverage table")
            disagreements += 1
    print(f"{len(defined)} source rules, {len(rows)} FR rows with Sources, {len(missing)} uncovered, {len(undefined)} undefined, "
          f"{disagreements} differences between the coverage table and the Sources cells (reported, not failing).")
    return 1 if problems else 0


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--root", default=REPOSITORY_ROOT)
    parser.add_argument("--record", action="store_true", help="lower baselines to today's counts (adds gates that have none)")
    parser.add_argument("--allow-raise", action="store_true", help="with --record: also raise a baseline (a reviewed exception only)")
    parser.add_argument("--strict", action="store_true", help="fail when a count is below its baseline too")
    parser.add_argument("--show", metavar="GATE", help="print the hits of one gate")
    parser.add_argument("--coverage", action="store_true", help="check that every source rule appears in a Sources cell of section 11")
    parser.add_argument("--test-log", metavar="FILE", help="only compare the skipped-test count of a test log with its entry of skippedTestsBaselines")
    arguments = parser.parse_args()
    if arguments.coverage:
        return run_coverage(arguments)
    if arguments.test_log:
        return check_test_log(arguments, os.path.join(arguments.root, BASELINE_PATH))
    return run_checks(arguments)


if __name__ == "__main__":
    sys.exit(main())

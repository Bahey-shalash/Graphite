#!/usr/bin/env python3
"""Check that every add-on pack the app downloads matches the files at its pinned revision.

An add-on pack (`AddOnPack`) lists each file's name, size and SHA-256 and the commit it is
downloaded from. This script reads each pack definition in Sources, takes the files from that
commit with `git show`, and fails when a file is missing or its size or hash differ, so a
build can never ask for files that do not exist or no longer match.

Usage:
  python3 scripts/check-add-on-packs.py
"""
import hashlib
import os
import re
import subprocess
import sys

REPOSITORY_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PACK_DEFINITIONS = ["Sources/GraphiteUI/WelcomeTourScreenshotPack.swift"]
FILE_PATTERN = re.compile(r'AddOnFile\(name: "([^"]+)", byteCount: (\d+),\s*sha256: "([0-9a-f]{64})"\)')


def check(definition_path):
    text = open(os.path.join(REPOSITORY_ROOT, definition_path), encoding="utf-8").read()
    revision = re.search(r'static let revision = "([0-9a-f]{40})"', text).group(1)
    folder = re.search(r'/\\\(revision\)/([^"]+)"\)', text).group(1)
    problems = []
    files = FILE_PATTERN.findall(text)
    for name, byte_count, sha256 in files:
        path = f"{folder}/{name}"
        result = subprocess.run(["git", "-C", REPOSITORY_ROOT, "show", f"{revision}:{path}"], capture_output=True)
        if result.returncode != 0:
            problems.append(f"{path} is not in {revision[:10]}")
            continue
        if len(result.stdout) != int(byte_count) or hashlib.sha256(result.stdout).hexdigest() != sha256:
            problems.append(f"{path} at {revision[:10]} does not match its size or SHA-256")
    print(f"{definition_path}: {len(files)} files at {revision[:10]}, {len(problems)} problems")
    return problems


def main():
    problems = [problem for path in PACK_DEFINITIONS for problem in check(path)]
    for problem in problems:
        print("  " + problem)
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())

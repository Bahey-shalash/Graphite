#!/usr/bin/env python3
"""Rebuild Docs/solid/findings-index.md from the finding headings of the area documents.

Every `#### <P>-<AREA>-<NN> title` heading in Docs/solid/areas/*.md and
Docs/solid/cross-cutting/architecture.md becomes one row, with the first word of the
**Severity** line under it ("—" when the heading has none). The text above the first
table of the index is kept as it is.

Usage: python3 scripts/findings-index.py [--check]
  --check   exits with status 1 when the index is not what the documents give, writing nothing.
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SOLID = ROOT / "Docs" / "solid"
INDEX = SOLID / "findings-index.md"
PREFIXES = ["SRP", "OCP", "LSP", "ISP", "DIP", "CC", "BUG"]
SEVERITIES = ["High", "Medium", "Low", "Critical"]
HEADING = re.compile(r"^#### ((SRP|OCP|LSP|ISP|DIP|CC|BUG)-([A-Z]+)-([A-Z]*\d+)) (.+)$")
SEVERITY = re.compile(r"^- \*\*Severity:\*\* (\w+)")


def anchor(heading_text):
    """The anchor GitHub gives a heading: lower case, punctuation dropped, spaces as hyphens."""
    text = heading_text.lower()
    text = re.sub(r"[^\w\- ]", "", text)
    return text.replace(" ", "-")


def findings():
    documents = sorted((SOLID / "areas").glob("*.md")) + [SOLID / "cross-cutting" / "architecture.md"]
    rows = []
    for document in documents:
        lines = document.read_text(encoding="utf-8").splitlines()
        for position, line in enumerate(lines):
            match = HEADING.match(line)
            if not match:
                continue
            identifier, prefix, area, number, title = match.groups()
            severity = "—"
            for following in lines[position + 1:position + 4]:
                severity_match = SEVERITY.match(following)
                if severity_match and severity_match.group(1) in SEVERITIES:
                    severity = severity_match.group(1)
                    break
            link = f"{document.relative_to(SOLID).as_posix()}#{anchor(identifier + ' ' + title)}"
            sort_number = int(re.sub(r"\D", "", number) or 0)
            rows.append((PREFIXES.index(prefix), area, sort_number, number, identifier, link, severity, title))
    rows.sort(key=lambda row: (row[0], row[1], row[2], row[3]))
    return rows


def render(rows, preamble):
    counts = {prefix: {severity: 0 for severity in SEVERITIES + ["—"]} for prefix in PREFIXES}
    for row in rows:
        counts[PREFIXES[row[0]]][row[6]] += 1
    lines = [preamble.rstrip("\n"), "", "| Prefix | High | Medium | Low | Critical | No severity | Total |",
             "| --- | ---: | ---: | ---: | ---: | ---: | ---: |"]
    totals = {severity: 0 for severity in SEVERITIES + ["—"]}
    for prefix in PREFIXES:
        values = [counts[prefix][severity] for severity in SEVERITIES + ["—"]]
        for severity in SEVERITIES + ["—"]:
            totals[severity] += counts[prefix][severity]
        lines.append(f"| {prefix} | " + " | ".join(str(value) for value in values) + f" | {sum(values)} |")
    total_values = [totals[severity] for severity in SEVERITIES + ["—"]]
    lines.append("| **All** | " + " | ".join(str(value) for value in total_values) + f" | **{sum(total_values)}** |")
    lines += ["", "| ID | Area | Severity | Title |", "| --- | --- | --- | --- |"]
    for row in rows:
        lines.append(f"| [{row[4]}]({row[5]}) | {row[1]} | {row[6]} | {row[7]} |")
    return "\n".join(lines) + "\n"


def main():
    current = INDEX.read_text(encoding="utf-8")
    preamble = current.split("\n| Prefix |", 1)[0]
    rebuilt = render(findings(), preamble)
    if "--check" in sys.argv[1:]:
        if rebuilt != current:
            print("Docs/solid/findings-index.md is out of date: run python3 scripts/findings-index.py")
            return 1
        print("findings-index.md matches the area documents.")
        return 0
    INDEX.write_text(rebuilt, encoding="utf-8")
    print(f"{len(findings())} findings written to {INDEX.relative_to(ROOT)}.")
    return 0


if __name__ == "__main__":
    sys.exit(main())

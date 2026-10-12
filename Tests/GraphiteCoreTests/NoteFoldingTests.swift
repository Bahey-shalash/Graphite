import XCTest
@testable import GraphiteCore

final class NoteFoldingTests: XCTestCase {
    private func hidden(_ region: FoldableRegion, in text: String) -> String {
        (text as NSString).substring(with: region.hiddenRange)
    }

    func testHeadingsFoldToTheNextHeadingOfTheSameOrHigherLevel() {
        let text = "# One\nIntro\n## Two\nBody two\n\n## Three\nBody three\n# Four\nEnd\n"
        let regions = NoteFolding.regions(in: text)
        XCTAssertEqual(regions.map(\.kind), [.heading(level: 1), .heading(level: 2), .heading(level: 2), .heading(level: 1)])
        XCTAssertEqual(hidden(regions[0], in: text), "\nIntro\n## Two\nBody two\n\n## Three\nBody three")
        XCTAssertEqual(hidden(regions[1], in: text), "\nBody two", "Blank lines before the next heading stay visible.")
        XCTAssertEqual((text as NSString).substring(from: regions[1].endLocation), "\n## Three\nBody three\n# Four\nEnd\n")
        XCTAssertEqual(hidden(regions[3], in: text), "\nEnd")
        XCTAssertEqual((text as NSString).substring(with: regions[0].headerRange), "# One")
    }

    func testHeadingsWithNothingUnderThemDoNotFold() {
        XCTAssertTrue(NoteFolding.regions(in: "# Alone\n# Also alone").isEmpty)
        XCTAssertTrue(NoteFolding.regions(in: "# Alone\n\n\n## Sub").filter { region in region.kind == .heading(level: 1) }.count == 1,
                      "A heading with only a subheading still folds it.")
    }

    func testCodeAndFrontmatterAreNotHeadings() {
        let text = "---\ntitle: x\n---\n# Real\n```\n# Not a heading\n```\n"
        let regions = NoteFolding.regions(in: text)
        XCTAssertEqual(regions.count, 1)
        XCTAssertEqual(hidden(regions[0], in: text), "\n```\n# Not a heading\n```", "The code block is part of the section.")
    }

    func testListItemsFoldTheirIndentedLines() {
        let text = "- Parent\n  - Child\n    - Grandchild\n\n  More of parent\n- Sibling\n  - Its child\n- Leaf\n"
        let regions = NoteFolding.regions(in: text)
        XCTAssertEqual(regions.map(\.kind), [.listItem, .listItem, .listItem])
        XCTAssertEqual(hidden(regions[0], in: text), "\n  - Child\n    - Grandchild\n\n  More of parent")
        XCTAssertEqual(hidden(regions[1], in: text), "\n    - Grandchild")
        XCTAssertEqual(hidden(regions[2], in: text), "\n  - Its child")
    }

    func testKeysSurviveEditsElsewhereAndCountRepeats() {
        let text = "## Notes\na\n## Notes\nb\n"
        let keys = NoteFolding.regions(in: text).map(\.key)
        XCTAssertEqual(keys, ["h2|## Notes|0", "h2|## Notes|1"])
        let edited = "Preface\n\n" + text
        XCTAssertEqual(NoteFolding.regions(in: edited).map(\.key), keys)
    }

    func testFoldedRegionsInsideFoldedRegionsAreLeftOut() {
        let text = "# One\n## Two\nx\n# Three\ny\n"
        let regions = NoteFolding.regions(in: text)
        let folded = NoteFolding.foldedRegions(in: regions, foldedKeys: Set(regions.map(\.key)))
        XCTAssertEqual(folded.map(\.key), ["h1|# One|0", "h1|# Three|0"])
        let source = text as NSString
        XCTAssertEqual(NoteFolding.region(atLine: source.range(of: "## Two").location + 2, in: regions, text: source)?.key, "h2|## Two|0")
        let hiddenLocation = source.range(of: "x").location
        XCTAssertEqual(NoteFolding.regions(hiding: hiddenLocation, in: folded).map(\.key), ["h1|# One|0"])
        XCTAssertTrue(NoteFolding.regions(hiding: regions[0].hiddenRange.location, in: folded).isEmpty, "The end of the header line is visible.")
    }

    func testReturnAtAFoldedLineStartsALineAfterTheSection() {
        let text = "- [ ] Parent\n  - Child\n- Next\n1. One\n   more\n## Heading\nBody\n"
        let regions = NoteFolding.regions(in: text)
        func applying(_ region: FoldableRegion) -> String {
            let edit = NoteFolding.newLineAfterFoldedSection(region, in: text)
            return (text as NSString).replacingCharacters(in: edit.range, with: edit.replacement)
        }
        XCTAssertEqual(applying(regions[0]), "- [ ] Parent\n  - Child\n- [ ] \n- Next\n1. One\n   more\n## Heading\nBody\n", "A task gets a sibling task.")
        XCTAssertEqual(applying(regions[1]), "- [ ] Parent\n  - Child\n- Next\n1. One\n   more\n2. \n## Heading\nBody\n", "Numbers continue.")
        XCTAssertEqual(applying(regions[2]), "- [ ] Parent\n  - Child\n- Next\n1. One\n   more\n## Heading\nBody\n\n")
    }
    /// Folding reads list items character by character; it must agree with the list pattern
    /// the editor uses everywhere else.
    func testListItemScanAgreesWithTheListPattern() {
        let lines = ["- item", "-item", "-", "- ", "* star", "+ plus", "1. one", "1) one", "1234567890. too long", "12.no space", "a. letter",
                     "  - indented", "\t- tabbed", "> - quoted", ">- quoted", "> > 2. nested", "> quote only", ">", "- - -", "***", "* * *", "-- dash",
                     "- [ ] task", "- [x] done", "plain", "", "   ", "#- heading?", "-\tTabbed", "1.", "+", "*emphasis*", "- **bold** item", "---"]
        for line in lines {
            XCTAssertEqual(NoteFolding.isListItem(line), MarkdownEditing.listLine(line)?.isListItem == true, "\(line.debugDescription)")
        }
    }
    /// Regions moved across an edit are the regions found again in the edited text, for every
    /// edit the move accepts; edits that could change a region are refused.
    func testRegionsMovedAcrossPlainTextEditsMatchRegionsFoundAgain() {
        let text = "---\ntags: a\n---\n# One\nIntro text\n\n## Two\nBody two\n- item\n  more under item\n  - nested\n\n```\n# not a heading\n```\n## Three\nEnd text\n" as NSString
        let regions = NoteFolding.regions(in: text as String)
        var acceptedEdits = 0
        let replacements = ["", "x", "abc", "# ", "- ", "\n", " ", "`"]
        for location in 0...text.length {
            for replacedLength in 0...3 where location + replacedLength <= text.length {
                for replacement in replacements {
                    let replacedRange = NSRange(location: location, length: replacedLength)
                    let edited = text.replacingCharacters(in: replacedRange, with: replacement) as NSString
                    guard let moved = NoteFolding.regions(regions, across: replacedRange, replacementLength: (replacement as NSString).length,
                                                          before: text, after: edited) else { continue }
                    acceptedEdits += 1
                    XCTAssertEqual(moved, NoteFolding.regions(in: edited as String), "Replacing \(replacedRange) with \(replacement.debugDescription)")
                }
            }
        }
        XCTAssertGreaterThan(acceptedEdits, 100, "Typing in plain lines is moved, not found again.")
        let headingLine = text.range(of: "# One")
        XCTAssertNil(NoteFolding.regions(regions, across: NSRange(location: headingLine.location + 2, length: 0), replacementLength: 1,
                                         before: text, after: text.replacingCharacters(in: NSRange(location: headingLine.location + 2, length: 0), with: "x") as NSString),
                     "An edit in a heading changes its key, so the regions are found again.")
        // The text storage may report the whole line, line break included, as edited.
        let line = text.range(of: "Body two\n")
        let typed = text.replacingCharacters(in: line, with: "Body twox\n") as NSString
        XCTAssertEqual(NoteFolding.regions(regions, across: line, replacementLength: line.length + 1, before: text, after: typed),
                       NoteFolding.regions(in: typed as String))
    }
}

import XCTest
@testable import GraphiteCore

final class MentionTests: XCTestCase {
    private func mentioned(_ names: [String], in text: String) -> [String] {
        Mentions.unlinkedMentions(of: names, in: text).map { range in (text as NSString).substring(with: range) }
    }

    func testFindsPlainMentionsAsWholeWordsIgnoringCase() {
        XCTAssertEqual(mentioned(["Zebra note"], in: "A zebra note here. Zebra Note there. Zebra notes are not it, nor zebra notebook."),
                       ["zebra note", "Zebra Note"])
        XCTAssertEqual(mentioned(["Café"], in: "Meet at the cafe, or the CAFÉ."), ["cafe", "CAFÉ"], "Accents are ignored, as in Obsidian.")
    }

    func testSkipsLinksCodeTagsAndOtherMarkup() {
        let text = """
            ---
            aliases: [Zebra]
            ---
            [[Zebra]] and ![[Zebra.png]] and [Zebra](Zebra.md) and `Zebra` and #Zebra and https://example.com/Zebra
            %% Zebra %% and $Zebra$ and <span>Zebra</span>
            ```
            Zebra
            ```
            $$
            Zebra
            $$
            The Zebra is here.
            """
        let mentions = Mentions.unlinkedMentions(of: ["Zebra"], in: text)
        XCTAssertEqual(mentions.count, 2, "Only the text between the span tags and the last line.")
        XCTAssertEqual(mentions.map { range in (text as NSString).substring(with: range) }, ["Zebra", "Zebra"])
        XCTAssertEqual(mentions.last.map { range in (text as NSString).substring(to: range.location).hasSuffix("The ") }, true)
    }

    func testPrefersTheLongestNameWhereNamesOverlap() {
        XCTAssertEqual(mentioned(["Zebra", "Zebra note"], in: "Zebra note, then Zebra."), ["Zebra note", "Zebra"])
    }

    func testFindsLinksThatCouldNameTheNote() throws {
        let text = "[[Zebra note]], [[Folder/Zebra note#Head|shown]], [z](Folder/Zebra%20note.md), [[Zebra]], ![[Zebra note]], [[Other]], [x](https://zebra note)"
        let links = try Mentions.linkCandidates(in: text, names: ["Zebra note", "Zebra"])
        XCTAssertEqual(links.map(\.target), ["Zebra note", "Folder/Zebra note#Head", "Folder/Zebra%20note.md", "Zebra"],
                       "Embeds and web links are left out; aliases count.")
    }

    func testLinkingAMentionKeepsItsWords() {
        let text = "See zebra note today."
        let range = (text as NSString).range(of: "zebra note")
        let edit = Mentions.linkingEdit(mention: range, in: text, linkTarget: "Zebra note", usesWikilinks: true, markdownDestination: "Zebra%20note.md")
        XCTAssertEqual((text as NSString).replacingCharacters(in: edit.range, with: edit.replacement), "See [[Zebra note|zebra note]] today.")
        let exact = "See Zebra note today."
        let exactEdit = Mentions.linkingEdit(mention: (exact as NSString).range(of: "Zebra note"), in: exact, linkTarget: "Zebra note", usesWikilinks: true, markdownDestination: "")
        XCTAssertEqual(exactEdit.replacement, "[[Zebra note]]")
        let markdown = Mentions.linkingEdit(mention: range, in: text, linkTarget: "Zebra note", usesWikilinks: false, markdownDestination: "Zebra%20note.md")
        XCTAssertEqual(markdown.replacement, "[zebra note](Zebra%20note.md)")
    }

    func testExcerptsMarkTheRange() {
        let text = "Intro line\nA long line where the Zebra note is mentioned somewhere in the middle of it.\n" as NSString
        let range = text.range(of: "Zebra note")
        let match = SearchExcerpts.excerpt(around: range, in: text)
        XCTAssertEqual(match.location, range.location)
        let highlighted = try? XCTUnwrap(match.highlightedRanges.first)
        XCTAssertEqual(highlighted.map { highlight in (match.excerpt as NSString).substring(with: NSRange(location: highlight.lowerBound, length: highlight.count)) }, "Zebra note")
    }
}

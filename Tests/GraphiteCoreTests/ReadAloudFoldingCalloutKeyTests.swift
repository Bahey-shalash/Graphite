import XCTest
@testable import GraphiteCore

/// A callout's expansion is remembered under one key, `type.lowercased() + "|" + the written
/// title trimmed`, which the reading view, Live Preview and Read Aloud all build with
/// `ReadAloudFolding.calloutKey`. Without an entry the callout's `-` or `+` marker decides.
final class ReadAloudFoldingCalloutKeyTests: XCTestCase {
    func testKeyIsTheLowercasedTypeAndTheTrimmedWrittenTitle() throws {
        let header = try XCTUnwrap(NotePreviewDocument.calloutHeader(in: "> [!NOTE]-  Title "))
        XCTAssertEqual(header.type, "note")
        XCTAssertEqual(ReadAloudFolding.calloutKey(type: header.type, title: header.title), "note|Title")
        XCTAssertEqual(ReadAloudFolding.calloutKey(type: "WARNING", title: "\t Mixed Case  "), "warning|Mixed Case")
        XCTAssertEqual(ReadAloudFolding.calloutKey(type: "tip", title: "See [[Plan]] and ==marked=="), "tip|See [[Plan]] and ==marked==")
    }

    func testCalloutWithoutATitleHasTheTypeAsTitleInItsKey() throws {
        let header = try XCTUnwrap(NotePreviewDocument.calloutHeader(in: "> [!note]-"))
        XCTAssertEqual(ReadAloudFolding.calloutKey(type: header.type, title: header.title), "note|Note")
    }

    func testReadingViewBlockProducesTheSameKeyAsTheHeaderLine() throws {
        let blocks = NotePreviewDocument.blocks(from: "> [!NOTE]-  Title \n> body\n")
        guard case .callout(let type, let title, let folding, _)? = blocks.first else { return XCTFail("Expected a callout, got \(blocks)") }
        XCTAssertEqual(folding, .collapsed)
        XCTAssertEqual(ReadAloudFolding.calloutKey(type: type, title: title), "note|Title")
    }

    func testWithoutAnEntryTheMarkerDecidesWhetherReadAloudSkipsTheBody() throws {
        let text = "> [!NOTE]-  Title \n> body\n\n> [!tip]+ Open\n> advice\n\n> [!quote] Plain\n> words\n"
        let source = text as NSString
        let hidden = ReadAloudFolding.hiddenRanges(in: text, foldedKeys: [], calloutExpansion: [:])
        XCTAssertEqual(hidden, [source.range(of: "> body\n")], "Only the body of the '-' callout is skipped.")
    }

    func testAnEntryUnderTheKeyOverridesTheMarker() throws {
        let text = "> [!NOTE]-  Title \n> body\n\n> [!tip]+ Open\n> advice\n"
        let source = text as NSString
        let expanded = ReadAloudFolding.hiddenRanges(in: text, foldedKeys: [], calloutExpansion: ["note|Title": true])
        XCTAssertEqual(expanded, [], "The person expanded the '-' callout, so Read Aloud reads its body.")
        let collapsed = ReadAloudFolding.hiddenRanges(in: text, foldedKeys: [], calloutExpansion: ["note|Title": false, "tip|Open": false])
        XCTAssertEqual(collapsed, [source.range(of: "> body\n"), source.range(of: "> advice\n")])
    }

    func testAnEntryUnderAnyOtherSpellingOfTheKeyIsNotUsed() throws {
        let text = "> [!NOTE]-  Title \n> body\n"
        let source = text as NSString
        for wrongKey in ["NOTE|Title", "note|Title ", "note|title", "note| Title", "Note|Title"] {
            XCTAssertEqual(ReadAloudFolding.hiddenRanges(in: text, foldedKeys: [], calloutExpansion: [wrongKey: true]), [source.range(of: "> body\n")], wrongKey)
        }
    }
}

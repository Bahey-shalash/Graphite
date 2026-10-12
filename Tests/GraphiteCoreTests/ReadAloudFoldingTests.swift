import XCTest
@testable import GraphiteCore

/// "Do not read what is collapsed": folded callouts are read as their title only, folded
/// sections and list items are skipped, and the person's own expansion decides.
final class ReadAloudFoldingTests: XCTestCase {
    private let note = """
    # Lecture

    Opening line.

    > [!note]- Hidden derivation
    > The long hidden proof.

    > [!tip]+ Open tip
    > The visible advice.

    ## Details

    Section text.

    ## After

    Closing line.
    """

    private func spoken(foldedKeys: Set<String> = [], expansion: [String: Bool] = [:]) throws -> [String] {
        let hidden = ReadAloudFolding.hiddenRanges(in: note, foldedKeys: foldedKeys, calloutExpansion: expansion)
        return try ReadAloudDocument.markdown(note, hiddenRanges: hidden).passages.map(\.text)
    }

    func testCollapsedCalloutIsReadAsItsTitleAndAnOpenOneInFull() throws {
        XCTAssertEqual(try spoken(), ["Lecture", "Opening line.", "Hidden derivation", "Open tip", "The visible advice.",
                                      "Details", "Section text.", "After", "Closing line."])
    }

    func testThePersonsOwnExpansionDecides() throws {
        let expanded = try spoken(expansion: [ReadAloudFolding.calloutKey(type: "note", title: "Hidden derivation"): true,
                                              ReadAloudFolding.calloutKey(type: "tip", title: "Open tip"): false])
        XCTAssertTrue(expanded.contains("The long hidden proof."), "A '-' callout the person opened is read.")
        XCTAssertFalse(expanded.contains("The visible advice."), "A '+' callout the person collapsed is skipped.")
        XCTAssertTrue(expanded.contains("Open tip"), "Its title is still read.")
    }

    func testFoldedHeadingSectionIsSkipped() throws {
        let detailsKey = try XCTUnwrap(NoteFolding.regions(in: note).first { region in
            (note as NSString).substring(with: region.headerRange) == "## Details"
        }).key
        let passages = try spoken(foldedKeys: [detailsKey])
        XCTAssertTrue(passages.contains("Details"))
        XCTAssertFalse(passages.contains("Section text."))
        XCTAssertTrue(passages.contains("Closing line."))
    }
}

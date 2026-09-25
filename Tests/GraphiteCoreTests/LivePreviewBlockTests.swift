import XCTest
@testable import GraphiteCore

final class LivePreviewBlockTests: XCTestCase {
    func testFindsRenderedBlocks() {
        let source = """
        ---
        title: A
        ---
        Text
        | a | b |
        | --- | :-: |
        | 1 | $x$ |
        $$
        f = x
        $$
        ![[Figure.png|300]]
        ```base
        views: []
        ```
        ```swift
        | not | a table |
        | --- | --- |
        ```

        ---
        Heading
        ---
        """ as NSString
        let blocks = LivePreviewBlockScanner.blocks(in: source)
        guard blocks.count == 6 else { return XCTFail("Expected 6 blocks, found \(blocks.map(\.kind))") }
        XCTAssertEqual(blocks[0].kind, .frontmatter)
        XCTAssertEqual(source.substring(with: blocks[0].range), "---\ntitle: A\n---\n")
        XCTAssertEqual(blocks[1].kind, .table)
        XCTAssertEqual(blocks[1].markdown, "| a | b |\n| --- | :-: |\n| 1 | $x$ |")
        XCTAssertEqual(blocks[2].kind, .mathBlock)
        XCTAssertEqual(blocks[2].markdown, "$$\nf = x\n$$")
        guard case .embed(let embed) = blocks[3].kind else { return XCTFail("Expected an embed") }
        XCTAssertEqual(embed.target, "Figure.png")
        XCTAssertEqual(embed.displayWidth, 300)
        XCTAssertEqual(blocks[4].kind, .baseDefinition("views: []"))
        XCTAssertEqual(blocks[5].kind, .horizontalRule, "The rule after a blank line; the one after 'Heading' is an underline.")
        XCTAssertEqual(source.substring(with: blocks[5].range), "---\n")
    }

    func testCalloutIncludesItsQuotedBody() {
        let source = "Intro\n> [!note]- Folded title\n> Body with $x$\n>\n> - item\nAfter\n> plain quote\n" as NSString
        let blocks = LivePreviewBlockScanner.blocks(in: source)
        guard blocks.count == 1 else { return XCTFail("Expected only the callout; a plain quote stays text. Found \(blocks.map(\.kind))") }
        XCTAssertEqual(blocks[0].kind, .callout)
        XCTAssertEqual(blocks[0].markdown, "> [!note]- Folded title\n> Body with $x$\n>\n> - item")
        XCTAssertEqual(source.substring(with: blocks[0].range), "> [!note]- Folded title\n> Body with $x$\n>\n> - item\n")
    }

    func testTableNeedsDelimiterRow() {
        XCTAssertTrue(LivePreviewBlockScanner.blocks(in: "| just a pipe line |\nnext" as NSString).isEmpty)
    }
}

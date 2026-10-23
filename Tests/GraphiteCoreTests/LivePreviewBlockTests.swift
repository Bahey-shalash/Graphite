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

    func testPluginCodeBlocksAreBlocksOnlyInLanguagesPluginsDraw() {
        let source = "Intro\n```dataview\nLIST\n```\n```swift\nlet x = 1\n```\n~~~ad-note title\nBody\n~~~\n" as NSString
        XCTAssertTrue(LivePreviewBlockScanner.blocks(in: source).isEmpty, "Without plugins, fenced code stays text.")
        let blocks = LivePreviewBlockScanner.blocks(in: source, pluginCodeBlockLanguages: ["dataview", "ad-note"])
        XCTAssertEqual(blocks.map(\.kind), [.pluginCodeBlock(language: "dataview"), .pluginCodeBlock(language: "ad-note")])
        XCTAssertEqual(blocks[0].markdown, "LIST")
        XCTAssertEqual(source.substring(with: blocks[0].range), "```dataview\nLIST\n```\n")
        XCTAssertEqual(blocks[1].markdown, "Body")
    }

    /// A diagram is its whole fence, closing line and line break included, so the view covers it all; its code is what
    /// lies between the fences, as reading view reads it.
    func testAMermaidFenceIsADiagramBlockOfItsWholeFence() {
        let source = "Intro\n```mermaid\nflowchart TD\n  A --> B\n```\nAfter\n~~~Mermaid\npie\n~~~\n```mermaid\n```\n" as NSString
        let blocks = LivePreviewBlockScanner.blocks(in: source)
        XCTAssertEqual(blocks.map(\.kind), [.mermaidDiagram, .mermaidDiagram, .mermaidDiagram])
        XCTAssertEqual(blocks.map(\.markdown), ["flowchart TD\n  A --> B", "pie", ""])
        XCTAssertEqual(blocks.map { block in source.substring(with: block.range) },
                       ["```mermaid\nflowchart TD\n  A --> B\n```\n", "~~~Mermaid\npie\n~~~\n", "```mermaid\n```\n"])
    }

    func testAnUnclosedMermaidFenceRunsToTheEndOfTheNote() {
        let source = "Intro\n```mermaid\nflowchart TD\n  A --> B\n" as NSString
        let blocks = LivePreviewBlockScanner.blocks(in: source)
        XCTAssertEqual(blocks.map(\.kind), [.mermaidDiagram])
        XCTAssertEqual(blocks.first?.markdown, "flowchart TD\n  A --> B")
        XCTAssertEqual(blocks.first.map { block in NSMaxRange(block.range) }, source.length)
    }

    /// In a callout the diagram is part of the callout's block, which draws its body.
    func testAMermaidFenceInACalloutIsPartOfTheCallout() {
        let blocks = LivePreviewBlockScanner.blocks(in: "> [!note] Flow\n> ```mermaid\n> graph TD\n> ```\n" as NSString)
        XCTAssertEqual(blocks.map(\.kind), [.callout])
    }

    func testThePluginBlockIsFoundOnlyWhenOneBlockMatches() {
        let note = "# Title\n\n```dataview\nLIST\n```\n\n```dataview\nTABLE file.name\n```\n"
        let place = LivePreviewBlockScanner.onlyPluginCodeBlock(language: "dataview", code: "TABLE file.name", in: note)
        XCTAssertEqual(place?.firstLine, 6)
        XCTAssertEqual(place?.lineCount, 3)
        XCTAssertNil(LivePreviewBlockScanner.onlyPluginCodeBlock(language: "dataview", code: "LIST", in: note + "```dataview\nLIST\n```\n"),
                     "Two matching blocks: a plugin must not be given either's lines.")
        XCTAssertNil(LivePreviewBlockScanner.onlyPluginCodeBlock(language: "dataview", code: "TASK", in: note))
    }
}

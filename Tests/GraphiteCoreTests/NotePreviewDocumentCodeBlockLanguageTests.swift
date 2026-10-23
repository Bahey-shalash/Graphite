import XCTest
@testable import GraphiteCore

/// The language of a fenced block decides whether it is a base, a diagram or a community
/// plugin's block. Reading view (`NotePreviewDocument`) and Live Preview (`LivePreviewBlockScanner`)
/// read it by the same rule: a plugin's language is the first word of the info text, matched
/// exactly as written; `base` and `mermaid` are matched without regard to case, on the whole info text.
final class NotePreviewDocumentCodeBlockLanguageTests: XCTestCase {
    private func readingViewBlocks(_ source: String, pluginLanguages: Set<String> = []) -> [NotePreviewBlock] {
        NotePreviewDocument.locatedBlocks(from: source, pluginCodeBlockLanguages: pluginLanguages).map(\.block)
    }

    private func livePreviewKinds(_ source: String, pluginLanguages: Set<String> = []) -> [LivePreviewBlock.Kind] {
        LivePreviewBlockScanner.blocks(in: source as NSString, pluginCodeBlockLanguages: pluginLanguages).map(\.kind)
    }

    func testPluginLanguageIsTheFirstWordOfTheInfoTextInBothScanners() {
        let source = "```dataview table\nTABLE rating\n```"
        XCTAssertEqual(MarkdownFenceSyntax.language(ofInfo: "dataview table"), "dataview")
        XCTAssertEqual(readingViewBlocks(source, pluginLanguages: ["dataview"]), [.pluginCodeBlock(language: "dataview", source: "TABLE rating")])
        XCTAssertEqual(livePreviewKinds(source, pluginLanguages: ["dataview"]), [.pluginCodeBlock(language: "dataview")])
        // The whole info text is not the language.
        XCTAssertEqual(readingViewBlocks(source, pluginLanguages: ["dataview table"]), [.markdown("```dataview table\nTABLE rating\n```")])
        XCTAssertEqual(livePreviewKinds(source, pluginLanguages: ["dataview table"]), [])
    }

    func testPluginLanguageIsMatchedAsWrittenInBothScanners() {
        let source = "```Dataview\nTABLE rating\n```"
        XCTAssertEqual(readingViewBlocks(source, pluginLanguages: ["dataview"]), [.markdown("```Dataview\nTABLE rating\n```")])
        XCTAssertEqual(livePreviewKinds(source, pluginLanguages: ["dataview"]), [])
        XCTAssertEqual(readingViewBlocks(source, pluginLanguages: ["Dataview"]), [.pluginCodeBlock(language: "Dataview", source: "TABLE rating")])
        XCTAssertEqual(livePreviewKinds(source, pluginLanguages: ["Dataview"]), [.pluginCodeBlock(language: "Dataview")])
    }

    func testBaseFenceIsMatchedWithoutRegardToCaseInBothScanners() {
        for info in ["base", "Base", "BASE"] {
            let source = "```\(info)\nviews: []\n```"
            XCTAssertEqual(readingViewBlocks(source), [.baseDefinition("views: []")], "Reading view, \(info)")
            XCTAssertEqual(livePreviewKinds(source), [.baseDefinition("views: []")], "Live Preview, \(info)")
        }
    }

    func testBaseFenceWithMoreInfoTextIsNotABaseInEitherScanner() {
        let source = "```base title\nviews: []\n```"
        XCTAssertEqual(readingViewBlocks(source), [.markdown("```base title\nviews: []\n```")])
        XCTAssertEqual(livePreviewKinds(source), [])
    }

    func testPluginBlockWithoutALanguageIsNeverAPluginBlockInEitherScanner() {
        let source = "```\ncode\n```"
        XCTAssertEqual(readingViewBlocks(source, pluginLanguages: [""]), [.markdown("```\ncode\n```")])
        XCTAssertEqual(livePreviewKinds(source, pluginLanguages: [""]), [])
    }

    func testMermaidFenceIsADiagramMatchedWithoutRegardToCaseOnTheWholeInfoTextInBothScanners() {
        for info in ["mermaid", "Mermaid", "MERMAID"] {
            XCTAssertEqual(readingViewBlocks("```\(info)\nflowchart LR\n  A --> B\n```"), [.mermaidDiagram("flowchart LR\n  A --> B")], "Reading view, \(info)")
            XCTAssertEqual(livePreviewKinds("```\(info)\nflowchart LR\n  A --> B\n```"), [.mermaidDiagram], "Live Preview, \(info)")
        }
        XCTAssertEqual(readingViewBlocks("```mermaid title\nA\n```"), [.markdown("```mermaid title\nA\n```")])
        XCTAssertEqual(livePreviewKinds("```mermaid title\nA\n```"), [])
    }

    func testMermaidFenceIsAPluginsBlockWhenAPluginDrawsMermaidInBothScanners() {
        XCTAssertEqual(readingViewBlocks("```mermaid\ngraph TD\n```", pluginLanguages: ["mermaid"]), [.pluginCodeBlock(language: "mermaid", source: "graph TD")])
        XCTAssertEqual(livePreviewKinds("```mermaid\ngraph TD\n```", pluginLanguages: ["mermaid"]), [.pluginCodeBlock(language: "mermaid")])
        XCTAssertEqual(livePreviewKinds("```mermaid\ngraph TD\n```", pluginLanguages: ["dataview"]), [.mermaidDiagram], "Another plugin's language leaves the diagram")
    }

    func testMermaidFenceSplitsTheMarkdownAroundItAndInsideACallout() {
        XCTAssertEqual(readingViewBlocks("Before\n```mermaid\ngraph TD\n```\nAfter"), [.markdown("Before"), .mermaidDiagram("graph TD"), .markdown("After")])
        XCTAssertEqual(readingViewBlocks("> [!note] Flow\n> ```mermaid\n> graph TD\n> ```"),
                       [.callout(type: "note", title: "Flow", folding: .notFoldable, body: [.mermaidDiagram("graph TD")])])
    }

    /// The two scanners find the same code: Live Preview draws the diagram reading view draws.
    func testBothScannersFindTheSameDiagramCode() throws {
        let source = "Before\n```mermaid\npie\n  \"A\" : 1\n```\nAfter"
        let livePreviewBlock = try XCTUnwrap(LivePreviewBlockScanner.blocks(in: source as NSString).first)
        XCTAssertEqual(livePreviewBlock.kind, .mermaidDiagram)
        XCTAssertEqual(readingViewBlocks(source), [.markdown("Before"), .mermaidDiagram(livePreviewBlock.markdown), .markdown("After")])
    }
}

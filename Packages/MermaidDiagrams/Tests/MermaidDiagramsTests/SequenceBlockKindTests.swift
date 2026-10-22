import XCTest
@testable import MermaidDiagrams

final class SequenceBlockKindTests: XCTestCase {
    func testEachFramedBlockShowsTheKeywordMermaidWritesInItsTab() {
        let keywords = [SequenceBlockKind.loop, .alternatives, .optional, .parallel, .critical, .break].map(\.keyword)
        XCTAssertEqual(keywords, ["loop", "alt", "opt", "par", "critical", "break"])
    }

    func testAHighlightHasNoTab() {
        XCTAssertNil(SequenceBlockKind.highlight(nil).keyword)
        XCTAssertNil(SequenceBlockKind.highlight(SequenceHighlightColor(red: 1, green: 0, blue: 0)).keyword)
    }
}

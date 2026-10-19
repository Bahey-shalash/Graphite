import XCTest
@testable import GraphiteCore

/// Notes and YAML nested deeper than these limits are not given to the recursive parsers,
/// whose stack a deep enough input exhausts. The limits are values the app depends on, so
/// each is pinned with a case just below it and a case just above it.
final class ParserNestingLimitsTests: XCTestCase {
    func testLimitsKeepTheirValues() {
        XCTAssertEqual(MarkdownNesting.maximumContainerDepth, 32)
        XCTAssertEqual(YAMLNesting.maximumFlowDepth, 32)
        XCTAssertEqual(YAMLNesting.maximumBlockIndentation, 64)
        XCTAssertEqual(NotePreviewDocument.maximumCalloutNestingDepth, 16)
        XCTAssertEqual(HTMLToMarkdown.maximumConvertedLength, 2_000_000)
        XCTAssertEqual(NotePreviewDocument.maximumEmbeddedNoteBytes, 1_048_576)
    }

    // MARK: Markdown quotes and lists

    func testMarkdownIsTooDeepOnlyBeyondThirtyTwoQuotes() {
        XCTAssertFalse(MarkdownNesting.exceedsSafeDepth(String(repeating: "> ", count: 32) + "x"))
        XCTAssertTrue(MarkdownNesting.exceedsSafeDepth(String(repeating: "> ", count: 33) + "x"))
    }

    func testMarkdownIndentationCountsOneLevelPerTwoColumnsBeforeAMarker() {
        XCTAssertFalse(MarkdownNesting.exceedsSafeDepth(String(repeating: " ", count: 62) + "- x"), "31 levels of indentation and the marker make 32.")
        XCTAssertTrue(MarkdownNesting.exceedsSafeDepth(String(repeating: " ", count: 64) + "- x"), "32 levels of indentation and the marker make 33.")
    }

    func testMarkdownDepthIsTheDeepestLineNotTheSum() {
        let shallowLines = Array(repeating: String(repeating: "> ", count: 20) + "x", count: 5).joined(separator: "\n")
        XCTAssertFalse(MarkdownNesting.exceedsSafeDepth(shallowLines))
        XCTAssertTrue(MarkdownNesting.exceedsSafeDepth(shallowLines + "\n" + String(repeating: "- ", count: 33) + "x"))
    }

    func testThirtyTwoQuotesAndThirtyThreeAreParsedOnAConcurrencySizedStack() {
        let parsedLinkTargets = onConcurrencySizedStack { depth -> [String] in
            (try? MarkdownSemantics.parse(String(repeating: "> ", count: depth) + "See [[Target]]\n"))?.links.map(\.target) ?? []
        }
        XCTAssertEqual(parsedLinkTargets(32), ["Target"], "Just below the limit the Markdown is parsed.")
        XCTAssertEqual(parsedLinkTargets(33), ["Target"], "Beyond it the note still opens and its links are found.")
    }

    // MARK: YAML

    func testYAMLFlowCollectionsAreTooDeepOnlyBeyondThirtyTwoLevels() {
        func flowYAML(depth: Int) -> String { "key: " + String(repeating: "[", count: depth) + "x" + String(repeating: "]", count: depth) }
        XCTAssertFalse(YAMLNesting.exceedsSafeDepth(flowYAML(depth: 32)))
        XCTAssertTrue(YAMLNesting.exceedsSafeDepth(flowYAML(depth: 33)))
        XCTAssertFalse(YAMLNesting.exceedsSafeDepth("key: " + String(repeating: "{", count: 32) + String(repeating: "}", count: 32)))
        XCTAssertTrue(YAMLNesting.exceedsSafeDepth("key: " + String(repeating: "{", count: 33) + String(repeating: "}", count: 33)))
    }

    func testYAMLBracketsInQuotesAndCommentsAreNotNesting() {
        XCTAssertFalse(YAMLNesting.exceedsSafeDepth("key: \"" + String(repeating: "[", count: 40) + "\""))
        XCTAssertFalse(YAMLNesting.exceedsSafeDepth("key: x # " + String(repeating: "[", count: 40)))
    }

    func testYAMLBlockIndentationIsTooDeepOnlyBeyondSixtyFourColumns() {
        XCTAssertFalse(YAMLNesting.exceedsSafeDepth(String(repeating: " ", count: 64) + "key: 1"))
        XCTAssertTrue(YAMLNesting.exceedsSafeDepth(String(repeating: " ", count: 65) + "key: 1"))
    }

    func testYAMLCompactSequenceIndicatorsCountAsIndentation() {
        XCTAssertFalse(YAMLNesting.exceedsSafeDepth(String(repeating: "- ", count: 32) + "x"))
        XCTAssertTrue(YAMLNesting.exceedsSafeDepth(String(repeating: "- ", count: 33) + "x"))
    }

    func testYAMLBlockScalarContentIsTextAndNotIndentation() {
        let deepText = "description: |\n" + String(repeating: " ", count: 200) + "text\nnext: 1"
        XCTAssertFalse(YAMLNesting.exceedsSafeDepth(deepText))
    }

    // MARK: Callouts

    func testCalloutsNestedSixteenDeepAreCalloutsAndTheSeventeenthStaysQuotedMarkdown() {
        func depthOfCallouts(in blocks: [NotePreviewBlock]) -> (callouts: Int, remainder: String?) {
            var callouts = 0
            var current = blocks
            while case .callout(_, _, _, let body)? = current.first {
                callouts += 1
                current = body
            }
            if case .markdown(let remainder)? = current.first { return (callouts, remainder) }
            return (callouts, nil)
        }
        func nestedCallouts(_ depth: Int) -> String {
            (1...depth).map { level in String(repeating: "> ", count: level) + "[!note] Level \(level)" }.joined(separator: "\n")
        }
        let atLimit = depthOfCallouts(in: NotePreviewDocument.blocks(from: nestedCallouts(16)))
        XCTAssertEqual(atLimit.callouts, 16)
        let beyondLimit = depthOfCallouts(in: NotePreviewDocument.blocks(from: nestedCallouts(17)))
        XCTAssertEqual(beyondLimit.callouts, 16)
        XCTAssertNotNil(beyondLimit.remainder, "The level beyond the limit is left as Markdown.")
    }

    // MARK: Helpers

    /// A function that runs `work` on a thread with the 512 KB stack that Swift concurrency
    /// threads have, where the index parses notes.
    private func onConcurrencySizedStack<Value: Sendable>(_ work: @escaping @Sendable (Int) -> Value) -> (Int) -> Value {
        { depth in
            let resultBox = ResultBox<Value>()
            let finished = DispatchSemaphore(value: 0)
            let thread = Thread {
                resultBox.value = work(depth)
                finished.signal()
            }
            thread.stackSize = 512 * 1_024
            thread.start()
            finished.wait()
            return resultBox.value!
        }
    }
}

/// Written once by the worker thread before it signals the semaphore, and read only after the wait.
private final class ResultBox<Value>: @unchecked Sendable {
    var value: Value?
}

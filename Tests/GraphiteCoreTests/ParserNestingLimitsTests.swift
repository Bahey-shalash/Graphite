import XCTest
@testable import GraphiteCore
import GraphiteTestSupport

/// Notes and YAML nested deeper than these limits are not given to the recursive parsers,
/// whose stack a deep enough input exhausts. The limits are values the app depends on, so
/// each is pinned with a case just below it and a case just above it.
final class ParserNestingLimitsTests: XCTestCase {
    func testLimitsKeepTheirValues() {
        XCTAssertEqual(MarkdownNesting.maximumContainerDepth, 32)
        XCTAssertEqual(YAMLNesting.maximumFlowDepth, 32)
        XCTAssertEqual(YAMLNesting.maximumBlockIndentation, 64)
        XCTAssertEqual(NotePreviewDocument.maximumCalloutNestingDepth, 16)
        XCTAssertEqual(LaTeXCompatibility.maximumAlignmentNestingDepth, 16)
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

    // MARK: Display formulas

    func testAlignmentsNestedSixteenDeepAreRewrittenAndTheSeventeenthIsLeftAsWritten() {
        func nestedAlignments(_ depth: Int) -> String {
            String(repeating: "\\begin{align*}", count: depth) + "x" + String(repeating: "\\end{align*}", count: depth)
        }
        func occurrences(of marker: String, in text: String) -> Int { text.components(separatedBy: marker).count - 1 }
        let atLimit = LaTeXCompatibility.normalized(nestedAlignments(16))
        XCTAssertEqual(occurrences(of: "\\begin{aligned}", in: atLimit), 16)
        XCTAssertEqual(occurrences(of: "\\begin{align*}", in: atLimit), 0)
        let beyondLimit = LaTeXCompatibility.normalized(nestedAlignments(17))
        XCTAssertEqual(occurrences(of: "\\begin{aligned}", in: beyondLimit), 16)
        XCTAssertEqual(occurrences(of: "\\begin{align*}", in: beyondLimit), 1, "The level beyond the limit is left for the typesetter.")
    }

    func testFiveThousandNestedAlignmentsArePreparedOnAConcurrencySizedStack() {
        let formula = Self.nestedAlignedEnvironments(5_000)
        let normalizedLength = onConcurrencySizedStack { _ in LaTeXCompatibility.normalized(formula).count }(5_000)
        let isNumbered = onConcurrencySizedStack { _ in LaTeXCompatibility.numberedEquation(formula + "\\tag{1}") != nil }(5_000)
        XCTAssertGreaterThan(normalizedLength, formula.count / 2, "The formula is prepared rather than dropped.")
        XCTAssertTrue(isNumbered, "A tag after the formula still numbers it.")
    }

    func testNestedAlignmentsArePreparedInTimeProportionalToTheirLength() {
        ScalingChecks.assertScalesLinearly(smallSize: 1_250, largeSize: 5_000, "nested alignment environments") { depth in
            _ = LaTeXCompatibility.normalized(Self.nestedAlignedEnvironments(depth))
        }
    }

    private static func nestedAlignedEnvironments(_ depth: Int) -> String {
        String(repeating: "\\begin{aligned}", count: depth) + "x" + String(repeating: "\\end{aligned}", count: depth)
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

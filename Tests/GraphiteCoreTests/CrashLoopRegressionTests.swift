import XCTest
@testable import GraphiteCore

/// Files from a synced vault that used to crash Graphite. Because the last document
/// reopens and the vault is indexed at every launch, each of these crashed it again on
/// every launch. A regression here crashes the test process instead of failing a test.
final class CrashLoopRegressionTests: XCTestCase {
    // MARK: Numbers that do not fit in Int

    func testFrontmatterNumbersBeyondIntDoNotTrap() throws {
        let semantics = try MarkdownSemantics.parse("---\ntags: 1e300\naliases: [.inf, 12345678901234567890, 7]\n---\nBody\n")
        XCTAssertEqual(semantics.tags.count, 1)
        XCTAssertEqual(semantics.aliases.count, 3)
        XCTAssertTrue(semantics.aliases.contains("7"))
    }

    func testBaseFormulasWithHugeNumbersReturnValuesInsteadOfTrapping() throws {
        let record = BaseTestRecords.record("Notes/Big.md", yaml: "big: 1e20\nnegative: -1e20")
        let evaluator = BaseEvaluator(formulas: [], environment: BaseTestRecords.environment(), thisRecord: nil, knownRecords: [record])
        func value(_ formula: String) throws -> BaseValue { try evaluator.evaluate(sourceText: formula, for: record) }

        XCTAssertEqual(try value("[1, 2][note.big]"), .null)
        XCTAssertEqual(try value("[1, 2][note.negative]"), .null)
        XCTAssertEqual(try value("\"ab\"[note.big]"), .null)
        XCTAssertEqual(try value("[1, 2].slice(0, note.big)"), .list([.number(1), .number(2)]))
        XCTAssertEqual(try value("[1, 2].slice(note.negative)"), .list([.number(1), .number(2)]))
        XCTAssertEqual(try value("\"a,b\".split(\",\", note.big)"), .list([.string("a"), .string("b")]))
        XCTAssertEqual(try value("\"\".repeat(note.big)"), .string(""))
        XCTAssertNoThrow(try value("(1.5).toFixed(note.big)"))
    }

    func testDurationTextForHugeDurationsDoesNotTrap() {
        XCTAssertFalse(BaseDateFormatting.text(for: BaseDuration(milliseconds: 1e300)).isEmpty)
        XCTAssertFalse(BaseDateFormatting.text(for: BaseDuration(milliseconds: -.infinity)).isEmpty)
        XCTAssertFalse(BaseDateFormatting.relativeText(from: Date(timeIntervalSinceReferenceDate: -1e300), to: Date()).isEmpty)
    }

    func testWholeNumberConversionClampsSymmetrically() {
        XCTAssertEqual(Int(clampingWholePartOf: 1e300), .max)
        XCTAssertEqual(Int(clampingWholePartOf: -.infinity), -.max)
        XCTAssertEqual(Int(clampingWholePartOf: -2.7), -2)
        XCTAssertNil(Int(clampingWholePartOf: .nan))
    }

    // MARK: Nesting deep enough to exhaust the stack

    func testDeeplyNestedNotesStillIndexWikilinksAndTags() {
        let deepNotes = [
            String(repeating: "> ", count: 5_000) + "x",
            String(repeating: "- ", count: 5_000) + "x",
            (0..<400).map { level in String(repeating: "  ", count: level) + "- item" }.joined(separator: "\n"),
        ]
        for deepNote in deepNotes {
            let semantics = onConcurrencySizedStack { try? MarkdownSemantics.parse(deepNote + "\n\n[[Target]] #kept\n") }
            XCTAssertEqual(semantics?.links.map(\.target), ["Target"])
            XCTAssertEqual(semantics?.tags, ["kept"])
        }
    }

    func testOrdinaryNestingIsNotTreatedAsTooDeep() {
        let ordinaryNote = """
            - one
              - two
                - three
                  1. four
            > quote
            > > nested quote
            - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
                                                                                  let indentedCode = 1
            """
        XCTAssertFalse(MarkdownNesting.exceedsSafeDepth(ordinaryNote))
        XCTAssertTrue(MarkdownNesting.exceedsSafeDepth(String(repeating: "> ", count: MarkdownNesting.maximumContainerDepth + 1) + "x"))
    }

    func testDeeplyNestedYAMLIsRefusedInsteadOfParsed() {
        let deepFilters = "filters: " + String(repeating: "{and: [", count: 250) + "x" + String(repeating: "]}", count: 250)
        let deepBlock = "root:\n" + (1...300).map { level in String(repeating: " ", count: level) + "key:" }.joined(separator: "\n")
        let definitionError = onConcurrencySizedStack { () -> Error? in
            do { _ = try BaseDefinition.parse(deepFilters); return nil } catch { return error }
        }
        XCTAssertEqual(definitionError as? BaseDefinitionError, .invalidYAML(BaseDefinitionError.nestedTooDeeplyReason))
        XCTAssertThrowsError(try BaseDefinitionEditor(yaml: deepFilters))
        XCTAssertNil(onConcurrencySizedStack { NoteProperties.parse(deepBlock) })
        XCTAssertNil(onConcurrencySizedStack { BaseFrontmatter.entries(fromYAML: deepFilters) })
        let semantics = onConcurrencySizedStack { try? MarkdownSemantics.parse("---\n\(deepFilters)\n---\nBody [[Target]]\n") }
        XCTAssertEqual(semantics?.links.map(\.target), ["Target"])
    }

    func testOrdinaryYAMLIsNotTreatedAsTooDeep() {
        let ordinaryFrontmatter = """
            title: Dune
            tags: [fiction, "classic [1965]"]
            description: |
                                                                                            deeply indented text inside a block scalar
            nested:
              first:
                second: [1, [2, [3]]]
            """
        XCTAssertFalse(YAMLNesting.exceedsSafeDepth(ordinaryFrontmatter))
        XCTAssertNotNil(NoteProperties.parse(ordinaryFrontmatter))
    }

    // MARK: Drawing metadata

    func testDrawingMetadataRoundTripsAndRejectsDeeplyNestedPropertyLists() throws {
        let payload = DrawingPayload(width: 800, height: 600, background: .white, strokes: Data([1, 2, 3]))
        XCTAssertEqual(DrawingPayload.decodeIfValid(try payload.encoded()), payload)

        let nestedXML = "<?xml version=\"1.0\" encoding=\"UTF-8\"?><plist version=\"1.0\"><dict><key>version</key>"
            + String(repeating: "<array>", count: 2_000) + String(repeating: "</array>", count: 2_000) + "</dict></plist>"
        var nestedArray: Any = [1]
        for _ in 0..<2_000 { nestedArray = [nestedArray] }
        let nestedBinary = try PropertyListSerialization.data(fromPropertyList: ["version": nestedArray], format: .binary, options: 0)
        XCTAssertNil(onConcurrencySizedStack { DrawingPayload.decodeIfValid(Data(nestedXML.utf8)) })
        XCTAssertNil(onConcurrencySizedStack { DrawingPayload.decodeIfValid(nestedBinary) })
    }

    // MARK: Helpers

    /// Runs `work` on a thread with the 512 KB stack that Swift concurrency threads have,
    /// which is where the index parses notes.
    private func onConcurrencySizedStack<Value>(_ work: @escaping @Sendable () -> Value) -> Value {
        let resultBox = ResultBox<Value>()
        let finished = DispatchSemaphore(value: 0)
        let thread = Thread {
            resultBox.value = work()
            finished.signal()
        }
        thread.stackSize = 512 * 1_024
        thread.start()
        finished.wait()
        return resultBox.value!
    }
}

/// Written once by the worker thread before it signals the semaphore, and read only after
/// the wait, so the semaphore orders the two accesses.
private final class ResultBox<Value>: @unchecked Sendable {
    var value: Value?
}

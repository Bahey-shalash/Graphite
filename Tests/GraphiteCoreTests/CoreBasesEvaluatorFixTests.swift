import XCTest
@testable import GraphiteCore

/// Regressions for Bases formula evaluation: numbers that do not fit in Int, deep
/// formulas, JavaScript string semantics, and Obsidian's link and date rules.
final class CoreBasesEvaluatorFixTests: XCTestCase {
    private let note = BaseTestRecords.record("Folder/Note.md", yaml: """
        price: "5"
        empty: ""
        big: 1e20
        day: "[[2024-01-05|Friday]]"
        pages: 412
        """, links: [
            BaseTestRecords.wikiLink("Target"),
            BaseRecordLink(target: "https://example.com/page", isEmbed: false, isWiki: false),
            BaseRecordLink(target: "mailto:a@b.c", isEmbed: false, isWiki: false),
            BaseRecordLink(target: "https://example.com/i.png", isEmbed: true, isWiki: false),
            BaseRecordLink(target: "Folder/Image.png", isEmbed: true, isWiki: false),
        ])
    private let target = BaseTestRecords.record("Target.md")
    private let embeddingNote = BaseTestRecords.record("Home/Dashboard.md", yaml: "topic: study")

    private func makeEvaluator(formulas: [BaseFormula] = [], declaredTypes: [String: PropertyType] = [:]) -> BaseEvaluator {
        BaseEvaluator(formulas: formulas, environment: BaseTestRecords.environment(declaredTypes: declaredTypes), thisRecord: embeddingNote,
                      knownRecords: [note, target])
    }

    private func evaluate(_ sourceText: String, declaredTypes: [String: PropertyType] = [:]) throws -> BaseValue {
        try makeEvaluator(declaredTypes: declaredTypes).evaluate(sourceText: sourceText, for: note)
    }

    private func texts(_ sourceText: String) throws -> [String?] {
        guard case .list(let elements) = try evaluate(sourceText) else { XCTFail("\(sourceText) is not a list"); return [] }
        return elements.map { element in element.isNull ? nil : element.displayText }
    }

    // MARK: Numbers that do not fit in Int (F15, F16, F17, F106, F107, F294)

    func testHugeInfiniteAndNaNNumbersNeverTrap() throws {
        XCTAssertEqual(try evaluate("[1, 2][1e400]"), .null)
        XCTAssertEqual(try evaluate("[1, 2][big]"), .null)
        XCTAssertEqual(try evaluate("\"ab\"[1e20]"), .null)
        XCTAssertEqual(try evaluate("[1, 2].slice(0, 1e400)"), .list([.number(1), .number(2)]))
        XCTAssertEqual(try evaluate("[1, 2].slice(-1e400)"), .list([.number(1), .number(2)]))
        XCTAssertEqual(try evaluate("[1, 2].slice(number(\"nan\"))"), .list([.number(1), .number(2)]))
        XCTAssertEqual(try evaluate("\"abc\".slice(10000000000000000000)"), .string(""))
        XCTAssertEqual(try evaluate("\"a,b\".split(\",\", 1e400)"), .list([.string("a"), .string("b")]))
        XCTAssertEqual(try evaluate("\"a,b\".split(\",\", 1e20)"), .list([.string("a"), .string("b")]))
        XCTAssertEqual(try evaluate("\"\".repeat(1e300)"), .string(""))
        XCTAssertEqual(try evaluate("(1).toFixed(number(\"nan\"))"), .string("1"))
    }

    // MARK: Indexes (F395)

    func testOnlyWholeNumbersIndexListsAndText() throws {
        XCTAssertEqual(try evaluate("[1, 2, 3][1]"), .number(2))
        XCTAssertEqual(try evaluate("[1, 2, 3][1.7]"), .null)
        XCTAssertEqual(try evaluate("[1, 2, 3][-1]"), .null)
        XCTAssertEqual(try evaluate("\"abc\"[2]"), .string("c"))
        XCTAssertEqual(try evaluate("\"abc\"[0.5]"), .null)
    }

    // MARK: Links and files (F117, F390, F396)

    func testFileLinksAndEmbedsHoldOnlyVaultLinks() throws {
        XCTAssertEqual(try texts("file.links"), ["Target", "2024-01-05"], "Body links, then the property link.")
        XCTAssertEqual(try texts("file.embeds"), ["Folder/Image.png"])
        XCTAssertEqual(try evaluate("file.hasLink(\"https://example.com/page\")"), .boolean(false))
        XCTAssertEqual(try evaluate("file.hasLink(\"Target\")"), .boolean(true))
    }

    func testEmptyTextNamesNoFile() throws {
        XCTAssertEqual(try evaluate("file(\"\")"), .null)
        XCTAssertEqual(try evaluate("file(empty)"), .null)
        XCTAssertEqual(try evaluate("file(\"\") == file"), .boolean(false))
        XCTAssertEqual(try evaluate("file(\"Target\")"), .file(try VaultPath("Target.md")))
    }

    func testThisSubscriptMatchesThisMember() throws {
        XCTAssertEqual(try evaluate("this[\"file\"].name"), .string("Dashboard.md"))
        XCTAssertEqual(try evaluate("this[\"file\"].name == this.file.name"), .boolean(true))
        XCTAssertEqual(try evaluate("this[\"note\"].topic"), .string("study"))
        XCTAssertEqual(try evaluate("this[\"topic\"]"), .string("study"))
    }

    // MARK: Dates and durations (F110, F111, F391)

    func testDateDifferenceComparesWithMilliseconds() throws {
        XCTAssertEqual(try evaluate("(now() - date(\"2025-09-15\")) > 1000"), .boolean(true))
        XCTAssertEqual(try evaluate("(now() - date(\"2025-09-15\")) < 1000"), .boolean(false))
        XCTAssertEqual(try evaluate("86400000 <= (today() - date(\"2025-09-15\"))"), .boolean(true))
        XCTAssertEqual(try evaluate("(today() - date(\"2025-09-15\")) == 86400000"), .boolean(true))
        XCTAssertEqual(try evaluate("(today() - date(\"2025-09-15\")).days"), .number(1))
    }

    func testDateOfAliasedLinkReadsTheLinkedNoteName() throws {
        XCTAssertEqual(try evaluate("date(day).format(\"YYYY-MM-DD\")"), .string("2024-01-05"))
        XCTAssertEqual(try evaluate("date(link(\"Journal/2024-01-05\", \"Friday\")).format(\"YYYY-MM-DD\")"), .string("2024-01-05"))
        XCTAssertEqual(try evaluate("date(link(\"Meeting\", \"2024-02-03\")).format(\"YYYY-MM-DD\")"), .string("2024-02-03"))
        XCTAssertThrowsError(try evaluate("date(link(\"Meeting\", \"Friday\"))"))
    }

    func testMillisecondIsExact() throws {
        XCTAssertEqual(try evaluate("date(1700000000123).millisecond"), .number(123))
        XCTAssertEqual(try evaluate("date(1700000000999).millisecond"), .number(999))
        XCTAssertEqual(try evaluate("date(1700000000001).millisecond"), .number(1))
        XCTAssertEqual(try evaluate("date(-500).millisecond"), .number(500))
        XCTAssertEqual(try evaluate("date(-1000).millisecond"), .number(0))
    }

    // MARK: Arithmetic (F109, F397)

    func testSubtractionAndAdditionCoerceLikeMultiplication() throws {
        XCTAssertEqual(try evaluate("\"5\" - 2"), .number(3))
        XCTAssertEqual(try evaluate("price - 1"), .number(4))
        XCTAssertEqual(try evaluate("price * 1"), .number(5))
        XCTAssertEqual(try evaluate("true + 1"), .number(2))
        XCTAssertEqual(try evaluate("true - 1"), .number(0))
        XCTAssertEqual(try evaluate("true + false"), .number(1))
        XCTAssertEqual(try evaluate("\"5\" + 1"), .string("51"), "Text still concatenates, as in JavaScript.")
        XCTAssertThrowsError(try evaluate("\"abc\" - 1"))
    }

    func testRoundKeepsNumbersItCannotScale() throws {
        XCTAssertEqual(try evaluate("(1e295).round(15)"), .number(1e295))
        XCTAssertEqual(try evaluate("(4503599627370497).round()"), .number(4_503_599_627_370_497))
        XCTAssertEqual(try evaluate("(2.5).round()"), .number(3))
        XCTAssertEqual(try evaluate("(-2.5).round()"), .number(-2))
        XCTAssertEqual(try evaluate("(1.25).round(1)"), .number(1.3))
    }

    // MARK: Text functions (F392, F393, F394, F697)

    func testEmptyQueriesFollowJavaScript() throws {
        XCTAssertEqual(try evaluate("\"abc\".contains(\"\")"), .boolean(true))
        XCTAssertEqual(try evaluate("\"abc\".containsAll(\"\", \"b\")"), .boolean(true))
        XCTAssertEqual(try evaluate("\"abc\".containsAny(\"\", \"z\")"), .boolean(true))
        XCTAssertEqual(try evaluate("\"abc\".contains(\"z\")"), .boolean(false))
        XCTAssertEqual(try evaluate("\"abc\".replace(\"\", \"x\")"), .string("xabc"))
    }

    func testReplacementUsesJavaScriptPatterns() throws {
        XCTAssertEqual(try evaluate("\"a\".replace(/a/, \"x\\\\y\")"), .string("x\\y"))
        XCTAssertEqual(try evaluate("\"a/b/c\".replace(/\\//g, \"\\\\\")"), .string("a\\b\\c"))
        XCTAssertEqual(try evaluate("\"abc\".replace(/b/, \"[$&]\")"), .string("a[b]c"))
        XCTAssertEqual(try evaluate("\"abc\".replace(\"b\", \"[$&]\")"), .string("a[b]c"))
        XCTAssertEqual(try evaluate("\"abc\".replace(/(b)/g, \"$1$1\")"), .string("abbc"))
        XCTAssertEqual(try evaluate("\"abc\".replace(/b/, \"$$\")"), .string("a$c"))
        XCTAssertEqual(try evaluate("\"abc\".replace(/b/, \"$`\")"), .string("aac"))
        XCTAssertEqual(try evaluate("\"abc\".replace(/b/, \"$'\")"), .string("acc"))
        XCTAssertEqual(try evaluate("\"abc\".replace(/b/, \"$0$2\")"), .string("a$0$2c"))
        XCTAssertEqual(try evaluate("\"2024-01\".replace(/(?<year>\\d+)-(\\d+)/, \"$<year>/$2\")"), .string("2024/01"))
        XCTAssertEqual(try evaluate("\"abc\".replace(/b/, \"$<name>\")"), .string("a$<name>c"))
        XCTAssertEqual(try evaluate("\"abc\".replace(/(?:)/g, \"-\")"), .string("-a-b-c-"))
        XCTAssertEqual(try evaluate("\"aXbX\".replace(/x/gi, \"_\")"), .string("a_b_"))
    }

    func testRegularExpressionSplitFollowsJavaScript() throws {
        XCTAssertEqual(try texts("\"a1b\".split(/(\\d)/)"), ["a", "1", "b"])
        XCTAssertEqual(try texts("\"abc\".split(/(?:)/)"), ["a", "b", "c"])
        XCTAssertEqual(try texts("\"ab\".split(/a*/)"), ["", "b"])
        XCTAssertEqual(try texts("\"a,b\".split(/(,)|(;)/)"), ["a", ",", nil, "b"])
        XCTAssertEqual(try texts("\"a, b,c\".split(/,\\s*/)"), ["a", "b", "c"])
        XCTAssertEqual(try texts("\"\".split(/x/)"), [""])
        XCTAssertEqual(try texts("\"\".split(/(?:)/)"), [])
        XCTAssertEqual(try texts("\"a1b2c\".split(/\\d/, 2)"), ["a", "b"])
    }

    func testRegularExpressionsStayCorrectAcrossRowsAndCalls() throws {
        let evaluator = makeEvaluator()
        for _ in 0..<3 {
            XCTAssertEqual(try evaluator.evaluate(sourceText: "/^Note/.matches(file.name)", for: note), .boolean(true))
            XCTAssertEqual(try evaluator.evaluate(sourceText: "/^note$/i.matches(\"Note\")", for: target), .boolean(true))
            XCTAssertEqual(try evaluator.evaluate(sourceText: "/^Note/.matches(file.name)", for: target), .boolean(false))
            XCTAssertThrowsError(try evaluator.evaluate(sourceText: "/(/.matches(\"a\")", for: note))
        }
    }

    // MARK: unique() (F389)

    func testUniqueKeepsFirstOfEqualValues() throws {
        XCTAssertEqual(try evaluate("[3, 1, 3, 2, 1].unique()"), .list([.number(3), .number(1), .number(2)]))
        XCTAssertEqual(try evaluate("[\"a\", \"b\", \"a\"].unique()"), .list([.string("a"), .string("b")]))
        XCTAssertEqual(try evaluate("[1, \"1\", 2].unique()"), .list([.number(1), .number(2)]), "Numeric text equals its number.")
        XCTAssertEqual(try evaluate("[0, -0, true, true, null, null].unique()"), .list([.number(0), .boolean(true), .null]))
        XCTAssertEqual(try evaluate("[date(\"2024-01-05\"), date(\"2024-01-05\"), date(\"2024-01-06\")].unique().length"), .number(2))
        XCTAssertEqual(try evaluate("[link(\"Target\"), file(\"Target\"), link(\"Target\")].unique().length"), .number(1))
        XCTAssertEqual(try evaluate("[number(\"nan\"), number(\"nan\")].unique().length"), .number(2), "NaN equals nothing, as with ==.")
    }

    func testUniqueOfLongListsIsCompleteAndBounded() throws {
        let evaluator = makeEvaluator()
        let distinctNumbers = (0..<150_000).map { number in BaseValue.number(Double(number)) }
        XCTAssertEqual(try evaluator.evaluateSummary(sourceText: "values.unique().length", values: distinctNumbers + distinctNumbers), .number(150_000))

        let files = (0..<10_001).map { index in BaseValue.file((try? VaultPath("File \(index).md")) ?? .root) }
        XCTAssertThrowsError(try evaluator.evaluateSummary(sourceText: "values.unique()", values: files))
        XCTAssertEqual(try evaluator.evaluateSummary(sourceText: "values.unique().length", values: Array(files.prefix(50)) + Array(files.prefix(50))), .number(50))
    }

    // MARK: Declared types (P63)

    func testDeclaredTypesMatchKeysCaseInsensitivelyOnEveryRead() throws {
        let evaluator = makeEvaluator(declaredTypes: ["Pages": .text])
        for _ in 0..<2 {
            XCTAssertEqual(try evaluator.evaluate(sourceText: "pages", for: note), .string("412"))
            XCTAssertEqual(try evaluator.evaluate(sourceText: "note.pages", for: note), .string("412"))
        }
        XCTAssertEqual(try evaluate("pages"), .number(412))
    }

    // MARK: Deep evaluation (F388)

    func testDeepFormulaChainsFailInsteadOfExhaustingTheStack() {
        let chainLength = 1_000
        let formulas = [BaseFormula(name: "step0", sourceText: "1")]
            + (1...chainLength).map { index in BaseFormula(name: "step\(index)", sourceText: "formula.step\(index - 1) + 1") }
        let note = self.note, target = self.target
        let outcome = onConcurrencySizedStack { () -> (shallow: BaseValue?, deepError: String?) in
            let evaluator = BaseEvaluator(formulas: formulas, environment: BaseTestRecords.environment(), thisRecord: nil, knownRecords: [note, target])
            let shallow = try? evaluator.evaluate(sourceText: "formula.step10", for: note)
            do {
                _ = try evaluator.evaluate(sourceText: "formula.step\(chainLength)", for: note)
                return (shallow, nil)
            } catch {
                return (shallow, error.localizedDescription)
            }
        }
        XCTAssertEqual(outcome?.shallow, .number(11))
        XCTAssertNotNil(outcome?.deepError)
    }

    func testLongMethodChainsFailOrEvaluateWithoutExhaustingTheStack() {
        let note = self.note
        let chainedTrims = "\" a \"" + String(repeating: ".trim()", count: 3_000)
        let nestedConditions = String(repeating: "if(true, ", count: 150) + "1" + String(repeating: ")", count: 150)
        let finished = onConcurrencySizedStack { () -> Bool in
            let evaluator = BaseEvaluator(formulas: [], environment: BaseTestRecords.environment(), thisRecord: nil, knownRecords: [note])
            _ = try? evaluator.evaluate(sourceText: chainedTrims, for: note)
            _ = try? evaluator.evaluate(sourceText: nestedConditions, for: note)
            return true
        }
        XCTAssertEqual(finished, true)
    }

    /// Runs `work` on a thread with the 512 KiB stack of a Swift concurrency thread,
    /// where the base query engine runs in the app.
    private func onConcurrencySizedStack<Value>(_ work: @escaping @Sendable () -> Value) -> Value? {
        let resultBox = EvaluatorResultBox<Value>()
        let finished = DispatchSemaphore(value: 0)
        let thread = Thread {
            resultBox.value = work()
            finished.signal()
        }
        thread.stackSize = 512 * 1_024
        thread.start()
        finished.wait()
        return resultBox.value
    }
}

/// Written once by the worker thread before it signals the semaphore, and read only after
/// the wait, so the semaphore orders the two accesses.
private final class EvaluatorResultBox<Value>: @unchecked Sendable {
    var value: Value?
}

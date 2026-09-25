import XCTest
@testable import GraphiteCore

/// Collects outcomes from a worker thread. `@unchecked Sendable` is sound because every
/// access to `outcomes` holds `lock`.
private final class ThreadOutcomes: @unchecked Sendable {
    private let lock = NSLock()
    private var outcomes: [String: String] = [:]

    func record(_ outcome: String, for name: String) {
        lock.lock()
        defer { lock.unlock() }
        outcomes[name] = outcome
    }

    var recorded: [String: String] {
        lock.lock()
        defer { lock.unlock() }
        return outcomes
    }
}

final class CoreBasesValuesFixTests: XCTestCase {
    private func evaluator() -> BaseEvaluator {
        BaseEvaluator(formulas: [], environment: BaseTestRecords.environment(), thisRecord: nil)
    }

    private func evaluate(_ sourceText: String) throws -> BaseValue {
        try evaluator().evaluate(sourceText: sourceText, for: nil)
    }

    private func sortedTexts(_ values: [BaseValue]) -> [String] {
        values.map(\.normalizedForSorting).sorted { leftValue, rightValue in BaseValue.sortOrder(leftValue, rightValue) == .orderedAscending }.map(\.displayText)
    }

    // MARK: Durations

    func testMultiplyingAHugeCalendarDurationDoesNotTrap() throws {
        guard case .duration(let product) = try evaluate("duration(\"999999999y\") * 999999999") else { return XCTFail("Expected a duration") }
        XCTAssertEqual(product.months, 0, "An overflowing calendar part collapses to exact milliseconds.")
        XCTAssertEqual(product.milliseconds, 11_999_999_988 * 999_999_999 * BaseDuration.averageDaysPerMonth * BaseDuration.millisecondsPerDay, accuracy: 1e20)
        XCTAssertNoThrow(try evaluate("duration(\"1y\") * 100000000 * 100000000 * 100000000"))
        XCTAssertNoThrow(try evaluate("(duration(\"999999999y\") * 999999999 * 999999999).toString()"))
    }

    func testDurationArithmeticKeepsCalendarPartsWhenTheyFit() {
        let duration = BaseDuration(months: 2, days: 3, milliseconds: 500)
        XCTAssertEqual(duration.scaled(by: 3), BaseDuration(months: 6, days: 9, milliseconds: 1_500))
        XCTAssertEqual(duration.negated(), BaseDuration(months: -2, days: -3, milliseconds: -500))
        XCTAssertEqual(duration.adding(BaseDuration(months: 1, days: 1)), BaseDuration(months: 3, days: 4, milliseconds: 500))
    }

    func testDurationArithmeticNeverProducesIntMinimum() {
        let nearMinimum = BaseDuration(months: -Int.max)
        let sum = nearMinimum.adding(BaseDuration(months: -1))
        XCTAssertEqual(sum.months, 0, "Int.min would trap when negated, so the sum collapses to milliseconds.")
        XCTAssertLessThan(sum.milliseconds, 0)
        XCTAssertEqual(BaseDuration(months: Int.max).adding(BaseDuration(months: 1)).months, 0)
        XCTAssertEqual(BaseDuration(days: Int.min).negated().days, 0)
    }

    // MARK: Sorting

    func testTextSortsInNaturalCaseInsensitiveOrder() {
        let values: [BaseValue] = ["apple", "Banana", "item10", "item2", "Zebra", "éclair"].map(BaseValue.string)
        XCTAssertEqual(sortedTexts(values), ["apple", "Banana", "éclair", "item2", "item10", "Zebra"])
    }

    func testSortingMixedTypesIsAStrictWeakOrder() {
        let link = BaseValue.link(BaseLink(target: "5x"))
        XCTAssertEqual(BaseValue.sortOrder(link, .number(9)), .orderedDescending, "Numbers sort before text of any kind.")
        XCTAssertEqual(BaseValue.sortOrder(.number(9), .string("1a")), .orderedAscending)
        XCTAssertEqual(BaseValue.sortOrder(.string("1a"), link), .orderedAscending)

        XCTAssertEqual(BaseValue.sortOrder(.string("a"), .image("B")), .orderedAscending)
        XCTAssertEqual(BaseValue.sortOrder(.image("B"), .string("C")), .orderedAscending)
        XCTAssertEqual(BaseValue.sortOrder(.string("a"), .string("C")), .orderedAscending, "Text pairs use the same order as text against images.")

        XCTAssertEqual(BaseValue.sortOrder(.number(.nan), .number(1)), .orderedDescending, "NaN sorts after every number.")
        XCTAssertEqual(BaseValue.sortOrder(.number(.nan), .number(5)), .orderedDescending)
        XCTAssertEqual(BaseValue.sortOrder(.number(.nan), .number(.nan)), .orderedSame)
    }

    func testEveryTripleOfMixedValuesSortsTransitively() {
        let writtenValues: [BaseValue] = [
            .link(BaseLink(target: "5x")), .number(9), .string("1a"), .string("a"), .image("B"), .string("C"), .number(.nan), .number(1),
            .boolean(true), .file((try? VaultPath("Notes/b.md")) ?? .root), .list([.number(1)]), .string("12"), .string("nan"),
        ]
        let values = writtenValues.map(\.normalizedForSorting)
        for first in values {
            for second in values where BaseValue.sortOrder(first, second) == .orderedAscending {
                for third in values where BaseValue.sortOrder(second, third) == .orderedAscending {
                    XCTAssertEqual(BaseValue.sortOrder(first, third), .orderedAscending, "\(first) < \(second) < \(third)")
                }
            }
        }
    }

    // MARK: Comparison with text

    func testNumbersDoNotEqualNaNOrHexadecimalText() throws {
        XCTAssertEqual(try evaluate("5 == \"NaN\""), .boolean(false))
        XCTAssertEqual(try evaluate("5 <= \"nan\""), .boolean(false))
        XCTAssertEqual(try evaluate("5 >= \"nan\""), .boolean(false))
        XCTAssertEqual(try evaluate("26 == \"0x1A\""), .boolean(false))
        XCTAssertEqual(try evaluate("5 == \" 5 \""), .boolean(true), "Decimal text still compares by value.")
        XCTAssertEqual(try evaluate("1000 == \"1e3\""), .boolean(true))
        XCTAssertEqual(try evaluate("number(\"nan\") == 1"), .boolean(false))
        XCTAssertEqual(try evaluate("number(\"nan\") <= 1"), .boolean(false), "Every comparison with NaN is false, as in JavaScript.")
    }

    func testLinksCompareAsTheirText() {
        let link = BaseValue.link(BaseLink(target: "5x"))
        XCTAssertNil(BaseValue.orderedComparison(link, .number(5)), "Text that is not a number cannot be ordered against one.")
        XCTAssertEqual(BaseValue.orderedComparison(.link(BaseLink(target: "12")), .number(5)), .orderedDescending)
        XCTAssertEqual(BaseValue.orderedComparison(link, .string("5a")), .orderedDescending)
    }

    // MARK: Equality

    func testNaNValuesEqualThemselves() {
        XCTAssertEqual(BaseValue.number(.nan), BaseValue.number(.nan))
        XCTAssertEqual(Set([BaseValue.number(.nan), .number(-.nan), .number(.nan)]).count, 1)
        XCTAssertEqual(BaseValue.list([.number(.nan)]), BaseValue.list([.number(.nan)]))
        XCTAssertEqual(BaseValue.duration(BaseDuration(milliseconds: .nan)), BaseValue.duration(BaseDuration(milliseconds: .nan)))
        XCTAssertEqual(Set([BaseValue.number(0), .number(-0.0)]).count, 1)
        XCTAssertNotEqual(BaseValue.string("x"), BaseValue.image("x"))
        XCTAssertNotEqual(BaseValue.number(1), BaseValue.number(2))
        XCTAssertEqual(Set([BaseValue.string("x"), .image("x"), .icon("x")]).count, 3)
    }

    // MARK: Number text

    func testNumbersFormatLikeJavaScript() {
        let expectations: [(Double, String)] = [
            (1e15, "1000000000000000"), (1.5e15, "1500000000000000"), (1e16, "10000000000000000"),
            (9_007_199_254_740_992, "9007199254740992"), (1e21, "1e+21"), (1.5e21, "1.5e+21"), (1e-5, "0.00001"),
            (1e-6, "0.000001"), (1e-7, "1e-7"), (1.25e-7, "1.25e-7"), (-1e-7, "-1e-7"), (0.1 + 0.2, "0.30000000000000004"),
            (123.456, "123.456"), (-0.5, "-0.5"), (42, "42"), (-0.0, "0"), (5e-324, "5e-324"), (1.7976931348623157e308, "1.7976931348623157e+308"),
            (-2.5e16, "-25000000000000000"), (123_456_789.125, "123456789.125"),
        ]
        for (number, expectedText) in expectations {
            XCTAssertEqual(BaseValue.formatted(number), expectedText, "\(number)")
        }
    }

    // MARK: Links

    func testMarkdownLinkParsingKeepsURLsAndRejectsSeveralLinks() {
        XCTAssertNil(BaseLink.parse("[a](b) and [c](d)"))
        XCTAssertNil(BaseLink.parse("[a](b)(c)"))
        XCTAssertEqual(BaseLink.parse("[Doc](https://example.com/my%20file%2Fx.pdf)")?.target, "https://example.com/my%20file%2Fx.pdf")
        XCTAssertEqual(BaseLink.parse("[Search](https://example.com/?q=a%26b)")?.target, "https://example.com/?q=a%26b")
        XCTAssertEqual(BaseLink.parse("[Note](My%20Note.md)")?.target, "My Note.md", "Note paths are still decoded.")
        XCTAssertEqual(BaseLink.parse("[Wiki](https://en.wikipedia.org/wiki/Swift_(programming_language))")?.target,
                       "https://en.wikipedia.org/wiki/Swift_(programming_language)")
        XCTAssertEqual(BaseLink.parse("[Spaces](<My Note.md>)")?.target, "My Note.md")
        XCTAssertEqual(BaseLink.parse("[Label](Folder/Note.md)")?.display, "Label")
    }

    // MARK: Colors

    func testColorVariableFallback() {
        XCTAssertEqual(BaseColorParsing.color(from: "var(--color-red, #f00)"), .theme("red"))
        XCTAssertEqual(BaseColorParsing.color(from: "var(--my-color, #f00)"), .rgba(red: 1, green: 0, blue: 0, alpha: 1))
        XCTAssertEqual(BaseColorParsing.color(from: "var(--color-custom, blue)"), .rgba(red: 0, green: 0, blue: 1, alpha: 1))
        XCTAssertEqual(BaseColorParsing.color(from: "var(--color-accent, #f00)"), .accent)
        XCTAssertEqual(BaseColorParsing.color(from: "var(--color-custom)"), .theme("custom"))
        XCTAssertNil(BaseColorParsing.color(from: "var(--my-color)"))
    }

    func testColorNumbersFollowCSS() {
        XCTAssertNil(BaseColorParsing.color(from: "rgb(nan, 0, 0)"))
        XCTAssertNil(BaseColorParsing.color(from: "rgb(inf, 0, 0)"))
        XCTAssertNil(BaseColorParsing.color(from: "rgb(0x10, 0, 0)"))
        XCTAssertNil(BaseColorParsing.color(from: "rgba(0, 0, 0, nan)"))
        XCTAssertNil(BaseColorParsing.color(from: "rgba(0, 0, 0, bogus)"))
        XCTAssertEqual(BaseColorParsing.color(from: "rgb(2.55e2, 0, 0)"), .rgba(red: 1, green: 0, blue: 0, alpha: 1), "Exponents are valid CSS numbers.")
        XCTAssertEqual(BaseColorParsing.color(from: "rgb(300, -5, 0)"), .rgba(red: 1, green: 0, blue: 0, alpha: 1), "Out-of-range channels clamp.")
        XCTAssertEqual(BaseColorParsing.color(from: "rgba(0, 0, 255, 0.25)"), .rgba(red: 0, green: 0, blue: 1, alpha: 0.25))
    }

    func testColorArgumentListsFollowCSS() {
        XCTAssertNil(BaseColorParsing.color(from: "rgb(255,,0,0)"))
        XCTAssertNil(BaseColorParsing.color(from: "rgb(1 2 3 4 5 6)"))
        XCTAssertNil(BaseColorParsing.color(from: "rgb(1, 2, 3, 4, 5)"))
        XCTAssertNil(BaseColorParsing.color(from: "rgb(1, 2 3)"))
        XCTAssertNil(BaseColorParsing.color(from: "rgb(1 2)"))
        XCTAssertNil(BaseColorParsing.color(from: "rgb(1 2 3 / 4 / 5)"))
        XCTAssertEqual(BaseColorParsing.color(from: "rgb(255 0 0 / 0.5)"), .rgba(red: 1, green: 0, blue: 0, alpha: 0.5))
        XCTAssertEqual(BaseColorParsing.color(from: "rgba(255,0,0,50%)"), .rgba(red: 1, green: 0, blue: 0, alpha: 0.5))
    }

    func testHueUnits() {
        func assertCyan(_ text: String, file: StaticString = #filePath, line: UInt = #line) {
            guard case .rgba(let red, let green, let blue, _)? = BaseColorParsing.color(from: text) else { return XCTFail(text, file: file, line: line) }
            XCTAssertEqual(red, 0, accuracy: 0.001, text, file: file, line: line)
            XCTAssertEqual(green, 1, accuracy: 0.001, text, file: file, line: line)
            XCTAssertEqual(blue, 1, accuracy: 0.001, text, file: file, line: line)
        }
        assertCyan("hsl(0.5turn 100% 50%)")
        assertCyan("hsl(180deg, 100%, 50%)")
        assertCyan("hsl(180 100% 50%)")
        assertCyan("hsl(200grad 100% 50%)")
        assertCyan("hsl(\(Double.pi)rad 100% 50%)")
        XCTAssertNil(BaseColorParsing.color(from: "hsl(1e999 100% 50%)"))
        XCTAssertNil(BaseColorParsing.color(from: "hsl(1e308turn 100% 50%)"))
        XCTAssertNil(BaseColorParsing.color(from: "hsl(180furlongs 100% 50%)"))
    }

    func testEveryCSSColorName() {
        XCTAssertEqual(BaseColorParsing.color(from: "lightgray"), .rgba(red: Double(0xD3) / 255, green: Double(0xD3) / 255, blue: Double(0xD3) / 255, alpha: 1))
        XCTAssertEqual(BaseColorParsing.color(from: "DarkGrey"), .rgba(red: Double(0xA9) / 255, green: Double(0xA9) / 255, blue: Double(0xA9) / 255, alpha: 1))
        XCTAssertEqual(BaseColorParsing.color(from: "transparent"), .rgba(red: 0, green: 0, blue: 0, alpha: 0))
        for name in ["whitesmoke", "aliceblue", "papayawhip", "lightgoldenrodyellow", "mediumspringgreen", "yellowgreen", "rebeccapurple"] {
            XCTAssertNotNil(BaseColorParsing.color(from: name), name)
        }
    }

    // MARK: String escapes

    func testJavaScriptStringEscapes() throws {
        XCTAssertEqual(try evaluate(#""😀""#), .string("😀"))
        XCTAssertEqual(try evaluate(#""\u{1F600}""#), .string("😀"))
        XCTAssertEqual(try evaluate(#""A\x42""#), .string("AB"))
        XCTAssertEqual(try evaluate(#""a\0b""#), .string("a\u{0}b"))
        XCTAssertEqual(try evaluate(#""\b\f\v""#), .string("\u{8}\u{C}\u{B}"))
        XCTAssertEqual(try evaluate(#""\q\"\\""#), .string("q\"\\"))
        XCTAssertEqual(try evaluate(#""\uD83D!""#), .string("\u{FFFD}!"), "A lone surrogate becomes the replacement character.")
        for malformed in [#""\u+041""#, #""\u-000""#, #""\u12""#, #""\x4""#, #""\u{}""#, #""\u{110000}""#, #""\u{1234567}""#] {
            XCTAssertThrowsError(try BaseExpression.parse(malformed), malformed)
        }
    }

    // MARK: Nesting

    /// Runs `body` on a thread with the 512 KB stack that secondary threads get on iOS,
    /// where Bases work runs through `Task.detached`.
    private func runOnSmallStack(_ body: @escaping @Sendable () -> Void) {
        let finished = expectation(description: "The small-stack thread finished")
        let thread = Thread {
            body()
            finished.fulfill()
        }
        thread.stackSize = 512 * 1_024
        thread.start()
        wait(for: [finished], timeout: 120)
    }

    func testLongFlatChainsAreRejectedWithoutOverflowingTheStack() {
        let outcomes = ThreadOutcomes()
        runOnSmallStack {
            let longChains = [
                "sum": Array(repeating: "1", count: 10_000).joined(separator: "+"),
                "member": "a" + String(repeating: ".b", count: 10_000),
                "method": "\"x\"" + String(repeating: ".lower()", count: 10_000),
                "subscript": "[1]" + String(repeating: "[0]", count: 10_000),
            ]
            for (name, sourceText) in longChains {
                do {
                    _ = try BaseExpression.parse(sourceText)
                    outcomes.record("parsed", for: name)
                } catch {
                    outcomes.record(error.localizedDescription, for: name)
                }
            }
        }
        for (name, outcome) in outcomes.recorded {
            XCTAssertTrue(outcome.contains("nested too deeply"), "\(name): \(outcome)")
        }
        XCTAssertEqual(outcomes.recorded.count, 4)
    }

    /// The deepest expression of each shape that the parser accepts: `maximumStackCost`
    /// bounds the tree (a function call costs 4, a method call 3, anything else 1) and
    /// `maximumNestingDepth` bounds the parser's own recursion.
    private static func deepestAllowedExpressions() -> [String: String] {
        let cost = BaseExpressionParser.maximumStackCost, depth = BaseExpressionParser.maximumNestingDepth
        return [
            "sum": Array(repeating: "1", count: cost - 1).joined(separator: "+"),
            "method": "\"X\"" + String(repeating: ".lower()", count: (cost - 2) / 3),
            "subscript": "\"x\"" + String(repeating: "[0]", count: cost - 2),
            "parentheses": String(repeating: "(", count: depth - 3) + "1+1" + String(repeating: ")", count: depth - 3),
            "function": String(repeating: "max(", count: (cost - 2) / 4) + "1" + String(repeating: ")", count: (cost - 2) / 4),
            "list": String(repeating: "[", count: depth - 2) + "1" + String(repeating: "]", count: depth - 2),
            "conditional": String(repeating: "if(true, ", count: (cost - 2) / 4) + "1" + String(repeating: ", 0)", count: (cost - 2) / 4),
            "negation": String(repeating: "!", count: depth - 2) + "true",
            "lambda": String(repeating: "[1].map(", count: (cost - 2) / 3) + "value" + String(repeating: ")", count: (cost - 2) / 3),
        ]
    }

    func testDeepestAllowedExpressionsEvaluateOnASmallStack() {
        let outcomes = ThreadOutcomes()
        runOnSmallStack {
            let evaluator = BaseEvaluator(formulas: [], environment: BaseTestRecords.environment(), thisRecord: nil)
            for (name, sourceText) in Self.deepestAllowedExpressions() {
                do {
                    let expression = try BaseExpression.parse(sourceText)
                    _ = expression.dependsOnCurrentRow
                    _ = expression.hashValue
                    outcomes.record(try evaluator.evaluate(expression, for: nil).displayText, for: name)
                } catch {
                    outcomes.record("error: \(error.localizedDescription)", for: name)
                }
            }
            outcomes.record("finished", for: "all")
        }
        let recorded = outcomes.recorded
        XCTAssertEqual(recorded["all"], "finished")
        XCTAssertEqual(recorded["sum"], String(BaseExpressionParser.maximumStackCost - 1))
        XCTAssertEqual(recorded["method"], "x")
        XCTAssertEqual(recorded["subscript"], "x")
        XCTAssertEqual(recorded["parentheses"], "2")
        XCTAssertEqual(recorded["function"], "1")
        XCTAssertEqual(recorded["list"], "1")
        XCTAssertEqual(recorded["negation"], "true")
        XCTAssertEqual(recorded["conditional"], "1")
        XCTAssertEqual(recorded["lambda"], "1")
    }

    func testNestingOneLevelPastTheLimitIsReported() {
        let cost = BaseExpressionParser.maximumStackCost, depth = BaseExpressionParser.maximumNestingDepth
        let tooDeep = [
            Array(repeating: "1", count: cost).joined(separator: "+"),
            "\"X\"" + String(repeating: ".lower()", count: (cost - 2) / 3 + 1),
            String(repeating: "max(", count: (cost - 2) / 4 + 1) + "1" + String(repeating: ")", count: (cost - 2) / 4 + 1),
            String(repeating: "(", count: depth - 2) + "1+1" + String(repeating: ")", count: depth - 2),
            String(repeating: "!", count: depth - 1) + "true",
        ]
        for sourceText in tooDeep {
            XCTAssertThrowsError(try BaseExpression.parse(sourceText), sourceText) { error in
                XCTAssertTrue(error.localizedDescription.contains("nested too deeply"), error.localizedDescription)
            }
        }
        for (name, sourceText) in Self.deepestAllowedExpressions() {
            XCTAssertNoThrow(try BaseExpression.parse(sourceText), name)
        }
    }
}

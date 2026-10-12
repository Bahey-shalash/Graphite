import XCTest
import GraphiteCore
@testable import GraphiteApple

final class ReadAloudMathematicsTests: XCTestCase {
    func testOfflineEngineReadsStructuredTechnicalMathematics() async throws {
        let preparation = ReadAloudMarkdownPreparation()
        let fixtures = [
            (#"\sum_{n=1}^{N} n^2"#, "the sum from n equals 1 to N of n squared"),
            (#"\int_0^1 x^2\,dx"#, "the integral from 0 to 1 of x squared d x"),
            (#"\prod_{k=1}^{n} k"#, "the product from k equals 1 to n of k"),
            (#"\lim_{x\to 0} \frac{\sin x}{x}"#, "lim over x right arrow 0 of sine x over x"),
            (#"\begin{pmatrix}a&b\\c&d\end{pmatrix}"#, "the 2 by 2 matrix Row 1: a b Row 2: c d"),
            (#"\begin{cases}x^2&x\ge0\\-x&x<0\end{cases}"#, "2 cases Case 1: x squared x is greater than or equal to 0 Case 2: negative x x is less than 0"),
            (#"\begin{aligned}a&=b+c\\d&=e\end{aligned}"#, "2 lines Line 1: a equals b plus c Line 2: d equals e"),
            (#"\sqrt[3]{x}"#, "the cube root of x"),
            (#"\operatorname{rank}(A)"#, "rank of A"),
            (#"\frac{df}{dx}"#, "d f over d x"),
            (#"\vec{v}\cdot\vec{w}"#, "v right arrow times w right arrow"),
            (#"\color{purple}x^2"#, "x squared"),
            (#"\frac{a+b}{c}"#, "the fraction with numerator a plus b and denominator c")
        ]
        for (expression, expectedSpeech) in fixtures {
            let source = "Read $\(expression)$ now."
            let document = try await preparation.prepare(source)
            XCTAssertEqual(document.passages.map(\.text).joined(separator: " "), "Read \(expectedSpeech) now.")
            XCTAssertTrue(document.notices.isEmpty)
            let passage = try XCTUnwrap(document.passages.first)
            let spokenRange = (passage.text as NSString).range(of: expectedSpeech)
            let sourceRange = try XCTUnwrap(passage.sourceRange(for: spokenRange))
            XCTAssertEqual((source as NSString).substring(with: sourceRange), "$\(expression)$")
            XCTAssertEqual(ReadAloudSourceToken.tokens(in: document).filter(\.isEquation).count, 1)
        }
    }

    func testGroupingSignsAndScriptsRemainMathematicallyDistinct() async throws {
        let preparation = ReadAloudMarkdownPreparation()
        let fixtures = [
            ("(a+b)/c", "open paren a plus b close paren divided by c"),
            ("a+b/c", "a plus b divided by c"),
            ("-x^2", "negative x squared"),
            ("(-x)^2", "open paren negative x close paren squared")
        ]
        for (expression, expectedSpeech) in fixtures {
            let document = try await preparation.prepare("$\(expression)$")
            XCTAssertEqual(document.passages.map(\.text), [expectedSpeech])
        }
    }

    func testDetailedSpeechRetainsFractionGroupingAndStylesDoNotLeak() async throws {
        let preparation = ReadAloudMarkdownPreparation()
        let source = #"$\frac{a+b}{c}$"#
        let detailed = try await preparation.prepare(source, mathematicalStyle: .detailed)
        XCTAssertEqual(detailed.passages.map(\.text), ["StartFraction a plus b Over c EndFraction"])
        let concise = try await preparation.prepare(source)
        XCTAssertEqual(concise.passages.map(\.text), ["the fraction with numerator a plus b and denominator c"])
    }

    func testUnknownAndMalformedEquationsAreAnnouncedWithoutExecutingSource() async throws {
        let preparation = ReadAloudMarkdownPreparation()
        for expression in [#"\unknown{x}"#, #"\frac{a}"#, #"\input{secret}"#, #"\href{https://example.org}{x}"#,
                           #"\newcommand{\f}{x}\f"#, #"\begin{matrix}x\end{cases}"#] {
            let document = try await preparation.prepare("Before $\(expression)$ after.")
            XCTAssertEqual(document.passages.map(\.text), ["Before Equation not yet supported. after."], expression)
            XCTAssertFalse(document.notices.isEmpty)
        }
        let prose = try await preparation.prepare("Plain words.")
        XCTAssertEqual(prose.passages.map(\.text), ["Plain words."])
    }

    func testOversizedAndDeepMathematicsFailSafelyThenEngineRemainsUsable() async throws {
        let preparation = ReadAloudMarkdownPreparation()
        let expressions = [String(repeating: "x+", count: 4_097) + "x",
                           String(repeating: "{", count: 33) + "x" + String(repeating: "}", count: 33),
                           String(repeating: #"\left("#, count: 33) + "x" + String(repeating: #"\right)"#, count: 33)]
        for expression in expressions {
            let document = try await preparation.prepare("$\(expression)$")
            XCTAssertEqual(document.passages.map(\.text), ["Equation not yet supported."])
        }
        let valid = try await preparation.prepare("$x^2$")
        XCTAssertEqual(valid.passages.map(\.text), ["x squared"])
    }

    func testCanceledPreparationDoesNotPreventTheNextRequest() async throws {
        let preparation = ReadAloudMarkdownPreparation()
        let source = String(repeating: "Read $x^2$.\n\n", count: 20_000)
        let worker = Task { try await preparation.prepare(source) }
        try await Task.sleep(for: .milliseconds(10))
        worker.cancel()
        do {
            _ = try await worker.value
            XCTFail("A canceled note must not finish preparing.")
        } catch is CancellationError {
        }
        let valid = try await preparation.prepare("$x^2$")
        XCTAssertEqual(valid.passages.map(\.text), ["x squared"])
    }
}

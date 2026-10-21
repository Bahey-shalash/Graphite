import GraphiteTestSupport
import XCTest
@testable import GraphiteCore

final class SearchQueryParserTests: XCTestCase {
    func testParsesObsidianSearchSyntax() {
        XCTAssertEqual(SearchQueryParser.parse("meeting -work"),
                       .all([.term(SearchTerm(text: "meeting", kind: .word)), .not(.term(SearchTerm(text: "work", kind: .word)))]))
        XCTAssertEqual(SearchQueryParser.parse("a b OR c"),
                       .any([.all([.term(SearchTerm(text: "a", kind: .word)), .term(SearchTerm(text: "b", kind: .word))]), .term(SearchTerm(text: "c", kind: .word))]))
        XCTAssertEqual(SearchQueryParser.parse("path:\"Daily notes/2022\" -(x y)"),
                       .all([.scoped(.path, .term(SearchTerm(text: "Daily notes/2022", kind: .phrase))),
                             .not(.all([.term(SearchTerm(text: "x", kind: .word)), .term(SearchTerm(text: "y", kind: .word))]))]))
        XCTAssertEqual(SearchQueryParser.parse("[status:draft OR done]"),
                       .property(name: "status", value: .any([.term(SearchTerm(text: "draft", kind: .word)), .term(SearchTerm(text: "done", kind: .word))])))
        XCTAssertEqual(SearchQueryParser.parse("/\\d{4}-\\d{2}/"), .term(SearchTerm(text: "\\d{4}-\\d{2}", kind: .regularExpression)))
        XCTAssertEqual(SearchQueryParser.parse("\"say \\\"hi\\\"\""), .term(SearchTerm(text: "say \"hi\"", kind: .phrase)))
        XCTAssertEqual(SearchQueryParser.parse("file:\u{201C}14 Review\u{201D}"), .scoped(.file, .term(SearchTerm(text: "14 Review", kind: .phrase))),
                       "Curly quotes from the iPad keyboard quote a phrase.")
    }

    func testForgivesUnbalancedInput() {
        XCTAssertEqual(SearchQueryParser.parse("(a OR b"), .any([.term(SearchTerm(text: "a", kind: .word)), .term(SearchTerm(text: "b", kind: .word))]))
        XCTAssertEqual(SearchQueryParser.parse("a) b"), .all([.term(SearchTerm(text: "a", kind: .word)), .term(SearchTerm(text: "b", kind: .word))]))
        XCTAssertNil(SearchQueryParser.parse("   "))
        XCTAssertNil(SearchQueryParser.parse("OR"))
        XCTAssertEqual(SearchQueryParser.parse("\"unclosed phrase"), .term(SearchTerm(text: "unclosed phrase", kind: .phrase)))
        XCTAssertEqual(SearchQueryParser.parse("e-mail"), .term(SearchTerm(text: "e-mail", kind: .word)), "A hyphen inside a word does not exclude.")
    }
}

import Foundation
import XCTest
@testable import GraphiteCore

final class MarkdownListSyntaxTests: XCTestCase {
    /// `listMarker` reads by hand what `listLineRanges` reads with its pattern; every line
    /// built from the pieces of the rule gets the same marker from both.
    func testTheHandWrittenMarkerReaderAgreesWithThePatternOnEveryCombination() {
        let quotePrefixes = ["", ">", "> ", ">\t", " > > ", ">>", "  >  > "]
        let indentations = ["", " ", "   ", "    ", "\t", " \t "]
        let markers = ["-", "*", "+", "1.", "1)", "123456789.", "1234567890.", "12)", "a.", "-.", "#", "", ".", "١."]
        let spacings = ["", " ", "\t", "  ", "x"]
        let rests = ["", "item", "- -", "* *", "-", "[x] task", "[ ]", "\u{00A0}text"]
        var comparedLineCount = 0
        for quotePrefix in quotePrefixes {
            for indentation in indentations {
                for marker in markers {
                    for spacing in spacings {
                        for rest in rests {
                            let line = quotePrefix + indentation + marker + spacing + rest
                            let text = line as NSString
                            let wholeLine = NSRange(location: 0, length: text.length)
                            let patternMarker = MarkdownListSyntax.listLineRanges(in: text, range: wholeLine).flatMap { ranges in ranges.isListItem ? ranges.marker : nil }
                            XCTAssertEqual(MarkdownListSyntax.listMarker(in: text, range: wholeLine), patternMarker, "\(line.debugDescription)")
                            XCTAssertEqual(MarkdownListSyntax.isListItem(line), patternMarker != nil, "\(line.debugDescription)")
                            comparedLineCount += 1
                        }
                    }
                }
            }
        }
        XCTAssertEqual(comparedLineCount, 7 * 6 * 14 * 5 * 8)
    }

    func testTheMarkerReaderAnswersForThePartOfALineItIsGiven() {
        let text = "intro\n  - item\nafter" as NSString
        XCTAssertEqual(MarkdownListSyntax.listMarker(in: text, range: NSRange(location: 6, length: 8)), NSRange(location: 8, length: 1))
        XCTAssertNil(MarkdownListSyntax.listMarker(in: text, range: NSRange(location: 0, length: 5)))
    }
}

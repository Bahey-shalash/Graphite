import XCTest
@testable import GraphiteCore

/// Text Read Aloud must not say (frontmatter, comments, equations replaced by markers) is
/// masked inside a copy of the note, unit for unit, so every offset the speech reports still
/// points at the same place in the note the person wrote.
final class ReadAloudDocumentMaskingTests: XCTestCase {
    private static let wordJoiner = "\u{2060}"
    private static let firstMarker = "\u{E100}"

    private func spokenEquation(_ expression: String) -> String { "EQUATION(\(expression))" }

    private func document(_ note: String, selectedRange: NSRange? = nil) throws -> ReadAloudDocument {
        try ReadAloudDocument.markdown(note, selectedRange: selectedRange, mathematicalSpeech: { expression in "EQUATION(\(expression))" })
    }

    func testHiddenTextAcrossCarriageReturnAndLineFeedLinesIsNotSpokenAndOffsetsStayExact() throws {
        let note = "---\r\nsecret: private\r\n---\r\nBefore the comment.\r\n\r\n%% hidden\r\nacross lines %%\r\n\r\nAfter the comment with café."

        let read = try document(note)

        let spoken = read.passages.map(\.text).joined(separator: " ")
        XCTAssertFalse(spoken.contains("hidden"))
        XCTAssertFalse(spoken.contains("private"))
        XCTAssertFalse(spoken.contains(Self.wordJoiner), "The masking character is never spoken.")
        XCTAssertEqual(read.passages.map(\.text), ["Before the comment.", "After the comment with café."])
        for word in ["Before", "comment", "After", "café"] {
            let passage = try XCTUnwrap(read.passages.first { passage in passage.text.contains(word) })
            let sourceRange = try XCTUnwrap(passage.sourceRange(for: (passage.text as NSString).range(of: word)))
            XCTAssertEqual((note as NSString).substring(with: sourceRange), word)
        }
    }

    func testFoldedRangesAreMaskedAndTheRestKeepsItsOffsets() throws {
        let note = "Visible one.\n\nFolded away text.\n\nVisible two."
        let folded = (note as NSString).range(of: "Folded away text.")

        let read = try ReadAloudDocument.markdown(note, hiddenRanges: [folded])

        XCTAssertEqual(read.passages.map(\.text), ["Visible one.", "Visible two."])
        let second = try XCTUnwrap(read.passages.last)
        let sourceRange = try XCTUnwrap(second.sourceRange(for: NSRange(location: 0, length: second.text.utf16.count)))
        XCTAssertEqual((note as NSString).substring(with: sourceRange), "Visible two.")
    }

    func testOneEquationIsOneSpanThatCoversItsWholeWrittenForm() throws {
        let note = "Energy is $x^2$ here."

        let passage = try XCTUnwrap(try document(note).passages.first)

        let equationSpans = passage.spans.filter(\.isEquation)
        XCTAssertEqual(equationSpans.count, 1)
        let span = try XCTUnwrap(equationSpans.first)
        XCTAssertFalse(span.isVerbatim)
        XCTAssertEqual((passage.text as NSString).substring(with: span.speechRange), spokenEquation("x^2"))
        XCTAssertEqual((note as NSString).substring(with: span.sourceRange), "$x^2$")
        XCTAssertEqual(passage.text, "Energy is \(spokenEquation("x^2")) here.")
    }

    func testADisplayEquationOverSeveralLinesIsOneSpan() throws {
        let note = "Before.\n\n$$\na + b\n= c\n$$\n\nAfter."

        let read = try document(note)

        let equationSpans = read.passages.flatMap(\.spans).filter(\.isEquation)
        XCTAssertEqual(equationSpans.count, 1)
        XCTAssertEqual((note as NSString).substring(with: try XCTUnwrap(equationSpans.first).sourceRange), "$$\na + b\n= c\n$$")
    }

    func testANoteThatContainsTheFirstMarkerScalarStillReadsItsEquation() throws {
        let note = "Private use \(Self.firstMarker) in the note, then $x^2$ and $y$."

        let passage = try XCTUnwrap(try document(note).passages.first)

        let equationSpans = passage.spans.filter(\.isEquation)
        XCTAssertEqual(equationSpans.count, 2)
        XCTAssertEqual(equationSpans.map { span in (note as NSString).substring(with: span.sourceRange) }, ["$x^2$", "$y$"])
        XCTAssertEqual(equationSpans.map { span in (passage.text as NSString).substring(with: span.speechRange) },
                       [spokenEquation("x^2"), spokenEquation("y")])
        XCTAssertTrue(passage.text.hasPrefix("Private use \(Self.firstMarker) in the note, then "),
                      "The note's own private-use character is read as it is, not taken for an equation.")
    }

    func testNoMarkerScalarOfTheSpokenTextSurvivesIntoThePassage() throws {
        let passage = try XCTUnwrap(try document("One $a$, two $b$, three $c$.").passages.first)

        XCTAssertFalse(passage.text.unicodeScalars.contains { scalar in (0xE100...0xF8FF).contains(scalar.value) })
    }
}

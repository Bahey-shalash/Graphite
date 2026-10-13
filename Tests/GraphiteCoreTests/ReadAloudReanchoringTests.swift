import XCTest
@testable import GraphiteCore

/// Finding the sentence being read again after the note around it was edited.
final class ReadAloudReanchoringTests: XCTestCase {
    private let note = "# Title\n\nFirst sentence here. The second sentence is read now. A third one follows.\n\nAnother paragraph."

    private func anchorOfSecondSentence() throws -> ReadAloudReanchoring.Anchor {
        let document = try ReadAloudDocument.markdown(note)
        let passage = try XCTUnwrap(document.passages.first { passage in passage.text.contains("second") })
        let offset = (passage.text as NSString).range(of: "read now").location
        return try XCTUnwrap(ReadAloudReanchoring.anchor(in: note, passage: passage, spokenOffset: offset))
    }

    func testTheSentenceIsFoundAgainAfterAnEditAboveIt() throws {
        let anchor = try anchorOfSecondSentence()
        XCTAssertEqual(anchor.text, "The second sentence is read now.")
        let edited = "Added at the top.\n\n" + note
        let location = try XCTUnwrap(ReadAloudReanchoring.location(of: anchor, in: edited))
        XCTAssertTrue((edited as NSString).substring(from: location).hasPrefix("The second sentence"))
        let document = try ReadAloudDocument.markdown(edited)
        let position = ReadAloudReanchoring.position(of: location, in: document)
        let passage = document.passages[position.passageIndex]
        XCTAssertTrue((passage.text as NSString).substring(from: position.offset).hasPrefix("The second sentence"), passage.text)
    }

    func testAnEditInsideTheSentenceKeepsItsStartAndARemovedSentenceIsNotFound() throws {
        let anchor = try anchorOfSecondSentence()
        let editedEnd = note.replacingOccurrences(of: "is read now.", with: "is being read right now, slowly.")
        let longAnchor = ReadAloudReanchoring.Anchor(text: anchor.text + " A third one follows and goes on for a while longer", location: anchor.location)
        XCTAssertNotNil(ReadAloudReanchoring.location(of: anchor, in: note))
        XCTAssertNil(ReadAloudReanchoring.location(of: anchor, in: editedEnd), "A short sentence edited is not guessed at.")
        let longNote = note.replacingOccurrences(of: "A third one follows.", with: "A third one follows and goes on for a while longer.")
        let editedLong = longNote.replacingOccurrences(of: "for a while longer", with: "briefly")
        let found = try XCTUnwrap(ReadAloudReanchoring.location(of: longAnchor, in: editedLong))
        XCTAssertTrue((editedLong as NSString).substring(from: found).hasPrefix("The second sentence"))
        XCTAssertNil(ReadAloudReanchoring.location(of: anchor, in: note.replacingOccurrences(of: "The second sentence is read now. ", with: "")))
    }

    func testTheNearestOccurrenceWins() {
        let text = "Repeat. Middle. Repeat. End."
        XCTAssertEqual(ReadAloudReanchoring.range(of: "Repeat.", near: 15, in: text)?.location, 16)
        XCTAssertEqual(ReadAloudReanchoring.range(of: "Repeat.", near: 2, in: text)?.location, 0)
    }
}

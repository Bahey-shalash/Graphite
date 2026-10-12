import XCTest
@testable import GraphiteCore

/// Where documents were left, so they open there again after the app quits.
final class DocumentPlacesTests: XCTestCase {
    private func path(_ rawPath: String) throws -> VaultPath { try VaultPath(rawPath) }

    func testPlacesAreKeptPerDocumentAndTheStartIsNotKept() throws {
        var memory = DocumentPlaceMemory()
        let note = try path("Courses/Signals.md"), slides = try path("Courses/Lecture 3.pdf")
        let notePlace = DocumentPlace.note(NotePlace(topLocation: 1_200, selectionLocation: 1_250, selectionLength: 4))
        let slidesPlace = DocumentPlace.pdf(PDFPagePlace(pageIndex: 12, fractionFromTop: 0.4))
        memory.remember(notePlace, of: note, at: Date(timeIntervalSince1970: 10))
        memory.remember(slidesPlace, of: slides, at: Date(timeIntervalSince1970: 11))
        XCTAssertEqual(memory.place(of: note), notePlace)
        XCTAssertEqual(memory.place(of: slides), slidesPlace)
        XCTAssertNil(memory.place(of: try path("Courses/Other.md")))

        // Back at the start, a document is forgotten: it opens there anyway.
        memory.remember(.note(NotePlace(topLocation: 0, selectionLocation: 0, selectionLength: 0)), of: note, at: Date(timeIntervalSince1970: 12))
        memory.remember(.pdf(PDFPagePlace(pageIndex: 0, fractionFromTop: 0)), of: slides, at: Date(timeIntervalSince1970: 13))
        XCTAssertEqual(memory.documentCount, 0)
        // The top of a note with the cursor further down is a place, as is the first page scrolled into.
        memory.remember(.note(NotePlace(topLocation: 0, selectionLocation: 30, selectionLength: 0)), of: note, at: Date(timeIntervalSince1970: 14))
        memory.remember(.pdf(PDFPagePlace(pageIndex: 0, fractionFromTop: 0.25)), of: slides, at: Date(timeIntervalSince1970: 15))
        XCTAssertEqual(memory.documentCount, 2)
    }

    func testTheDocumentsLeftLongestAgoMakeWayBeyondTheBound() throws {
        var memory = DocumentPlaceMemory()
        for documentIndex in 0..<(DocumentPlaceMemory.maximumDocumentCount + 3) {
            memory.remember(.pdf(PDFPagePlace(pageIndex: documentIndex + 1, fractionFromTop: 0)), of: try path("Document \(documentIndex).pdf"),
                            at: Date(timeIntervalSince1970: Double(documentIndex)))
        }
        XCTAssertEqual(memory.documentCount, DocumentPlaceMemory.maximumDocumentCount)
        XCTAssertNil(memory.place(of: try path("Document 0.pdf")))
        XCTAssertNil(memory.place(of: try path("Document 2.pdf")))
        XCTAssertNotNil(memory.place(of: try path("Document 3.pdf")))
        XCTAssertNotNil(memory.place(of: try path("Document \(DocumentPlaceMemory.maximumDocumentCount + 2).pdf")))
    }

    func testPlacesFollowRenamedFilesAndFoldersAndGoWithDeletedOnes() throws {
        var memory = DocumentPlaceMemory()
        let place = DocumentPlace.pdf(PDFPagePlace(pageIndex: 3, fractionFromTop: 0.5))
        memory.remember(place, of: try path("Courses/Week 1/Slides.pdf"), at: Date())
        memory.remember(place, of: try path("Courses/Notes.md"), at: Date())
        memory.remember(place, of: try path("Inbox.md"), at: Date())
        memory.followMove(from: try path("Courses"), to: try path("Archive/Courses 2025"))
        XCTAssertEqual(memory.place(of: try path("Archive/Courses 2025/Week 1/Slides.pdf")), place)
        XCTAssertEqual(memory.place(of: try path("Archive/Courses 2025/Notes.md")), place)
        XCTAssertNil(memory.place(of: try path("Courses/Notes.md")))
        memory.followMove(from: try path("Inbox.md"), to: try path("Done.md"))
        XCTAssertEqual(memory.place(of: try path("Done.md")), place)

        memory.forget(inside: try path("Archive"))
        XCTAssertEqual(memory.documentCount, 1)
        XCTAssertEqual(memory.place(of: try path("Done.md")), place)
    }

    func testPlacesAreKeptBetweenLaunches() throws {
        var memory = DocumentPlaceMemory()
        memory.remember(.note(NotePlace(topLocation: 88, selectionLocation: 90, selectionLength: 2)), of: try path("A note.md"), at: Date(timeIntervalSince1970: 5))
        memory.remember(.pdf(PDFPagePlace(pageIndex: 4, fractionFromTop: -0.05)), of: try path("Book.pdf"), at: Date(timeIntervalSince1970: 6))
        let decoded = try JSONDecoder().decode(DocumentPlaceMemory.self, from: try JSONEncoder().encode(memory))
        XCTAssertEqual(decoded, memory)
    }
}

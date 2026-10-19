import XCTest
@testable import GraphiteCore

/// The places documents were left at, as the device's preferences store them for each
/// vault: JSON whose `leftAt` dates are the encoder's default, seconds since 2001-01-01 UTC.
final class DocumentPlaceMemoryPersistedFormatTests: XCTestCase {
    private let notePlaceLeftAt = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private let pdfPlaceLeftAt = Date(timeIntervalSinceReferenceDate: 800_000_050.5)

    private let goldenMemory = """
    {"placesByPath":{"Lecture.md":{"leftAt":800000000,"place":{"note":{"_0":{"selectionLength":3,"selectionLocation":12,"topLocation":10}}}},\
    "Slides.pdf":{"leftAt":800000050.5,"place":{"pdf":{"_0":{"fractionFromTop":0.25,"pageIndex":4}}}}}}
    """

    private func makeMemory() throws -> DocumentPlaceMemory {
        var memory = DocumentPlaceMemory()
        memory.remember(.note(NotePlace(topLocation: 10, selectionLocation: 12, selectionLength: 3)), of: try VaultPath("Lecture.md"), at: notePlaceLeftAt)
        memory.remember(.pdf(PDFPagePlace(pageIndex: 4, fractionFromTop: 0.25)), of: try VaultPath("Slides.pdf"), at: pdfPlaceLeftAt)
        return memory
    }

    func testMemoryEncodesWithTheseFieldNamesAndDatesAsSecondsSince2001() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        XCTAssertEqual(String(decoding: try encoder.encode(try makeMemory()), as: UTF8.self), goldenMemory)
    }

    func testMemoryStoredByAnEarlierBuildDecodesWithItsPlaces() throws {
        let memory = try JSONDecoder().decode(DocumentPlaceMemory.self, from: Data(goldenMemory.utf8))
        XCTAssertEqual(memory, try makeMemory())
        XCTAssertEqual(memory.place(of: try VaultPath("Lecture.md")), .note(NotePlace(topLocation: 10, selectionLocation: 12, selectionLength: 3)))
        XCTAssertEqual(memory.place(of: try VaultPath("Slides.pdf")), .pdf(PDFPagePlace(pageIndex: 4, fractionFromTop: 0.25)))
    }

    func testStoredLeftAtDatesDecideWhichPlacesMakeWayBeyondTheBound() throws {
        // The oldest places, by the stored dates read as seconds since 2001, are forgotten first.
        let oldestLeftAt = 800_000_000.0
        var placesByPath: [String: String] = [:]
        for index in 0..<DocumentPlaceMemory.maximumDocumentCount {
            placesByPath["Note \(index).md"] = #"{"leftAt":\#(oldestLeftAt + Double(index) + 1),"place":{"note":{"_0":{"selectionLength":0,"selectionLocation":5,"topLocation":5}}}}"#
        }
        let storedMemory = #"{"placesByPath":{"# + placesByPath.map { path, record in #""\#(path)":\#(record)"# }.joined(separator: ",") + "}}"
        var memory = try JSONDecoder().decode(DocumentPlaceMemory.self, from: Data(storedMemory.utf8))
        XCTAssertEqual(memory.documentCount, DocumentPlaceMemory.maximumDocumentCount)
        // Left now, which is seconds since 2001 far beyond the stored ones.
        memory.remember(.note(NotePlace(topLocation: 9, selectionLocation: 9, selectionLength: 0)), of: try VaultPath("Newest.md"),
                        at: Date(timeIntervalSinceReferenceDate: oldestLeftAt + 10_000))
        XCTAssertEqual(memory.documentCount, DocumentPlaceMemory.maximumDocumentCount)
        XCTAssertNil(memory.place(of: try VaultPath("Note 0.md")), "The place stored with the earliest date goes first.")
        XCTAssertNotNil(memory.place(of: try VaultPath("Note 1.md")))
        XCTAssertNotNil(memory.place(of: try VaultPath("Newest.md")))
    }
}

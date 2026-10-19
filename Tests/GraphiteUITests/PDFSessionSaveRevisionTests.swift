import XCTest
import PDFKit
import GraphiteCore
import GraphiteApple
@testable import GraphiteUI

/// A save replaces the PDF only if it still is the file that was read. When it is not,
/// nothing is written, the edits stay open, and later saves are refused until the person
/// chooses; the baseline the next save replays on moves only after a save succeeded.
@MainActor
final class PDFSessionSaveRevisionTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("PDFSessionSaveRevision-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path)
        try? FileManager.default.removeItem(at: directory)
    }

    private func makePDF(named filename: String, pageCount: Int) throws -> URL {
        let location = directory.appendingPathComponent(filename)
        var mediaBox = CGRect(x: 0, y: 0, width: 300, height: 400)
        let context = try XCTUnwrap(CGContext(location as CFURL, mediaBox: &mediaBox, nil))
        for pageNumber in 1...pageCount {
            context.beginPDFPage(nil)
            context.fill(CGRect(x: 20, y: 20, width: 10 * pageNumber, height: 10))
            context.endPDFPage()
        }
        context.closePDF()
        return location
    }

    private func highlight() -> PDFMarkup {
        PDFMarkup(name: UUID().uuidString, kind: .highlight, color: .yellow, lineBounds: [CGRect(x: 40, y: 300, width: 100, height: 14)])
    }

    private func markupCount(onPage pageIndex: Int, ofFileAt location: URL) throws -> Int {
        let page = try XCTUnwrap(PDFDocument(url: location)?.page(at: pageIndex))
        return page.annotations.filter { annotation in PDFMarkupKind(annotationType: annotation.type) != nil }.count
    }

    func testAFileChangedBetweenTheEditAndTheSaveIsNotOverwrittenAndTheEditsStay() async throws {
        let location = try makePDF(named: "Notes.pdf", pageCount: 1)
        let session = try await PDFSession.open(location)
        try session.apply(.addMarkup(page: 0, markup: highlight()))
        // Another app replaces the file; no check for external changes ran in between.
        let otherVersion = try Data(contentsOf: makePDF(named: "Other.pdf", pageCount: 3))
        try otherVersion.write(to: location)

        do {
            try await session.save()
            XCTFail("The save must be refused.")
        } catch {
            XCTAssertEqual(error as? GraphiteError, .conflict)
        }
        XCTAssertEqual(try Data(contentsOf: location), otherVersion, "The other version is kept.")
        XCTAssertTrue(session.hasExternalConflict)
        XCTAssertTrue(session.hasUnsavedChanges, "The edits remain.")
        XCTAssertFalse(session.hasFailedSave, "A conflict is not a failed save: the person chooses what happens to the edits.")
        XCTAssertEqual(try markupCount(onPage: 0, ofFileAt: location), 0)
    }

    func testAfterAConflictLaterSavesAreRefusedWithoutWritingAndASeparateCopyKeepsTheEdits() async throws {
        let location = try makePDF(named: "Notes.pdf", pageCount: 1)
        let session = try await PDFSession.open(location)
        try session.apply(.addMarkup(page: 0, markup: highlight()))
        let otherVersion = try Data(contentsOf: makePDF(named: "Other.pdf", pageCount: 2))
        try otherVersion.write(to: location)
        _ = try? await session.save()
        XCTAssertTrue(session.hasExternalConflict)

        for _ in 0..<2 {
            do {
                try await session.save()
                XCTFail("Saving over another version stays refused.")
            } catch {
                XCTAssertEqual(error as? GraphiteError, .conflict)
            }
        }
        XCTAssertEqual(try Data(contentsOf: location), otherVersion)

        var savedLocations: [URL] = []
        session.didSave = { savedLocation in savedLocations.append(savedLocation) }
        let copyLocation = try await session.saveSeparateCopy()
        XCTAssertNotEqual(copyLocation, location)
        XCTAssertEqual(savedLocations, [copyLocation])
        XCTAssertEqual(try markupCount(onPage: 0, ofFileAt: copyLocation), 1, "The copy holds the edits made on the file that was read.")
        XCTAssertEqual(try Data(contentsOf: location), otherVersion, "The other version is still the file.")
    }

    func testAFailedSaveDoesNotMoveTheBaselineSoTheRetryWritesEveryEditOnce() async throws {
        let location = try makePDF(named: "Notes.pdf", pageCount: 2)
        let session = try await PDFSession.open(location)
        try session.apply(.addMarkup(page: 0, markup: highlight()))
        try session.apply(.addMarkup(page: 1, markup: highlight()))
        var savedLocations: [URL] = []
        session.didSave = { savedLocation in savedLocations.append(savedLocation) }

        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: directory.path)
        do {
            try await session.save()
            XCTFail("The folder is read-only.")
        } catch {
            XCTAssertNotEqual(error as? GraphiteError, .conflict)
        }
        XCTAssertTrue(savedLocations.isEmpty, "Nothing is reported saved.")
        XCTAssertTrue(session.hasFailedSave)
        XCTAssertFalse(session.hasExternalConflict)

        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path)
        try await session.save()
        XCTAssertEqual(savedLocations, [location])
        XCTAssertEqual(try markupCount(onPage: 0, ofFileAt: location), 1)
        XCTAssertEqual(try markupCount(onPage: 1, ofFileAt: location), 1)

        // The written file is the new baseline: a later save replays only newer edits.
        try session.apply(.addMarkup(page: 0, markup: highlight()))
        try await session.save()
        XCTAssertEqual(try markupCount(onPage: 0, ofFileAt: location), 2)
        XCTAssertEqual(try markupCount(onPage: 1, ofFileAt: location), 1)
    }

    func testAnEditMadeWhileASaveRunsIsNotLostWhenTheSavedEditsAreDropped() async throws {
        let location = try makePDF(named: "Notes.pdf", pageCount: 1)
        let session = try await PDFSession.open(location)
        try session.apply(.addMarkup(page: 0, markup: highlight()))
        let runningSave = Task { @MainActor in try await session.save() }
        for _ in 0..<5 { await Task.yield() }
        try session.apply(.addMarkup(page: 0, markup: highlight()))
        try await runningSave.value
        try await session.save()

        XCTAssertFalse(session.hasUnsavedChanges)
        XCTAssertEqual(try markupCount(onPage: 0, ofFileAt: location), 2)
    }
}

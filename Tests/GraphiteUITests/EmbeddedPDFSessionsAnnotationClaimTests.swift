import XCTest
import PDFKit
import GraphiteCore
import GraphiteApple
@testable import GraphiteUI

/// Only one embed annotates a given PDF at a time. Before an embed starts, the other
/// sessions of that file are saved; if one cannot save, the embed does not start and that
/// session keeps its edits. A session whose closing save failed is kept until an embed
/// shows it again.
@MainActor
final class EmbeddedPDFSessionsAnnotationClaimTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("EmbeddedPDFSessionsClaim-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path)
        try? FileManager.default.removeItem(at: directory)
    }

    private func makePDF(named name: String, pageCount: Int = 2) throws -> URL {
        let location = directory.appendingPathComponent(name)
        try PDFTemplateGenerator.documentData(paper: PaperSpecification(template: .blank), pageCount: pageCount).write(to: location)
        return location
    }

    // MARK: Who annotates

    func testTheLastEmbedToStartAnnotatingIsTheOneAndAnEarlierOneCannotEndTheClaim() async throws {
        let location = try makePDF(named: "Slides.pdf")
        let sessions = EmbeddedPDFSessions()
        let first = try await PDFSession.open(location), second = try await PDFSession.open(location)
        sessions.add(first)
        sessions.add(second)
        XCTAssertNil(sessions.annotatingSession(at: location))

        sessions.beginAnnotating(first)
        XCTAssertEqual(sessions.annotatingSession(at: location), ObjectIdentifier(first))
        sessions.beginAnnotating(second)
        XCTAssertEqual(sessions.annotatingSession(at: location), ObjectIdentifier(second), "Starting to annotate takes the claim from the other embed.")
        sessions.endAnnotating(first)
        XCTAssertEqual(sessions.annotatingSession(at: location), ObjectIdentifier(second), "An embed that lost the claim cannot end the other's.")
        sessions.endAnnotating(second)
        XCTAssertNil(sessions.annotatingSession(at: location))
    }

    func testEmbedsOfDifferentFilesAnnotateIndependently() async throws {
        let sessions = EmbeddedPDFSessions()
        let firstLocation = try makePDF(named: "First.pdf"), secondLocation = try makePDF(named: "Second.pdf")
        let first = try await PDFSession.open(firstLocation), second = try await PDFSession.open(secondLocation)
        sessions.add(first)
        sessions.add(second)
        sessions.beginAnnotating(first)
        sessions.beginAnnotating(second)
        XCTAssertEqual(sessions.annotatingSession(at: firstLocation), ObjectIdentifier(first))
        XCTAssertEqual(sessions.annotatingSession(at: secondLocation), ObjectIdentifier(second))
        XCTAssertEqual(sessions.otherSessions(showing: firstLocation, besides: first).count, 0)
    }

    func testRemovingASessionEndsItsClaim() async throws {
        let location = try makePDF(named: "Slides.pdf")
        let sessions = EmbeddedPDFSessions()
        let session = try await PDFSession.open(location)
        sessions.add(session)
        sessions.beginAnnotating(session)
        sessions.remove(session)
        XCTAssertNil(sessions.annotatingSession(at: location))
        XCTAssertTrue(sessions.otherSessions(showing: location, besides: session).isEmpty)
    }

    // MARK: Saving the others first

    func testStartingToAnnotateSavesTheOtherSessionsOfTheFileFirst() async throws {
        let location = try makePDF(named: "Slides.pdf")
        let sessions = EmbeddedPDFSessions()
        let first = try await PDFSession.open(location), second = try await PDFSession.open(location)
        sessions.add(first)
        sessions.add(second)
        try first.apply(.rotate(page: 0, clockwise: true))
        XCTAssertTrue(first.hasUnsavedChanges)

        _ = try await sessions.prepareToAnnotate(second)

        XCTAssertFalse(first.hasUnsavedChanges, "The other session was saved before this one started.")
        XCTAssertEqual(PDFDocument(url: location)?.page(at: 0)?.rotation, 90)
    }

    func testWhenAnotherSessionCannotSaveTheEmbedDoesNotStartAndTheOtherKeepsItsEdits() async throws {
        let location = try makePDF(named: "Slides.pdf")
        let sessions = EmbeddedPDFSessions()
        let first = try await PDFSession.open(location), second = try await PDFSession.open(location)
        sessions.add(first)
        sessions.add(second)
        try first.apply(.rotate(page: 0, clockwise: true))
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: directory.path)

        do {
            _ = try await sessions.prepareToAnnotate(second)
            XCTFail("The other session's save fails, so the embed must not start annotating.")
        } catch {
            XCTAssertNotEqual(error as? GraphiteError, .conflict)
        }
        XCTAssertNil(sessions.annotatingSession(at: location), "The claim is given up.")
        XCTAssertTrue(first.hasUnsavedChanges, "The other session still holds its edits.")
        XCTAssertTrue(first.hasFailedSave)

        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path)
        _ = try await sessions.prepareToAnnotate(second)
        XCTAssertFalse(first.hasUnsavedChanges)
        XCTAssertEqual(PDFDocument(url: location)?.page(at: 0)?.rotation, 90)
    }

    // MARK: Sessions whose closing save failed

    func testSessionsKeptAfterAFailedClosingSaveAreHandedBackOldestFirstAndOnlyForTheirFile() async throws {
        let sessions = EmbeddedPDFSessions()
        let location = try makePDF(named: "Notes.pdf"), otherLocation = try makePDF(named: "Other.pdf")
        let first = try await PDFSession.open(location), second = try await PDFSession.open(location)
        sessions.keep(first)
        sessions.keep(second)

        XCTAssertNil(sessions.takeKeptSession(at: otherLocation))
        XCTAssertTrue(sessions.takeKeptSession(at: location) === first)
        XCTAssertTrue(sessions.takeKeptSession(at: location) === second)
        XCTAssertNil(sessions.takeKeptSession(at: location))
    }

    func testAKeptSessionIsNotCountedAmongTheOtherSessionsOfItsFile() async throws {
        let location = try makePDF(named: "Notes.pdf")
        let sessions = EmbeddedPDFSessions()
        let kept = try await PDFSession.open(location), shown = try await PDFSession.open(location)
        sessions.add(kept)
        sessions.remove(kept)
        sessions.keep(kept)
        sessions.add(shown)
        XCTAssertTrue(sessions.otherSessions(showing: location, besides: shown).isEmpty)
    }
}

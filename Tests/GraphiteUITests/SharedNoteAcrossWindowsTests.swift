import XCTest
import GraphiteCore
@testable import GraphiteUI
#if canImport(GraphiteTestSupport)
import GraphiteTestSupport
#endif

/// The same note open in two windows of one process is one text: either window shows the
/// other's edits without a reload, and neither save overwrites the other.
@MainActor
final class SharedNoteAcrossWindowsTests: XCTestCase {
    private var device: IsolatedWorkspaceDevice!
    private var processServices: ProcessServices!
    private var vault: URL!
    private let notePath = try! VaultPath("Lecture.md")

    override func setUp() async throws {
        device = try IsolatedWorkspaceDevice.make(for: self)
        processServices = device.makeServices()
        vault = try TemporaryVault.make(prefix: "SharedNoteVault", for: self).root.resolvingSymlinksInPath()
        try Data("Notes from the lecture.".utf8).write(to: vault.appendingPathComponent("Lecture.md"))
    }

    private func windowShowingTheNote() async throws -> (window: WorkspaceModel, note: MarkdownSession) {
        let window = WorkspaceModel(processServices: processServices, clock: LiveApplicationClock())
        try await window.openFolderAsVault(vault)
        await window.open(notePath)
        return (window, try XCTUnwrap(window.markdownSession))
    }

    private var textOnDisk: String { (try? String(contentsOf: vault.appendingPathComponent("Lecture.md"), encoding: .utf8)) ?? "" }

    func testAnEditInOneWindowShowsInTheOtherAndItsSaveIsTheOthersToo() async throws {
        let (_, firstNote) = try await windowShowingTheNote()
        let (_, secondNote) = try await windowShowingTheNote()
        XCTAssertNotIdentical(firstNote, secondNote, "Each window keeps its own place in the note.")

        firstNote.text = "Notes from the lecture. Typed in the first window."

        XCTAssertEqual(secondNote.text, firstNote.text, "Shown without a reload.")
        try await firstNote.save()
        XCTAssertFalse(secondNote.hasUnsavedChanges, "The first window's save is the second's saved state.")
        XCTAssertEqual(textOnDisk, firstNote.text)
    }

    func testEditsInBothWindowsAreBothKeptAndNeitherSaveIsRefused() async throws {
        let (firstWindow, firstNote) = try await windowShowingTheNote()
        let (secondWindow, secondNote) = try await windowShowingTheNote()

        firstNote.text += " First."
        secondNote.text += " Second."
        async let firstSave: Void = firstWindow.saveOpenDocuments()
        async let secondSave: Void = secondWindow.saveOpenDocuments()
        try await firstSave
        try await secondSave

        XCTAssertEqual(textOnDisk, "Notes from the lecture. First. Second.")
        XCTAssertFalse(firstNote.hasExternalConflict)
        XCTAssertFalse(secondNote.hasExternalConflict)
        XCTAssertNil(firstNote.errorMessage)
        XCTAssertNil(secondNote.errorMessage)
    }

    func testAWindowOpeningTheNoteShowsTheEditsNotSavedYet() async throws {
        let (_, firstNote) = try await windowShowingTheNote()
        firstNote.text = "Not saved yet."

        let (_, secondNote) = try await windowShowingTheNote()

        XCTAssertEqual(secondNote.text, "Not saved yet.")
        XCTAssertTrue(secondNote.hasUnsavedChanges)
        try await secondNote.save()
        XCTAssertFalse(firstNote.hasUnsavedChanges)
        XCTAssertEqual(textOnDisk, "Not saved yet.")
    }

    func testAnotherAppsChangeReadInOneWindowLetsTheOtherSave() async throws {
        let (_, firstNote) = try await windowShowingTheNote()
        let (_, secondNote) = try await windowShowingTheNote()
        try Data("Changed in another app.".utf8).write(to: vault.appendingPathComponent("Lecture.md"))

        await firstNote.checkExternalChange()
        XCTAssertEqual(secondNote.text, "Changed in another app.")
        secondNote.text += " Then typed here."
        try await secondNote.save()

        XCTAssertEqual(textOnDisk, "Changed in another app. Then typed here.")
        XCTAssertFalse(secondNote.hasExternalConflict)
    }
}

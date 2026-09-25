import XCTest
import Observation
import os
import GraphiteCore
import GraphiteIndex
import GraphiteApple
@testable import GraphiteUI

/// Vault switching, link following, external changes, and attachment saving in the
/// workspace model, run against real vault folders.
@MainActor
final class UiWorkspaceModelFixTests: XCTestCase {
    private var temporaryDirectories: [URL] = []
    private var savedGraphitePreferences: [String: Any] = [:]
    private var vaultIdentifiersBeforeTest: Set<UUID> = []

    override func setUp() async throws {
        // The workspace remembers vaults in the standard preferences; the test process's
        // own preferences are put back as they were afterwards.
        savedGraphitePreferences = UserDefaults.standard.dictionaryRepresentation().filter { key, _ in key.hasPrefix("Graphite") }
        vaultIdentifiersBeforeTest = Set(VaultLibrary().vaults.map(\.id))
    }

    override func tearDown() async throws {
        // Indexes are kept per vault identifier; those of the vaults these tests opened go.
        for vault in VaultLibrary().vaults where !vaultIdentifiersBeforeTest.contains(vault.id) {
            VaultIndex.removeIndex(forVault: vault.id)
        }
        for key in UserDefaults.standard.dictionaryRepresentation().keys where key.hasPrefix("Graphite") {
            UserDefaults.standard.removeObject(forKey: key)
        }
        for (key, storedValue) in savedGraphitePreferences { UserDefaults.standard.set(storedValue, forKey: key) }
        for directory in temporaryDirectories {
            if let cacheURL = try? VaultIndex.cacheURL(for: directory) { try? FileManager.default.removeItem(at: cacheURL) }
            try? FileManager.default.removeItem(at: directory)
        }
    }

    // MARK: Helpers

    private func makeVault(files: [String: String] = [:], folders: [String] = []) throws -> URL {
        let vault = FileManager.default.temporaryDirectory.appendingPathComponent("WorkspaceVault-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        temporaryDirectories.append(vault)
        for folder in folders {
            try FileManager.default.createDirectory(at: vault.appendingPathComponent(folder, isDirectory: true), withIntermediateDirectories: true)
        }
        for (path, contents) in files {
            let location = vault.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: location.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(contents.utf8).write(to: location)
        }
        // The workspace reads the folder through its resolved path, as the file system reports it.
        return vault.resolvingSymlinksInPath()
    }

    private func waitUntil(timeoutSeconds: Double = 20, _ condition: () -> Bool) async throws {
        let deadline = Date.now.addingTimeInterval(timeoutSeconds)
        while !condition() {
            guard Date.now < deadline else {
                XCTFail("The condition did not become true in time.")
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    private func openedWorkspace(_ vault: URL) async throws -> WorkspaceModel {
        let workspace = WorkspaceModel()
        try await workspace.openFolderAsVault(vault)
        return workspace
    }

    private func fileText(_ path: String, in vault: URL) -> String? {
        (try? Data(contentsOf: vault.appendingPathComponent(path))).flatMap { data in String(data: data, encoding: .utf8) }
    }

    // MARK: Vault settings

    /// A vault whose `app.json` cannot be read used to keep the previous vault's settings,
    /// including permanent deletion without confirmation.
    func testUnreadableSettingsFallBackToObsidianDefaultsAfterSwitchingVaults() async throws {
        let permanentDeletionVault = try makeVault(files: [".obsidian/app.json": #"{"trashOption":"none","promptDelete":false,"fileSortOrder":"alphabeticalReverse"}"#])
        let unreadableSettingsVault = try makeVault(files: [".obsidian/app.json": #"{"trashOption":"#])
        let workspace = try await openedWorkspace(permanentDeletionVault)
        XCTAssertEqual(workspace.vaultSettings.deletionMethod, .permanent)
        XCTAssertFalse(workspace.vaultSettings.confirmsDeletion)

        try await workspace.openFolderAsVault(unreadableSettingsVault)

        XCTAssertEqual(workspace.vaultSettings, ObsidianSettings())
        XCTAssertEqual(workspace.vaultSettings.deletionMethod, .systemTrash)
        XCTAssertTrue(workspace.vaultSettings.confirmsDeletion)
        XCTAssertNotNil(workspace.errorMessage)
    }

    // MARK: Leaving a vault

    /// Creating a vault that cannot be switched to used to leave its empty folder behind,
    /// so trying the same name again failed.
    func testCreatingVaultThatCannotBeOpenedLeavesNoFolder() async throws {
        let vault = try makeVault(files: ["Note.md": "original"])
        let parentFolder = try makeVault()
        let workspace = try await openedWorkspace(vault)
        await workspace.open(try VaultPath("Note.md"))
        let session = try XCTUnwrap(workspace.markdownSession)
        session.text = "edited while another app changed the note"
        session.hasExternalConflict = true

        do {
            try await workspace.createVault(named: "Fresh", in: parentFolder)
            XCTFail("A note in conflict cannot be saved, so the vault switch is refused.")
        } catch {
            XCTAssertEqual(error as? GraphiteError, .conflict)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: parentFolder.appendingPathComponent("Fresh").path))
    }

    /// Text typed while the next vault is read is saved before the note closes.
    func testTextTypedWhileAnotherVaultOpensIsSaved() async throws {
        let firstVault = try makeVault(files: ["Note.md": "original"])
        let secondVault = try makeVault()
        let workspace = try await openedWorkspace(firstVault)
        await workspace.open(try VaultPath("Note.md"))
        let session = try XCTUnwrap(workspace.markdownSession)

        let switching = Task { @MainActor in try await workspace.openFolderAsVault(secondVault) }
        // Lets the switch pass its first save and start reading the new vault.
        await Task.yield()
        session.text = "original plus words typed while the vault opens"
        try await switching.value

        XCTAssertEqual(workspace.folderAccess?.root.lastPathComponent, secondVault.lastPathComponent)
        XCTAssertEqual(fileText("Note.md", in: firstVault), "original plus words typed while the vault opens")
    }

    /// The folds, recent files, and tabs remembered for a vault go with it from the list.
    func testRemovingVaultFromListForgetsItsRememberedState() async throws {
        let removedVault = try makeVault(files: ["Private note.md": "secret"])
        let otherVault = try makeVault()
        let workspace = try await openedWorkspace(removedVault)
        await workspace.open(try VaultPath("Private note.md"))
        let removedIdentifier = try XCTUnwrap(workspace.currentVaultIdentifier)
        let rememberedKeys = ["GraphiteRecentFiles.", "GraphiteExpandedFolders.", "GraphiteTabLayout."].map { prefix in prefix + removedIdentifier.uuidString }
        UserDefaults.standard.set(["Folder"], forKey: rememberedKeys[1])
        XCTAssertNotNil(UserDefaults.standard.object(forKey: rememberedKeys[0]))
        XCTAssertNotNil(UserDefaults.standard.object(forKey: rememberedKeys[2]))

        try await workspace.openFolderAsVault(otherVault)
        workspace.removeFromVaultList(try XCTUnwrap(workspace.vaultLibrary.vault(withIdentifier: removedIdentifier)))

        XCTAssertNil(workspace.vaultLibrary.vault(withIdentifier: removedIdentifier))
        for key in rememberedKeys { XCTAssertNil(UserDefaults.standard.object(forKey: key), key) }
        XCTAssertTrue(FileManager.default.fileExists(atPath: removedVault.appendingPathComponent("Private note.md").path))
    }

    // MARK: Links

    /// A dot that starts no known file type is part of the note's name, as in Obsidian.
    func testFollowingMissingLinkWithDotInNameCreatesNote() async throws {
        let vault = try makeVault(files: ["Source.md": "[[Homework 2.1]]"])
        let workspace = try await openedWorkspace(vault)
        try await waitUntil { workspace.hasCompletedIndexScan }
        let source = try VaultPath("Source.md")

        await workspace.follow("Homework 2.1", from: source)

        XCTAssertNil(workspace.errorMessage)
        XCTAssertEqual(workspace.selection, try VaultPath("Homework 2.1.md"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: vault.appendingPathComponent("Homework 2.1.md").path))
    }

    /// A missing attachment is not created as a note.
    func testFollowingMissingAttachmentLinkCreatesNothing() async throws {
        let vault = try makeVault(files: ["Source.md": "![[Diagram.png]]"])
        let workspace = try await openedWorkspace(vault)
        try await waitUntil { workspace.hasCompletedIndexScan }

        await workspace.follow("Diagram.png", from: try VaultPath("Source.md"))

        XCTAssertNotNil(workspace.errorMessage)
        XCTAssertFalse(FileManager.default.fileExists(atPath: vault.appendingPathComponent("Diagram.png.md").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: vault.appendingPathComponent("Diagram.png").path))
    }

    /// `[[Projects]]` beside a Projects folder names a note, not the folder.
    func testFollowingLinkNamedLikeFolderCreatesNoteInsteadOfOpeningFolder() async throws {
        let vault = try makeVault(files: ["Source.md": "[[Projects]]", "Projects/Plan.md": "plan"])
        let workspace = try await openedWorkspace(vault)
        try await waitUntil { workspace.hasCompletedIndexScan }
        let source = try VaultPath("Source.md")

        let resolvedBeforeCreation = await workspace.resolveLink("Projects", from: source)
        XCTAssertNil(resolvedBeforeCreation)
        await workspace.follow("Projects", from: source)

        XCTAssertEqual(workspace.selection, try VaultPath("Projects.md"))
        XCTAssertFalse(workspace.recentFiles.paths.contains(try VaultPath("Projects")))
        XCTAssertTrue(FileManager.default.fileExists(atPath: vault.appendingPathComponent("Projects.md").path))
    }

    // MARK: Index scans

    /// A scan asked for while one runs, as a folder arriving from sync asks, used to be
    /// dropped; it now runs after the current scan.
    func testScanRequestedDuringScanRunsAfterIt() async throws {
        var notes: [String: String] = [:]
        for noteNumber in 1...200 { notes["Notes/Note \(noteNumber).md"] = "Note \(noteNumber) links [[Note \(noteNumber + 1)]]" }
        let vault = try makeVault(files: notes)
        let workspace = try await openedWorkspace(vault)
        XCTAssertTrue(workspace.isIndexing)
        let indexVersionBeforeScans = workspace.indexVersion

        workspace.startIndexing()
        try await waitUntil { !workspace.isIndexing }

        XCTAssertEqual(workspace.indexVersion - indexVersionBeforeScans, 2)
        XCTAssertTrue(workspace.hasCompletedIndexScan)
    }

    // MARK: External changes

    func testExternalChangesToHiddenFilesRefreshNothing() throws {
        let vault = try makeVault(files: [".obsidian/workspace.json": "{}", ".obsidian/app.json": "{}"])
        let changes: Set<URL> = [vault.appendingPathComponent(".obsidian/workspace.json"), vault.appendingPathComponent(".obsidian/app.json"), vault]
        XCTAssertEqual(ExternalChangeRefresh(changedLocations: changes, root: vault, maximumFileCount: 200), .nothingShown)
    }

    func testVaultFolderReportedWithChangedFilesRefreshesOnlyThoseFiles() throws {
        let vault = try makeVault(files: ["Note.md": "text", "Drawing.png": "image", ".obsidian/workspace.json": "{}"])
        let changes: Set<URL> = [vault, vault.appendingPathComponent("Note.md"), vault.appendingPathComponent("Drawing.png"), vault.appendingPathComponent(".obsidian/workspace.json")]
        XCTAssertEqual(ExternalChangeRefresh(changedLocations: changes, root: vault, maximumFileCount: 200),
                       .files([try VaultPath("Drawing.png"), try VaultPath("Note.md")]))
    }

    func testChangesThatCannotBeNamedFileByFileScanTheWholeVault() throws {
        let vault = try makeVault(files: ["Folder/Note.md": "text", "Other.md": "text"])
        XCTAssertEqual(ExternalChangeRefresh(changedLocations: [vault], root: vault, maximumFileCount: 200), .wholeVault)
        XCTAssertEqual(ExternalChangeRefresh(changedLocations: [], root: vault, maximumFileCount: 200), .wholeVault)
        XCTAssertEqual(ExternalChangeRefresh(changedLocations: [vault.appendingPathComponent("Folder")], root: vault, maximumFileCount: 200), .wholeVault)
        XCTAssertEqual(ExternalChangeRefresh(changedLocations: [URL(fileURLWithPath: "/elsewhere/Note.md")], root: vault, maximumFileCount: 200), .wholeVault)
        let manyChanges: Set<URL> = [vault.appendingPathComponent("Folder/Note.md"), vault.appendingPathComponent("Other.md")]
        XCTAssertEqual(ExternalChangeRefresh(changedLocations: manyChanges, root: vault, maximumFileCount: 1), .wholeVault)
    }

    // MARK: PDFs changed by another app

    private func writePDF(pageCount: Int, to location: URL) throws {
        try PDFTemplateGenerator.documentData(paper: PaperSpecification(template: .blank), pageCount: pageCount).write(to: location)
    }

    /// Reopening a PDF another app changed keeps the reader on the page they were reading.
    func testReloadedPDFStaysOnCurrentPage() async throws {
        let vault = try makeVault()
        try writePDF(pageCount: 5, to: vault.appendingPathComponent("Lecture.pdf"))
        let workspace = try await openedWorkspace(vault)
        await workspace.open(try VaultPath("Lecture.pdf"))
        let originalSession = try XCTUnwrap(workspace.pdfSession)
        originalSession.currentPageIndex = 3

        try writePDF(pageCount: 6, to: vault.appendingPathComponent("Lecture.pdf"))
        await workspace.checkOpenDocumentsForExternalChanges()

        let reloadedSession = try XCTUnwrap(workspace.pdfSession)
        XCTAssertFalse(reloadedSession === originalSession)
        XCTAssertEqual(reloadedSession.pageCount, 6)
        XCTAssertEqual(reloadedSession.currentPageIndex, 3)
    }

    /// Edits made to the PDF on screen while its new version loads used to be dropped with
    /// the old session. They are kept, as a conflict with the other app's version.
    func testEditsMadeWhileChangedPDFReloadsAreKept() async throws {
        let vault = try makeVault()
        let location = vault.appendingPathComponent("Lecture.pdf")
        try writePDF(pageCount: 2, to: location)
        let workspace = try await openedWorkspace(vault)
        await workspace.open(try VaultPath("Lecture.pdf"))
        let originalSession = try XCTUnwrap(workspace.pdfSession)

        // A long PDF, so its reload takes long enough to draw on the old one meanwhile.
        try writePDF(pageCount: 1_000, to: location)
        let temporaryDirectory = FileManager.default.temporaryDirectory
        let snapshotPrefix = "Graphite-OpenPDF-"
        let snapshotsBeforeReload = Set((try FileManager.default.contentsOfDirectory(atPath: temporaryDirectory.path)).filter { name in name.hasPrefix(snapshotPrefix) })
        let reload = Task { @MainActor in await workspace.checkOpenDocumentsForExternalChanges() }
        // The reload's private copy of the new version appears as soon as it starts reading.
        let deadline = Date.now.addingTimeInterval(20)
        while Date.now < deadline {
            let snapshots = Set((try FileManager.default.contentsOfDirectory(atPath: temporaryDirectory.path)).filter { name in name.hasPrefix(snapshotPrefix) })
            if !snapshots.subtracting(snapshotsBeforeReload).isEmpty { break }
            try await Task.sleep(for: .milliseconds(1))
        }
        guard workspace.pdfSession === originalSession else {
            await reload.value
            throw XCTSkip("The reload finished before an edit could be made during it.")
        }
        try originalSession.apply(.rotate(page: 0, clockwise: true))
        await reload.value

        XCTAssertTrue(workspace.pdfSession === originalSession)
        XCTAssertTrue(originalSession.hasUnsavedChanges)
        XCTAssertTrue(originalSession.hasExternalConflict)
    }

    // MARK: Attachments

    /// Images dropped in the same second get the same "Pasted image" name, and each drop
    /// saves in its own task. Each gets its own file and embed. (On the iPad two drops could
    /// both find the name free, and the second failed with the external-change error; this
    /// test's scheduling on macOS does not reproduce that interleaving by itself.)
    func testAttachmentsSavedTogetherUnderOneNameAreBothKept() async throws {
        let vault = try makeVault(files: ["Note.md": ""])
        let workspace = try await openedWorkspace(vault)
        await workspace.open(try VaultPath("Note.md"))
        let session = try XCTUnwrap(workspace.markdownSession)
        let stem = WorkspaceModel.pastedImageStem(at: Date(timeIntervalSince1970: 1_800_000_000))

        let saves = (1...3).map { imageNumber in
            Task { @MainActor in await workspace.saveAttachment(Data("image \(imageNumber)".utf8), stem: stem, fileExtension: "png", into: session) }
        }
        for save in saves { await save.value }

        XCTAssertNil(workspace.errorMessage)
        let attachmentNames = try FileManager.default.contentsOfDirectory(atPath: vault.path).filter { name in name.hasPrefix(stem) }.sorted()
        // Numbered as Obsidian numbers new files: "Name.png", then "Name 1.png", "Name 2.png".
        XCTAssertEqual(attachmentNames, [stem + " 1.png", stem + " 2.png", stem + ".png"])
        for name in attachmentNames { XCTAssertTrue(session.text.contains(name), name) }
    }

    // MARK: Inserting into a note that changed

    func testRangeFollowsTextTypedBeforeIt() {
        let original = "Keep this: REPLACE ME"
        let range = (original as NSString).range(of: "REPLACE ME")
        let current = "IMPORTANT " + original
        XCTAssertEqual(WorkspaceModel.insertionRange(range, chosenIn: original, currentText: current), (current as NSString).range(of: "REPLACE ME"))
    }

    func testRangeStaysWhenTextIsTypedAfterIt() {
        let original = "Title\n\nREPLACE ME\n"
        let range = (original as NSString).range(of: "REPLACE ME")
        XCTAssertEqual(WorkspaceModel.insertionRange(range, chosenIn: original, currentText: original + "More text 🎉\n"), range)
    }

    func testRangeWhoseTextChangedIsNotReused() {
        let original = "Keep this: REPLACE ME, and this"
        let range = (original as NSString).range(of: "REPLACE ME")
        XCTAssertNil(WorkspaceModel.insertionRange(range, chosenIn: original, currentText: "Keep this: REPLACED, and this"))
        XCTAssertNil(WorkspaceModel.insertionRange(range, chosenIn: original, currentText: "Now keep this: REPLACE ME, and this too"))
    }

    /// A pasted image used to replace the characters at the selection's old place, which
    /// were the person's own text once they had typed before it while the image saved.
    func testTextTypedWhileAttachmentSavesIsKept() async throws {
        let vault = try makeVault(files: ["Note.md": "Keep this: REPLACE ME"])
        let workspace = try await openedWorkspace(vault)
        await workspace.open(try VaultPath("Note.md"))
        let session = try XCTUnwrap(workspace.markdownSession)
        let textWhenPasted = session.text
        let selectionWhenPasted = (textWhenPasted as NSString).range(of: "REPLACE ME")
        session.text = "IMPORTANT " + textWhenPasted

        await workspace.saveAttachment(Data("image".utf8), stem: "Screenshot", fileExtension: "png", into: session, at: selectionWhenPasted, textWhenChosen: textWhenPasted)

        XCTAssertNil(workspace.errorMessage)
        XCTAssertTrue(session.text.hasPrefix("IMPORTANT Keep this: "), session.text)
        XCTAssertTrue(session.text.contains("![[Screenshot.png]]"), session.text)
        XCTAssertFalse(session.text.contains("REPLACE ME"), session.text)
    }

    /// An attachment finished after its note closed used to lose its embed without a word.
    func testAttachmentSavedAfterItsNoteClosedIsReported() async throws {
        let vault = try makeVault(files: ["A.md": "first", "B.md": "second"])
        let workspace = try await openedWorkspace(vault)
        await workspace.open(try VaultPath("A.md"))
        let closedSession = try XCTUnwrap(workspace.markdownSession)
        await workspace.open(try VaultPath("B.md"))
        XCTAssertNil(workspace.openMarkdownSession(at: try VaultPath("A.md")))

        await workspace.saveAttachment(Data("image".utf8), stem: "Photo", fileExtension: "png", into: closedSession)

        XCTAssertTrue(FileManager.default.fileExists(atPath: vault.appendingPathComponent("Photo.png").path))
        XCTAssertEqual(fileText("A.md", in: vault), "first")
        let message = try XCTUnwrap(workspace.errorMessage)
        XCTAssertTrue(message.contains("Photo.png"), message)
    }

    // MARK: Links to dropped vault files

    /// A dropped file whose name another file shares, and which the index does not know
    /// yet, used to get a shortest link that named the other file.
    func testDroppedFileNotYetIndexedGetsFullPathWhenItsNameIsShared() async throws {
        let vault = try makeVault(files: ["Note.md": "", "Archive/Plan.md": "old plan"])
        let workspace = try await openedWorkspace(vault)
        try await waitUntil { workspace.hasCompletedIndexScan && !workspace.isIndexing }
        try FileManager.default.createDirectory(at: vault.appendingPathComponent("Notes"), withIntermediateDirectories: true)
        try Data("new plan".utf8).write(to: vault.appendingPathComponent("Notes/Plan.md"))

        let linkText = await workspace.linkText(for: try VaultPath("Notes/Plan.md"), in: try VaultPath("Note.md"))

        XCTAssertEqual(linkText, "[[Notes/Plan]]")
    }

    /// `![[Fig [1].png]]` is not a link, and `![[C#.pdf]]` names a heading of `C`.
    func testDroppedFileWithWikilinkReservedCharactersGetsMarkdownLink() async throws {
        let vault = try makeVault(files: ["Note.md": "", "Fig [1].png": "image", "C#.pdf": "document"])
        let workspace = try await openedWorkspace(vault)
        try await waitUntil { workspace.hasCompletedIndexScan && !workspace.isIndexing }

        let figureLink = await workspace.linkText(for: try VaultPath("Fig [1].png"), in: try VaultPath("Note.md"))
        let documentLink = await workspace.linkText(for: try VaultPath("C#.pdf"), in: try VaultPath("Note.md"))

        XCTAssertEqual(figureLink, #"![Fig \[1\].png](Fig%20%5B1%5D.png)"#)
        XCTAssertEqual(documentLink, "![C#.pdf](C%23.pdf)")
    }

    // MARK: Index

    /// While Rebuild Index empties the index, the index is not complete; a link followed
    /// then used to create a duplicate of a note that exists.
    func testIndexBeingRebuiltIsNotComplete() async throws {
        let vault = try makeVault(files: ["Note.md": "text"])
        let workspace = try await openedWorkspace(vault)
        try await waitUntil { workspace.hasCompletedIndexScan && !workspace.isIndexing }

        let rebuilding = Task { @MainActor in await workspace.rebuildIndex() }
        // Lets the rebuild run until it waits for the entries to be removed.
        await Task.yield()
        XCTAssertFalse(workspace.hasCompletedIndexScan)
        await rebuilding.value
        try await waitUntil { workspace.hasCompletedIndexScan && !workspace.isIndexing }
    }

    // MARK: Vault switching

    /// The root used to stay alphabetical when the vault opened had the same sort order
    /// as the one before it.
    func testRootIsSortedInVaultOrderWhenPreviousVaultHadSameOrder() async throws {
        let settings = #"{"fileSortOrder":"alphabeticalReverse"}"#
        let firstVault = try makeVault(files: [".obsidian/app.json": settings, "a.md": "", "b.md": ""])
        let secondVault = try makeVault(files: [".obsidian/app.json": settings, "x.md": "", "y.md": ""])
        let workspace = try await openedWorkspace(firstVault)
        XCTAssertEqual(workspace.rootEntries.map(\.path.name), ["b.md", "a.md"])

        try await workspace.openFolderAsVault(secondVault)

        XCTAssertEqual(workspace.rootEntries.map(\.path.name), ["y.md", "x.md"])
    }

    /// A recording saved again after another vault opened lands in its own vault; that
    /// its note got no embed used to go unmentioned.
    func testRecordingSavedAfterSwitchingVaultsIsReported() async throws {
        let firstVault = try makeVault(files: ["Lecture.md": ""])
        let secondVault = try makeVault()
        let workspace = try await openedWorkspace(firstVault)
        try await workspace.openFolderAsVault(secondVault)

        await workspace.recordingDidFinish(at: firstVault.appendingPathComponent("Lecture Recording 2026-09-23 22-15.m4a"))

        let message = try XCTUnwrap(workspace.errorMessage)
        XCTAssertTrue(message.contains("Lecture Recording 2026-09-23 22-15.m4a"), message)
    }

    // MARK: Recording names

    func testRecordingTimestampTellsMorningFromEveningInEveryRegion() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let morning = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 23, hour: 10, minute: 15)))
        let evening = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 23, hour: 22, minute: 15)))

        XCTAssertEqual(WorkspaceModel.recordingTimestamp(at: morning), "2026-09-23 10-15")
        XCTAssertEqual(WorkspaceModel.recordingTimestamp(at: evening), "2026-09-23 22-15")
    }

    // MARK: External changes

    /// A sync that keeps reporting changes used to postpone the refresh until it paused.
    func testSteadyExternalChangesRefreshWithinTwoSeconds() {
        let firstReport = ContinuousClock.now
        XCTAssertEqual(WorkspaceModel.externalRefreshDeadline(firstReport: firstReport, latestReport: firstReport), firstReport + .milliseconds(500))
        XCTAssertEqual(WorkspaceModel.externalRefreshDeadline(firstReport: firstReport, latestReport: firstReport + .seconds(1)), firstReport + .milliseconds(1_500))
        XCTAssertEqual(WorkspaceModel.externalRefreshDeadline(firstReport: firstReport, latestReport: firstReport + .seconds(10)), firstReport + .seconds(2))
    }

    func testManyChangedFilesScanTheWholeVault() throws {
        let vault = try makeVault()
        let changes = Set((1...250).map { fileNumber in vault.appendingPathComponent("Note \(fileNumber).md") })
        XCTAssertEqual(ExternalChangeRefresh(changedLocations: changes, root: vault, maximumFileCount: 200), .wholeVault)
    }

    /// A change reported for one file reads only that file's tab again.
    func testCheckLimitedToChangedFilesLeavesOtherTabsUnread() async throws {
        let vault = try makeVault(files: ["A.md": "first", "B.md": "second"])
        let workspace = try await openedWorkspace(vault)
        await workspace.open(try VaultPath("A.md"))
        let firstSession = try XCTUnwrap(workspace.markdownSession)
        await workspace.open(try VaultPath("B.md"), placement: .newTab)
        let secondSession = try XCTUnwrap(workspace.markdownSession)
        try Data("first, changed".utf8).write(to: vault.appendingPathComponent("A.md"))
        try Data("second, changed".utf8).write(to: vault.appendingPathComponent("B.md"))

        await workspace.checkOpenDocumentsForExternalChanges(limitedTo: [try VaultPath("A.md")])

        XCTAssertEqual(firstSession.text, "first, changed")
        XCTAssertEqual(secondSession.text, "second")
    }

    // MARK: Tabs

    /// Dragging the divider or moving focus within a file changes the layout but not the
    /// focused file; views showing only the file are not redrawn for it.
    func testLayoutChangeThatKeepsFocusedFileLeavesSelectionObserversAlone() async throws {
        let vault = try makeVault(files: ["A.md": "first", "B.md": "second"])
        let workspace = try await openedWorkspace(vault)
        await workspace.open(try VaultPath("A.md"))
        await workspace.open(try VaultPath("B.md"))
        XCTAssertEqual(workspace.selection, try VaultPath("B.md"))
        XCTAssertEqual(workspace.history, workspace.layout.activeTab.history)
        XCTAssertTrue(workspace.history.canGoBack)

        let selectionChanged = OSAllocatedUnfairLock(initialState: false)
        withObservationTracking {
            _ = workspace.selection
            _ = workspace.history
        } onChange: {
            selectionChanged.withLock { changed in changed = true }
        }
        workspace.layout.splitFraction = 0.3
        XCTAssertFalse(selectionChanged.withLock { changed in changed })

        await workspace.goBack()
        XCTAssertTrue(selectionChanged.withLock { changed in changed })
        XCTAssertEqual(workspace.selection, try VaultPath("A.md"))
        XCTAssertEqual(workspace.history, workspace.layout.activeTab.history)
    }
}

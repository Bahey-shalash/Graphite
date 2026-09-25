import XCTest
import GraphiteCore
import GraphiteIndex
import GraphiteApple
@testable import GraphiteUI

/// Moving, copying, and deleting through `WorkspaceModel`, against a real vault folder
/// and index.
@MainActor
final class UiFileManagementFixTests: XCTestCase {
    private var vaultFolders: [URL] = []

    override func tearDown() async throws {
        for folder in vaultFolders {
            // Folders made read-only by a test are writable again, so they can be removed.
            let subpaths = FileManager.default.subpaths(atPath: folder.path) ?? []
            for subpath in subpaths {
                try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.appendingPathComponent(subpath).path)
            }
            try? FileManager.default.removeItem(at: folder)
        }
        vaultFolders = []
    }

    // MARK: Moving several items

    /// A drop of two notes that both need the "Update links?" question used to move only the
    /// second one: its question replaced the first's.
    func testMultiItemDropAsksAboutEachMoveInTurn() async throws {
        let (workspace, vault) = try await makeWorkspace(files: ["A.md": "a", "B.md": "b", "Linker.md": "[a](A.md) [b](B.md)", "Sub/Existing.md": ""])
        let folder = try VaultPath("Sub")
        await workspace.move(try VaultPath("A.md"), into: folder)
        await workspace.move(try VaultPath("B.md"), into: folder)

        let firstQuestion = try XCTUnwrap(workspace.pendingMove)
        XCTAssertEqual(firstQuestion.path, try VaultPath("A.md"))
        await workspace.resolve(firstQuestion, updatesLinks: true)
        let secondQuestion = try XCTUnwrap(workspace.pendingMove, "The second item asks its own question once the first is answered.")
        XCTAssertEqual(secondQuestion.path, try VaultPath("B.md"))
        await workspace.resolve(secondQuestion, updatesLinks: true)

        XCTAssertNil(workspace.pendingMove)
        XCTAssertNil(workspace.errorMessage)
        XCTAssertTrue(FileManager.default.fileExists(atPath: vault.appendingPathComponent("Sub/A.md").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: vault.appendingPathComponent("Sub/B.md").path))
        XCTAssertEqual(try text(of: "Linker.md", in: vault), "[a](Sub/A.md) [b](Sub/B.md)")
    }

    /// The title bar can report one rename twice; the copy reported while the question is
    /// open must not move the file a second time.
    func testRepeatedRequestForTheQuestionedMoveIsIgnored() async throws {
        let (workspace, _) = try await makeWorkspace(files: ["A.md": "a", "Linker.md": "[a](A.md)"])
        await workspace.rename(try VaultPath("A.md"), to: "Renamed")
        await workspace.rename(try VaultPath("A.md"), to: "Renamed")
        let question = try XCTUnwrap(workspace.pendingMove)
        await workspace.resolve(question, updatesLinks: true)
        XCTAssertNil(workspace.pendingMove)
        XCTAssertNil(workspace.errorMessage)
    }

    /// Moving onto a name already taken used to ask about links first and fail only after.
    func testMoveOntoExistingNameFailsBeforeAskingAboutLinks() async throws {
        let (workspace, vault) = try await makeWorkspace(files: ["A.md": "root", "Sub/A.md": "sub", "Linker.md": "[a](A.md)"])
        await workspace.move(try VaultPath("A.md"), into: try VaultPath("Sub"))
        XCTAssertNil(workspace.pendingMove)
        XCTAssertEqual(workspace.errorMessage, "“Sub/A.md” already exists.")
        XCTAssertEqual(try text(of: "A.md", in: vault), "root")
        XCTAssertEqual(try text(of: "Sub/A.md", in: vault), "sub")
    }

    // MARK: Index after moves and copies

    /// Renaming a folder with "Don't Update" used to leave the index at the old paths.
    func testFolderRenameWithoutLinkUpdatesReindexesItsFiles() async throws {
        let (workspace, _) = try await makeWorkspace(files: ["F/N.md": "note", "Linker.md": "[n](F/N.md)"])
        let index = try XCTUnwrap(workspace.index)
        await workspace.rename(try VaultPath("F"), to: "G")
        let question = try XCTUnwrap(workspace.pendingMove)
        await workspace.resolve(question, updatesLinks: false)

        try await waitUntil { try await index.paths(inside: VaultPath("G")) == [VaultPath("G/N.md")] }
        let oldPaths = try await index.paths(inside: VaultPath("F"))
        XCTAssertEqual(oldPaths, [])
    }

    /// Make a Copy of a folder used to index none of the copied files.
    func testFolderCopyIndexesTheCopiedFiles() async throws {
        let (workspace, vault) = try await makeWorkspace(files: ["F/N.md": "note", "F/Deeper/M.md": "more"])
        let index = try XCTUnwrap(workspace.index)
        await workspace.duplicate(try VaultPath("F"))
        XCTAssertNil(workspace.errorMessage)
        XCTAssertTrue(FileManager.default.fileExists(atPath: vault.appendingPathComponent("F 1/N.md").path))
        try await waitUntil { try await Set(index.paths(inside: VaultPath("F 1"))) == [VaultPath("F 1/N.md"), VaultPath("F 1/Deeper/M.md")] }
    }

    // MARK: Deleting

    /// A failed deletion used to close the note first and lose the text not yet saved.
    func testFailedDeletionKeepsUnsavedEdits() async throws {
        let (workspace, vault) = try await makeWorkspace(files: ["Locked/Doc.md": "saved"])
        workspace.vaultSettings.deletionMethod = .permanent
        let path = try VaultPath("Locked/Doc.md")
        await workspace.open(path)
        let session = try XCTUnwrap(workspace.openMarkdownSession(at: path))
        session.text = "typed but not yet saved"
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: vault.appendingPathComponent("Locked").path)

        await workspace.delete(path)

        XCTAssertNotNil(workspace.errorMessage)
        XCTAssertTrue(FileManager.default.fileExists(atPath: vault.appendingPathComponent("Locked/Doc.md").path))
        XCTAssertEqual(workspace.selection, path, "The note stays open when it could not be deleted.")
        XCTAssertEqual(workspace.openMarkdownSession(at: path)?.text, "typed but not yet saved")
    }

    /// The copy in the trash used to lack the edits still waiting for autosave.
    func testDeletedNoteGoesToTheTrashWithItsLatestEdits() async throws {
        let (workspace, vault) = try await makeWorkspace(files: ["Doc.md": "saved"])
        workspace.vaultSettings.deletionMethod = .vaultTrash
        let path = try VaultPath("Doc.md")
        await workspace.open(path)
        try XCTUnwrap(workspace.openMarkdownSession(at: path)).text = "latest edit"

        await workspace.delete(path)

        XCTAssertNil(workspace.errorMessage)
        XCTAssertNil(workspace.selection)
        XCTAssertFalse(FileManager.default.fileExists(atPath: vault.appendingPathComponent("Doc.md").path))
        XCTAssertEqual(try text(of: ".trash/Doc.md", in: vault), "latest edit")
    }

    // MARK: Typing during a move

    /// Text typed into the open note while its move rewrote links elsewhere used to be
    /// dropped when the note reopened at its new place.
    func testTextTypedDuringMoveIsSavedAtTheNewPlace() async throws {
        var files = ["Doc.md": "original", "Sub/Existing.md": ""]
        for linkerNumber in 1...40 { files["Linker \(linkerNumber).md"] = "[doc](Doc.md)" }
        let (workspace, vault) = try await makeWorkspace(files: files)
        workspace.vaultSettings.updatesLinksAutomatically = true
        let didType = try await typeWhileMoving(workspace: workspace, vault: vault, note: "Doc.md", into: "Sub", typedText: "typed during the move")
        try XCTSkipUnless(didType, "The move finished before the test could type into the note.")

        XCTAssertEqual(try text(of: "Sub/Doc.md", in: vault), "typed during the move")
        XCTAssertNil(workspace.errorMessage)
    }

    /// When the move rewrote the note's own links, the typed text is kept as a copy.
    func testTextTypedDuringMoveOfARewrittenNoteIsKeptAsACopy() async throws {
        var files = ["Doc.md": "[other](Other.md)", "Other.md": "", "Sub/Existing.md": ""]
        for linkerNumber in 1...40 { files["Linker \(linkerNumber).md"] = "[doc](Doc.md)" }
        let (workspace, vault) = try await makeWorkspace(files: files)
        workspace.vaultSettings.updatesLinksAutomatically = true
        let didType = try await typeWhileMoving(workspace: workspace, vault: vault, note: "Doc.md", into: "Sub", typedText: "[other](Other.md) typed")
        try XCTSkipUnless(didType, "The move finished before the test could type into the note.")

        XCTAssertEqual(try text(of: "Sub/Doc.md", in: vault), "[other](../Other.md)")
        XCTAssertEqual(try text(of: "Sub/Doc Graphite edits.md", in: vault), "[other](Other.md) typed")
        XCTAssertTrue(workspace.errorMessage?.contains("Doc Graphite edits.md") == true)
    }

    // MARK: Links not updated

    /// A note that could not be written used to be reported as changed elsewhere.
    func testUnwritableLinkingNoteIsNotBlamedOnOutsideEdits() async throws {
        let (workspace, vault) = try await makeWorkspace(files: ["A.md": "a", "Locked/Linker.md": "[a](../A.md)"])
        workspace.vaultSettings.updatesLinksAutomatically = true
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: vault.appendingPathComponent("Locked").path)

        await workspace.rename(try VaultPath("A.md"), to: "Renamed")

        let message = try XCTUnwrap(workspace.errorMessage)
        XCTAssertTrue(message.contains("could not be saved"), message)
        XCTAssertTrue(message.contains("Linker.md"), message)
        XCTAssertFalse(message.contains("changed elsewhere"), message)
    }

    func testLinkingNoteChangedWhileTheQuestionWasOpenIsReportedAsChangedElsewhere() async throws {
        let (workspace, vault) = try await makeWorkspace(files: ["A.md": "a", "Linker.md": "[a](A.md)"])
        await workspace.rename(try VaultPath("A.md"), to: "Renamed")
        let question = try XCTUnwrap(workspace.pendingMove)
        try Data("[a](A.md) edited in another app".utf8).write(to: vault.appendingPathComponent("Linker.md"))

        await workspace.resolve(question, updatesLinks: true)

        let message = try XCTUnwrap(workspace.errorMessage)
        XCTAssertTrue(message.contains("changed elsewhere"), message)
        XCTAssertFalse(message.contains("could not be saved"), message)
        XCTAssertEqual(try text(of: "Linker.md", in: vault), "[a](A.md) edited in another app")
    }

    // MARK: Helpers

    private func makeWorkspace(files: [String: String]) async throws -> (WorkspaceModel, URL) {
        let vault = FileManager.default.temporaryDirectory.appendingPathComponent("UiFileManagementVault-\(UUID().uuidString)").resolvingSymlinksInPath()
        vaultFolders.append(vault)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        for (relativePath, contents) in files {
            let location = vault.appendingPathComponent(relativePath)
            try FileManager.default.createDirectory(at: location.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(contents.utf8).write(to: location)
        }
        let indexFolder = FileManager.default.temporaryDirectory.appendingPathComponent("UiFileManagementIndex-\(UUID().uuidString)")
        vaultFolders.append(indexFolder)
        try FileManager.default.createDirectory(at: indexFolder, withIntermediateDirectories: true)
        let index = try VaultIndex(databaseURL: indexFolder.appendingPathComponent("index.sqlite"))
        _ = try await index.reconcile(root: vault)
        let workspace = WorkspaceModel()
        workspace.folderAccess = FolderAccess(root: vault)
        workspace.store = VaultStore(root: vault)
        workspace.index = index
        // The index has read the whole vault above.
        workspace.hasCompletedIndexScan = true
        return (workspace, vault)
    }

    /// Opens `note`, moves it into `folder`, and types into it once its file has left the
    /// old place while its editor is still open.
    /// - Returns: Whether the text was typed during the move.
    private func typeWhileMoving(workspace: WorkspaceModel, vault: URL, note: String, into folder: String, typedText: String) async throws -> Bool {
        let path = try VaultPath(note)
        await workspace.open(path)
        let session = try XCTUnwrap(workspace.openMarkdownSession(at: path))
        let move = Task { @MainActor in await workspace.move(path, into: try VaultPath(folder)) }
        let oldLocation = vault.appendingPathComponent(note)
        var didType = false
        let deadline = Date.now.addingTimeInterval(10)
        while Date.now < deadline {
            if !FileManager.default.fileExists(atPath: oldLocation.path) {
                // Checked in the same main-actor turn as the typing: the move lets go of the
                // session in one turn once its link rewrites are done.
                if workspace.openMarkdownSession(at: path) === session {
                    session.text = typedText
                    didType = true
                }
                break
            }
            await Task.yield()
        }
        try await move.value
        return didType
    }

    private func text(of relativePath: String, in vault: URL) throws -> String? {
        String(data: try Data(contentsOf: vault.appendingPathComponent(relativePath)), encoding: .utf8)
    }

    /// Waits for the index refresh that file operations start in the background.
    private func waitUntil(timeoutSeconds: TimeInterval = 10, _ condition: () async throws -> Bool) async throws {
        let deadline = Date.now.addingTimeInterval(timeoutSeconds)
        while Date.now < deadline {
            if try await condition() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("The condition did not become true within \(timeoutSeconds) seconds.")
    }
}

/// The stored vault list and the single-vault bookmark from before it.
@MainActor
final class UiFileManagementVaultLibraryTests: XCTestCase {
    private var suiteName = ""
    private var defaults = UserDefaults.standard

    override func setUp() async throws {
        suiteName = "UiFileManagementVaultLibraryTests-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    /// One entry this build cannot decode used to empty the whole list, and the next change
    /// wrote the empty list over the stored one.
    func testUndecodableEntryKeepsTheOtherVaultsAndIsWrittenBack() throws {
        var storedList = VaultList()
        storedList.recordOpening(name: "Good", location: VaultLocation(anchor: .applicationDocuments, relativePath: "Good"), path: "/Good", at: .now)
        storedList.recordOpening(name: "Future", location: VaultLocation(anchor: .applicationDocuments, relativePath: "Future"), path: "/Future", at: .now)
        var storedObject = try XCTUnwrap(try JSONSerialization.jsonObject(with: JSONEncoder().encode(storedList)) as? [String: Any])
        var entries = try XCTUnwrap(storedObject["vaults"] as? [[String: Any]])
        var futureLocation = try XCTUnwrap(entries[1]["location"] as? [String: Any])
        futureLocation["anchor"] = ["kindFromANewerBuild": ["identifier": "abc"]]
        entries[1]["location"] = futureLocation
        storedObject["vaults"] = entries
        defaults.set(try JSONSerialization.data(withJSONObject: storedObject), forKey: "GraphiteKnownVaults")

        let library = VaultLibrary(defaults: defaults)
        XCTAssertEqual(library.vaults.map(\.name), ["Good"])

        library.recordOpening(identifier: nil, root: URL(fileURLWithPath: "/Another"), location: VaultLocation(anchor: .applicationDocuments, relativePath: "Another"))
        let savedData = try XCTUnwrap(defaults.data(forKey: "GraphiteKnownVaults"))
        let savedObject = try XCTUnwrap(try JSONSerialization.jsonObject(with: savedData) as? [String: Any])
        let savedEntries = try XCTUnwrap(savedObject["vaults"] as? [[String: Any]])
        XCTAssertEqual(Set(savedEntries.compactMap { entry in entry["name"] as? String }), ["Good", "Future", "Another"])
        XCTAssertEqual(VaultLibrary(defaults: defaults).vaults.map(\.name), ["Another", "Good"])
    }

    func testUnreadableStoredListIsKeptInsteadOfOverwritten() throws {
        let unreadableData = Data("not a vault list".utf8)
        defaults.set(unreadableData, forKey: "GraphiteKnownVaults")
        let library = VaultLibrary(defaults: defaults)
        XCTAssertTrue(library.vaults.isEmpty)
        library.recordOpening(identifier: nil, root: URL(fileURLWithPath: "/Another"), location: VaultLocation(anchor: .applicationDocuments, relativePath: "Another"))
        XCTAssertEqual(defaults.data(forKey: VaultLibrary.unreadableListKey), unreadableData)
    }

    /// The single-vault bookmark used to be removed before it was resolved, so a folder
    /// unavailable at the first launch after the update was forgotten for good.
    func testSingleVaultBookmarkThatDoesNotResolveIsKeptForTheNextLaunch() {
        let unresolvableBookmark = Data("not a bookmark".utf8)
        defaults.set(unresolvableBookmark, forKey: "GraphiteVaultBookmark")
        let library = VaultLibrary(defaults: defaults)
        XCTAssertTrue(library.vaults.isEmpty)
        XCTAssertEqual(defaults.data(forKey: "GraphiteVaultBookmark"), unresolvableBookmark)
    }

    /// Once the bookmark resolves, the vault joins a list made meanwhile without becoming
    /// the vault reopened at launch.
    func testSingleVaultBookmarkResolvedLaterJoinsTheListBehindExistingVaults() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("UiFileManagementLegacyVault-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let bookmark: Data
        do { bookmark = try folder.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) }
        catch { throw XCTSkip("This process cannot create security-scoped bookmarks: \(error.localizedDescription)") }

        let existingLibrary = VaultLibrary(defaults: defaults)
        existingLibrary.recordOpening(identifier: nil, root: URL(fileURLWithPath: "/Current"), location: VaultLocation(anchor: .applicationDocuments, relativePath: "Current"))
        defaults.set(bookmark, forKey: "GraphiteVaultBookmark")

        let library = VaultLibrary(defaults: defaults)
        XCTAssertEqual(Set(library.vaults.map(\.name)), ["Current", folder.lastPathComponent])
        XCTAssertEqual(library.list.mostRecentlyOpened?.name, "Current")
        XCTAssertNil(defaults.data(forKey: "GraphiteVaultBookmark"))
    }
}

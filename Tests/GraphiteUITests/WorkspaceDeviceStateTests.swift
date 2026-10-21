import XCTest
import GraphiteCore
import GraphiteIndex
@testable import GraphiteUI
import GraphiteTestSupport

/// What a workspace keeps on the device for each vault, written to the preferences and the
/// folders it is given: the formats and the key names (`ST-18`), what removing a vault from
/// the list takes away (`D-24`), and where the indexes and File recovery copies go. The
/// workspaces here have a preferences suite and folders of their own, so nothing reaches the
/// machine that runs the tests.
@MainActor
final class WorkspaceDeviceStateTests: XCTestCase {
    private var device: IsolatedWorkspaceDevice!

    override func setUp() async throws {
        device = try IsolatedWorkspaceDevice.make(for: self)
    }

    private func makeVault(files: [String: String] = [:]) throws -> URL {
        try TemporaryVault.make(prefix: "WorkspaceDeviceStateVault", files: files, for: self).root
    }

    private func key(_ prefix: String, _ vaultIdentifier: UUID) -> String { prefix + "." + vaultIdentifier.uuidString }

    // MARK: ST-18: open folders and recent files

    func testOpenFoldersAreKeptAsASortedListOfVaultPathsUnderTheVaultsIdentifier() async throws {
        let workspace = device.makeWorkspace()
        try await workspace.openFolderAsVault(try makeVault(files: ["Zoo/Animal.md": "a", "Archive/Old/Note.md": "b"]))
        let identifier = try XCTUnwrap(workspace.currentVaultIdentifier)

        workspace.expandedFolders.insert(try VaultPath("Zoo"))
        workspace.expandedFolders.insert(try VaultPath("Archive/Old"))
        workspace.expandedFolders.insert(try VaultPath("Archive"))

        XCTAssertEqual(device.defaults.stringArray(forKey: "GraphiteExpandedFolders." + identifier.uuidString), ["Archive", "Archive/Old", "Zoo"])
    }

    func testRecentFilesAreKeptAsAListOfVaultPathsMostRecentFirstUnderTheVaultsIdentifier() async throws {
        let workspace = device.makeWorkspace()
        try await workspace.openFolderAsVault(try makeVault())
        let identifier = try XCTUnwrap(workspace.currentVaultIdentifier)

        workspace.recentFiles.record(try VaultPath("Old.md"))
        workspace.recentFiles.record(try VaultPath("Folder/New.md"))
        workspace.recentFiles.record(try VaultPath("Old.md"))

        XCTAssertEqual(device.defaults.stringArray(forKey: "GraphiteRecentFiles." + identifier.uuidString), ["Old.md", "Folder/New.md"])
    }

    func testOpenFoldersAndRecentFilesSavedInTheirStoredFormatsAreReadWhenTheVaultOpensAgain() async throws {
        let vault = try makeVault(files: ["Notes/Idea.md": "idea", "Other.md": "other"])
        let otherVault = try makeVault()
        let workspace = device.makeWorkspace()
        try await workspace.openFolderAsVault(vault)
        let identifier = try XCTUnwrap(workspace.currentVaultIdentifier)
        try await workspace.openFolderAsVault(otherVault)
        XCTAssertNotEqual(workspace.currentVaultIdentifier, identifier)
        // As an earlier build wrote them: plain string arrays under the vault's identifier.
        device.defaults.set(["Notes", "Deleted in the meantime"], forKey: "GraphiteExpandedFolders." + identifier.uuidString)
        device.defaults.set(["Other.md", "Notes/Idea.md"], forKey: "GraphiteRecentFiles." + identifier.uuidString)

        try await workspace.openFolderAsVault(vault)

        XCTAssertEqual(workspace.currentVaultIdentifier, identifier)
        XCTAssertEqual(workspace.expandedFolders.map(\.rawValue).sorted(), ["Deleted in the meantime", "Notes"])
        XCTAssertEqual(workspace.recentFiles.paths.map(\.rawValue), ["Other.md", "Notes/Idea.md"])
    }

    func testOpenFoldersAndRecentFilesStayWithTheirVaultWhenAnotherVaultOpens() async throws {
        let workspace = device.makeWorkspace()
        try await workspace.openFolderAsVault(try makeVault(files: ["First/Note.md": "a"]))
        let firstIdentifier = try XCTUnwrap(workspace.currentVaultIdentifier)
        workspace.expandedFolders.insert(try VaultPath("First"))
        workspace.recentFiles.record(try VaultPath("First/Note.md"))

        try await workspace.openFolderAsVault(try makeVault(files: ["Second/Note.md": "b"]))

        XCTAssertEqual(workspace.expandedFolders, [], "The new vault starts with its own folders.")
        XCTAssertEqual(workspace.recentFiles.paths, [])
        XCTAssertEqual(device.defaults.stringArray(forKey: "GraphiteExpandedFolders." + firstIdentifier.uuidString), ["First"], "What the first vault had is not overwritten.")
        XCTAssertEqual(device.defaults.stringArray(forKey: "GraphiteRecentFiles." + firstIdentifier.uuidString), ["First/Note.md"])
    }

    func testWhatAWorkspaceRemembersForAVaultIsKeptInTheDeviceItWasGivenAndNotInTheStandardPreferences() async throws {
        let workspace = device.makeWorkspace()
        try await workspace.openFolderAsVault(try makeVault(files: ["Folder/Note.md": "a"]))
        let identifier = try XCTUnwrap(workspace.currentVaultIdentifier)

        workspace.expandedFolders.insert(try VaultPath("Folder"))
        workspace.recentFiles.record(try VaultPath("Folder/Note.md"))
        await workspace.open(try VaultPath("Folder/Note.md"))

        for prefix in ["GraphiteExpandedFolders", "GraphiteRecentFiles", "GraphiteTabLayout"] {
            XCTAssertNotNil(device.defaults.object(forKey: key(prefix, identifier)), "\(prefix) is written to the workspace's own preferences.")
            XCTAssertNil(UserDefaults.standard.object(forKey: key(prefix, identifier)), "\(prefix) is not written to the standard preferences.")
        }
        XCTAssertNotNil(device.defaults.data(forKey: "GraphiteKnownVaults"), "The vault list is kept in the workspace's own preferences too.")
    }

    // MARK: Folds

    func testFoldedHeadingsAreKeptByNotePathUnderTheVaultsIdentifier() async throws {
        let workspace = device.makeWorkspace()
        try await workspace.openFolderAsVault(try makeVault(files: ["Note.md": "# One\ntext\n"]))
        let identifier = try XCTUnwrap(workspace.currentVaultIdentifier)
        await workspace.open(try VaultPath("Note.md"))
        let session = try XCTUnwrap(workspace.markdownSession)

        session.foldedKeys = ["heading-b", "heading-a"]

        let stored = device.defaults.dictionary(forKey: "GraphiteFolds." + identifier.uuidString) as? [String: [String]]
        XCTAssertEqual(stored, ["Note.md": ["heading-a", "heading-b"]], "Keys are sorted, and kept by the note's vault path.")
    }

    // MARK: D-24 and what removing a vault takes away

    /// The folds of a removed vault name its notes, and nothing would read them again:
    /// opening its folder again makes a new identifier (BUG-SHELL-02).
    func testRemovingAVaultFromTheListForgetsItsFolds() async throws {
        let removedVault = try makeVault(files: ["Note.md": "# One\n"])
        let workspace = device.makeWorkspace()
        try await workspace.openFolderAsVault(removedVault)
        let removedIdentifier = try XCTUnwrap(workspace.currentVaultIdentifier)
        await workspace.open(try VaultPath("Note.md"))
        try XCTUnwrap(workspace.markdownSession).foldedKeys = ["heading-a"]
        XCTAssertNotNil(device.defaults.object(forKey: "GraphiteFolds." + removedIdentifier.uuidString), "The folds were kept.")
        try await workspace.openFolderAsVault(try makeVault())

        workspace.removeFromVaultList(try XCTUnwrap(workspace.vaultLibrary.vault(withIdentifier: removedIdentifier)))

        XCTAssertNil(device.defaults.object(forKey: "GraphiteFolds." + removedIdentifier.uuidString))
    }

    func testRemovingAVaultFromTheListForgetsEveryOtherThingKeptForItOnTheDevice() async throws {
        let removedVault = try makeVault(files: ["Note.md": "text"])
        let workspace = device.makeWorkspace()
        try await workspace.openFolderAsVault(removedVault)
        let removedIdentifier = try XCTUnwrap(workspace.currentVaultIdentifier)
        await workspace.open(try VaultPath("Note.md"))
        workspace.expandedFolders.insert(try VaultPath("Folder"))
        workspace.recentFiles.record(try VaultPath("Note.md"))
        workspace.rememberPlacesOfOpenDocuments()
        device.defaults.set(true, forKey: "GraphiteCommunityPluginsTurnedOn." + removedIdentifier.uuidString)
        device.defaults.set(Data("{}".utf8), forKey: "GraphiteDocumentPlaces." + removedIdentifier.uuidString)
        let remembered = ["GraphiteExpandedFolders", "GraphiteRecentFiles", "GraphiteTabLayout", "GraphiteCommunityPluginsTurnedOn", "GraphiteDocumentPlaces"]
        for prefix in remembered { XCTAssertNotNil(device.defaults.object(forKey: key(prefix, removedIdentifier)), prefix) }
        let otherVault = try makeVault()
        try await workspace.openFolderAsVault(otherVault)

        workspace.removeFromVaultList(try XCTUnwrap(workspace.vaultLibrary.vault(withIdentifier: removedIdentifier)))

        for prefix in remembered { XCTAssertNil(device.defaults.object(forKey: key(prefix, removedIdentifier)), prefix) }
        XCTAssertNil(workspace.vaultLibrary.vault(withIdentifier: removedIdentifier))
        XCTAssertNotNil(workspace.vaultLibrary.vault(withIdentifier: try XCTUnwrap(workspace.currentVaultIdentifier)), "The open vault stays in the list.")
        XCTAssertNil(device.makeServices().vaultLibrary.vault(withIdentifier: removedIdentifier), "The list saved on the device no longer has it.")
    }

    func testTheOpenVaultCannotBeRemovedFromTheList() async throws {
        let workspace = device.makeWorkspace()
        try await workspace.openFolderAsVault(try makeVault(files: ["Folder/Note.md": "a"]))
        let identifier = try XCTUnwrap(workspace.currentVaultIdentifier)
        workspace.expandedFolders.insert(try VaultPath("Folder"))

        workspace.removeFromVaultList(try XCTUnwrap(workspace.vaultLibrary.vault(withIdentifier: identifier)))

        XCTAssertNotNil(workspace.vaultLibrary.vault(withIdentifier: identifier))
        XCTAssertEqual(device.defaults.stringArray(forKey: "GraphiteExpandedFolders." + identifier.uuidString), ["Folder"])
    }

    // MARK: Folders

    func testAVaultsIndexAndFileRecoveryAreKeptInTheFoldersTheWorkspaceWasGiven() async throws {
        let workspace = device.makeWorkspace()
        try await workspace.openFolderAsVault(try makeVault(files: ["Note.md": "text"]))
        let identifier = try XCTUnwrap(workspace.currentVaultIdentifier)
        let folders = device.applicationFolders
        let cachesFolder = try XCTUnwrap(folders.cachesFolder)
        let applicationSupportFolder = try XCTUnwrap(folders.applicationSupportFolder)

        let indexLocation = cachesFolder.appendingPathComponent("Graphite/Indexes/" + identifier.uuidString + ".sqlite")
        XCTAssertTrue(FileManager.default.fileExists(atPath: indexLocation.path), "The index is made below the Caches folder it was given.")
        let recoveryFolder = try XCTUnwrap(workspace.fileRecovery).directory
        XCTAssertEqual(recoveryFolder.standardizedFileURL, applicationSupportFolder.appendingPathComponent("Graphite/File Recovery/" + identifier.uuidString, isDirectory: true).standardizedFileURL)
    }

    func testRemovingAVaultFromTheListDeletesItsIndexFromTheCachesFolderTheWorkspaceWasGiven() async throws {
        let workspace = device.makeWorkspace()
        try await workspace.openFolderAsVault(try makeVault(files: ["Note.md": "text"]))
        let removedIdentifier = try XCTUnwrap(workspace.currentVaultIdentifier)
        let cachesFolder = try XCTUnwrap(device.applicationFolders.cachesFolder)
        let indexLocation = cachesFolder.appendingPathComponent("Graphite/Indexes/" + removedIdentifier.uuidString + ".sqlite")
        try await workspace.openFolderAsVault(try makeVault())
        XCTAssertTrue(FileManager.default.fileExists(atPath: indexLocation.path))

        workspace.removeFromVaultList(try XCTUnwrap(workspace.vaultLibrary.vault(withIdentifier: removedIdentifier)))

        XCTAssertFalse(FileManager.default.fileExists(atPath: indexLocation.path))
    }

    // MARK: Windows

    func testTwoWindowsOfOneProcessShareThePreferencesTheVaultListAndThePlaces() throws {
        let device = try IsolatedWorkspaceDevice.make(for: self)
        let processServices = device.makeServices()
        let firstWindow = WorkspaceModel(processServices: processServices, clock: LiveApplicationClock())
        let secondWindow = WorkspaceModel(processServices: processServices, clock: LiveApplicationClock())

        XCTAssertIdentical(firstWindow.preferences, secondWindow.preferences, "A setting changed in one window reaches the other at once.")
        XCTAssertIdentical(firstWindow.vaultLibrary, secondWindow.vaultLibrary)
        XCTAssertIdentical(firstWindow.processServices.documentPlaceStore, secondWindow.processServices.documentPlaceStore)
        XCTAssertIdentical(firstWindow.processServices.addOns, secondWindow.processServices.addOns)
    }

    // MARK: Hosted launch

    func testAHostedTestsLaunchGetsAPreferencesSuiteAndFoldersOfItsOwn() throws {
        let services = ProcessServices.make(for: .hostedTests)

        XCTAssertNotIdentical(services.defaults, UserDefaults.standard)
        XCTAssertTrue(services.vaultLibrary.vaults.isEmpty, "No vault of the device's is in its list.")
        let temporaryRoot = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().path
        let cachesFolder = try XCTUnwrap(services.applicationFolders.cachesFolder)
        let applicationSupportFolder = try XCTUnwrap(services.applicationFolders.applicationSupportFolder)
        XCTAssertTrue(cachesFolder.resolvingSymlinksInPath().path.hasPrefix(temporaryRoot), cachesFolder.path)
        XCTAssertTrue(applicationSupportFolder.resolvingSymlinksInPath().path.hasPrefix(temporaryRoot), applicationSupportFolder.path)
        XCTAssertNotEqual(cachesFolder, ProcessServices.make(for: .hostedTests).applicationFolders.cachesFolder, "Each launch has folders of its own.")
    }

    func testAHostedTestsWorkspaceRestoresNoVault() async throws {
        let workspace = WorkspaceModel(processServices: .make(for: .hostedTests), clock: LiveApplicationClock())

        await workspace.restoreVault()

        XCTAssertNil(workspace.folderAccess)
        XCTAssertNil(workspace.errorMessage)
    }
}

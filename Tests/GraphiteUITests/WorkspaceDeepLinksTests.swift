import XCTest
import GraphiteCore
import GraphiteIndex
@testable import GraphiteUI

/// `graphite://` links handled by the workspace, run against a real vault folder.
@MainActor
final class WorkspaceDeepLinksTests: XCTestCase {
    private var temporaryDirectories: [URL] = []
    private var savedGraphitePreferences: [String: Any] = [:]
    private var vaultIdentifiersBeforeTest: Set<UUID> = []

    override func setUp() async throws {
        // The workspace remembers vaults in the standard preferences; they are put back afterwards.
        savedGraphitePreferences = UserDefaults.standard.dictionaryRepresentation().filter { key, _ in key.hasPrefix("Graphite") }
        vaultIdentifiersBeforeTest = Set(VaultLibrary().vaults.map(\.id))
    }

    override func tearDown() async throws {
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

    private func makeVault(files: [String: String]) throws -> URL {
        let vault = FileManager.default.temporaryDirectory.appendingPathComponent("DeepLinkVault-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        temporaryDirectories.append(vault)
        for (path, contents) in files {
            try Data(contents.utf8).write(to: vault.appendingPathComponent(path))
        }
        return vault.resolvingSymlinksInPath()
    }

    func testReadLinkToAMissingFileDoesNotReadTheNoteThatIsOpen() async throws {
        let vault = try makeVault(files: ["Open.md": "The note that is already open."])
        let workspace = WorkspaceModel()
        try await workspace.openFolderAsVault(vault)
        await workspace.open(try VaultPath("Open.md"))
        XCTAssertNotNil(workspace.markdownSession)
        workspace.readAloud.stop()

        await workspace.handle(try XCTUnwrap(URL(string: "graphite://read?file=Missing")))

        XCTAssertNotNil(workspace.errorMessage)
        XCTAssertFalse(workspace.readAloud.isActive)
    }

    func testReadLinkToAnExistingNoteReadsThatNote() async throws {
        let vault = try makeVault(files: ["Open.md": "The note that is already open.", "Target.md": "The linked note."])
        let workspace = WorkspaceModel()
        try await workspace.openFolderAsVault(vault)
        await workspace.open(try VaultPath("Open.md"))

        await workspace.handle(try XCTUnwrap(URL(string: "graphite://read?file=Target")))

        XCTAssertEqual(workspace.markdownSession?.path.rawValue, "Target.md")
        XCTAssertEqual(workspace.readAloud.sourceIdentifier, "Target.md")
    }
}

import XCTest
import GraphiteCore
import GraphiteIndex
@testable import GraphiteUI
import GraphiteTestSupport

/// `graphite://` links handled by the workspace, run against a real vault folder.
@MainActor
final class WorkspaceDeepLinksTests: XCTestCase {
    private var temporaryDirectories: [URL] = []
    private var device: IsolatedWorkspaceDevice!

    override func setUp() async throws {
        // The workspace remembers vaults in preferences and folders of its own.
        device = try IsolatedWorkspaceDevice.make(for: self)
    }

    override func tearDown() async throws {
        for directory in temporaryDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
    }

    private func makeVault(files: [String: String]) throws -> URL {
        let vault = try TemporaryVault.make(prefix: "DeepLinkVault", for: self).root
        temporaryDirectories.append(vault)
        for (path, contents) in files {
            try Data(contents.utf8).write(to: vault.appendingPathComponent(path))
        }
        return vault.resolvingSymlinksInPath()
    }

    func testReadLinkToAMissingFileDoesNotReadTheNoteThatIsOpen() async throws {
        let vault = try makeVault(files: ["Open.md": "The note that is already open."])
        let workspace = device.makeWorkspace()
        workspace.setCorePluginEnabled(.readAloud, true)
        let reader = try XCTUnwrap(workspace.readAloud)
        try await workspace.openFolderAsVault(vault)
        await workspace.open(try VaultPath("Open.md"))
        XCTAssertNotNil(workspace.markdownSession)
        reader.stop()

        await workspace.handle(try XCTUnwrap(URL(string: "graphite://read?file=Missing")))

        XCTAssertNotNil(workspace.errorMessage)
        XCTAssertFalse(reader.isActive)
    }

    func testReadLinkToAnExistingNoteReadsThatNote() async throws {
        let vault = try makeVault(files: ["Open.md": "The note that is already open.", "Target.md": "The linked note."])
        let workspace = device.makeWorkspace()
        workspace.setCorePluginEnabled(.readAloud, true)
        let reader = try XCTUnwrap(workspace.readAloud)
        try await workspace.openFolderAsVault(vault)
        await workspace.open(try VaultPath("Open.md"))

        await workspace.handle(try XCTUnwrap(URL(string: "graphite://read?file=Target")))

        XCTAssertEqual(workspace.markdownSession?.path.rawValue, "Target.md")
        XCTAssertEqual(reader.sourceIdentifier, "Target.md")
    }
}

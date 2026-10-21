import XCTest
import GraphiteCore
import GraphiteIndex
import GraphiteApple
@testable import GraphiteUI
import GraphiteTestSupport

/// Make a Copy for several items chosen in the library: each is copied beside itself and
/// none is opened.
@MainActor
final class WorkspaceDuplicateSeveralItemsTests: XCTestCase {
    private func makeWorkspace(files: [String: String]) async throws -> (WorkspaceModel, URL) {
        let vault = try TemporaryVault.make(prefix: "DuplicateSeveral", files: files, for: self).root
        let indexFolder = try TemporaryVault.make(prefix: "DuplicateSeveralIndex", for: self).root
        let index = try VaultIndex(databaseURL: indexFolder.appendingPathComponent("index.sqlite"))
        _ = try await index.reconcile(root: vault)
        let workspace = WorkspaceModel()
        workspace.folderAccess = FolderAccess(root: vault)
        workspace.store = VaultStore(root: vault)
        workspace.index = index
        workspace.hasCompletedIndexScan = true
        return (workspace, vault)
    }

    func testEveryItemIsCopiedAndNoneIsOpened() async throws {
        let (workspace, vault) = try await makeWorkspace(files: ["A.md": "a", "B.md": "b", "F/N.md": "n"])
        await workspace.duplicate([try VaultPath("A.md"), try VaultPath("B.md"), try VaultPath("F")])
        XCTAssertNil(workspace.errorMessage)
        XCTAssertNil(workspace.selection, "Copies made for a whole choice are not opened.")
        for copied in ["A 1.md", "B 1.md", "F 1/N.md"] {
            XCTAssertTrue(FileManager.default.fileExists(atPath: vault.appendingPathComponent(copied).path), copied)
        }
    }

    func testAnItemThatCannotBeCopiedIsNamedAndTheOthersAreStillCopied() async throws {
        let (workspace, vault) = try await makeWorkspace(files: ["A.md": "a"])
        await workspace.duplicate([try VaultPath("Missing.md"), try VaultPath("A.md")])
        XCTAssertEqual(workspace.errorMessage, "Could not make a copy of “Missing.md”.")
        XCTAssertTrue(FileManager.default.fileExists(atPath: vault.appendingPathComponent("A 1.md").path))
    }

    func testNothingChosenCopiesNothing() async throws {
        let (workspace, vault) = try await makeWorkspace(files: ["A.md": "a"])
        await workspace.duplicate([])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: vault.path).filter { $0 == "A.md" }.count, 1)
        XCTAssertNil(workspace.errorMessage)
    }
}

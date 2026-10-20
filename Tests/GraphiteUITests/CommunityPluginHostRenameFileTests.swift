import XCTest
import GraphiteCore
import GraphiteIndex
import GraphiteApple
@testable import GraphiteUI
import GraphiteTestSupport

/// A plugin's `app.fileManager.renameFile`, answered by `CommunityPluginHost` from what the
/// workspace's move came to.
@MainActor
final class CommunityPluginHostRenameFileTests: XCTestCase {

    func testRenameOntoAnExistingNameIsAnsweredAsAFailureAndMovesNothing() async throws {
        let (workspace, vault) = try await makeWorkspace(files: ["A.md": "first", "B.md": "second"])

        let answer = await renameAnswer(in: workspace, from: "A.md", to: "B.md")

        XCTAssertEqual(answer.failureKind, "alreadyExists", "The plugin must be told the rename did not happen.")
        XCTAssertFalse(answer.reportsRenamedFile)
        XCTAssertEqual(try text(of: "A.md", in: vault), "first")
        XCTAssertEqual(try text(of: "B.md", in: vault), "second")
    }

    func testRenameToAFreeNameIsAnsweredAsASuccessAndMovesTheFile() async throws {
        let (workspace, vault) = try await makeWorkspace(files: ["A.md": "first"])
        workspace.vaultSettings.updatesLinksAutomatically = true

        let answer = await renameAnswer(in: workspace, from: "A.md", to: "Renamed.md")

        XCTAssertNil(answer.failureKind)
        XCTAssertTrue(answer.reportsRenamedFile)
        XCTAssertEqual(try text(of: "Renamed.md", in: vault), "first")
        XCTAssertFalse(FileManager.default.fileExists(atPath: vault.appendingPathComponent("A.md").path))
    }

    func testRenameWaitsForTheLinkQuestionAndAnswersWithItsOutcome() async throws {
        let (workspace, vault) = try await makeWorkspace(files: ["A.md": "first", "Linker.md": "[a](A.md)"])
        let sourceDestinationPaths = (source: "A.md", destination: "Renamed.md")

        let answerTask = Task { @MainActor in
            await self.renameAnswer(in: workspace, from: sourceDestinationPaths.source, to: sourceDestinationPaths.destination)
        }
        try await waitUntil { workspace.pendingMove != nil }
        let question = try XCTUnwrap(workspace.pendingMove)
        await workspace.resolve(question, updatesLinks: true)
        let answer = await answerTask.value

        XCTAssertNil(answer.failureKind)
        XCTAssertTrue(answer.reportsRenamedFile)
        XCTAssertEqual(try text(of: "Renamed.md", in: vault), "first")
        XCTAssertEqual(try text(of: "Linker.md", in: vault), "[a](Renamed.md)")
    }

    // MARK: Helpers

    /// What the runtime receives when a plugin renames `source` to `destination`.
    private func renameAnswer(in workspace: WorkspaceModel, from source: String, to destination: String) async -> RenameAnswer {
        workspace.communityPlugins.vaultDidOpen(workspace)
        let answer = await workspace.communityPlugins.answer(["operation": "workspace.renameFile", "path": source, "destinationPath": destination])
        let fields = answer as? [String: Any] ?? [:]
        return RenameAnswer(failureKind: (fields["failure"] as? [String: Any])?["kind"] as? String, reportsRenamedFile: fields["stat"] != nil)
    }

    /// The parts of the runtime's answer to a rename that the tests check.
    private struct RenameAnswer: Sendable {
        let failureKind: String?
        let reportsRenamedFile: Bool
    }

    private func makeWorkspace(files: [String: String]) async throws -> (WorkspaceModel, URL) {
        let vault = try TemporaryVault.make(prefix: "PluginRenameVault", for: self).root
        for (relativePath, contents) in files {
            let location = vault.appendingPathComponent(relativePath)
            try FileManager.default.createDirectory(at: location.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(contents.utf8).write(to: location)
        }
        let indexFolder = try TemporaryVault.make(prefix: "PluginRenameIndex", for: self).root
        let index = try VaultIndex(databaseURL: indexFolder.appendingPathComponent("index.sqlite"))
        _ = try await index.reconcile(root: vault)
        let workspace = WorkspaceModel()
        workspace.folderAccess = FolderAccess(root: vault)
        workspace.store = VaultStore(root: vault)
        workspace.index = index
        workspace.hasCompletedIndexScan = true
        return (workspace, vault)
    }

    private func text(of path: String, in vault: URL) throws -> String {
        try String(contentsOf: vault.appendingPathComponent(path), encoding: .utf8)
    }
}

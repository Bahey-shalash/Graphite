import XCTest
import GraphiteCore
import GraphiteIndex
import GraphiteApple
@testable import GraphiteUI

/// Edits made to an open canvas while the canvas, or a folder holding it, moves.
@MainActor
final class WorkspaceModelCanvasEditsDuringMoveTests: XCTestCase {
    private var temporaryFolders: [URL] = []
    private let cardIdentifier = "1000000000000001"
    private let canvasText = "{\"nodes\":[{\"id\":\"1000000000000001\",\"type\":\"text\",\"text\":\"Original\",\"x\":0,\"y\":0,\"width\":250,\"height\":200}],\"edges\":[]}"

    override func tearDown() async throws {
        for folder in temporaryFolders { try? FileManager.default.removeItem(at: folder) } // best-effort removal of temporary folders
        temporaryFolders = []
    }

    private func makeWorkspace(canvasPath: String) async throws -> (WorkspaceModel, URL) {
        let vault = FileManager.default.temporaryDirectory.appendingPathComponent("CanvasMoveVault-\(UUID().uuidString)").resolvingSymlinksInPath()
        temporaryFolders.append(vault)
        var files = [canvasPath: canvasText, "Sub/Existing.md": ""]
        // Many linking notes make the move long enough to type into the canvas during it.
        for linkerNumber in 1...40 { files["Linker \(linkerNumber).md"] = "[board](\(canvasPath))" }
        for (relativePath, contents) in files {
            let location = vault.appendingPathComponent(relativePath)
            try FileManager.default.createDirectory(at: location.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(contents.utf8).write(to: location)
        }
        let indexFolder = FileManager.default.temporaryDirectory.appendingPathComponent("CanvasMoveIndex-\(UUID().uuidString)")
        temporaryFolders.append(indexFolder)
        try FileManager.default.createDirectory(at: indexFolder, withIntermediateDirectories: true)
        let index = try VaultIndex(databaseURL: indexFolder.appendingPathComponent("index.sqlite"))
        _ = try await index.reconcile(root: vault)
        let workspace = WorkspaceModel()
        workspace.folderAccess = FolderAccess(root: vault)
        workspace.store = VaultStore(root: vault)
        workspace.index = index
        workspace.hasCompletedIndexScan = true
        workspace.vaultSettings.updatesLinksAutomatically = true
        return (workspace, vault)
    }

    /// Opens the canvas, moves `movedItem` into `folder`, and edits the card once the file has
    /// left its old place while the canvas is still open.
    /// - Returns: Whether the card was edited during the move.
    private func editCardWhileMoving(workspace: WorkspaceModel, vault: URL, canvasPath: String, movedItem: String, into folder: String) async throws -> Bool {
        let path = try VaultPath(canvasPath)
        await workspace.open(path)
        let session = try XCTUnwrap(workspace.canvasSession)
        let move = Task { @MainActor in await workspace.move(try VaultPath(movedItem), into: try VaultPath(folder)) }
        let oldLocation = vault.appendingPathComponent(canvasPath)
        var didEdit = false
        let deadline = Date.now.addingTimeInterval(10)
        while Date.now < deadline {
            if !FileManager.default.fileExists(atPath: oldLocation.path) {
                // Checked in the same main-actor turn as the edit: the move lets go of the
                // session in one turn once its link rewrites are done.
                if workspace.canvasSession === session {
                    didEdit = session.perform([.setText("Typed during the move", nodeIdentifier: cardIdentifier)], named: "Edit Text")
                }
                break
            }
            await Task.yield()
        }
        _ = try await move.value
        return didEdit
    }

    private func cardText(atPath relativePath: String, in vault: URL) throws -> String? {
        let canvas = try CanvasFile(data: Data(contentsOf: vault.appendingPathComponent(relativePath)))
        guard case .text(let text)? = canvas.node(withIdentifier: cardIdentifier)?.content else { return nil }
        return text
    }

    func testCanvasEditedDuringItsOwnMoveIsSavedAtTheNewPlace() async throws {
        let (workspace, vault) = try await makeWorkspace(canvasPath: "Board.canvas")
        let didEdit = try await editCardWhileMoving(workspace: workspace, vault: vault, canvasPath: "Board.canvas", movedItem: "Board.canvas", into: "Sub")
        try XCTSkipUnless(didEdit, "The move finished before the test could edit the canvas.")

        XCTAssertEqual(try cardText(atPath: "Sub/Board.canvas", in: vault), "Typed during the move")
        XCTAssertNil(workspace.errorMessage)
    }

    func testCanvasEditedDuringTheMoveOfItsFolderIsSavedAtTheNewPlace() async throws {
        let (workspace, vault) = try await makeWorkspace(canvasPath: "Boards/Board.canvas")
        try FileManager.default.createDirectory(at: vault.appendingPathComponent("Sub/Inner"), withIntermediateDirectories: true)
        let didEdit = try await editCardWhileMoving(workspace: workspace, vault: vault, canvasPath: "Boards/Board.canvas", movedItem: "Boards", into: "Sub")
        try XCTSkipUnless(didEdit, "The move finished before the test could edit the canvas.")

        XCTAssertEqual(try cardText(atPath: "Sub/Boards/Board.canvas", in: vault), "Typed during the move")
        XCTAssertNil(workspace.errorMessage)
    }
}

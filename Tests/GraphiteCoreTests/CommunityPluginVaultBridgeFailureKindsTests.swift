import XCTest
@testable import GraphiteCore
import GraphiteTestSupport

/// The failure kinds `CommunityPluginVaultBridge` answers with, which the plugin runtime
/// compares as text (`conflict`, `missing`, `outsideVault`…), and the vault operations it
/// answers at all. The Node tests' host answers the same operations with the same kinds.
final class CommunityPluginVaultBridgeFailureKindsTests: XCTestCase {
    private var vault: URL!

    override func setUpWithError() throws {
        vault = try TemporaryVault.make(prefix: "BridgeKindsVault", for: self).root
        try FileManager.default.createDirectory(at: vault.appendingPathComponent("Folder"), withIntermediateDirectories: true)
        try Data("text".utf8).write(to: vault.appendingPathComponent("Note.md"))
        try Data("inner".utf8).write(to: vault.appendingPathComponent("Folder/Inner.md"))
    }

    private func answer(_ message: [String: Any]) async throws -> [String: Any] {
        let bridge = CommunityPluginVaultBridge(store: VaultStore(root: vault)) { .vaultTrash }
        let answerData = await bridge.respond(to: try JSONSerialization.data(withJSONObject: message))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: answerData) as? [String: Any])
    }

    private func failure(of message: [String: Any]) async throws -> (kind: String?, fieldNames: Set<String>) {
        let fields = try await answer(message)
        let failure = fields["failure"] as? [String: Any]
        return (failure?["kind"] as? String, Set((failure ?? [:]).keys))
    }

    func testOnlyOperationsStartingWithVaultDotBelongToTheBridge() {
        XCTAssertTrue(CommunityPluginVaultBridge.handles("vault.read"))
        XCTAssertTrue(CommunityPluginVaultBridge.handles("vault.nonsense"))
        XCTAssertFalse(CommunityPluginVaultBridge.handles("workspace.openFile"))
        XCTAssertFalse(CommunityPluginVaultBridge.handles("vaultread"))
    }

    func testEveryVaultOperationThePluginRuntimeSendsIsAnswered() async throws {
        let operations: [[String: Any]] = [
            ["operation": "vault.list"],
            ["operation": "vault.listFolder", "path": "Folder"],
            ["operation": "vault.stat", "path": "Note.md"],
            ["operation": "vault.read", "path": "Note.md", "encoding": "text"],
            ["operation": "vault.write", "path": "Written.md", "text": "new", "expectation": ["kind": "absent"]],
            ["operation": "vault.createFolder", "path": "Made"],
            ["operation": "vault.copy", "path": "Note.md", "destinationPath": "Copy.md"],
            ["operation": "vault.rename", "path": "Copy.md", "destinationPath": "Moved.md"],
            ["operation": "vault.remove", "path": "Moved.md", "method": "permanent"],
        ]
        for operation in operations {
            let fields = try await answer(operation)
            XCTAssertNil(fields["failure"], "\(operation["operation"] ?? "") must not fail: \(fields)")
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: vault.appendingPathComponent("Written.md").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: vault.appendingPathComponent("Made").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: vault.appendingPathComponent("Moved.md").path))
    }

    func testAFailureIsAKindAndAMessageAndEachWayToFailHasItsKind() async throws {
        let unknownOperation = try await failure(of: ["operation": "vault.explode"])
        XCTAssertEqual(unknownOperation.kind, "unknownOperation")
        XCTAssertEqual(unknownOperation.fieldNames, ["kind", "message"])
        let readMissing = try await failure(of: ["operation": "vault.read", "path": "Missing.md", "encoding": "text"])
        XCTAssertEqual(readMissing.kind, "missing")
        let readFolder = try await failure(of: ["operation": "vault.read", "path": "Folder", "encoding": "text"])
        XCTAssertEqual(readFolder.kind, "isFolder")
        let removeMissing = try await failure(of: ["operation": "vault.remove", "path": "Missing.md", "method": "permanent"])
        XCTAssertEqual(removeMissing.kind, "missing")
        let removeFileAsFolder = try await failure(of: ["operation": "vault.remove", "path": "Note.md", "method": "permanent", "isFolderExpected": true])
        XCTAssertEqual(removeFileAsFolder.kind, "notFolder")
        let removeFolderAsFile = try await failure(of: ["operation": "vault.remove", "path": "Folder", "method": "permanent", "isFolderExpected": false])
        XCTAssertEqual(removeFolderAsFile.kind, "isFolder")
        let removeNonEmptyFolder = try await failure(of: ["operation": "vault.remove", "path": "Folder", "method": "permanent", "isRecursive": false, "isFolderExpected": true])
        XCTAssertEqual(removeNonEmptyFolder.kind, "notEmpty")
        let removeWithUnknownMethod = try await failure(of: ["operation": "vault.remove", "path": "Note.md", "method": "shred"])
        XCTAssertEqual(removeWithUnknownMethod.kind, "invalidData")
        let copyOntoExisting = try await failure(of: ["operation": "vault.copy", "path": "Note.md", "destinationPath": "Folder/Inner.md"])
        XCTAssertEqual(copyOntoExisting.kind, "exists")
        let copyMissing = try await failure(of: ["operation": "vault.copy", "path": "Missing.md", "destinationPath": "Anywhere.md"])
        XCTAssertEqual(copyMissing.kind, "missing")
        let writeNothing = try await failure(of: ["operation": "vault.write", "path": "Empty.md", "expectation": ["kind": "replace"]])
        XCTAssertEqual(writeNothing.kind, "invalidData")
        let writeUnknownExpectation = try await failure(of: ["operation": "vault.write", "path": "Note.md", "text": "x", "expectation": ["kind": "whatever"]])
        XCTAssertEqual(writeUnknownExpectation.kind, "invalidData")
        let writeRevisionWithoutRevision = try await failure(of: ["operation": "vault.write", "path": "Note.md", "text": "x", "expectation": ["kind": "revision"]])
        XCTAssertEqual(writeRevisionWithoutRevision.kind, "invalidData")
        let writeOntoExistingAsNew = try await failure(of: ["operation": "vault.write", "path": "Note.md", "text": "x", "expectation": ["kind": "absent"]])
        XCTAssertEqual(writeOntoExistingAsNew.kind, "conflict")
        let undecodableMessage = try await failure(of: ["operation": "vault.read"])
        XCTAssertEqual(undecodableMessage.kind, "invalidData")
        let listMissingFolder = try await failure(of: ["operation": "vault.listFolder", "path": "Missing"])
        XCTAssertEqual(listMissingFolder.kind, "failed", "Anything the bridge has no kind for is failed.")
        XCTAssertEqual(try String(contentsOf: vault.appendingPathComponent("Note.md"), encoding: .utf8), "text", "No refused write or removal changed the note.")
    }

    func testAPathOutsideTheVaultFailsAsOutsideVaultAndAMissingFileHasNoStat() async throws {
        let readOutside = try await failure(of: ["operation": "vault.read", "path": "../outside.md", "encoding": "text"])
        XCTAssertEqual(readOutside.kind, "outsideVault")
        let statOutside = try await failure(of: ["operation": "vault.stat", "path": "../outside.md"])
        XCTAssertEqual(statOutside.kind, "outsideVault")
        let absolute = try await failure(of: ["operation": "vault.stat", "path": "/etc/passwd"])
        XCTAssertEqual(absolute.kind, "invalidPath")

        let missing = try await answer(["operation": "vault.stat", "path": "Missing.md"])
        XCTAssertNil(missing["failure"])
        XCTAssertTrue(missing["stat"] is NSNull, "A file that is not there has a null stat, not a failure.")
    }
}

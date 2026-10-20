import XCTest
@testable import GraphiteCore

/// What a plugin's file messages cannot reach, and how much one message can carry. Each test
/// sends the message an attacking plugin would send (a path with `..`, an absolute path, a
/// path through a symbolic link that leads out of the vault) and checks the answer is a
/// refusal with the kind the runtime understands, and that nothing outside the vault changed.
final class CommunityPluginVaultBridgeBoundaryTests: XCTestCase {
    private var container: URL!
    private var vault: URL!
    private var outsideFolder: URL!
    private var outsideSecretText: String!

    override func setUpWithError() throws {
        container = FileManager.default.temporaryDirectory.appendingPathComponent("PluginBoundary-\(UUID().uuidString)", isDirectory: true).resolvingSymlinksInPath()
        vault = container.appendingPathComponent("Vault", isDirectory: true)
        outsideFolder = container.appendingPathComponent("Outside", isDirectory: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outsideFolder, withIntermediateDirectories: true)
        outsideSecretText = "outside secret"
        try Data(outsideSecretText.utf8).write(to: outsideFolder.appendingPathComponent("secret.txt"))
        try Data("inside".utf8).write(to: vault.appendingPathComponent("Inside.md"))
        // A folder link and a file link, both leading out of the vault.
        try FileManager.default.createSymbolicLink(at: vault.appendingPathComponent("FolderLink"), withDestinationURL: outsideFolder)
        try FileManager.default.createSymbolicLink(at: vault.appendingPathComponent("FileLink.txt"), withDestinationURL: outsideFolder.appendingPathComponent("secret.txt"))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: container)
    }

    // MARK: Helpers

    private func respond(_ message: [String: Any]) async throws -> [String: Any] {
        let bridge = CommunityPluginVaultBridge(store: VaultStore(root: vault)) { .permanent }
        let answer = await bridge.respond(to: try JSONSerialization.data(withJSONObject: message))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: answer) as? [String: Any])
    }

    private func failureKind(of answer: [String: Any]) -> String? {
        (answer["failure"] as? [String: Any])?["kind"] as? String
    }

    /// The paths an attacker names, each with the refusal the bridge gives.
    private var attackedPaths: [(path: String, expectedKind: String)] {
        [
            ("../Outside/secret.txt", "outsideVault"),
            ("..", "outsideVault"),
            ("Folder/../../Outside/secret.txt", "outsideVault"),
            ("/etc/hosts", "invalidPath"),
            (outsideFolder.appendingPathComponent("secret.txt").path, "invalidPath"),
            ("FolderLink/secret.txt", "outsideVault"),
            ("FileLink.txt", "outsideVault"),
            ("FolderLink/created.txt", "outsideVault"),
        ]
    }

    private func assertOutsideFolderIsUntouched(file: StaticString = #filePath, line: UInt = #line) throws {
        let names = try FileManager.default.contentsOfDirectory(atPath: outsideFolder.path)
        XCTAssertEqual(names, ["secret.txt"], "Nothing is created or removed outside the vault.", file: file, line: line)
        XCTAssertEqual(try String(contentsOf: outsideFolder.appendingPathComponent("secret.txt"), encoding: .utf8), outsideSecretText, file: file, line: line)
    }

    // MARK: Refusals

    func testReadingAPathOutsideTheVaultIsRefused() async throws {
        for attack in attackedPaths {
            for encoding in ["text", "binary"] {
                let answer = try await respond(["operation": "vault.read", "path": attack.path, "encoding": encoding])
                XCTAssertEqual(failureKind(of: answer), attack.expectedKind, "\(attack.path) (\(encoding))")
                XCTAssertNil(answer["text"], attack.path)
                XCTAssertNil(answer["base64"], attack.path)
            }
        }
    }

    func testWritingAPathOutsideTheVaultIsRefusedWhateverTheExpectation() async throws {
        let expectations: [[String: Any]] = [["kind": "absent"], ["kind": "replace"]]
        for attack in attackedPaths {
            for expectation in expectations {
                let answer = try await respond(["operation": "vault.write", "path": attack.path, "text": "overwritten", "expectation": expectation])
                XCTAssertEqual(failureKind(of: answer), attack.expectedKind, "\(attack.path) (\(expectation["kind"] ?? ""))")
            }
        }
        try assertOutsideFolderIsUntouched()
    }

    func testRemovingAPathOutsideTheVaultIsRefused() async throws {
        for attack in attackedPaths {
            for method in ["permanent", "local", "system", "vaultSetting"] {
                let answer = try await respond(["operation": "vault.remove", "path": attack.path, "method": method])
                XCTAssertEqual(failureKind(of: answer), attack.expectedKind, "\(attack.path) (\(method))")
            }
        }
        try assertOutsideFolderIsUntouched()
        XCTAssertTrue(FileManager.default.fileExists(atPath: vault.appendingPathComponent("FileLink.txt").path), "A link that leads out is refused, not deleted.")
    }

    func testRenamingFromOrToAPathOutsideTheVaultIsRefused() async throws {
        for attack in attackedPaths {
            let movingOut = try await respond(["operation": "vault.rename", "path": "Inside.md", "destinationPath": attack.path])
            XCTAssertEqual(failureKind(of: movingOut), attack.expectedKind, "to \(attack.path)")
            let movingIn = try await respond(["operation": "vault.rename", "path": attack.path, "destinationPath": "Taken.md"])
            XCTAssertEqual(failureKind(of: movingIn), attack.expectedKind, "from \(attack.path)")
        }
        try assertOutsideFolderIsUntouched()
        XCTAssertTrue(FileManager.default.fileExists(atPath: vault.appendingPathComponent("Inside.md").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: vault.appendingPathComponent("Taken.md").path))
    }

    func testCopyingFromOrToAPathOutsideTheVaultIsRefused() async throws {
        for attack in attackedPaths {
            let copyingOut = try await respond(["operation": "vault.copy", "path": "Inside.md", "destinationPath": attack.path])
            XCTAssertEqual(failureKind(of: copyingOut), attack.expectedKind, "to \(attack.path)")
            let copyingIn = try await respond(["operation": "vault.copy", "path": attack.path, "destinationPath": "Taken.md"])
            XCTAssertEqual(failureKind(of: copyingIn), attack.expectedKind, "from \(attack.path)")
        }
        try assertOutsideFolderIsUntouched()
        XCTAssertFalse(FileManager.default.fileExists(atPath: vault.appendingPathComponent("Taken.md").path))
    }

    func testStatCreatingAFolderAndListingAPathOutsideTheVaultAreRefused() async throws {
        for attack in attackedPaths {
            let statAnswer = try await respond(["operation": "vault.stat", "path": attack.path])
            XCTAssertEqual(failureKind(of: statAnswer), attack.expectedKind, "stat \(attack.path)")
            let createAnswer = try await respond(["operation": "vault.createFolder", "path": attack.path + "/NewFolder"])
            XCTAssertNotNil(failureKind(of: createAnswer), "createFolder \(attack.path)")
            let listAnswer = try await respond(["operation": "vault.listFolder", "path": attack.path])
            XCTAssertNotNil(failureKind(of: listAnswer), "listFolder \(attack.path)")
        }
        let listedVault = try await respond(["operation": "vault.list", "folder": "FolderLink"])
        XCTAssertEqual(failureKind(of: listedVault), "outsideVault", "A listing does not follow a link out.")
        try assertOutsideFolderIsUntouched()
    }

    func testAFolderListingLeavesOutALinkThatLeadsOutsideTheVault() async throws {
        let answer = try await respond(["operation": "vault.listFolder", "path": ""])
        XCTAssertEqual(answer["files"] as? [String], ["Inside.md"])
        XCTAssertEqual(answer["folders"] as? [String], [])
    }

    func testAPathInsideTheVaultStillWorksAroundTheRefusals() async throws {
        let readAnswer = try await respond(["operation": "vault.read", "path": "./Folder/../Inside.md", "encoding": "text"])
        XCTAssertNil(failureKind(of: readAnswer))
        XCTAssertEqual(readAnswer["text"] as? String, "inside")
    }

    // MARK: One message's size

    func testAMessageCarriesExactlySixtyFourMebibytesAndNotOneByteMore() async throws {
        let cap = CommunityPluginVaultBridge.maximumTransferredBytes
        XCTAssertEqual(cap, 64 * 1_048_576)

        let atCap = Data(count: cap).base64EncodedString()
        let writtenAtCap = try await respond(["operation": "vault.write", "path": "AtCap.bin", "base64": atCap, "expectation": ["kind": "absent"]])
        XCTAssertNil(failureKind(of: writtenAtCap))
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: vault.appendingPathComponent("AtCap.bin").path)[.size] as? Int, cap)

        let overCap = Data(count: cap + 1).base64EncodedString()
        let writtenOverCap = try await respond(["operation": "vault.write", "path": "OverCap.bin", "base64": overCap, "expectation": ["kind": "absent"]])
        XCTAssertEqual(failureKind(of: writtenOverCap), "tooLarge")
        XCTAssertFalse(FileManager.default.fileExists(atPath: vault.appendingPathComponent("OverCap.bin").path), "A refused write leaves no file.")

        let readAtCap = try await respond(["operation": "vault.read", "path": "AtCap.bin", "encoding": "binary"])
        XCTAssertNil(failureKind(of: readAtCap))
        XCTAssertEqual((readAtCap["base64"] as? String)?.count, atCap.count)

        let handle = try FileHandle(forWritingTo: vault.appendingPathComponent("AtCap.bin"))
        try handle.seekToEnd()
        try handle.write(contentsOf: Data([0]))
        try handle.close()
        let readOverCap = try await respond(["operation": "vault.read", "path": "AtCap.bin", "encoding": "binary"])
        XCTAssertEqual(failureKind(of: readOverCap), "tooLarge")
    }
}

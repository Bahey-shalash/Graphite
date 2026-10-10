import XCTest
@testable import GraphiteCore

/// Obsidian community plugin packages in a vault, and the bridge the plugin runtime's file
/// operations go through. The bridge follows the same contract as the Node tests' host
/// (`Tests/CommunityPluginRuntimeTests/support/test-vault-host.js`).
final class CommunityPluginTests: XCTestCase {
    private var vault: URL!

    override func setUpWithError() throws {
        vault = FileManager.default.temporaryDirectory.appendingPathComponent("PluginVault-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: vault)
    }

    private func write(_ text: String, to relativePath: String) throws {
        try write(Data(text.utf8), to: relativePath)
    }

    private func write(_ data: Data, to relativePath: String) throws {
        let location = vault.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: location.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: location)
    }

    private func read(_ relativePath: String) throws -> String {
        try String(contentsOf: vault.appendingPathComponent(relativePath), encoding: .utf8)
    }

    private let sampleManifest = """
    {"id": "sample", "name": "Sample", "version": "1.2.0", "minAppVersion": "1.0.0", "description": "A sample.", "author": "Someone", "fundingUrl": "https://example.com"}
    """

    // MARK: Manifests

    func testManifestKeepsItsBytesAndReadsObsidianKeys() throws {
        let manifest = try CommunityPluginManifest(manifestData: Data(sampleManifest.utf8))
        XCTAssertEqual(manifest.identifier, "sample")
        XCTAssertEqual(manifest.name, "Sample")
        XCTAssertEqual(manifest.version, "1.2.0")
        XCTAssertEqual(manifest.minimumApplicationVersion, "1.0.0")
        XCTAssertFalse(manifest.isDesktopOnly)
        XCTAssertEqual(manifest.manifestData, Data(sampleManifest.utf8), "Keys Graphite does not read, such as fundingUrl, reach the runtime unchanged.")
    }

    func testManifestRefusesIdentifiersThatAreNotOneFolderName() throws {
        for identifier in ["", "../escape", "a/b", ".hidden", "..", "with\nbreak"] {
            let manifestData = try JSONSerialization.data(withJSONObject: ["id": identifier, "name": "X"])
            XCTAssertThrowsError(try CommunityPluginManifest(manifestData: manifestData), identifier)
        }
        XCTAssertThrowsError(try CommunityPluginManifest(manifestData: Data("[1, 2]".utf8)))
    }

    func testVersionNumbersCompareByPart() {
        XCTAssertEqual(ObsidianVersionNumber.compare("1.4.10", "1.4.9"), .orderedDescending)
        XCTAssertEqual(ObsidianVersionNumber.compare("1.4", "1.4.0"), .orderedSame)
        XCTAssertEqual(ObsidianVersionNumber.compare("0.15.9", "1.0.0"), .orderedAscending)
    }

    // MARK: community-plugins.json

    func testListIsWrittenAsObsidianWritesIt() throws {
        var list = try CommunityPluginList(configurationData: Data("[\"dataview\", 3, \"templater-obsidian\"]".utf8))
        XCTAssertEqual(list.enabledIdentifiers, ["dataview", "templater-obsidian"])
        list.setEnabled("calendar", true)
        list.setEnabled("dataview", false)
        list.setEnabled("calendar", true)
        XCTAssertEqual(String(decoding: try list.configurationData(), as: UTF8.self), "[\n  \"templater-obsidian\",\n  \"calendar\"\n]")
        XCTAssertEqual(String(decoding: try CommunityPluginList().configurationData(), as: UTF8.self), "[]")
        XCTAssertEqual(try CommunityPluginList(configurationData: Data(" \n".utf8)).enabledIdentifiers, [])
        XCTAssertThrowsError(try CommunityPluginList(configurationData: Data("{\"dataview\": true}".utf8)))
    }

    func testTurningPluginsOnAndOffKeepsWhatObsidianChanged() async throws {
        let store = VaultStore(root: vault)
        try await store.updateCommunityPluginList { list in list.setEnabled("nothing", false) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: vault.appendingPathComponent(".obsidian/community-plugins.json").path), "No file until a plugin is on.")
        try await store.updateCommunityPluginList { list in list.setEnabled("sample", true) }
        try write("[\n  \"sample\",\n  \"added-in-obsidian\"\n]", to: ".obsidian/community-plugins.json")
        let updated = try await store.updateCommunityPluginList { list in list.setEnabled("sample", false) }
        XCTAssertEqual(updated.enabledIdentifiers, ["added-in-obsidian"])
        XCTAssertEqual(try read(".obsidian/community-plugins.json"), "[\n  \"added-in-obsidian\"\n]")
    }

    // MARK: Installed plugins

    func testInstalledPluginsAreListedWithWhatTheyNeed() async throws {
        try write(sampleManifest, to: ".obsidian/plugins/sample/manifest.json")
        try write("var obsidian = require(\"obsidian\"); var view = require('@codemirror/view'); if (desktop) require(\"fs\"); require(\"./local\");", to: ".obsidian/plugins/sample/main.js")
        try write("{\"id\": \"desk\", \"name\": \"Desk\", \"isDesktopOnly\": true, \"minAppVersion\": \"9.0.0\"}", to: ".obsidian/plugins/desk/manifest.json")
        try write("not json", to: ".obsidian/plugins/broken/manifest.json")
        let inventory = try await VaultStore(root: vault).installedCommunityPlugins()
        XCTAssertEqual(inventory.plugins.map(\.id), ["desk", "sample"])
        let sample = try XCTUnwrap(inventory.plugins.first { plugin in plugin.id == "sample" })
        XCTAssertTrue(sample.compatibility.canLoad)
        XCTAssertEqual(sample.compatibility.missingModules, [
            .init(name: "@codemirror/view", kind: .codeMirror), .init(name: "fs", kind: .desktopOnly),
        ])
        let desk = try XCTUnwrap(inventory.plugins.first { plugin in plugin.id == "desk" })
        XCTAssertEqual(desk.compatibility.blockers, [.desktopOnly, .needsNewerApi(required: "9.0.0"), .missingMainScript])
        XCTAssertEqual(inventory.unreadableFolders.map(\.folder.name), ["broken"])
        let package = try await VaultStore(root: vault).communityPluginPackage(for: sample)
        XCTAssertTrue(package.mainScript.hasPrefix("var obsidian"))
        XCTAssertEqual(package.styles, "")
    }

    // MARK: The vault bridge

    private func bridge() -> CommunityPluginVaultBridge {
        CommunityPluginVaultBridge(store: VaultStore(root: vault)) { .vaultTrash }
    }

    private func respond(_ message: [String: Any]) async throws -> [String: Any] {
        let data = try JSONSerialization.data(withJSONObject: message)
        let answer = await bridge().respond(to: data)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: answer) as? [String: Any])
    }

    private func failureKind(_ answer: [String: Any]) -> String? {
        (answer["failure"] as? [String: Any])?["kind"] as? String
    }

    func testListsTheVaultWithoutHiddenItems() async throws {
        try write("a", to: "Note.md")
        try write("b", to: "Course/Lecture.md")
        try write("{}", to: ".obsidian/app.json")
        let answer = try await respond(["operation": "vault.list"])
        let paths = (answer["entries"] as? [[String: Any]] ?? []).compactMap { entry in entry["path"] as? String }.sorted()
        XCTAssertEqual(paths, ["Course", "Course/Lecture.md", "Note.md"])
        XCTAssertEqual(answer["isTruncated"] as? Bool, false)
        let folder = try await respond(["operation": "vault.listFolder", "path": ".obsidian"])
        XCTAssertEqual(folder["files"] as? [String], [".obsidian/app.json"])
    }

    func testReadsTextWithoutTheByteOrderMarkAndKeepsItWhenWriting() async throws {
        try write(Data([0xEF, 0xBB, 0xBF]) + Data("text".utf8), to: "Marked.md")
        let readAnswer = try await respond(["operation": "vault.read", "path": "Marked.md", "encoding": "text"])
        XCTAssertEqual(readAnswer["text"] as? String, "text")
        let revision = try XCTUnwrap(readAnswer["revision"] as? [String: Any])
        let writeAnswer = try await respond(["operation": "vault.write", "path": "Marked.md", "text": "new", "expectation": ["kind": "revision", "revision": revision]])
        XCTAssertNil(writeAnswer["failure"])
        XCTAssertEqual(try Data(contentsOf: vault.appendingPathComponent("Marked.md")), Data([0xEF, 0xBB, 0xBF]) + Data("new".utf8))
    }

    func testAWriteBasedOnAStaleReadIsRefused() async throws {
        try write("original", to: "Note.md")
        let readAnswer = try await respond(["operation": "vault.read", "path": "Note.md", "encoding": "text"])
        let revision = try XCTUnwrap(readAnswer["revision"] as? [String: Any])
        try write("changed in another app", to: "Note.md")
        let writeAnswer = try await respond(["operation": "vault.write", "path": "Note.md", "text": "plugin", "expectation": ["kind": "revision", "revision": revision]])
        XCTAssertEqual(failureKind(writeAnswer), "conflict")
        XCTAssertEqual(try read("Note.md"), "changed in another app")
        let createAnswer = try await respond(["operation": "vault.write", "path": "Note.md", "text": "again", "expectation": ["kind": "absent"]])
        XCTAssertEqual(failureKind(createAnswer), "conflict")
        let replaceAnswer = try await respond(["operation": "vault.write", "path": "New/Made.md", "base64": Data([1, 2]).base64EncodedString(), "expectation": ["kind": "replace"]])
        XCTAssertNil(replaceAnswer["failure"])
        XCTAssertEqual(try Data(contentsOf: vault.appendingPathComponent("New/Made.md")), Data([1, 2]))
    }

    func testPathsOutsideTheVaultAreRefused() async throws {
        let answer = try await respond(["operation": "vault.read", "path": "../outside.txt", "encoding": "text"])
        XCTAssertNotNil(failureKind(answer))
    }

    func testRemovingRenamingAndCopying() async throws {
        try write("a", to: "Folder/Note.md")
        let copyAnswer = try await respond(["operation": "vault.copy", "path": "Folder", "destinationPath": "Copy"])
        XCTAssertNil(copyAnswer["failure"])
        XCTAssertEqual(try read("Copy/Note.md"), "a")
        let renameAnswer = try await respond(["operation": "vault.rename", "path": "Copy/Note.md", "destinationPath": "Copy/Renamed.md"])
        XCTAssertNil(renameAnswer["failure"])
        let notEmptyAnswer = try await respond(["operation": "vault.remove", "path": "Folder", "method": "permanent", "isRecursive": false, "isFolderExpected": true])
        XCTAssertEqual(failureKind(notEmptyAnswer), "notEmpty")
        let trashAnswer = try await respond(["operation": "vault.remove", "path": "Copy/Renamed.md", "method": "vaultSetting"])
        XCTAssertEqual(trashAnswer["outcome"] as? String, "vaultTrash", "The vault's “Deleted files” setting decides.")
        XCTAssertTrue(FileManager.default.fileExists(atPath: vault.appendingPathComponent(".trash/Renamed.md").path))
        let missingAnswer = try await respond(["operation": "vault.remove", "path": "Gone.md", "method": "permanent"])
        XCTAssertEqual(failureKind(missingAnswer), "missing")
    }

    // MARK: Editor changes

    func testEditorChangeReplacesOnlyWhatDiffers() throws {
        let edit = try XCTUnwrap(CommunityPluginEditorChange.edit(from: "alpha beta gamma", to: "alpha **beta** gamma", selectionAnchor: 14, selectionHead: 14))
        XCTAssertEqual(edit.range, NSRange(location: 6, length: 4))
        XCTAssertEqual(edit.replacement, "**beta**")
        XCTAssertEqual(edit.selectionAfter, NSRange(location: 14, length: 0))
        XCTAssertNil(CommunityPluginEditorChange.edit(from: "same", to: "same", selectionAnchor: 0, selectionHead: 0))
    }

    func testEditorChangeNeverSplitsASurrogatePair() throws {
        // 😀 and 😁 share their first UTF-16 unit.
        let edit = try XCTUnwrap(CommunityPluginEditorChange.edit(from: "a😀b", to: "a😁b", selectionAnchor: 0, selectionHead: 0))
        XCTAssertEqual(edit.range, NSRange(location: 1, length: 2))
        XCTAssertEqual(edit.replacement, "😁")
    }

    // MARK: Installing

    func testNewestCompatibleReleaseIsChosenFromVersionsFile() {
        let versions = Data("{\"1.0.0\": \"0.15.0\", \"2.0.0\": \"1.4.0\", \"3.0.0\": \"9.0.0\", \"2.1.0\": \"1.5.0\"}".utf8)
        XCTAssertEqual(CommunityPluginInstaller.newestCompatibleVersion(versionsData: versions, providedApiVersion: "1.14.4"), "2.1.0")
        XCTAssertNil(CommunityPluginInstaller.newestCompatibleVersion(versionsData: versions, providedApiVersion: "0.1.0"))
    }

    func testRepositoriesMustBeOwnerAndName() {
        XCTAssertTrue(CommunityPluginInstaller.isUsableRepository("blacksmithgu/obsidian-dataview"))
        for repository in ["owner", "owner/", "/name", "owner/name/extra", "../name", "owner/..", "owner/na me"] {
            XCTAssertFalse(CommunityPluginInstaller.isUsableRepository(repository), repository)
        }
    }

    func testMarkdownIsRenderedForPluginViews() throws {
        let html = try CommunityPluginMarkdownRendering.html(for: "# Title\n\nSome *text*.")
        XCTAssertTrue(html.contains("<h1>Title</h1>"))
        XCTAssertTrue(html.contains("<em>text</em>"))
    }
}

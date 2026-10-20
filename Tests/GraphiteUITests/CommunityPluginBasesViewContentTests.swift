import XCTest
import GraphiteCore
import GraphiteIndex
@testable import GraphiteUI
import GraphiteTestSupport

/// When a plugin's view of a base is sent the base's results again.
@MainActor
final class CommunityPluginBasesViewContentTests: XCTestCase {

    func testUpdateKeyChangesWhenAFormulaValueChangesAndTheRowsStay() async throws {
        let vault = try makeVault(files: [
            "Tasks/First.md": "---\npriority: 1\n---\n",
            "Tasks/Second.md": "---\npriority: 2\n---\n",
        ], baseText: "filters: file.inFolder(\"Tasks\")\nformulas:\n  urgency: priority * 2\nviews:\n  - type: table\n    name: Table\n    order: [file.name, formula.urgency]\n")
        let before = try await queryResult(in: vault)

        try Data("---\npriority: 5\n---\n".utf8).write(to: vault.appendingPathComponent("Tasks/First.md"))
        let after = try await queryResult(in: vault)

        XCTAssertEqual(before.rows.map(\.path), after.rows.map(\.path), "The same rows match in the same order.")
        XCTAssertNotEqual(CommunityPluginBasesViewContent.updateKey(for: before), CommunityPluginBasesViewContent.updateKey(for: after))
    }

    func testUpdateKeyChangesWhenTheViewsColumnsChangeAndTheRowsStay() async throws {
        let vault = try makeVault(files: ["Tasks/First.md": "---\npriority: 1\n---\n"],
                                  baseText: "filters: file.inFolder(\"Tasks\")\nviews:\n  - type: table\n    name: Table\n    order: [file.name]\n")
        let before = try await queryResult(in: vault)

        try Data("filters: file.inFolder(\"Tasks\")\nviews:\n  - type: table\n    name: Table\n    order: [file.name, priority]\n".utf8).write(to: vault.appendingPathComponent("Tasks.base"))
        let after = try await queryResult(in: vault)

        XCTAssertNotEqual(CommunityPluginBasesViewContent.updateKey(for: before), CommunityPluginBasesViewContent.updateKey(for: after))
    }

    func testUpdateKeyStaysTheSameForAnUnchangedResult() async throws {
        let vault = try makeVault(files: ["Tasks/First.md": "---\npriority: 1\n---\n"],
                                  baseText: "filters: file.inFolder(\"Tasks\")\nformulas:\n  urgency: priority * 2\nviews:\n  - type: table\n    name: Table\n    order: [file.name, formula.urgency]\n")
        let first = try await queryResult(in: vault)
        let second = try await queryResult(in: vault)

        XCTAssertEqual(CommunityPluginBasesViewContent.updateKey(for: first), CommunityPluginBasesViewContent.updateKey(for: second))
    }

    // MARK: Helpers

    private func makeVault(files: [String: String], baseText: String) throws -> URL {
        let vault = try TemporaryVault.make(prefix: "PluginBasesVault", for: self).root
        for (relativePath, text) in files {
            let location = vault.appendingPathComponent(relativePath)
            try FileManager.default.createDirectory(at: location.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: location)
        }
        try Data(baseText.utf8).write(to: vault.appendingPathComponent("Tasks.base"))
        return vault
    }

    /// The base's results as its document model computes them now.
    private func queryResult(in vault: URL) async throws -> BaseQueryResult {
        let indexFolder = try TemporaryVault.make(prefix: "PluginBasesIndex", for: self).root
        let index = try VaultIndex(databaseURL: indexFolder.appendingPathComponent("index.sqlite"))
        _ = try await index.reconcile(root: vault)
        let basePath = try VaultPath("Tasks.base")
        let model = BaseDocumentModel(source: .file(basePath), contextPath: basePath, store: VaultStore(root: vault), index: index)
        await model.reload()
        XCTAssertNil(model.loadErrorMessage)
        return try XCTUnwrap(model.result)
    }
}

import XCTest
import GraphiteTestSupport
@testable import GraphiteCore

final class VaultStoreMyPaperTemplatesTests: XCTestCase {
    private func makeStore(files: [String: String] = [:]) throws -> (VaultStore, TemporaryVault) {
        let vault = try TemporaryVault.make(prefix: "MyPaperTemplates", files: files, for: self)
        return (VaultStore(root: vault.root), vault)
    }

    private let pdfBytes = Data("%PDF-1.4 a page".utf8)

    func testATemplateIsKeptAsAnOrdinaryPDFInTheVaultsTemplatesFolderAndShownLast() async throws {
        let (store, vault) = try makeStore()
        let first = try await store.addMyPaperTemplate(pdfBytes, named: "Lecture grid")
        let second = try await store.addMyPaperTemplate(pdfBytes, named: "Cornell")
        XCTAssertEqual(first.fileName, "Lecture grid.pdf")
        XCTAssertEqual(try Data(contentsOf: vault.location(of: ".obsidian/graphite-templates/Lecture grid.pdf")), pdfBytes)
        let shown = try await store.myPaperTemplates()
        XCTAssertEqual(shown.map(\.fileName), ["Lecture grid.pdf", second.fileName], "A new template comes after the others, not by name.")
    }

    func testTheSameNameGetsAFreeFileName() async throws {
        let (store, _) = try makeStore()
        _ = try await store.addMyPaperTemplate(pdfBytes, named: "Grid")
        let second = try await store.addMyPaperTemplate(pdfBytes, named: "Grid")
        XCTAssertEqual(second.fileName, "Grid 1.pdf")
    }

    func testAnUnusableNameAddsNothing() async throws {
        let (store, vault) = try makeStore()
        do {
            _ = try await store.addMyPaperTemplate(pdfBytes, named: "a/b")
            XCTFail("A name with a slash is refused.")
        } catch {
            XCTAssertFalse(FileManager.default.fileExists(atPath: vault.location(of: ".obsidian/graphite-templates").path))
        }
    }

    func testAPDFPutInTheFolderByHandIsShownAndOtherFilesAreNot() async throws {
        let (store, _) = try makeStore(files: [".obsidian/graphite-templates/Hand placed.PDF": "x", ".obsidian/graphite-templates/readme.txt": "x"])
        let shown = try await store.myPaperTemplates()
        XCTAssertEqual(shown.map(\.fileName), ["Hand placed.PDF"])
    }

    func testRenamingMovesTheFileAndKeepsPlaceAndHiding() async throws {
        let (store, vault) = try makeStore()
        _ = try await store.addMyPaperTemplate(pdfBytes, named: "A")
        _ = try await store.addMyPaperTemplate(pdfBytes, named: "B")
        try await store.updateMyPaperTemplateList { @Sendable list in list.setHidden(true, fileName: "A.pdf") }
        let renamed = try await store.renameMyPaperTemplate("A.pdf", to: "Weekly planner")
        XCTAssertEqual(renamed, MyPaperTemplateList.Template(fileName: "Weekly planner.pdf", isHidden: true))
        XCTAssertFalse(FileManager.default.fileExists(atPath: vault.location(of: ".obsidian/graphite-templates/A.pdf").path))
        let shown = try await store.myPaperTemplates()
        XCTAssertEqual(shown.map(\.fileName), ["Weekly planner.pdf", "B.pdf"])
    }

    func testRenamingOntoAnotherTemplateIsRefusedAndChangesNothing() async throws {
        let (store, _) = try makeStore()
        _ = try await store.addMyPaperTemplate(pdfBytes, named: "A")
        _ = try await store.addMyPaperTemplate(pdfBytes, named: "B")
        do {
            _ = try await store.renameMyPaperTemplate("A.pdf", to: "B")
            XCTFail("An existing name is not replaced.")
        } catch {
            let shown = try await store.myPaperTemplates()
            XCTAssertEqual(shown.map(\.fileName), ["A.pdf", "B.pdf"])
        }
    }

    func testDeletingRemovesTheFileAndForgetsItsArrangement() async throws {
        let (store, vault) = try makeStore()
        _ = try await store.addMyPaperTemplate(pdfBytes, named: "A")
        _ = try await store.addMyPaperTemplate(pdfBytes, named: "B")
        try await store.deleteMyPaperTemplate("A.pdf")
        XCTAssertFalse(FileManager.default.fileExists(atPath: vault.location(of: ".obsidian/graphite-templates/A.pdf").path))
        let list = try await store.myPaperTemplateList()
        XCTAssertEqual(list.order, ["B.pdf"])
    }

    func testAnArrangementThisBuildCannotReadIsKeptAsItIsAndNeverOverwritten() async throws {
        let (store, vault) = try makeStore(files: [".obsidian/graphite-templates/templates.json": "not json", ".obsidian/graphite-templates/A.pdf": "x"])
        do {
            _ = try await store.myPaperTemplates()
            XCTFail("An unreadable arrangement is refused, not read as empty.")
        } catch {
            XCTAssertEqual(error as? MyPaperTemplateListError, .notAJSONObject)
        }
        do {
            try await store.updateMyPaperTemplateList { @Sendable list in list.setHidden(true, fileName: "A.pdf") }
            XCTFail("An unreadable arrangement is never written over.")
        } catch {
            XCTAssertEqual(try String(contentsOf: vault.location(of: ".obsidian/graphite-templates/templates.json"), encoding: .utf8), "not json")
        }
        let keptCopy = try await store.moveMyPaperTemplateListAside()
        XCTAssertEqual(keptCopy.name, "templates.unreadable.json")
        XCTAssertEqual(try String(contentsOf: vault.location(of: ".obsidian/graphite-templates/templates.unreadable.json"), encoding: .utf8), "not json")
        let shown = try await store.myPaperTemplates()
        XCTAssertEqual(shown.map(\.fileName), ["A.pdf"])
    }

    func testAnUnchangedArrangementWritesNoFile() async throws {
        let (store, vault) = try makeStore()
        try await store.updateMyPaperTemplateList { @Sendable _ in }
        XCTAssertFalse(FileManager.default.fileExists(atPath: vault.location(of: ".obsidian/graphite-templates/templates.json").path))
    }

    func testAFolderThatCannotBeWrittenFailsAndLeavesNoTemplate() async throws {
        let (store, vault) = try makeStore(files: [".obsidian/graphite-templates/Existing.pdf": "x"])
        let folder = vault.location(of: ".obsidian/graphite-templates")
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path) } // So the vault can be removed.
        do {
            _ = try await store.addMyPaperTemplate(pdfBytes, named: "New")
            XCTFail("A read-only folder cannot take a template.")
        } catch {
            XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent("New.pdf").path))
        }
    }
}

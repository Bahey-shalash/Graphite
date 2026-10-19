import XCTest
import GraphiteCore
import GraphiteApple
import GraphiteTestSupport
@testable import GraphiteUI

@MainActor
final class LibraryModelTests: XCTestCase {
    private var vault: URL!

    override func setUpWithError() throws {
        let files = ["Courses/Week 1.pdf": "x", "Courses/Summary.md": "x", "Courses/Photos/board.png": "x", "Inbox.md": "x"]
        vault = try TemporaryVault.make(prefix: "LibraryModel", files: files, for: self).root
    }

    private func source(identifier: UUID = UUID()) -> LibraryModel.Source {
        LibraryModel.Source(vaultIdentifier: identifier, store: VaultStore(root: vault),
                            loader: LibraryPreviewLoader(root: vault) { _, _ in nil })
    }

    func testListsTheVaultRootFoldersFirst() async {
        let library = LibraryModel()
        await library.reload(source: source(), sortOrder: .alphabetical)
        XCTAssertEqual(library.items.map(\.path.rawValue), ["Courses", "Inbox.md"])
    }

    func testShowingAFolderListsItAndTheFilterApplies() async throws {
        let library = LibraryModel()
        await library.reload(source: source(), sortOrder: .alphabetical)
        await library.show(try VaultPath("Courses"))
        XCTAssertEqual(library.items.map(\.path.name), ["Photos", "Summary.md", "Week 1.pdf"])
        library.filter = .notebooks
        XCTAssertEqual(library.items.map(\.path.name), ["Photos", "Week 1.pdf"])
    }

    func testAnotherVaultStartsAtItsRoot() async throws {
        let library = LibraryModel()
        await library.reload(source: source(), sortOrder: .alphabetical)
        await library.show(try VaultPath("Courses"))
        await library.reload(source: source(), sortOrder: .alphabetical)
        XCTAssertEqual(library.folder, .root)
    }

    func testAFolderDeletedWhileShownGoesUpToOneThatExists() async throws {
        let identifier = UUID()
        let library = LibraryModel()
        await library.reload(source: source(identifier: identifier), sortOrder: .alphabetical)
        await library.show(try VaultPath("Courses/Photos"))
        try FileManager.default.removeItem(at: vault.appendingPathComponent("Courses/Photos"))
        await library.reload(source: source(identifier: identifier), sortOrder: .alphabetical)
        XCTAssertEqual(library.folder, try VaultPath("Courses"))
        XCTAssertNil(library.failure)
    }

    func testAFolderStyleIsSavedInTheVault() async throws {
        let library = LibraryModel()
        await library.reload(source: source(), sortOrder: .alphabetical)
        await library.setStyle(FolderStyle(color: .green, symbolName: "flask"), for: try VaultPath("Courses"))
        XCTAssertNil(library.failure)
        XCTAssertEqual(library.style(of: try VaultPath("Courses")), FolderStyle(color: .green, symbolName: "flask"))
        let stored = try FolderStyleList(configurationData: Data(contentsOf: vault.appendingPathComponent(FolderStyleList.configurationPath)))
        XCTAssertEqual(stored.style(for: try VaultPath("Courses"))?.color, .green)
    }

    func testHomeStartsShownAndStepsBackWhenADocumentIsChosen() {
        let library = LibraryModel()
        XCTAssertTrue(library.isShownAsHome)
        library.leaveHome()
        XCTAssertFalse(library.isShownAsHome)
        library.showHome()
        XCTAssertTrue(library.isShownAsHome)
    }
}

extension LibraryModelTests {
    /// SwiftUI showed a rebuilt grid's tile before removing the old one; the old tile's
    /// disappearance cancelled the new tile's preview, and the grid stayed blank.
    func testAPreviewSurvivesItsOldTileDisappearingAfterTheNewOneAppeared() async throws {
        let library = LibraryModel()
        await library.reload(source: source(), sortOrder: .alphabetical)
        let note = try XCTUnwrap(library.items.first { entry in entry.path.name == "Inbox.md" })
        library.tileAppeared(note)
        library.tileAppeared(note)
        library.tileDisappeared(note)
        let deadline = Date.now.addingTimeInterval(10)
        while library.visiblePreviews[note.path] == nil, Date.now < deadline { await Task.yield() }
        XCTAssertNotNil(library.visiblePreviews[note.path])
        library.tileDisappeared(note)
        XCTAssertNil(library.visiblePreviews[note.path])
    }
}

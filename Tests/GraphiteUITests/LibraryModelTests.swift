import XCTest
import CoreGraphics
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
        let loader = LibraryPreviewLoader(root: vault) { _, _ in nil }
        return LibraryModel.Source(vaultIdentifier: identifier, store: VaultStore(root: vault)) { path, longerSidePixels in
            await loader.preview(of: path, longerSidePixels: longerSidePixels)
        }
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
        await library.setStyle(FolderStyle(color: .green, mark: .symbol("flask")), for: try VaultPath("Courses"))
        XCTAssertNil(library.failure)
        XCTAssertEqual(library.style(of: try VaultPath("Courses")), FolderStyle(color: .green, mark: .symbol("flask")))
        let stored = try FolderStyleList(configurationData: Data(contentsOf: vault.appendingPathComponent(FolderStyleList.configurationPath)))
        XCTAssertEqual(stored.style(for: try VaultPath("Courses"))?.color, .green)
    }

    func testHomeStartsShownAndStepsBackWhenADocumentIsChosen() async {
        let library = LibraryModel()
        XCTAssertTrue(library.isShownAsHome)
        library.leaveHome()
        XCTAssertFalse(library.isShownAsHome)
        await library.showHome()
        XCTAssertTrue(library.isShownAsHome)
    }

    func testHomeReturnsToTheFolderShownThenToTheVaultRoot() async throws {
        let library = LibraryModel()
        await library.reload(source: source(), sortOrder: .alphabetical)
        await library.show(try VaultPath("Courses/Photos"))
        library.leaveHome()
        await library.showHome()
        XCTAssertTrue(library.isShownAsHome)
        XCTAssertEqual(library.folder, try VaultPath("Courses/Photos"))
        await library.showHome()
        XCTAssertEqual(library.folder, .root)
        XCTAssertEqual(library.items.map(\.path.rawValue), ["Courses", "Inbox.md"])
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
        try await waitUntil("the preview is drawn") { library.visiblePreviews[note.path] != nil }
        library.tileDisappeared(note)
        XCTAssertNil(library.visiblePreviews[note.path])
    }
}

// MARK: Regression tests for the delta audit's findings

/// A render that waits until the test lets it finish, and records how many ran at once and
/// which were cancelled while they ran.
private actor RenderProbe {
    private(set) var startedPaths: [VaultPath] = []
    private(set) var cancelledPaths: [VaultPath] = []
    private(set) var maximumRunningCount = 0
    private var runningCount = 0
    private var waitingRenders: [CheckedContinuation<Void, Never>] = []

    func render(_ path: VaultPath) async -> LibraryTilePreview {
        startedPaths.append(path)
        runningCount += 1
        maximumRunningCount = max(maximumRunningCount, runningCount)
        await withCheckedContinuation { continuation in waitingRenders.append(continuation) }
        runningCount -= 1
        if Task.isCancelled { cancelledPaths.append(path) }
        return .kindIcon
    }

    func finishWaitingRenders() {
        for continuation in waitingRenders { continuation.resume() }
        waitingRenders = []
    }
}

extension LibraryModelTests {
    private func probedSource(_ probe: RenderProbe) -> LibraryModel.Source {
        LibraryModel.Source(vaultIdentifier: UUID(), store: VaultStore(root: vault)) { path, _ in await probe.render(path) }
    }

    /// BUG-SHELL-07: a style file that is not Graphite's format made every folder "Can't Show
    /// This Folder", until the person deleted the hidden file by hand.
    func testAStyleFileNotInGraphitesFormatIsKeptAsideAndTheFolderStillShows() async throws {
        let styleFile = vault.appendingPathComponent(FolderStyleList.configurationPath)
        try FileManager.default.createDirectory(at: styleFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(#"{"folders": []}"#.utf8).write(to: styleFile)
        let library = LibraryModel()

        await library.reload(source: source(), sortOrder: .alphabetical)

        XCTAssertEqual(library.items.map(\.path.rawValue), ["Courses", "Inbox.md"])
        XCTAssertEqual(library.failure, .folderStylesSetAside(keptCopyName: "graphite-folder-styles.unreadable.json"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: styleFile.path))
        let keptCopy = vault.appendingPathComponent(".obsidian/graphite-folder-styles.unreadable.json")
        XCTAssertEqual(try String(contentsOf: keptCopy, encoding: .utf8), #"{"folders": []}"#)
    }

    /// BUG-SHELL-08: a file that changed while its tile was on screen kept its old preview.
    func testAFileChangedWhileItsTileIsShownGetsANewPreview() async throws {
        let identifier = UUID()
        let library = LibraryModel()
        try Data("Old text".utf8).write(to: vault.appendingPathComponent("Inbox.md"))
        await library.reload(source: source(identifier: identifier), sortOrder: .alphabetical)
        let note = try XCTUnwrap(library.items.first { entry in entry.path.name == "Inbox.md" })
        library.tileAppeared(note)
        try await waitUntil("the first preview is drawn") { self.noteText(in: library, at: note.path) == "Old text" }

        try Data("New, longer text".utf8).write(to: vault.appendingPathComponent("Inbox.md"))
        await library.reload(source: source(identifier: identifier), sortOrder: .alphabetical)

        try await waitUntil("the changed note's preview is drawn") { self.noteText(in: library, at: note.path) == "New, longer text" }
    }

    /// BUG-SHELL-09: every tile on screen rendered at once, without a limit.
    func testNoMoreRendersRunAtOnceThanTheLimit() async throws {
        for number in 1...10 { try Data("x".utf8).write(to: vault.appendingPathComponent("Page \(number).md")) }
        let probe = RenderProbe()
        let library = LibraryModel()
        await library.reload(source: probedSource(probe), sortOrder: .alphabetical)
        let files = library.items.filter { entry in !entry.isDirectory }
        XCTAssertEqual(files.count, 11)

        for file in files { library.tileAppeared(file) }
        try await waitUntil("the first renders start") { await probe.startedPaths.count == LibraryModel.maximumConcurrentRenders }
        for _ in 0..<20 { await Task.yield() }
        let startedBeforeAnyFinished = await probe.startedPaths.count
        XCTAssertEqual(startedBeforeAnyFinished, LibraryModel.maximumConcurrentRenders)

        try await waitUntil("every tile has its preview") {
            await probe.finishWaitingRenders()
            return library.visiblePreviews.count == files.count
        }
        let maximumRunningCount = await probe.maximumRunningCount
        XCTAssertLessThanOrEqual(maximumRunningCount, LibraryModel.maximumConcurrentRenders)
    }

    /// BUG-SHELL-09: a tile scrolled away cancelled only the task waiting for its render; the
    /// render itself ran on in a detached task.
    func testATileScrolledAwayCancelsItsRender() async throws {
        let probe = RenderProbe()
        let library = LibraryModel()
        await library.reload(source: probedSource(probe), sortOrder: .alphabetical)
        let note = try XCTUnwrap(library.items.first { entry in entry.path.name == "Inbox.md" })

        library.tileAppeared(note)
        try await waitUntil("the render starts") { await probe.startedPaths == [note.path] }
        library.tileDisappeared(note)
        try await waitUntil("the render ends") {
            await probe.finishWaitingRenders()
            return await !probe.cancelledPaths.isEmpty
        }

        let cancelledPaths = await probe.cancelledPaths
        XCTAssertEqual(cancelledPaths, [note.path])
        XCTAssertNil(library.visiblePreviews[note.path])
    }

    /// CC-SHELL-11: the cache counted previews but not their memory.
    func testACachedPreviewCostsItsPixelsBytes() throws {
        let context = try XCTUnwrap(CGContext(data: nil, width: 300, height: 200, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let image = try XCTUnwrap(context.makeImage())
        XCTAssertEqual(LibraryPreviewCache.costBytes(of: .picture(image)), image.bytesPerRow * 200)
        XCTAssertEqual(LibraryPreviewCache.costBytes(of: .note(NotePreviewSummary(blocks: [], firstPictureTarget: nil), picture: image)), image.bytesPerRow * 200)
        XCTAssertEqual(LibraryPreviewCache.costBytes(of: .kindIcon), 0)
        XCTAssertGreaterThanOrEqual(LibraryModel.cachedPreviewBytes / (LibraryModel.previewPixels * LibraryModel.previewPixels * 4), 16)
    }

    private func noteText(in library: LibraryModel, at path: VaultPath) -> String? {
        guard case .note(let summary, _) = library.visiblePreviews[path], case .paragraph(let text) = summary.blocks.first else { return nil }
        return String(text.characters)
    }
}

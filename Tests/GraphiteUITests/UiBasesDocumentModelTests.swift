import XCTest
import GraphiteCore
import GraphiteIndex
@testable import GraphiteUI

@MainActor
final class UiBasesDocumentModelTests: XCTestCase {
    private var vault: URL!
    private var index: VaultIndex!
    private var store: VaultStore!

    override func setUp() async throws {
        vault = FileManager.default.temporaryDirectory.appendingPathComponent("UiBasesVault-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        index = try VaultIndex(databaseURL: vault.appendingPathExtension("cache").appendingPathComponent("index.sqlite"))
        store = VaultStore(root: vault)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: vault)
        try? FileManager.default.removeItem(at: vault.appendingPathExtension("cache"))
    }

    private func write(_ text: String, to relativePath: String) throws {
        try write(Data(text.utf8), to: relativePath)
    }

    private func write(_ data: Data, to relativePath: String) throws {
        let location = vault.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: location.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: location)
    }

    private func text(at relativePath: String) throws -> String {
        try String(contentsOf: vault.appendingPathComponent(relativePath), encoding: .utf8)
    }

    private func loadedModel(basePath: String) async throws -> BaseDocumentModel {
        _ = try await index.reconcile(root: vault)
        let path = try VaultPath(basePath)
        let model = BaseDocumentModel(source: .file(path), contextPath: path, store: store, index: index)
        await model.reload()
        XCTAssertNil(model.loadErrorMessage)
        return model
    }

    private func rowNames(_ model: BaseDocumentModel) -> [String] {
        model.result?.rows.map(\.path.name) ?? []
    }

    // MARK: Header sort

    func testHeaderTapOnAColumnTheViewSortsDescendingSortsItAscending() async throws {
        try write("A", to: "Notes/A.md")
        try write("B", to: "Notes/B.md")
        try write("filters: 'file.inFolder(\"Notes\")'\nviews:\n  - type: table\n    name: Table\n    sort:\n      - property: file.name\n        direction: DESC\n", to: "Sorted.base")
        let model = try await loadedModel(basePath: "Sorted.base")
        XCTAssertEqual(rowNames(model), ["B.md", "A.md"])

        await model.toggleSort(on: .file("name"))
        XCTAssertEqual(model.sortOverride, [BaseSortKey(property: .file("name"), direction: .ascending)])
        XCTAssertEqual(rowNames(model), ["A.md", "B.md"])

        await model.toggleSort(on: .file("name"))
        XCTAssertEqual(rowNames(model), ["B.md", "A.md"])
        await model.toggleSort(on: .file("name"))
        XCTAssertEqual(rowNames(model), ["A.md", "B.md"])
    }

    func testHeaderTapsStillReturnToTheViewSortWhenItDiffers() {
        let name = BasePropertyIdentifier.file("name")
        let viewSort = [BaseSortKey(property: .note("rating"), direction: .descending)]
        let ascending = BaseDocumentModel.sortOverride(afterTappingHeaderOf: name, effectiveSort: viewSort, viewSort: viewSort)
        XCTAssertEqual(ascending, [BaseSortKey(property: name, direction: .ascending)])
        let descending = BaseDocumentModel.sortOverride(afterTappingHeaderOf: name, effectiveSort: ascending ?? [], viewSort: viewSort)
        XCTAssertEqual(descending, [BaseSortKey(property: name, direction: .descending)])
        XCTAssertNil(BaseDocumentModel.sortOverride(afterTappingHeaderOf: name, effectiveSort: descending ?? [], viewSort: viewSort))
    }

    // MARK: Selection across reloads

    func testReloadKeepsTheSelectedViewAndItsSortWhenAnotherAppInsertsAView() async throws {
        try write("A", to: "A.md")
        try write("views:\n  - type: table\n    name: A\n  - type: table\n    name: B\n", to: "V.base")
        let model = try await loadedModel(basePath: "V.base")
        await model.selectView(1)
        await model.toggleSort(on: .file("name"))

        try write("views:\n  - type: table\n    name: Z\n  - type: table\n    name: A\n  - type: table\n    name: B\n", to: "V.base")
        await model.reload()
        XCTAssertEqual(model.selectedView?.name, "B")
        XCTAssertNotNil(model.sortOverride)

        await model.saveSortToView()
        XCTAssertNil(model.actionErrorMessage)
        let definition = try BaseDefinition.parse(try text(at: "V.base"))
        XCTAssertEqual(definition.views.map(\.name), ["Z", "A", "B"])
        XCTAssertEqual(definition.views[2].sort, [BaseSortKey(property: .file("name"), direction: .ascending)])
        XCTAssertEqual(definition.views[1].sort, [])
    }

    func testReloadDropsTheHeaderSortWhenTheSelectedViewIsRemoved() async throws {
        try write("A", to: "A.md")
        try write("views:\n  - type: table\n    name: A\n  - type: table\n    name: B\n", to: "V.base")
        let model = try await loadedModel(basePath: "V.base")
        await model.selectView(1)
        await model.toggleSort(on: .file("name"))

        try write("views:\n  - type: table\n    name: A\n", to: "V.base")
        await model.reload()
        XCTAssertEqual(model.selectedView?.name, "A")
        XCTAssertNil(model.sortOverride)
    }

    func testAnEditPreparedOnAViewThatMovedIsRefused() async throws {
        try write("A", to: "A.md")
        try write("views:\n  - type: table\n    name: A\n  - type: table\n    name: B\n", to: "V.base")
        let model = try await loadedModel(basePath: "V.base")
        let viewB = try XCTUnwrap(model.views.first { view in view.name == "B" })
        let target = BaseViewTarget(viewB)

        try write("views:\n  - type: table\n    name: Z\n  - type: table\n    name: A\n  - type: table\n    name: B\n", to: "V.base")
        await model.reload()
        let viewPosition = target.position
        let editResult: Void? = await model.editDefinition(target: target) { editor in try editor.setSort([], forViewAt: viewPosition) }
        XCTAssertNil(editResult)
        XCTAssertNotNil(model.actionErrorMessage)
        XCTAssertEqual(try text(at: "V.base"), "views:\n  - type: table\n    name: Z\n  - type: table\n    name: A\n  - type: table\n    name: B\n")
    }

    func testDeletingAConfirmedViewRemovesThatViewEvenAfterTheSelectionMoved() async throws {
        try write("A", to: "A.md")
        try write("views:\n  - type: table\n    name: A\n  - type: table\n    name: B\n  - type: table\n    name: C\n", to: "V.base")
        let model = try await loadedModel(basePath: "V.base")
        await model.selectView(1)
        let target = try XCTUnwrap(model.selectedView.map(BaseViewTarget.init))
        await model.selectView(2)

        await model.deleteView(target)
        XCTAssertNil(model.actionErrorMessage)
        XCTAssertEqual(try BaseDefinition.parse(try text(at: "V.base")).views.map(\.name), ["A", "C"])
        XCTAssertEqual(model.selectedView?.name, "C")
    }

    func testAnOlderReloadDoesNotReplaceTheDefinitionOfANewerOne() async throws {
        try write("A", to: "A.md")
        var largeDefinition = "views:\n"
        for viewNumber in 0..<9_000 { largeDefinition += "  - type: table\n    name: Old \(viewNumber)\n" }
        try write(largeDefinition, to: "R.base")
        _ = try await index.reconcile(root: vault)
        let path = try VaultPath("R.base")
        let model = BaseDocumentModel(source: .file(path), contextPath: path, store: store, index: index)

        let olderReload = Task { await model.reload() }
        try await Task.sleep(for: .milliseconds(20))
        try write("views:\n  - type: table\n    name: New\n", to: "R.base")
        await model.reload()
        await olderReload.value

        XCTAssertEqual(model.views.count, 1)
        XCTAssertEqual(model.views.first?.name, "New")
    }

    // MARK: Links

    func testALinkCellReachesTheNoteBesideAFolderOfTheSameName() async throws {
        try FileManager.default.createDirectory(at: vault.appendingPathComponent("Books"), withIntermediateDirectories: true)
        try write("Inside", to: "Books/Dune.md")
        try write("Folder note", to: "Library/Books.md")
        try write("views:\n  - type: table\n    name: Table\n", to: "Shelf.base")
        let model = try await loadedModel(basePath: "Shelf.base")

        let destination = try await model.resolve(BaseLink(target: "Books"))
        XCTAssertEqual(destination?.rawValue, "Library/Books.md")
        let rootedDestination = try await model.resolve(BaseLink(target: "Books/Dune.md"))
        XCTAssertEqual(rootedDestination?.rawValue, "Books/Dune.md")
    }

    // MARK: Property editing

    func testNestedValuesAreNotOfferedToThePropertyEditor() async throws {
        try write("---\ntitle: Dune\nmeta:\n  author: Frank\n  year: 1965\nshelves:\n  - name: Home\ntags: [fiction, classic]\n---\nBody\n", to: "Dune.md")
        try write("views:\n  - type: table\n    name: Table\n    order: [file.name, note.meta, note.shelves, note.tags, note.title]\n", to: "Books.base")
        let model = try await loadedModel(basePath: "Books.base")
        let row = try XCTUnwrap(model.result?.rows.first { row in row.path.name == "Dune.md" })
        let columns = try XCTUnwrap(model.result?.columns)
        func cellValue(_ property: BasePropertyIdentifier) throws -> BaseValue? {
            let position = try XCTUnwrap(columns.firstIndex { column in column.property == property })
            return row.cells[position].value
        }
        XCTAssertFalse(BaseDocumentModel.canEditValue(try cellValue(.note("meta"))))
        XCTAssertFalse(BaseDocumentModel.canEditValue(try cellValue(.note("shelves"))))
        XCTAssertTrue(BaseDocumentModel.canEditValue(try cellValue(.note("tags"))))
        XCTAssertTrue(BaseDocumentModel.canEditValue(try cellValue(.note("title"))))
        XCTAssertTrue(BaseDocumentModel.canEditValue(nil))
    }

    func testSettingAPropertyKeepsTheNoteByteOrderMark() async throws {
        let byteOrderMark = Data([0xEF, 0xBB, 0xBF])
        try write(byteOrderMark + Data("---\nrating: 1\n---\nBody\n".utf8), to: "Notes/Rated.md")
        try write("views:\n  - type: table\n    name: Table\n", to: "Ratings.base")
        let model = try await loadedModel(basePath: "Ratings.base")

        let didSave = await model.setProperty(.note("rating"), of: try VaultPath("Notes/Rated.md"), to: .number(5))
        XCTAssertTrue(didSave)
        let savedData = try Data(contentsOf: vault.appendingPathComponent("Notes/Rated.md"))
        XCTAssertTrue(savedData.starts(with: byteOrderMark))
        XCTAssertEqual(String(data: savedData.dropFirst(3), encoding: .utf8), "---\nrating: 5\n---\nBody\n")
    }

    func testEditingABaseKeepsItsByteOrderMark() async throws {
        let byteOrderMark = Data([0xEF, 0xBB, 0xBF])
        try write("A", to: "A.md")
        try write(byteOrderMark + Data("views:\n  - type: table\n    name: Table\n".utf8), to: "Marked.base")
        let model = try await loadedModel(basePath: "Marked.base")

        await model.addView(type: .list)
        XCTAssertNil(model.actionErrorMessage)
        let savedData = try Data(contentsOf: vault.appendingPathComponent("Marked.base"))
        XCTAssertTrue(savedData.starts(with: byteOrderMark))
        XCTAssertEqual(model.views.count, 2)
        XCTAssertEqual(model.selectedViewIndex, 1)
    }

    // MARK: Thumbnails

    func testConcurrentRequestsForOneCoverDecodeItOnceAndCountItsBytesOnce() async throws {
        let decodeCount = DecodeCounter()
        let thumbnailBytes = 550_000
        let thumbnails = BaseThumbnailStore { _, _ in
            await decodeCount.increment()
            try await Task.sleep(for: .milliseconds(20))
            return try Self.thumbnailImage(byteCount: thumbnailBytes)
        }
        try write(Data([1, 2, 3]), to: "Cover.png")
        let location = vault.appendingPathComponent("Cover.png")

        try await withThrowingTaskGroup(of: Int.self) { group in
            for _ in 0..<60 { group.addTask { BaseThumbnailStore.byteCount(of: try await thumbnails.thumbnail(at: location)) } }
            for try await byteCount in group { XCTAssertEqual(byteCount, thumbnailBytes) }
        }
        let decodes = await decodeCount.count
        let cachedByteCount = await thumbnails.cachedByteCount
        let cachedThumbnailCount = await thumbnails.cachedThumbnailCount
        XCTAssertEqual(decodes, 1)
        XCTAssertEqual(cachedByteCount, thumbnailBytes)
        XCTAssertEqual(cachedThumbnailCount, 1)

        _ = try await thumbnails.thumbnail(at: location)
        let decodesAfterCachedRequest = await decodeCount.count
        XCTAssertEqual(decodesAfterCachedRequest, 1)
    }

    func testAChangedCoverFileIsDecodedAgainAndReplacesItsCachedBytes() async throws {
        let decodeCount = DecodeCounter()
        let thumbnails = BaseThumbnailStore { location, _ in
            await decodeCount.increment()
            return try Self.thumbnailImage(byteCount: Self.pixelByteCount * Data(contentsOf: location).count)
        }
        try write(Data([1, 2, 3]), to: "Cover.png")
        let location = vault.appendingPathComponent("Cover.png")
        _ = try await thumbnails.thumbnail(at: location)

        try write(Data([4, 5, 6, 7, 8]), to: "Cover.png")
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: 60)], ofItemAtPath: location.path)
        let updatedThumbnail = try await thumbnails.thumbnail(at: location)
        XCTAssertEqual(updatedThumbnail.width, 5)
        let decodes = await decodeCount.count
        let cachedByteCount = await thumbnails.cachedByteCount
        XCTAssertEqual(decodes, 2)
        XCTAssertEqual(cachedByteCount, 5 * Self.pixelByteCount)
    }

    func testTheThumbnailBudgetEvictsTheOldestCovers() async throws {
        let thumbnailBytes = 10 * 1_048_576
        let thumbnails = BaseThumbnailStore { _, _ in try Self.thumbnailImage(byteCount: thumbnailBytes) }
        for coverNumber in 0..<5 {
            _ = try await thumbnails.thumbnail(at: vault.appendingPathComponent("Cover \(coverNumber).png"))
        }
        let cachedByteCount = await thumbnails.cachedByteCount
        let cachedThumbnailCount = await thumbnails.cachedThumbnailCount
        XCTAssertEqual(cachedThumbnailCount, 3)
        XCTAssertEqual(cachedByteCount, 3 * thumbnailBytes)
    }
}

extension UiBasesDocumentModelTests {
    fileprivate nonisolated static let pixelByteCount = 4

    /// An image holding exactly `byteCount` bytes of pixels, in rows of 4,096 bytes when
    /// they divide evenly and otherwise in one row.
    fileprivate nonisolated static func thumbnailImage(byteCount: Int) throws -> CGImage {
        let rowByteCount = byteCount.isMultiple(of: 4_096) ? 4_096 : byteCount
        let context = try XCTUnwrap(CGContext(data: nil, width: rowByteCount / pixelByteCount, height: byteCount / rowByteCount, bitsPerComponent: 8,
                                              bytesPerRow: rowByteCount, space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        return try XCTUnwrap(context.makeImage())
    }
}

private actor DecodeCounter {
    private(set) var count = 0
    func increment() { count += 1 }
}

import XCTest
import SwiftUI
import GraphiteCore
import GraphiteIndex
@testable import GraphiteUI

/// Resizing a table column of a base: the width under the finger, and the write into the
/// view's `columnSize`.
@MainActor
final class UiBasesColumnResizeTests: XCTestCase {
    private var vault: URL!
    private var index: VaultIndex!
    private var store: VaultStore!

    override func setUp() async throws {
        vault = FileManager.default.temporaryDirectory.appendingPathComponent("UiBasesColumnResizeVault-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        index = try VaultIndex(databaseURL: vault.appendingPathExtension("cache").appendingPathComponent("index.sqlite"))
        store = VaultStore(root: vault)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: vault)
        try? FileManager.default.removeItem(at: vault.appendingPathExtension("cache"))
    }

    private func write(_ text: String, to relativePath: String) throws {
        let location = vault.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: location.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: location)
    }

    private func text(at relativePath: String) throws -> String {
        try String(contentsOf: vault.appendingPathComponent(relativePath), encoding: .utf8)
    }

    private let booksBase = """
        # Reading list
        filters: file.inFolder("Books")
        views:
          - type: table
            name: Books
            order:
              - file.name
              - note.author
              - note.year
            columnSize:
              note.author: 120   # narrow
            rowHeight: extra
          - type: table
            name: Plain

        """

    private func loadedModel(source: BaseSource? = nil) async throws -> BaseDocumentModel {
        try write("---\nauthor: Frank Herbert\nyear: 1965\n---\n", to: "Books/Dune.md")
        try write(booksBase, to: "Books.base")
        _ = try await index.reconcile(root: vault)
        let basePath = try VaultPath("Books.base")
        let model = BaseDocumentModel(source: source ?? .file(basePath), contextPath: basePath, store: store, index: index)
        await model.reload()
        XCTAssertNil(model.loadErrorMessage)
        return model
    }

    private func shownWidths(_ model: BaseDocumentModel) throws -> [CGFloat] {
        BaseTableView.columnWidths(for: try XCTUnwrap(model.result))
    }

    // MARK: Widths shown

    func testColumnsTakeTheWidthsOfTheViewAndDefaultsOtherwise() async throws {
        let model = try await loadedModel()
        XCTAssertEqual(try shownWidths(model), [240, 120, 170], "The file name column is wider by default; the author column is 120 in the file.")
        await model.selectView(1)
        XCTAssertEqual(try shownWidths(model), [240])
    }

    func testObsidiansExtraTallRowHeightIsRead() {
        XCTAssertEqual(BaseTableView.rowLayout(forRowHeight: "extra").lineLimit, 5, "Obsidian writes extra tall rows as `extra`.")
        XCTAssertEqual(BaseTableView.rowLayout(forRowHeight: "tall").lineLimit, 3)
        XCTAssertEqual(BaseTableView.rowLayout(forRowHeight: "medium").lineLimit, 2)
        XCTAssertEqual(BaseTableView.rowLayout(forRowHeight: nil).lineLimit, 1)
        XCTAssertEqual(BaseTableView.rowLayout(forRowHeight: "").lineLimit, 1)
    }

    // MARK: The width under the finger

    func testDraggingTheEdgeWidensAndNarrowsTheColumnInWholePoints() {
        let author = BasePropertyIdentifier.note("author")
        XCTAssertEqual(BaseColumnResize(property: author, startWidth: 120, translation: 63.4, layoutDirection: .leftToRight).width, 183)
        XCTAssertEqual(BaseColumnResize(property: author, startWidth: 120, translation: -30.6, layoutDirection: .leftToRight).width, 89)
        XCTAssertEqual(BaseColumnResize(property: author, startWidth: 120, translation: 0, layoutDirection: .leftToRight).width, 120)
    }

    func testInARightToLeftLayoutTheTrailingEdgeMovesTheOtherWay() {
        let author = BasePropertyIdentifier.note("author")
        XCTAssertEqual(BaseColumnResize(property: author, startWidth: 120, translation: -60, layoutDirection: .rightToLeft).width, 180)
        XCTAssertEqual(BaseColumnResize(property: author, startWidth: 120, translation: 60, layoutDirection: .rightToLeft).width, 60)
    }

    func testADraggedWidthStaysWithinObsidiansColumnLimits() {
        let author = BasePropertyIdentifier.note("author")
        XCTAssertEqual(BaseColumnResize(property: author, startWidth: 120, translation: -500, layoutDirection: .leftToRight).width, 40)
        XCTAssertEqual(BaseColumnResize(property: author, startWidth: 120, translation: 50_000, layoutDirection: .leftToRight).width, 2_000)
        XCTAssertEqual(BaseColumnResize(property: author, startWidth: 120, translation: .nan, layoutDirection: .leftToRight).width, 40)
        XCTAssertEqual(BaseColumnResize(property: author, startWidth: 120, translation: .infinity, layoutDirection: .leftToRight).width, 40)
    }

    // MARK: Saving the width

    func testAResizedColumnIsSavedIntoTheViewAndShown() async throws {
        let model = try await loadedModel()
        let isSaved = await model.setColumnWidth(183, of: .note("author"))
        XCTAssertTrue(isSaved)
        XCTAssertNil(model.actionErrorMessage)
        XCTAssertEqual(try text(at: "Books.base"), booksBase.replacingOccurrences(of: "      note.author: 120   # narrow\n", with: "      note.author: 183\n"),
                       "Only the resized column's line changes.")
        XCTAssertEqual(try shownWidths(model), [240, 183, 170])
        XCTAssertEqual(model.selectedView?.name, "Books")
    }

    func testAColumnResizedForTheFirstTimeGainsAWidth() async throws {
        let model = try await loadedModel()
        let isSaved = await model.setColumnWidth(300, of: .file("name"))
        XCTAssertTrue(isSaved)
        XCTAssertEqual(try text(at: "Books.base"), booksBase.replacingOccurrences(of: "      note.author: 120   # narrow\n", with: "      note.author: 120   # narrow\n      file.name: 300\n"))
        XCTAssertEqual(try shownWidths(model), [300, 120, 170])

        await model.selectView(1)
        let isSavedInPlainView = await model.setColumnWidth(200, of: .file("name"))
        XCTAssertTrue(isSavedInPlainView)
        XCTAssertTrue(try text(at: "Books.base").hasSuffix("  - type: table\n    name: Plain\n    columnSize:\n      file.name: 200\n"))
        XCTAssertEqual(try shownWidths(model), [200])
    }

    func testResettingAColumnRemovesItsWidth() async throws {
        let model = try await loadedModel()
        let isSaved = await model.setColumnWidth(nil, of: .note("author"))
        XCTAssertTrue(isSaved)
        XCTAssertEqual(try text(at: "Books.base"), booksBase.replacingOccurrences(of: "    columnSize:\n      note.author: 120   # narrow\n", with: ""))
        XCTAssertEqual(try shownWidths(model), [240, 170, 170])
    }

    func testAResizeIsRefusedWhenTheBaseChangedInAnotherApp() async throws {
        let model = try await loadedModel()
        let changedElsewhere = booksBase.replacingOccurrences(of: "name: Plain", with: "name: Renamed elsewhere")
        try write(changedElsewhere, to: "Books.base")

        let isSaved = await model.setColumnWidth(183, of: .note("author"))
        XCTAssertFalse(isSaved)
        XCTAssertNotNil(model.actionErrorMessage)
        XCTAssertEqual(try text(at: "Books.base"), changedElsewhere, "The other app's change is never overwritten.")
    }

    func testABaseWrittenInANoteIsNotResizedFromItsTable() async throws {
        let model = try await loadedModel(source: .inline(booksBase))
        XCTAssertFalse(model.canEditDefinition, "The note's editor owns the code block, so its table shows no resize handles.")
        let isSaved = await model.setColumnWidth(183, of: .note("author"))
        XCTAssertFalse(isSaved)
        XCTAssertEqual(try text(at: "Books.base"), booksBase)
    }
}

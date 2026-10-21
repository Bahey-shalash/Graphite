/**
 * File: UiFileTreeNativeMacTests.swift
 * ------------------------------------
 * Layer: Tests
 * Description: The Mac's file tree (AppKit outline view): many root files at once, folding, dragging and dropping,
 *              and each row's menu, Reveal in Finder included.
 *
 * Authors: Bahey Shalash, Félix Chevalier
 * Version: 0.5
 * Date: 21/10/2026
 */

#if os(macOS)
import AppKit
import SwiftUI
import XCTest
import GraphiteApple
import GraphiteCore
import GraphiteIndex
@testable import GraphiteUI
import GraphiteTestSupport

/// The Mac's file tree is AppKit's outline view (`MacFileTree`): a vault's root lists at once
/// however many files it holds, folders fold as in Obsidian, rows drag into notes and folders,
/// and each row has the sidebar's menu.
@MainActor
final class UiFileTreeNativeMacTests: XCTestCase {
    private var windows: [NSWindow] = []

    override func tearDown() async throws {
        for window in windows { window.close() }
        windows = []
        try await super.tearDown()
    }

    /// The outline view asks for the rows it shows, not for every row: SwiftUI's list made a
    /// view for each of the 24,712 files at the owner's vault's root, and the main thread
    /// stayed busy 7 to 10 s after the vault opened.
    func testTwentyFiveThousandRootFilesShowAtOnce() async throws {
        let workspace = try makeWorkspace(files: [])
        workspace.rootEntries = try (0..<25_000).map { fileIndex in
            VaultEntry(path: try VaultPath(String(format: "Note %05d.md", fileIndex)), isDirectory: false, size: 10, modified: .now)
        }
        let outlineView = try await showSidebar(of: workspace)
        try await waitUntil { outlineView.numberOfRows == 25_000 }
        outlineView.layoutSubtreeIfNeeded()
        XCTAssertTrue(outlineView is FileTreeOutlineView, "The Mac's tree is the native outline view")
        // Counted, not timed: the outline view makes a view for each row in sight, a few dozen of a 700-point sidebar, and none
        // for the other thousands.
        let rowViewCount = outlineView.subviews.filter { subview in subview is NSTableRowView }.count
        XCTAssertGreaterThan(rowViewCount, 0)
        XCTAssertLessThan(rowViewCount, 100, "\(rowViewCount) row views for 25,000 files: only the rows shown have one.")
    }

    /// A note's name reads first; its extension follows, muted, where Settings shows extensions.
    func testAFilesExtensionIsMutedAfterItsName() async throws {
        let workspace = try makeWorkspace(files: ["Lecture.md"])
        await workspace.refreshDirectory()
        workspace.preferences.showsFileExtensions = true
        let outlineView = try await showSidebar(of: workspace)
        try await waitUntil { outlineView.numberOfRows == 1 }
        let cell = try XCTUnwrap(outlineView.view(atColumn: 0, row: 0, makeIfNecessary: true) as? FileTreeCellView)
        let title = cell.drawnTitle
        XCTAssertEqual(title.string, "Lecture.md")
        XCTAssertEqual(title.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor, .labelColor)
        XCTAssertEqual(title.attribute(.foregroundColor, at: 8, effectiveRange: nil) as? NSColor, .secondaryLabelColor)
    }

    /// Folding and unfolding a folder in the tree is remembered for the vault, as when the
    /// sidebar's list did it.
    func testAFolderFoldedInTheTreeIsRemembered() async throws {
        let workspace = try makeWorkspace(files: ["Course/Week 1.md", "Course/Week 2.md", "Root.md"])
        await workspace.refreshDirectory()
        let outlineView = try await showSidebar(of: workspace)
        try await waitUntil { outlineView.numberOfRows == 2 }
        let course = try XCTUnwrap(outlineView.item(atRow: 0))
        outlineView.expandItem(course)
        XCTAssertTrue(workspace.expandedFolders.contains(try VaultPath("Course")))
        try await waitUntil { outlineView.numberOfRows == 4 }
        outlineView.collapseItem(course)
        XCTAssertFalse(workspace.expandedFolders.contains(try VaultPath("Course")))
        XCTAssertEqual(outlineView.numberOfRows, 2)
    }

    /// A row dragged into a note becomes a link to it: the editor reads the same item.
    func testARowDraggedFromTheTreeIsAVaultItemForTheEditor() async throws {
        let workspace = try makeWorkspace(files: ["Lecture.md"])
        await workspace.refreshDirectory()
        let outlineView = try await showSidebar(of: workspace)
        try await waitUntil { outlineView.numberOfRows == 1 }
        let controller = try XCTUnwrap((outlineView as? FileTreeOutlineView)?.controller)
        let writer = try XCTUnwrap(controller.outlineView(outlineView, pasteboardWriterForItem: try XCTUnwrap(outlineView.item(atRow: 0))))
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("FileTreeDrag-\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        pasteboard.writeObjects([writer])
        XCTAssertEqual(MacPastedAttachment.attachments(on: pasteboard), [.vaultItem(try VaultPath("Lecture.md"))])
    }

    /// A drop on a folder moves into it; on a file, into that file's folder; outside any row,
    /// to the vault's root. An item never moves into its own folder, or into itself.
    func testDropsMoveIntoTheFolderTheyLandIn() async throws {
        let workspace = try makeWorkspace(files: ["Course/Week 1.md", "Inbox.md", "Archive/Old.md"])
        // Moving updates links through the index, which must have read the vault.
        let vault = try XCTUnwrap(workspace.folderAccess?.root)
        let index = try VaultIndex(databaseURL: vault.deletingLastPathComponent().appendingPathComponent("NativeTreeIndex-\(UUID().uuidString).sqlite"))
        _ = try await index.reconcile(root: vault)
        workspace.index = index
        workspace.hasCompletedIndexScan = true
        await workspace.refreshDirectory()
        workspace.expandedFolders.insert(try VaultPath("Course"))
        let outlineView = try await showSidebar(of: workspace)
        // Archive, Course, Week 1.md, Inbox.md.
        try await waitUntil { outlineView.numberOfRows == 4 }
        let controller = try XCTUnwrap((outlineView as? FileTreeOutlineView)?.controller)
        let archive = try XCTUnwrap(outlineView.item(atRow: 0))
        let weekOne = try XCTUnwrap(outlineView.item(atRow: 2))

        // Inbox.md dropped on Week 1.md lands in Course.
        let inboxDrag = try FakeDraggingInfo(paths: ["Inbox.md"])
        XCTAssertEqual(controller.outlineView(outlineView, validateDrop: inboxDrag, proposedItem: weekOne, proposedChildIndex: NSOutlineViewDropOnItemIndex), .move)
        XCTAssertTrue(controller.outlineView(outlineView, acceptDrop: inboxDrag, item: weekOne, childIndex: NSOutlineViewDropOnItemIndex))
        try await waitUntil { FileManager.default.fileExists(atPath: vault.appendingPathComponent("Course/Inbox.md").path) }

        // Archive is refused on itself, and Old.md in its own folder.
        XCTAssertEqual(controller.outlineView(outlineView, validateDrop: try FakeDraggingInfo(paths: ["Archive"]), proposedItem: archive, proposedChildIndex: NSOutlineViewDropOnItemIndex), [])
        XCTAssertEqual(controller.outlineView(outlineView, validateDrop: try FakeDraggingInfo(paths: ["Archive/Old.md"]), proposedItem: archive, proposedChildIndex: NSOutlineViewDropOnItemIndex), [])

        // Week 1.md dropped outside the rows goes to the root.
        let weekDrag = try FakeDraggingInfo(paths: ["Course/Week 1.md"])
        XCTAssertEqual(controller.outlineView(outlineView, validateDrop: weekDrag, proposedItem: nil, proposedChildIndex: 0), .move)
        XCTAssertTrue(controller.outlineView(outlineView, acceptDrop: weekDrag, item: nil, childIndex: 0))
        try await waitUntil { FileManager.default.fileExists(atPath: vault.appendingPathComponent("Week 1.md").path) }
    }

    /// A row's menu is the sidebar's: the iPad's rows show it as their context menu.
    func testARowsMenuIsTheSidebarsMenuForThatFile() async throws {
        let workspace = try makeWorkspace(files: ["Course/Week 1.md", "Inbox.md"])
        await workspace.refreshDirectory()
        let outlineView = try await showSidebar(of: workspace)
        try await waitUntil { outlineView.numberOfRows == 2 }
        let controller = try XCTUnwrap((outlineView as? FileTreeOutlineView)?.controller)
        let fileMenu = try XCTUnwrap(controller.menu(forRow: 1))
        fileMenu.update()
        let fileTitles = fileMenu.items.map(\.title)
        for title in ["Open in New Tab", "Rename…", "Move to…", "Copy Vault Path", "Reveal in Finder", "Delete"] {
            XCTAssertTrue(fileTitles.contains(title), "\(title) in \(fileTitles)")
        }
        XCTAssertEqual(fileMenu.items.first { item in item.title == "Reveal in Finder" }?.isEnabled, true)
        let folderMenu = try XCTUnwrap(controller.menu(forRow: 0))
        folderMenu.update()
        let folderTitles = folderMenu.items.map(\.title)
        for title in ["New Note", "Reveal in Finder"] {
            XCTAssertTrue(folderTitles.contains(title), "\(title) in \(folderTitles)")
        }
    }

    // MARK: Helpers

    private func makeWorkspace(files: [String]) throws -> WorkspaceModel {
        let vault = try TemporaryVault.make(prefix: "NativeTreeVault", for: self).root
        for file in files {
            let location = vault.appendingPathComponent(file)
            try FileManager.default.createDirectory(at: location.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("# \(file)\n".utf8).write(to: location)
        }
        let workspace = WorkspaceModel()
        workspace.folderAccess = FolderAccess(root: vault)
        workspace.store = VaultStore(root: vault)
        return workspace
    }

    private func showSidebar(of workspace: WorkspaceModel) async throws -> NSOutlineView {
        let sidebar = VaultSidebar(workspace: workspace, creation: .constant(nil), showsSettings: .constant(false), showsVaultManager: .constant(false))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 700), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: NavigationStack { sidebar })
        window.showInvisibly()
        windows.append(window)
        var outlineView: NSOutlineView?
        try await waitUntil {
            outlineView = Self.firstOutlineView(in: window.contentView)
            return outlineView != nil
        }
        return try XCTUnwrap(outlineView)
    }

    private static func firstOutlineView(in view: NSView?) -> NSOutlineView? {
        guard let view else { return nil }
        if let outlineView = view as? NSOutlineView { return outlineView }
        for subview in view.subviews {
            if let outlineView = firstOutlineView(in: subview) { return outlineView }
        }
        return nil
    }
}

/// A drag carrying vault items, as the tree's own rows write them.
@MainActor
private final class FakeDraggingInfo: NSObject, @MainActor NSDraggingInfo {
    let draggingPasteboard: NSPasteboard

    init(paths: [String]) throws {
        draggingPasteboard = NSPasteboard(name: NSPasteboard.Name("FileTreeDrop-\(UUID().uuidString)"))
        draggingPasteboard.clearContents()
        draggingPasteboard.writeObjects(try paths.map { path in
            let item = NSPasteboardItem()
            item.setData(try JSONEncoder().encode(VaultItemTransfer(path: path)), forType: FileTreeController.vaultItemType)
            return item
        })
    }

    var draggingDestinationWindow: NSWindow? { nil }
    var draggingSourceOperationMask: NSDragOperation { .move }
    var draggingLocation: NSPoint { .zero }
    var draggedImageLocation: NSPoint { .zero }
    var draggedImage: NSImage? { nil }
    var draggingSource: Any? { nil }
    var draggingSequenceNumber: Int { 1 }
    var draggingFormation: NSDraggingFormation = .default
    var animatesToDestination = false
    var numberOfValidItemsForDrop = 1
    var springLoadingHighlight: NSSpringLoadingHighlight { .none }
    func slideDraggedImage(to screenPoint: NSPoint) {}
    func enumerateDraggingItems(options enumOpts: NSDraggingItemEnumerationOptions = [], for view: NSView?, classes classArray: [AnyClass],
                                searchOptions: [NSPasteboard.ReadingOptionKey: Any] = [:], using block: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void) {}
    func resetSpringLoading() {}
}
#endif

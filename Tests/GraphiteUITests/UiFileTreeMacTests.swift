#if os(macOS)
import AppKit
import SwiftUI
import XCTest
import GraphiteApple
import GraphiteCore
@testable import GraphiteUI
import GraphiteTestSupport

/// The sidebar's file tree in the Mac's outline view: a vault with thousands of files at its
/// root shows, and an expanded folder's contents follow it as rows of their own.
@MainActor
final class UiFileTreeMacTests: XCTestCase {
    private static let rootFileCount = 2_000
    private var vaultDirectories: [URL] = []
    private var windows: [NSWindow] = []

    override func tearDown() async throws {
        for window in windows { window.close() }
        windows = []
        for vaultDirectory in vaultDirectories { try? FileManager.default.removeItem(at: vaultDirectory) }
        vaultDirectories = []
        try await super.tearDown()
    }

    func testThousandsOfRootFilesShowAndExpandedFoldersFollowTheirFolder() async throws {
        let workspace = try await makeWorkspace()
        // "Course" and the root files.
        let rootRowCount = Self.rootFileCount + 1

        // Before each row was a single view, the outline view made every earlier row to find
        // each one, and these steps took about 20 s with 2,000 files; since, about 1 s (2026-10-15).
        let started = Date.now
        let outlineView = try await showSidebar(of: workspace)
        try await waitUntil { outlineView.numberOfRows == rootRowCount }

        // Course: its folder Notes and Week 1.md follow it.
        workspace.expandedFolders.insert(try VaultPath("Course"))
        try await waitUntil { outlineView.numberOfRows == rootRowCount + 2 }

        // Course/Notes: Detail.md follows Notes, inside Course.
        workspace.expandedFolders.insert(try VaultPath("Course/Notes"))
        try await waitUntil { outlineView.numberOfRows == rootRowCount + 3 }

        // Folding Course hides everything in it, Notes' contents too, though Notes stays expanded.
        workspace.expandedFolders.remove(try VaultPath("Course"))
        try await waitUntil { outlineView.numberOfRows == rootRowCount }

        // Opening Course again shows both levels at once, from the contents already listed.
        workspace.expandedFolders.insert(try VaultPath("Course"))
        try await waitUntil { outlineView.numberOfRows == rootRowCount + 3 }

        let elapsedSeconds = Date.now.timeIntervalSince(started)
        XCTAssertLessThan(elapsedSeconds, 10, "Showing \(rootRowCount) rows and folding took \(elapsedSeconds) s")
    }

    /// A row is selected through its tag, the same tag a click sets the selection from. Set
    /// inside the row's `.equatable()` wrapper, the tag was lost: an open file's row showed
    /// unselected, and clicking a file opened nothing (2026-10-16). The test process's window
    /// never becomes the key window, so a click itself cannot be synthesized here.
    func testTheOpenFilesRowIsSelected() async throws {
        let workspace = try await makeWorkspace()
        let outlineView = try await showSidebar(of: workspace)
        try await waitUntil { outlineView.numberOfRows == Self.rootFileCount + 1 }

        // "Course" is row 0, so the first root file is row 1.
        await workspace.open(try VaultPath("Note 0000.md"))
        try await waitUntil { outlineView.selectedRow == 1 }
    }

    // MARK: Helpers

    private func makeWorkspace() async throws -> WorkspaceModel {
        let vault = FileManager.default.temporaryDirectory.appendingPathComponent("FileTreeVault-\(UUID().uuidString)", isDirectory: true)
        vaultDirectories.append(vault)
        let notesDirectory = vault.appendingPathComponent("Course/Notes", isDirectory: true)
        try FileManager.default.createDirectory(at: notesDirectory, withIntermediateDirectories: true)
        try Data("# Week 1\n".utf8).write(to: vault.appendingPathComponent("Course/Week 1.md"))
        try Data("# Detail\n".utf8).write(to: notesDirectory.appendingPathComponent("Detail.md"))
        for fileIndex in 0..<Self.rootFileCount {
            try Data("# Note \(fileIndex)\n".utf8).write(to: vault.appendingPathComponent(String(format: "Note %04d.md", fileIndex)))
        }
        let workspace = WorkspaceModel()
        workspace.folderAccess = FolderAccess(root: vault)
        workspace.store = VaultStore(root: vault)
        await workspace.refreshDirectory()
        XCTAssertEqual(workspace.rootEntries.count, Self.rootFileCount + 1)
        return workspace
    }

    private func showSidebar(of workspace: WorkspaceModel) async throws -> NSOutlineView {
        let sidebar = VaultSidebar(workspace: workspace, creation: .constant(nil), showsSettings: .constant(false), showsVaultManager: .constant(false))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 700), styleMask: [.titled], backing: .buffered, defer: false)
        // Swift owns the window; closing it in tearDown must not release it a second time.
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
#endif

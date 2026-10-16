#if os(macOS)
import AppKit
import GraphiteApple
import GraphiteCore
import GraphiteIndex
import SwiftUI
import XCTest
@testable import GraphiteUI

/// A closed note's editor goes away with its rendered blocks' views and its session: a
/// block's view left in the text view stayed registered with AppKit's notification center,
/// with the note's session and text, for as long as the app ran.
@MainActor
final class UiEditorReleaseTests: XCTestCase {
    func testAClosedNotesEditorAndItsBlockViewsAreReleased() async throws {
        let vault = FileManager.default.temporaryDirectory.appendingPathComponent("EditorRelease-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }
        let section = "## Section\n\n> [!note] Callout\n> Text of the callout.\n\n| A | B |\n| --- | --- |\n| 1 | 2 |\n\nA paragraph of text.\n\n"
        let notePath = try VaultPath("Note.md")
        try Data(String(repeating: section, count: 30).utf8).write(to: vault.appendingPathComponent(notePath.rawValue))

        weak var releasedEditor: MarkdownMacTextView?
        weak var releasedBlockView: NSView?
        weak var releasedSession: MarkdownSession?
        do {
            let workspace = WorkspaceModel()
            workspace.folderAccess = FolderAccess(root: vault)
            workspace.store = VaultStore(root: vault)
            await workspace.open(notePath, placement: .currentTab)
            let tab = try XCTUnwrap(workspace.layout.tabID(showing: notePath))
            let session = try XCTUnwrap(workspace.document(for: tab).markdownSession)
            session.viewMode = .livePreview
            let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 900, height: 700), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: NavigationStack {
                WorkspacePanes(workspace: workspace, showsLinksInspector: .constant(false), create: { _ in }, showQuickSwitcher: {})
            })
            // AppKit hands views it works with to the autorelease pool, which an async test
            // drains only when it ends; each step here drains its own, as the run loop does.
            var editor: MarkdownMacTextView?
            let deadline = ContinuousClock.now + .seconds(20)
            while ContinuousClock.now < deadline, editor == nil {
                editor = autoreleasepool {
                    window.contentView?.layoutSubtreeIfNeeded()
                    window.displayIfNeeded()
                    guard let found = Self.descendants(of: window.contentView ?? NSView()).first, found.string == session.text,
                          found.subviews.contains(where: { subview in subview is NSHostingView<AnyView> }) else { return nil }
                    return found
                }
                if editor == nil { try await Task.sleep(for: .milliseconds(5)) }
            }
            let shownEditor = try XCTUnwrap(editor)
            editor = nil
            // Scrolled to the end and back, so views are kept for scrolling back as well.
            for offset in [CGFloat(1_000_000), 0] {
                autoreleasepool {
                    let visibleHeight = shownEditor.enclosingScrollView?.contentView.bounds.height ?? 0
                    shownEditor.scroll(NSPoint(x: 0, y: min(offset, max(0, shownEditor.frame.height - visibleHeight))))
                    window.contentView?.layoutSubtreeIfNeeded()
                    window.displayIfNeeded()
                }
                try await Task.sleep(for: .milliseconds(50))
            }
            autoreleasepool {
                releasedEditor = shownEditor
                releasedBlockView = shownEditor.subviews.first { subview in subview is NSHostingView<AnyView> }
            }
            releasedSession = session
            XCTAssertNotNil(releasedBlockView)

            // Closed as the app closes a tab: the window stays, its pane no longer shows the note.
            try await workspace.document(for: tab).saveAllChanges()
            await workspace.closeTab(tab)
            for _ in 0..<5 {
                autoreleasepool {
                    window.contentView?.layoutSubtreeIfNeeded()
                    window.displayIfNeeded()
                }
                try await Task.sleep(for: .milliseconds(20))
            }
            autoreleasepool {
                window.contentView = nil
                window.close()
            }
        }
        // SwiftUI lets go of a removed view's representable on a later turn.
        let deadline = ContinuousClock.now + .seconds(5)
        while ContinuousClock.now < deadline, releasedEditor != nil || releasedBlockView != nil || releasedSession != nil {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertNil(releasedEditor, "The closed note's editor is kept alive")
        XCTAssertNil(releasedBlockView, "A rendered block's view outlives its editor")
        XCTAssertNil(releasedSession, "The closed note's session is kept alive")
    }

    private static func descendants(of parent: NSView) -> [MarkdownMacTextView] {
        parent.subviews.flatMap { child in ((child as? MarkdownMacTextView).map { [$0] } ?? []) + descendants(of: child) }
    }
}
#endif

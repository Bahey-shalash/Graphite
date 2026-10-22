#if os(macOS)
import XCTest
import SwiftUI
import AppKit
import GraphiteCore
@testable import GraphiteUI
import GraphiteTestSupport

/// Notes open in the tabs of a workspace on a device of its own, for the tests of the tab
/// overview, stacked tabs and switching tabs, and what a window shows of them.
@MainActor
struct TabTestBed {
    let workspace: WorkspaceModel
    /// The notes' tabs, in the order the notes were named.
    let tabs: [UUID]

    /// Each note is `# Title` and thirty lines, under `frontmatter` when it is given; the first
    /// opens in the current tab and the others in new tabs.
    static func make(notes names: [String], frontmatter: String? = nil, for testCase: XCTestCase) async throws -> TabTestBed {
        let device = try IsolatedWorkspaceDevice.make(for: testCase)
        var files: [String: String] = [:]
        for name in names {
            let title = (name as NSString).lastPathComponent
            let body = (1...30).map { line in "Line \(line) of the note about \(title.lowercased())." }.joined(separator: "\n\n")
            files["\(name).md"] = (frontmatter.map { "---\n\($0)\n---\n" } ?? "") + "# \(title)\n\n\(body)\n"
        }
        let vault = try TemporaryVault.make(prefix: "TabTestBed", files: files, for: testCase).root
        let workspace = device.makeWorkspace()
        try await workspace.openFolderAsVault(vault)
        var tabs: [UUID] = []
        for (position, name) in names.enumerated() {
            let path = try VaultPath("\(name).md")
            await workspace.open(path, placement: position == 0 ? .currentTab : .newTab)
            tabs.append(try XCTUnwrap(workspace.layout.tabID(showing: path)))
        }
        return TabTestBed(workspace: workspace, tabs: tabs)
    }

    /// A window of `width` by `height` points showing `content`, light whatever the system's
    /// appearance. The test closes it.
    static func window(width: CGFloat, height: CGFloat = 800, showing content: some View) -> NSWindow {
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: width, height: height), styleMask: [.titled, .resizable],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = NSHostingView(rootView: content)
        return window
    }

    static func close(_ windows: [NSWindow]) {
        for window in windows {
            window.contentView = nil
            window.close()
        }
    }

    static func layOut(_ window: NSWindow) {
        window.contentView?.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
    }

    /// The notes whose editor is in the window, by their heading, in their panes' order.
    static func shownNoteTitles(in window: NSWindow) -> [String] {
        layOut(window)
        return textViews(in: window.contentView).filter { textView in textView.window != nil && textView.visibleRect.width > 0 }
            .sorted { leftView, rightView in leftView.convert(leftView.bounds, to: nil).minX < rightView.convert(rightView.bounds, to: nil).minX }
            .compactMap { textView in
                textView.string.split(separator: "\n").first { line in line.hasPrefix("# ") }.map { heading in String(heading.dropFirst(2)) }
            }
    }

    static func textViews(in view: NSView?) -> [MarkdownMacTextView] {
        guard let view else { return [] }
        return ((view as? MarkdownMacTextView).map { [$0] } ?? []) + view.subviews.flatMap { subview in textViews(in: subview) }
    }
}
#endif

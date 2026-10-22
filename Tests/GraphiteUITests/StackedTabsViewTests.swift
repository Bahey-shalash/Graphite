#if os(macOS)
import XCTest
import SwiftUI
import AppKit
import GraphiteCore
@testable import GraphiteUI
import GraphiteTestSupport

/// Stacked tabs, as Obsidian's "Stack tabs": the side's tabs side by side as sliding panes,
/// each with its document while its content shows.
@MainActor
final class StackedTabsViewTests: XCTestCase {
    private var windows: [NSWindow] = []

    override func tearDown() async throws {
        TabTestBed.close(windows)
        windows.removeAll()
    }

    func testStackedTabsShowTheNotesThatFitAndSlideTheChosenOneIntoView() async throws {
        let bed = try await TabTestBed.make(notes: ["First", "Second", "Third"], for: self)
        let window = TabTestBed.window(width: 1_400, showing: NavigationStack {
            WorkspacePanes(workspace: bed.workspace, showsLinksInspector: .constant(false), create: { _ in }, showQuickSwitcher: {})
        })
        windows.append(window)
        try await waitUntil("the third note is shown") { TabTestBed.shownNoteTitles(in: window) == ["Third"] }

        bed.workspace.toggleStackedTabs()
        XCTAssertTrue(bed.workspace.layout.focusedGroup.isStacked)
        // 1,400 points hold the first pane whole and most of the second; the third waits at
        // the trailing edge as its spine.
        try await waitUntil("two panes show their notes") { TabTestBed.shownNoteTitles(in: window).count >= 2 }
        saveSnapshot(of: window, named: "stacked-tabs-third-active")
        let shownAfterStacking = TabTestBed.shownNoteTitles(in: window)
        XCTAssertTrue(shownAfterStacking.contains("Third"), "The active tab's pane slid into view: \(shownAfterStacking)")

        bed.workspace.activateTab(bed.tabs[0])
        // Once the row has slid back: the first pane whole, the third a spine at the trailing edge.
        try await waitUntil("the row slid back to the first note") {
            let shown = TabTestBed.shownNoteTitles(in: window)
            return shown.first == "First" && !shown.contains("Third")
        }
        saveSnapshot(of: window, named: "stacked-tabs-first-active")

        bed.workspace.toggleStackedTabs()
        try await waitUntil("one note is shown") { TabTestBed.shownNoteTitles(in: window) == ["First"] }
    }

    func testAStackedSideKeepsItsTabsAndTheirOrder() async throws {
        let bed = try await TabTestBed.make(notes: ["First", "Second"], for: self)
        bed.workspace.toggleStackedTabs()
        XCTAssertEqual(bed.workspace.layout.focusedGroup.tabs.map(\.id), bed.tabs)
        XCTAssertEqual(bed.workspace.layout.saved.groups.first?.isStacked, true, "The stacking is saved with the layout.")
        bed.workspace.toggleStackedTabs()
        XCTAssertNil(bed.workspace.layout.saved.groups.first?.isStacked)
    }

    /// A picture of the window for a person to look at, when `GRAPHITE_SNAPSHOT_DIRECTORY` names a folder.
    private func saveSnapshot(of window: NSWindow, named name: String) {
        guard let directory = ProcessInfo.processInfo.environment["GRAPHITE_SNAPSHOT_DIRECTORY"], let contentView = window.contentView,
              let representation = contentView.bitmapImageRepForCachingDisplay(in: contentView.bounds) else { return }
        contentView.cacheDisplay(in: contentView.bounds, to: representation)
        try? representation.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: directory).appendingPathComponent("\(name).png")) // A picture that cannot be written is only not looked at.
    }
}
#endif

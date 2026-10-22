#if os(macOS)
import XCTest
import SwiftUI
import AppKit
import GraphiteCore
@testable import GraphiteUI
import GraphiteTestSupport

/// Choosing another note's tab updates the window's toolbar in place. The pane a note shows
/// in, which declares the toolbar's items, stays for the next note; made again for every tab,
/// it made AppKit's toolbar items again too, which took most of a tab switch
/// (`PerformanceBenchmarkTests.testSwitchingBetweenOpenTabs`).
@MainActor
final class TabDocumentViewTests: XCTestCase {
    private var windows: [NSWindow] = []

    override func tearDown() async throws {
        TabTestBed.close(windows)
        windows.removeAll()
    }

    func testChoosingAnotherNotesTabKeepsTheToolbarsItemsAndShowsThatNote() async throws {
        let bed = try await TabTestBed.make(notes: ["First", "Second"], for: self)
        let window = TabTestBed.window(width: 1_100, showing: NavigationStack {
            WorkspacePanes(workspace: bed.workspace, showsLinksInspector: .constant(false), create: { _ in }, showQuickSwitcher: {})
        })
        windows.append(window)
        try await waitUntil("the second note is shown") { TabTestBed.shownNoteTitles(in: window) == ["Second"] }
        let itemsShowingSecond = toolbarItems(of: window)
        XCTAssertFalse(itemsShowingSecond.isEmpty, "The note's pane puts its buttons in the window's toolbar.")

        bed.workspace.activateTab(bed.tabs[0])
        try await waitUntil("the first note is shown") { TabTestBed.shownNoteTitles(in: window) == ["First"] }
        XCTAssertEqual(toolbarItems(of: window), itemsShowingSecond, "The toolbar's items were made again for the other note.")
    }

    private func toolbarItems(of window: NSWindow) -> [ObjectIdentifier] {
        TabTestBed.layOut(window)
        return (window.toolbar?.items ?? []).filter { item in item.view != nil || item.menuFormRepresentation != nil || !item.label.isEmpty }
            .map(ObjectIdentifier.init)
    }
}
#endif

import XCTest
import SwiftUI
@testable import GraphiteUI

final class WorkspaceFocusModeTests: XCTestCase {
    func testFocusRestoresEachPreviousPanelArrangement() {
        for originalVisibility in [NavigationSplitViewVisibility.automatic, .all, .detailOnly] {
            for originalInspector in [false, true] {
                var focusMode = WorkspaceFocusMode()
                var columnVisibility = originalVisibility
                var showsInspector = originalInspector
                focusMode.enter(columnVisibility: &columnVisibility, showsInspector: &showsInspector)
                XCTAssertTrue(focusMode.isActive)
                XCTAssertEqual(columnVisibility, .detailOnly)
                XCTAssertFalse(showsInspector)
                // A repeated request must not replace the saved layout with the hidden layout.
                focusMode.enter(columnVisibility: &columnVisibility, showsInspector: &showsInspector)
                focusMode.leave(columnVisibility: &columnVisibility, showsInspector: &showsInspector)
                XCTAssertFalse(focusMode.isActive)
                XCTAssertEqual(columnVisibility, originalVisibility)
                XCTAssertEqual(showsInspector, originalInspector)
            }
        }
    }

    /// Read/Write, Undo and Redo leave the toolbar before iPadOS would hide them in its
    /// overflow menu, which drops a segmented control altogether.
    func testDocumentControlsMoveBelowTheToolbarWhenTheDocumentsAreaIsNarrow() {
        let threshold = DocumentToolbarLayout.minimumDetailWidthForToolbarControls
        XCTAssertTrue(DocumentToolbarLayout.usesControlRow(detailWidth: 1_376, horizontalSizeClass: .compact))
        XCTAssertTrue(DocumentToolbarLayout.usesControlRow(detailWidth: 1_032, horizontalSizeClass: .regular), "iPad portrait")
        XCTAssertTrue(DocumentToolbarLayout.usesControlRow(detailWidth: threshold - 1, horizontalSizeClass: .regular))
        XCTAssertFalse(DocumentToolbarLayout.usesControlRow(detailWidth: threshold, horizontalSizeClass: .regular))
        XCTAssertFalse(DocumentToolbarLayout.usesControlRow(detailWidth: 1_376, horizontalSizeClass: .regular), "iPad landscape without the sidebar")
        XCTAssertFalse(DocumentToolbarLayout.usesControlRow(detailWidth: nil, horizontalSizeClass: .regular), "Not measured yet")
    }

    func testLeavingInactiveFocusDoesNotChangePanels() {
        var focusMode = WorkspaceFocusMode()
        var columnVisibility = NavigationSplitViewVisibility.all
        var showsInspector = true
        focusMode.leave(columnVisibility: &columnVisibility, showsInspector: &showsInspector)
        XCTAssertEqual(columnVisibility, .all)
        XCTAssertTrue(showsInspector)
    }
}

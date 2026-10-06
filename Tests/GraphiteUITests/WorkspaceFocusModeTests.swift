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

    /// Write, Undo and Redo leave a wide window's toolbar before iPadOS would hide them in
    /// its overflow menu; a compact width keeps them in its navigation bar, which holds
    /// nothing else.
    func testDocumentControlsMoveBelowTheToolbarWhenTheDocumentsAreaIsNarrow() {
        let threshold = DocumentToolbarLayout.minimumDetailWidthForToolbarControls
        XCTAssertFalse(DocumentToolbarLayout.usesControlRow(detailWidth: 1_376, horizontalSizeClass: .compact), "A compact width keeps them in the navigation bar")
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

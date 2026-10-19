import XCTest
@testable import GraphiteUI

/// The notifications the Pencil palette and the PDF pictures use inside the app, which have
/// no typed owner: observers elsewhere name them by these strings.
@MainActor
final class InAppNotificationNamesTests: XCTestCase {
    func testTheInProcessNotificationsAreNamedAsFollows() {
        XCTAssertEqual(PencilToolbox.selectionDidChange.rawValue, "GraphitePencilToolboxSelectionDidChange")
        XCTAssertEqual(PaletteInkSelection.didChange.rawValue, "GraphitePaletteInkSelectionDidChange")
        XCTAssertEqual(PDFSession.picturesDidChange.rawValue, "GraphitePDFSessionPicturesDidChange")
    }
}

import Foundation
import XCTest
@testable import NotebookImport

/// The pencil's opacity for the Apple Pencil's force (BUG-IMPORT-04): as pale as Goodnotes' export at no force, full
/// colour from an ordinary press.
final class GoodnotesPencilOpacityTests: XCTestCase {
    func testNoForceIsAsPaleAsTheExportAndAnOrdinaryPressIsFullColour() {
        XCTAssertEqual(GoodnotesPencilOpacity.opacity(forForces: [0, 0, 0]), 0.05, accuracy: 1e-12)
        XCTAssertEqual(GoodnotesPencilOpacity.opacity(forForces: [0.5]), 0.525, accuracy: 1e-12)
        XCTAssertEqual(GoodnotesPencilOpacity.opacity(forForces: [1]), 1)
        XCTAssertEqual(GoodnotesPencilOpacity.opacity(forForces: [4.17]), 1)
        XCTAssertEqual(GoodnotesPencilOpacity.opacity(forForces: [0, 1]), 0.525, accuracy: 1e-12, "the stroke's mean force")
    }

    func testStrokesWithoutUsableForcesKeepTheirColour() {
        XCTAssertEqual(GoodnotesPencilOpacity.opacity(forForces: []), 1)
        XCTAssertEqual(GoodnotesPencilOpacity.opacity(forForces: [.nan, -1]), 1)
    }
}

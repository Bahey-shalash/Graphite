import XCTest
@testable import GraphiteUI

final class CreatableItemTests: XCTestCase {
    func testPencilFirstOffersTheNotebookFirst() {
        let offered = CreatableItem.offered(firstKind: .notebook, isEnabled: { _ in true })
        XCTAssertEqual(offered.large, [.document(.notebook), .document(.note)])
    }

    func testKeyboardFirstOffersTheNoteFirst() {
        let offered = CreatableItem.offered(firstKind: .note, isEnabled: { _ in true })
        XCTAssertEqual(offered.large, [.document(.note), .document(.notebook)])
    }

    func testItemsOfTurnedOffPluginsAreLeftOut() {
        let offered = CreatableItem.offered(firstKind: .notebook, isEnabled: { plugin in plugin == .canvas })
        XCTAssertEqual(offered.others, [.document(.canvas), .importFiles, .folder])
    }

    func testNotebookAndNoteAreAlwaysOffered() {
        let offered = CreatableItem.offered(firstKind: .notebook, isEnabled: { _ in false })
        XCTAssertEqual(Set(offered.large), [.document(.notebook), .document(.note)])
        XCTAssertEqual(offered.others, [.importFiles, .folder])
    }
}

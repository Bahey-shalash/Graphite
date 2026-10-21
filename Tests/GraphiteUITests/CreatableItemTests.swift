import XCTest
@testable import GraphiteUI

final class CreatableItemTests: XCTestCase {
    func testPencilFirstOffersTheNotebookFirst() {
        let offered = CreatableItem.offered(firstKind: .notebook, isEnabled: { _ in true }, canScanDocuments: false)
        XCTAssertEqual(offered.large, [.document(.notebook), .document(.note)])
    }

    func testKeyboardFirstOffersTheNoteFirst() {
        let offered = CreatableItem.offered(firstKind: .note, isEnabled: { _ in true }, canScanDocuments: false)
        XCTAssertEqual(offered.large, [.document(.note), .document(.notebook)])
    }

    func testItemsOfTurnedOffPluginsAreLeftOut() {
        let offered = CreatableItem.offered(firstKind: .notebook, isEnabled: { plugin in plugin == .canvas }, canScanDocuments: false)
        XCTAssertEqual(offered.others, [.document(.canvas), .importFiles, .folder])
    }

    func testNotebookAndNoteAreAlwaysOffered() {
        let offered = CreatableItem.offered(firstKind: .notebook, isEnabled: { _ in false }, canScanDocuments: false)
        XCTAssertEqual(Set(offered.large), [.document(.notebook), .document(.note)])
        XCTAssertEqual(offered.others, [.importFiles, .folder])
    }

    func testScanDocumentsIsOfferedOnlyWhereTheDeviceCanScan() {
        let unsupported = CreatableItem.offered(firstKind: .notebook, isEnabled: { _ in true }, canScanDocuments: false)
        XCTAssertFalse(unsupported.others.contains(.scanDocuments))
        let supported = CreatableItem.offered(firstKind: .notebook, isEnabled: { _ in true }, canScanDocuments: true)
        XCTAssertEqual(supported.others, [.document(.canvas), .document(.base), .dailyNote, .scanDocuments, .importFiles, .folder])
    }

    func testScanDocumentsNeedsNoPluginSoItIsOfferedEvenWhenEveryPluginIsOff() {
        let offered = CreatableItem.offered(firstKind: .notebook, isEnabled: { _ in false }, canScanDocuments: true)
        XCTAssertEqual(offered.others, [.scanDocuments, .importFiles, .folder])
    }
}

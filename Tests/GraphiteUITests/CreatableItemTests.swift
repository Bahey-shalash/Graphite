import XCTest
@testable import GraphiteUI

final class CreatableItemTests: XCTestCase {
    func testPencilFirstOffersTheNotebookFirst() {
        let offered = CreatableItem.offered(firstKind: .notebook, isEnabled: { _ in true }, canScanDocuments: false, canTakePhoto: false)
        XCTAssertEqual(offered.large, [.document(.notebook), .document(.note)])
    }

    func testKeyboardFirstOffersTheNoteFirst() {
        let offered = CreatableItem.offered(firstKind: .note, isEnabled: { _ in true }, canScanDocuments: false, canTakePhoto: false)
        XCTAssertEqual(offered.large, [.document(.note), .document(.notebook)])
    }

    func testItemsOfTurnedOffPluginsAreLeftOut() {
        let offered = CreatableItem.offered(firstKind: .notebook, isEnabled: { plugin in plugin == .canvas }, canScanDocuments: false, canTakePhoto: false)
        XCTAssertEqual(offered.others, [.document(.canvas), .pictureFromPhotos, .importFiles, .folder])
    }

    func testNotebookAndNoteAreAlwaysOffered() {
        let offered = CreatableItem.offered(firstKind: .notebook, isEnabled: { _ in false }, canScanDocuments: false, canTakePhoto: false)
        XCTAssertEqual(Set(offered.large), [.document(.notebook), .document(.note)])
        XCTAssertEqual(offered.others, [.pictureFromPhotos, .importFiles, .folder])
    }

    func testScanDocumentsIsOfferedOnlyWhereTheDeviceCanScan() {
        let unsupported = CreatableItem.offered(firstKind: .notebook, isEnabled: { _ in true }, canScanDocuments: false, canTakePhoto: false)
        XCTAssertFalse(unsupported.others.contains(.scanDocuments))
        let supported = CreatableItem.offered(firstKind: .notebook, isEnabled: { _ in true }, canScanDocuments: true, canTakePhoto: false)
        XCTAssertEqual(supported.others, [.document(.canvas), .document(.base), .dailyNote, .scanDocuments, .pictureFromPhotos, .importFiles, .folder])
    }

    func testScanDocumentsNeedsNoPluginSoItIsOfferedEvenWhenEveryPluginIsOff() {
        let offered = CreatableItem.offered(firstKind: .notebook, isEnabled: { _ in false }, canScanDocuments: true, canTakePhoto: false)
        XCTAssertEqual(offered.others, [.scanDocuments, .pictureFromPhotos, .importFiles, .folder])
    }

    func testTakePhotoIsOfferedOnlyWhereTheDeviceHasACamera() {
        let withoutCamera = CreatableItem.offered(firstKind: .notebook, isEnabled: { _ in true }, canScanDocuments: false, canTakePhoto: false)
        XCTAssertFalse(withoutCamera.others.contains(.takePhoto))
        let withCamera = CreatableItem.offered(firstKind: .notebook, isEnabled: { _ in true }, canScanDocuments: false, canTakePhoto: true)
        XCTAssertEqual(withCamera.others, [.document(.canvas), .document(.base), .dailyNote, .pictureFromPhotos, .takePhoto, .importFiles, .folder])
    }

    func testImageFromPhotosNeedsNoPluginAndNoCamera() {
        let offered = CreatableItem.offered(firstKind: .notebook, isEnabled: { _ in false }, canScanDocuments: false, canTakePhoto: false)
        XCTAssertTrue(offered.others.contains(.pictureFromPhotos))
    }
}

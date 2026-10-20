import XCTest
import GraphiteCore
@testable import GraphiteUI
import GraphiteTestSupport

/// What the File recovery sheet reads (BUG-SHELL-05): a list or a copy's text that cannot be
/// read is a failure with its reason, never "No Snapshots Yet" or a wait that never ends.
final class FileRecoveryReadingTests: XCTestCase {
    func testAVaultWhoseRecoveryStoreCouldNotBeOpenedReadsAsAFailure() async {
        let reading = await FileRecoveryReading.load(from: nil) { fileRecovery in try fileRecovery.recoverableNotes() }

        guard case .failed(let reason) = reading else { return XCTFail("Read as \(reading).") }
        XCTAssertFalse(reason.isEmpty)
    }

    func testAListThatCannotBeReadIsAFailureNotAnEmptyList() async throws {
        let folder = try TemporaryVault.make(prefix: "FileRecoveryReading", for: self).root
        // A file where the store's folder belongs: listing it throws.
        let storeLocation = folder.appendingPathComponent("File Recovery")
        try Data("not a folder".utf8).write(to: storeLocation)

        let reading = await FileRecoveryReading.load(from: FileRecoveryStore(directory: storeLocation)) { fileRecovery in try fileRecovery.recoverableNotes() }

        guard case .failed(let reason) = reading else { return XCTFail("Read as \(reading).") }
        XCTAssertFalse(reason.isEmpty)
    }

    func testASnapshotRemovedBeforeItsTextIsReadIsAFailure() async throws {
        let folder = try TemporaryVault.make(prefix: "FileRecoveryReading", for: self).root
        let store = FileRecoveryStore(directory: folder.appendingPathComponent("File Recovery", isDirectory: true))
        let path = try VaultPath("Note.md")
        try store.takeSnapshot(of: "Text worth keeping", for: path, minimumInterval: 0)
        let snapshot = try XCTUnwrap(try store.snapshots(for: path).first)
        // Pruning removed it while its preview was opening.
        try FileManager.default.removeItem(at: snapshot.location)

        let reading = await FileRecoveryReading.load(from: store) { fileRecovery in try fileRecovery.text(of: snapshot) }

        guard case .failed = reading else { return XCTFail("Read as \(reading).") }
    }

    func testAReadableSnapshotIsReadWithItsText() async throws {
        let folder = try TemporaryVault.make(prefix: "FileRecoveryReading", for: self).root
        let store = FileRecoveryStore(directory: folder.appendingPathComponent("File Recovery", isDirectory: true))
        let path = try VaultPath("Note.md")
        try store.takeSnapshot(of: "Text worth keeping", for: path, minimumInterval: 0)
        let snapshot = try XCTUnwrap(try store.snapshots(for: path).first)

        let reading = await FileRecoveryReading.load(from: store) { fileRecovery in try fileRecovery.text(of: snapshot) }

        guard case .read(let text) = reading else { return XCTFail("Read as \(reading).") }
        XCTAssertEqual(text, "Text worth keeping")
    }
}

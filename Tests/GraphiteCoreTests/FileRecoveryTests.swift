import XCTest
@testable import GraphiteCore

final class FileRecoveryTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("FileRecovery-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testTakesSnapshotsAtMostOncePerIntervalAndSkipsRepeats() throws {
        let store = FileRecoveryStore(directory: directory)
        let path = try VaultPath("Course/Lecture.md")
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertTrue(try store.takeSnapshot(of: "one", for: path, at: start, minimumInterval: 300))
        XCTAssertFalse(try store.takeSnapshot(of: "two", for: path, at: start.addingTimeInterval(60), minimumInterval: 300), "Too soon.")
        XCTAssertFalse(try store.takeSnapshot(of: "one", for: path, at: start.addingTimeInterval(600), minimumInterval: 300), "Same text.")
        XCTAssertTrue(try store.takeSnapshot(of: "three", for: path, at: start.addingTimeInterval(600), minimumInterval: 300))
        let snapshots = try store.snapshots(for: path)
        XCTAssertEqual(try snapshots.map { snapshot in try store.text(of: snapshot) }, ["three", "one"], "Newest first.")
        XCTAssertEqual(snapshots.first?.date, start.addingTimeInterval(600))
        XCTAssertEqual(try store.recoverableNotes().map(\.path), [path])
    }

    func testSkipsBlankTextAndIgnoresSnapshotsDatedInTheFuture() throws {
        let store = FileRecoveryStore(directory: directory)
        let path = try VaultPath("New note.md")
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertFalse(try store.takeSnapshot(of: "", for: path, at: start, minimumInterval: 0), "A note just created has nothing to recover.")
        XCTAssertFalse(try store.takeSnapshot(of: " \n\t", for: path, at: start, minimumInterval: 0))
        XCTAssertTrue(try store.recoverableNotes().isEmpty)

        // A copy taken while the clock was a day ahead.
        XCTAssertTrue(try store.takeSnapshot(of: "ahead", for: path, at: start.addingTimeInterval(86_400), minimumInterval: 300))
        XCTAssertTrue(try store.takeSnapshot(of: "now", for: path, at: start, minimumInterval: 300))
        XCTAssertEqual(try store.snapshots(for: path).count, 2)
    }

    func testPrunesOldSnapshotsAndFollowsMoves() throws {
        let store = FileRecoveryStore(directory: directory)
        let path = try VaultPath("Old.md")
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        try store.takeSnapshot(of: "old", for: path, at: start, minimumInterval: 0)
        try store.takeSnapshot(of: "recent", for: path, at: start.addingTimeInterval(86_400 * 6), minimumInterval: 0)
        try store.pruneSnapshots(olderThan: 86_400 * 7, now: start.addingTimeInterval(86_400 * 8))
        XCTAssertEqual(try store.snapshots(for: path).map { snapshot in try store.text(of: snapshot) }, ["recent"])

        let moved = try VaultPath("Folder/New.md")
        try store.moveSnapshots(from: path, to: moved)
        XCTAssertTrue(try store.snapshots(for: path).isEmpty)
        XCTAssertEqual(try store.snapshots(for: moved).count, 1)
        XCTAssertEqual(try store.recoverableNotes().map(\.path), [moved])

        try store.pruneSnapshots(olderThan: 60, now: start.addingTimeInterval(86_400 * 30))
        XCTAssertTrue(try store.recoverableNotes().isEmpty, "A note left without snapshots is forgotten.")
    }

    func testKeepsAtMostTheNewestSnapshots() throws {
        let store = FileRecoveryStore(directory: directory)
        let path = try VaultPath("Busy.md")
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        for index in 0..<(FileRecoveryStore.maximumSnapshotsPerNote + 5) {
            try store.takeSnapshot(of: "version \(index)", for: path, at: start.addingTimeInterval(Double(index)), minimumInterval: 0)
        }
        let snapshots = try store.snapshots(for: path)
        XCTAssertEqual(snapshots.count, FileRecoveryStore.maximumSnapshotsPerNote)
        XCTAssertEqual(try store.text(of: try XCTUnwrap(snapshots.first)), "version \(FileRecoveryStore.maximumSnapshotsPerNote + 4)")
    }

    func testSnapshotsFollowAMovedFolder() throws {
        let store = FileRecoveryStore(directory: directory)
        let first = try VaultPath("Course/Week 1.md"), second = try VaultPath("Course/Deep/Week 2.md"), other = try VaultPath("Other.md")
        for path in [first, second, other] { try store.takeSnapshot(of: path.name, for: path, minimumInterval: 0) }
        try store.followMove(from: try VaultPath("Course"), to: try VaultPath("Signals"))
        XCTAssertEqual(Set(try store.recoverableNotes().map(\.path.rawValue)), ["Signals/Week 1.md", "Signals/Deep/Week 2.md", "Other.md"])
        XCTAssertEqual(try store.snapshots(for: try VaultPath("Signals/Deep/Week 2.md")).map { snapshot in try store.text(of: snapshot) }, ["Week 2.md"])
    }
}

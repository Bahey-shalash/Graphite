import XCTest
@testable import GraphiteCore

/// A lecture whose save failed leaves its converted `.m4a` beside the recording's `.caf`. The
/// two are one recording and are offered once.
final class RecordingRecoveryFolderConvertedCopyTests: XCTestCase {
    private var folder: URL!
    private let bytesHoldingAudio = Data(repeating: 1, count: RecordingRecoveryFolder.largestFileWithoutAudio + 1_000)

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("RecoveryFolder-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: folder)
    }

    private func write(_ name: String) throws -> URL {
        let location = folder.appendingPathComponent(name)
        try bytesHoldingAudio.write(to: location)
        return location
    }

    func testAnM4AConvertedFromARecordingInTheFolderIsNotOfferedAsASecondRecording() throws {
        _ = try write("Lecture.caf")
        _ = try write("Lecture.m4a")

        let found = RecordingRecoveryFolder.recordings(in: folder)

        XCTAssertEqual(found.map(\.mediaLocation.lastPathComponent), ["Lecture.caf"])
    }

    func testTheConvertedCopyIsNotOfferedWhileItsRecordingIsTheOneFailingToSave() throws {
        let recording = try write("Lecture.caf")
        _ = try write("Lecture.m4a")

        XCTAssertTrue(RecordingRecoveryFolder.recordings(in: folder, excluding: recording).isEmpty)
    }

    func testAnM4AWithoutARecordingBesideItIsStillOffered() throws {
        _ = try write("Lecture.m4a")
        _ = try write("Other.caf")

        let found = RecordingRecoveryFolder.recordings(in: folder)

        XCTAssertEqual(Set(found.map(\.mediaLocation.lastPathComponent)), ["Lecture.m4a", "Other.caf"])
    }

    func testAnM4ANextToARecordingWithNoAudioIsStillOffered() throws {
        try Data().write(to: folder.appendingPathComponent("Lecture.caf"))
        _ = try write("Lecture.m4a")

        XCTAssertEqual(RecordingRecoveryFolder.recordings(in: folder).map(\.mediaLocation.lastPathComponent), ["Lecture.m4a"])
    }
}

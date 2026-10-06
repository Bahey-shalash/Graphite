import XCTest
import AVFoundation
import GraphiteCore
@testable import GraphiteApple

@MainActor
final class RecordingRecoveryTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("Recordings-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    /// Writes `seconds` of a tone with the recorder's own settings and returns a copy of the
    /// file as it is on disk before it is closed, as Graphite leaves it if it stops mid-recording.
    private func recordingCutOff(after seconds: Int, named name: String) throws -> URL {
        let recording = folder.appendingPathComponent("\(name)-writing.caf")
        let file = try AVAudioFile(forWriting: recording, settings: RecordingController.recordingSettings, commonFormat: .pcmFormatFloat32, interleaved: false)
        guard let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1), let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 44_100),
              let samples = buffer.floatChannelData?[0] else { throw XCTSkip("No audio buffer.") }
        buffer.frameLength = 44_100
        for frame in 0..<44_100 { samples[frame] = sin(Float(frame) * 0.06) * 0.4 }
        for _ in 0..<seconds { try file.write(from: buffer) }
        let cutOff = folder.appendingPathComponent("\(name).caf")
        try FileManager.default.copyItem(at: recording, to: cutOff)
        try FileManager.default.removeItem(at: recording)
        return cutOff
    }

    func testARecordingCutOffIsConvertedUpToWhereItStopped() async throws {
        let cutOff = try recordingCutOff(after: 4, named: "lecture")
        let converted = try await RecordingController.convertedToM4A(cutOff)
        XCTAssertEqual(converted.pathExtension, "m4a")
        let duration = try await AVURLAsset(url: converted).load(.duration).seconds
        XCTAssertEqual(duration, 4, accuracy: 0.2, "Nearly all of the audio written before the stop is kept.")
        XCTAssertTrue(FileManager.default.fileExists(atPath: cutOff.path), "The original stays until the M4A is in place.")
    }

    func testFindsUnfinishedRecordingsWithWhereTheyBelong() throws {
        let withManifest = try recordingCutOff(after: 1, named: "first")
        let manifest = RecordingRecoveryManifest(vaultIdentifier: UUID(), destinationPath: "Course/Attachments/Lecture Recording.m4a",
                                                 notePath: "Course/Lecture.md", startedAt: Date(timeIntervalSince1970: 1_700_000_000))
        try RecordingRecoveryFolder.write(manifest, for: withManifest)
        let withoutManifest = try recordingCutOff(after: 1, named: "second")
        try Data().write(to: folder.appendingPathComponent("empty.caf"))
        _ = try recordingCutOff(after: 0, named: "never started")
        try Data("notes".utf8).write(to: folder.appendingPathComponent("other.txt"))

        let found = RecordingRecoveryFolder.recordings(in: folder)
        XCTAssertEqual(found.map(\.mediaLocation.lastPathComponent), ["first.caf", "second.caf"], "Oldest first; files without audio (a header alone) and other files left out.")
        XCTAssertEqual(found.first?.manifest, manifest)
        XCTAssertEqual(found.first?.destination, try VaultPath("Course/Attachments/Lecture Recording.m4a"))
        XCTAssertNil(found.last?.manifest)
        XCTAssertEqual(RecordingRecoveryFolder.recordings(in: folder, excluding: withoutManifest).count, 1, "The recording being made is not offered.")

        if let first = found.first { try RecordingRecoveryFolder.remove(first) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: RecordingRecoveryFolder.manifestLocation(for: withManifest).path))
        XCTAssertEqual(RecordingRecoveryFolder.recordings(in: folder).count, 1)
    }

    func testTheLaterPartsOfAVideoBelongToItsFirstPart() throws {
        func write(_ name: String, byteCount: Int = 10_000) throws -> URL {
            let location = folder.appendingPathComponent(name)
            try Data(repeating: 1, count: byteCount).write(to: location)
            return location
        }
        let firstPart = try write("lecture.mp4")
        XCTAssertEqual(RecordingRecoveryFolder.partLocation(1, ofRecordingAt: firstPart), firstPart)
        let secondPart = RecordingRecoveryFolder.partLocation(2, ofRecordingAt: firstPart)
        XCTAssertEqual(secondPart.lastPathComponent, "lecture.part-2.mp4")
        try Data(repeating: 1, count: 20_000).write(to: secondPart)
        // Parts are ordered by number, not by name.
        _ = try write("lecture.part-10.mp4", byteCount: 30_000)
        let manifest = RecordingRecoveryManifest(vaultIdentifier: UUID(), destinationPath: "Course/Lecture Recording.mp4", notePath: nil,
                                                 startedAt: Date(timeIntervalSince1970: 1_700_000_000))
        try RecordingRecoveryFolder.write(manifest, for: firstPart)
        try Data("joined".utf8).write(to: RecordingRecoveryFolder.combinedMovieLocation(forRecordingAt: firstPart))

        let found = RecordingRecoveryFolder.recordings(in: folder)
        XCTAssertEqual(found.count, 1, "The parts are one recording, and a join cut short is not offered.")
        let recording = try XCTUnwrap(found.first)
        XCTAssertEqual(recording.kind, .video)
        XCTAssertEqual(recording.partLocations.map(\.lastPathComponent), ["lecture.mp4", "lecture.part-2.mp4", "lecture.part-10.mp4"])
        XCTAssertEqual(recording.byteCount, 60_000)
        XCTAssertEqual(recording.destination, try VaultPath("Course/Lecture Recording.mp4"))
        XCTAssertEqual(RecordingRecoveryFolder.laterPartLocations(ofRecordingAt: firstPart).map(\.lastPathComponent), ["lecture.part-2.mp4", "lecture.part-10.mp4"])
        XCTAssertEqual(RecordingRecoveryFolder.recordings(in: folder, excluding: firstPart), [], "The parts of the video being recorded are not offered either.")

        try RecordingRecoveryFolder.remove(recording)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path), [], "Every part, the manifest and the cut-short join go together.")
    }

    func testALaterPartWhoseFirstPartIsGoneIsStillOfferedWithWhereItBelongs() throws {
        let firstPart = folder.appendingPathComponent("lecture.mp4")
        let manifest = RecordingRecoveryManifest(vaultIdentifier: nil, destinationPath: "Lecture Recording.mp4", notePath: nil, startedAt: Date(timeIntervalSince1970: 1_700_000_000))
        try RecordingRecoveryFolder.write(manifest, for: firstPart)
        try Data(repeating: 1, count: 10_000).write(to: RecordingRecoveryFolder.partLocation(2, ofRecordingAt: firstPart))

        let found = RecordingRecoveryFolder.recordings(in: folder)
        XCTAssertEqual(found.map(\.mediaLocation.lastPathComponent), ["lecture.part-2.mp4"])
        XCTAssertEqual(found.first?.manifest, manifest)
        XCTAssertEqual(found.first?.kind, .video)
    }

    func testAnAudioRecordingIsOneFileWhateverItsName() throws {
        _ = try recordingCutOff(after: 1, named: "audio.part-2")
        let found = RecordingRecoveryFolder.recordings(in: folder)
        XCTAssertEqual(found.map(\.mediaLocation.lastPathComponent), ["audio.part-2.caf"])
        XCTAssertEqual(found.first?.kind, .audio)
        XCTAssertEqual(found.first?.laterPartLocations, [])
    }

    func testAFileWithoutAudioIsRefused() async throws {
        let broken = folder.appendingPathComponent("broken.m4a")
        try Data(repeating: 0, count: 2_000).write(to: broken)
        do {
            _ = try await RecordingController.convertedToM4A(broken)
            XCTFail("There is nothing to play.")
        } catch {}
        XCTAssertTrue(FileManager.default.fileExists(atPath: broken.path), "Nothing is deleted.")
    }
}

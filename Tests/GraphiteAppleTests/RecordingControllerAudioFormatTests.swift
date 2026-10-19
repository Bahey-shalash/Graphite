import XCTest
import AVFoundation
import GraphiteCore
@testable import GraphiteApple
import GraphiteTestSupport

/// How a lecture's audio is stored: recorded as mono IMA4 at 44.1 kHz in a CAF file in the
/// recovery folder, then converted to an AAC M4A when it is saved into the vault. A file
/// with no playable audio is refused, and nothing is deleted.
@MainActor
final class RecordingControllerAudioFormatTests: XCTestCase {
    private var folder: URL!

    override func setUp() async throws {
        folder = try TemporaryVault.make(prefix: "RecordingFormat", for: self).root
    }

    /// A CAF written with the recorder's own settings holding `seconds` of a tone (none when 0).
    private func writeRecording(seconds: Int, named name: String) throws -> URL {
        let location = folder.appendingPathComponent("\(name).caf")
        let file = try AVAudioFile(forWriting: location, settings: RecordingController.recordingSettings, commonFormat: .pcmFormatFloat32, interleaved: false)
        guard let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1), let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 44_100),
              let samples = buffer.floatChannelData?[0] else { throw XCTSkip("No audio buffer.") }
        buffer.frameLength = 44_100
        for frame in 0..<44_100 { samples[frame] = sin(Float(frame) * 0.06) * 0.4 }
        for _ in 0..<seconds { try file.write(from: buffer) }
        return location
    }

    func testTheRecorderIsAskedForMonoIMA4AtFortyFourThousandOneHundredHertz() {
        let settings = RecordingController.recordingSettings

        XCTAssertEqual(settings.count, 3)
        XCTAssertEqual((settings[AVFormatIDKey] as? NSNumber)?.uint32Value, kAudioFormatAppleIMA4)
        XCTAssertEqual((settings[AVSampleRateKey] as? NSNumber)?.intValue, 44_100)
        XCTAssertEqual((settings[AVNumberOfChannelsKey] as? NSNumber)?.intValue, 1)
    }

    func testTheRecoveryFileIsIMA4InAMonoCAFAtTheRecordersRate() throws {
        let recording = try writeRecording(seconds: 1, named: "lecture")

        let file = try AVAudioFile(forReading: recording)

        XCTAssertEqual(recording.pathExtension, "caf")
        XCTAssertEqual(file.fileFormat.settings[AVFormatIDKey] as? UInt32, kAudioFormatAppleIMA4)
        XCTAssertEqual(file.fileFormat.channelCount, 1)
        XCTAssertEqual(file.fileFormat.sampleRate, 44_100)
    }

    func testSavingAnUnfinishedRecordingPublishesAnAACM4AAndRemovesTheRecoveryCopy() async throws {
        let recording = try writeRecording(seconds: 2, named: "lecture")
        let destination = folder.appendingPathComponent("Lecture Recording.m4a")
        let controller = RecordingController()
        let recoverable = RecoverableRecording(mediaLocation: recording, manifest: nil, startedAt: .now, byteCount: 100_000)

        try await controller.recover(recoverable, to: destination)

        let published = try AVAudioFile(forReading: destination)
        XCTAssertEqual(published.fileFormat.settings[AVFormatIDKey] as? UInt32, kAudioFormatMPEG4AAC)
        let duration = try await AVURLAsset(url: destination).load(.duration).seconds
        XCTAssertEqual(duration, 2, accuracy: 0.2)
        XCTAssertFalse(FileManager.default.fileExists(atPath: recording.path), "The recovery copy goes once the M4A is in place.")
        XCTAssertFalse(FileManager.default.fileExists(atPath: recording.deletingPathExtension().appendingPathExtension("m4a").path),
                       "So does the conversion beside it.")
    }

    func testARecordingWithNoAudioIsRefusedAndKeptWithNothingPublished() async throws {
        let empty = try writeRecording(seconds: 0, named: "never-spoke")
        let destination = folder.appendingPathComponent("Lecture Recording.m4a")
        let controller = RecordingController()

        do {
            try await controller.recover(RecoverableRecording(mediaLocation: empty, manifest: nil, startedAt: .now, byteCount: 100_000), to: destination)
            XCTFail("There is no audio to publish.")
        } catch {
            // The refusal is the expected outcome.
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: empty.path), "The recording is kept.")
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: empty.deletingPathExtension().appendingPathExtension("m4a").path))
    }

    func testConvertingAFileWithoutPlayableDurationFailsWithAnInvalidFileError() async throws {
        let broken = folder.appendingPathComponent("broken.m4a")
        try Data(repeating: 0, count: 2_000).write(to: broken)

        do {
            _ = try await RecordingController.convertedToM4A(broken)
            XCTFail("There is nothing to play.")
        } catch {
            XCTAssertTrue(FileManager.default.fileExists(atPath: broken.path))
        }
    }
}

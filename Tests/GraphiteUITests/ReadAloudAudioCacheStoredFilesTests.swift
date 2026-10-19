import XCTest
import AVFoundation
import AudioToolbox
import GraphiteCore
import GraphiteVoices

/// What the rendered-passage cache leaves on disk: where its folder is, which files hold a
/// passage, the details file's field names, and the audio's encoding. Folders written by
/// earlier builds are read by this one, so each of these stays as it is.
final class ReadAloudAudioCacheStoredFilesTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("AudioCacheFiles-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder) // Best-effort removal of a temporary folder.
    }

    private let key = ReadAloudAudioCacheKey(text: "Hello, world.", voiceIdentifier: "voice-id", voiceRevision: "r1+r2")

    /// Half a second of a quiet tone.
    private func tone(sampleRate: Int) -> RenderedSpeech {
        RenderedSpeech(samples: (0..<(sampleRate / 2)).map { index in sin(Float(index) * 0.06) * 0.3 }, sampleRate: sampleRate)
    }

    /// Two seconds of noise from a fixed sequence, which an encoder cannot compress below its bit rate.
    private func noise(sampleRate: Int) -> RenderedSpeech {
        var state: UInt32 = 12_345
        let samples = (0..<(sampleRate * 2)).map { _ -> Float in
            state = state &* 1_664_525 &+ 1_013_904_223
            return (Float(state >> 8) / Float(1 << 24) - 0.5) * 0.6
        }
        return RenderedSpeech(samples: samples, sampleRate: sampleRate)
    }

    private func storedDetails(of key: ReadAloudAudioCacheKey) throws -> [String: Any] {
        let data = try Data(contentsOf: folder.appendingPathComponent("\(key.value).json"))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testTheDefaultFolderIsReadAloudAudioInsideTheCachesFolder() throws {
        let location = try ReadAloudAudioCache.defaultFolder()

        XCTAssertEqual(location.lastPathComponent, "ReadAloudAudio")
        XCTAssertEqual(location.deletingLastPathComponent().lastPathComponent, "Caches")
    }

    func testACommittedPassageLeavesItsAudioItsDetailsAndTheIndexNamedByItsKey() async throws {
        let cache = ReadAloudAudioCache(folder: folder)

        _ = try await cache.writeAudio(tone(sampleRate: 24_000), for: key)
        try await cache.commit(key, durationSeconds: 0.5, wordTimings: nil)

        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted(),
                       ["\(key.value).json", "\(key.value).m4a", "index.json"])
    }

    func testTheDetailsFileHoldsTheDurationAndWordTimingsWithTheirFieldNames() async throws {
        let cache = ReadAloudAudioCache(folder: folder)
        let timings = [ReadAloudTimedWord(location: 0, length: 5, startSeconds: 0.1, endSeconds: 0.4),
                       ReadAloudTimedWord(location: 7, length: 5, startSeconds: 0.5, endSeconds: 0.9)]

        _ = try await cache.writeAudio(tone(sampleRate: 24_000), for: key)
        try await cache.commit(key, durationSeconds: 1.25, wordTimings: timings)

        let details = try storedDetails(of: key)
        XCTAssertEqual(Set(details.keys), ["durationSeconds", "wordTimings"], "readsPassageText is left out when false.")
        XCTAssertEqual(details["durationSeconds"] as? Double, 1.25)
        let words = try XCTUnwrap(details["wordTimings"] as? [[String: Any]])
        XCTAssertEqual(words.count, 2)
        XCTAssertEqual(Set(words[0].keys), ["location", "length", "startSeconds", "endSeconds"])
        XCTAssertEqual(words[0]["location"] as? Int, 0)
        XCTAssertEqual(words[0]["length"] as? Int, 5)
        XCTAssertEqual(words[0]["startSeconds"] as? Double, 0.1)
        XCTAssertEqual(words[0]["endSeconds"] as? Double, 0.4)
        XCTAssertEqual(words[1]["location"] as? Int, 7)
    }

    func testAPassageReadFromItsOwnTextRecordsThatInItsDetails() async throws {
        let cache = ReadAloudAudioCache(folder: folder)

        _ = try await cache.writeAudio(tone(sampleRate: 24_000), for: key)
        try await cache.commit(key, durationSeconds: 0.5, wordTimings: nil, readsPassageText: true)

        let details = try storedDetails(of: key)
        XCTAssertEqual(details["readsPassageText"] as? Bool, true)
        XCTAssertNil(details["wordTimings"], "A passage without timings has no timings field.")
    }

    func testDetailsWrittenByAnEarlierBuildAreReadBackWithTimingsAndTheirFlag() async throws {
        let withTimings = ReadAloudAudioCacheKey(text: "older", voiceIdentifier: "voice-id", voiceRevision: "r1")
        let withoutDetailsFlag = ReadAloudAudioCacheKey(text: "oldest", voiceIdentifier: "voice-id", voiceRevision: "r1")
        for storedKey in [withTimings, withoutDetailsFlag] {
            try Data(count: 64).write(to: folder.appendingPathComponent("\(storedKey.value).m4a"))
        }
        let newer = #"{"durationSeconds":2.5,"readsPassageText":true,"wordTimings":[{"endSeconds":0.75,"length":3,"location":4,"startSeconds":0.25}]}"#
        let oldest = #"{"durationSeconds":1}"#
        try Data(newer.utf8).write(to: folder.appendingPathComponent("\(withTimings.value).json"))
        try Data(oldest.utf8).write(to: folder.appendingPathComponent("\(withoutDetailsFlag.value).json"))
        let index = #"[{"byteCount":100,"key":{"value":"\#(withTimings.value)"},"lastUsed":800000000},{"byteCount":100,"key":{"value":"\#(withoutDetailsFlag.value)"},"lastUsed":800000000}]"#
        try Data(index.utf8).write(to: folder.appendingPathComponent("index.json"))

        let cache = ReadAloudAudioCache(folder: folder)

        let first = await cache.passage(for: withTimings)
        XCTAssertEqual(first?.durationSeconds, 2.5)
        XCTAssertEqual(first?.readsPassageText, true)
        XCTAssertEqual(first?.wordTimings, [ReadAloudTimedWord(location: 4, length: 3, startSeconds: 0.25, endSeconds: 0.75)])
        let second = await cache.passage(for: withoutDetailsFlag)
        XCTAssertEqual(second?.durationSeconds, 1)
        XCTAssertEqual(second?.readsPassageText, false, "A details file without the flag reads the chosen voice's text.")
        XCTAssertNil(second?.wordTimings)
    }

    func testRenderedAudioIsMonoAACAtTheModelsSampleRateAndSixtyFourKilobitsPerSecond() async throws {
        let cache = ReadAloudAudioCache(folder: folder)

        for sampleRate in [24_000, 44_100] {
            let audioKey = ReadAloudAudioCacheKey(text: "rate \(sampleRate)", voiceIdentifier: "voice-id", voiceRevision: "r1")
            let location = try await cache.writeAudio(noise(sampleRate: sampleRate), for: audioKey)

            XCTAssertEqual(location, folder.appendingPathComponent("\(audioKey.value).m4a"))
            let file = try AVAudioFile(forReading: location)
            XCTAssertEqual(file.fileFormat.settings[AVFormatIDKey] as? UInt32, kAudioFormatMPEG4AAC)
            XCTAssertEqual(file.fileFormat.channelCount, 1)
            XCTAssertEqual(file.fileFormat.sampleRate, Double(sampleRate))
            XCTAssertEqual(Double(try bitRate(of: location)), 64_000, accuracy: 3_200, "\(sampleRate) Hz: within 5 % of 64 kbit/s")
        }
    }

    private func bitRate(of location: URL) throws -> UInt32 {
        var audioFile: AudioFileID?
        XCTAssertEqual(AudioFileOpenURL(location as CFURL, .readPermission, 0, &audioFile), noErr)
        let opened = try XCTUnwrap(audioFile)
        defer { AudioFileClose(opened) }
        var bitRate: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        XCTAssertEqual(AudioFileGetProperty(opened, kAudioFilePropertyBitRate, &size, &bitRate), noErr)
        return bitRate
    }
}

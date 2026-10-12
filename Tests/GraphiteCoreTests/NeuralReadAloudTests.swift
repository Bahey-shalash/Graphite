import XCTest
@testable import GraphiteCore

final class NeuralVoiceManifestTests: XCTestCase {
    private var shippedManifestFile: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/GraphiteVoices/Resources/NeuralVoices.json")
    }

    private func manifestJSON(voiceIdentifier: String = "voice", path: String = "model.safetensors",
                              checksum: String = String(repeating: "a", count: 64), formatVersion: Int = 1, voiceCount: Int = 1) -> Data {
        let voice = """
        {"id":"\(voiceIdentifier)","name":"Voice","modelName":"Model","modelFamily":"pocket-tts","language":"en",
         "qualityNote":"Fine.","license":{"name":"MIT","address":"https://example.com/license"},
         "sources":[{"repository":"owner/name","revision":"0123abc","files":[{"path":"\(path)","byteCount":10,"sha256":"\(checksum)"}]}],
         "platforms":["iOS"],"minimumPhysicalMemoryBytes":1}
        """
        let voices = Array(repeating: voice, count: voiceCount).joined(separator: ",")
        return Data("""
        {"formatVersion":\(formatVersion),"downloadHost":"https://huggingface.co","voices":[\(voices)]}
        """.utf8)
    }

    func testShippedManifestListsTheFiveChosenVoicesWithPinnedRevisionsAndChecksums() throws {
        let manifest = try NeuralVoiceManifest.decode(Data(contentsOf: shippedManifestFile))
        XCTAssertEqual(manifest.voices.map(\.modelFamily), [.pocketTTS, .qwen3TTS, .qwen3TTS, .chatterboxTurbo, .dia])
        for voice in manifest.voices {
            XCTAssertFalse(voice.files.isEmpty, voice.id)
            XCTAssertGreaterThan(voice.byteCount, 100_000_000, voice.id)
            for source in voice.sources { XCTAssertEqual(source.revision.count, 40, "\(voice.id) pins a full commit") }
            XCTAssertFalse(voice.qualityNote.isEmpty)
        }
        let pocket = try XCTUnwrap(manifest.voice(identifier: "pocket-tts-alba"))
        XCTAssertEqual(pocket.license.name, "CC BY 4.0")
        XCTAssertNotNil(pocket.license.attribution, "CC BY requires attribution in Settings and About")
        XCTAssertTrue(pocket.files.contains { file in file.path == "embeddings/alba.safetensors" })
        let dia = try XCTUnwrap(manifest.voice(identifier: "dia-1.6b"))
        XCTAssertTrue(dia.files.contains { file in file.localPath == "codec/model.safetensors" }, "Dia's codec goes into its own subfolder")
    }

    func testDownloadAddressIsBuiltFromHostRepositoryRevisionAndPath() throws {
        let manifest = try NeuralVoiceManifest.decode(manifestJSON(path: "embeddings/alba.safetensors"))
        let voice = try XCTUnwrap(manifest.voices.first)
        let address = manifest.downloadAddress(of: voice.files[0], in: voice.sources[0])
        XCTAssertEqual(address.absoluteString, "https://huggingface.co/owner/name/resolve/0123abc/embeddings/alba.safetensors")
    }

    func testManifestRefusesPathsThatLeaveTheVoiceFolderBadChecksumsDuplicatesAndUnknownVersions() {
        for unsafePath in ["../escape", "/absolute", "a//b", "a/./b", "back\\slash", ""] {
            XCTAssertThrowsError(try NeuralVoiceManifest.decode(manifestJSON(path: unsafePath)), unsafePath)
        }
        XCTAssertThrowsError(try NeuralVoiceManifest.decode(manifestJSON(checksum: "xyz")))
        XCTAssertThrowsError(try NeuralVoiceManifest.decode(manifestJSON(checksum: String(repeating: "g", count: 64))))
        XCTAssertThrowsError(try NeuralVoiceManifest.decode(manifestJSON(voiceIdentifier: "../voice")))
        XCTAssertThrowsError(try NeuralVoiceManifest.decode(manifestJSON(voiceCount: 2))) { error in
            XCTAssertEqual(error as? NeuralVoiceManifest.ManifestError, .duplicateVoiceIdentifier("voice"))
        }
        XCTAssertThrowsError(try NeuralVoiceManifest.decode(manifestJSON(formatVersion: 2))) { error in
            XCTAssertEqual(error as? NeuralVoiceManifest.ManifestError, .unsupportedFormatVersion(2))
        }
        XCTAssertThrowsError(try NeuralVoiceManifest.decode(Data(count: NeuralVoiceManifest.maximumFileBytes + 1)))
        XCTAssertNoThrow(try NeuralVoiceManifest.decode(manifestJSON()))
    }

    func testVoiceIsOfferedOnlyOnItsPlatformsWithEnoughMemory() throws {
        let voice = try XCTUnwrap(NeuralVoiceManifest.decode(manifestJSON()).voices.first)
        XCTAssertTrue(voice.isOffered(onPlatform: "iOS", physicalMemoryBytes: 1))
        XCTAssertFalse(voice.isOffered(onPlatform: "macOS", physicalMemoryBytes: 1))
        XCTAssertFalse(voice.isOffered(onPlatform: "iOS", physicalMemoryBytes: 0))
    }
}

final class ReadAloudAudioCacheTests: XCTestCase {
    func testKeyChangesWithTextVoiceRevisionAndSettingsButNotOtherwise() {
        let key = ReadAloudAudioCacheKey(text: "Read this.", voiceIdentifier: "alba", voiceRevision: "r1")
        XCTAssertEqual(key, ReadAloudAudioCacheKey(text: "Read this.", voiceIdentifier: "alba", voiceRevision: "r1"))
        XCTAssertEqual(key.value.count, 64)
        XCTAssertNotEqual(key, ReadAloudAudioCacheKey(text: "Read this!", voiceIdentifier: "alba", voiceRevision: "r1"))
        XCTAssertNotEqual(key, ReadAloudAudioCacheKey(text: "Read this.", voiceIdentifier: "ryan", voiceRevision: "r1"))
        XCTAssertNotEqual(key, ReadAloudAudioCacheKey(text: "Read this.", voiceIdentifier: "alba", voiceRevision: "r2"))
        XCTAssertNotEqual(key, ReadAloudAudioCacheKey(text: "Read this.", voiceIdentifier: "alba", voiceRevision: "r1", renderSettingsVersion: 99))
        // Moving characters between fields must not produce the same key.
        XCTAssertNotEqual(ReadAloudAudioCacheKey(text: "b", voiceIdentifier: "a", voiceRevision: "r"),
                          ReadAloudAudioCacheKey(text: "", voiceIdentifier: "ab", voiceRevision: "r"))
        XCTAssertEqual(ReadAloudAudioCacheKey(fileName: key.value + ".m4a"), key)
        XCTAssertNil(ReadAloudAudioCacheKey(fileName: "index.json"))
    }

    func testEvictionRemovesLeastRecentlyUsedUntilUnderCapacityAndKeepsTheDocumentBeingRead() {
        func entry(_ text: String, bytes: Int64, minutesAgo: Double) -> ReadAloudAudioCacheEntry {
            ReadAloudAudioCacheEntry(key: ReadAloudAudioCacheKey(text: text, voiceIdentifier: "v", voiceRevision: "r"),
                                     byteCount: bytes, lastUsed: Date(timeIntervalSinceReferenceDate: 10_000 - minutesAgo * 60))
        }
        let oldest = entry("oldest", bytes: 40, minutesAgo: 30)
        let older = entry("older", bytes: 40, minutesAgo: 20)
        let recent = entry("recent", bytes: 40, minutesAgo: 1)
        let entries = [recent, oldest, older]
        XCTAssertEqual(ReadAloudAudioCacheEviction.keysToRemove(from: entries, capacityBytes: 120), [])
        XCTAssertEqual(ReadAloudAudioCacheEviction.keysToRemove(from: entries, capacityBytes: 100), [oldest.key])
        XCTAssertEqual(ReadAloudAudioCacheEviction.keysToRemove(from: entries, capacityBytes: 40), [oldest.key, older.key])
        XCTAssertEqual(ReadAloudAudioCacheEviction.keysToRemove(from: entries, capacityBytes: 40, protectedKeys: [oldest.key]),
                       [older.key, recent.key])
        XCTAssertEqual(ReadAloudAudioCacheEviction.keysToRemove(from: entries, capacityBytes: 0, protectedKeys: Set(entries.map(\.key))), [],
                       "audio about to play is never removed, even over the limit")
    }

    func testWaveFileHasAStandardHeaderAndClipsLoudSamples() {
        let data = PCMWaveFile.encode(samples: [0, 1, -1, 2, .nan], sampleRate: 24_000)
        XCTAssertEqual(data.count, 44 + 10)
        XCTAssertEqual(String(decoding: data[0..<4], as: UTF8.self), "RIFF")
        XCTAssertEqual(String(decoding: data[8..<16], as: UTF8.self), "WAVEfmt ")
        let sampleRate = data[24..<28].enumerated().reduce(0) { total, element in total | Int(element.element) << (8 * element.offset) }
        XCTAssertEqual(sampleRate, 24_000)
        let samples = stride(from: 44, to: 54, by: 2).map { offset in Int16(bitPattern: UInt16(data[offset]) | UInt16(data[offset + 1]) << 8) }
        XCTAssertEqual(samples, [0, Int16.max, -Int16.max, Int16.max, 0])
    }
}

final class ReadAloudWordAlignmentTests: XCTestCase {
    private func heard(_ words: [(String, Double)], wordSeconds: Double = 0.3) -> [ReadAloudRecognizedWord] {
        words.map { word in ReadAloudRecognizedWord(text: word.0, startSeconds: word.1, endSeconds: word.1 + wordSeconds) }
    }

    func testExactRecognitionTimesEveryWordOnItsOwnRange() throws {
        let passage = "Compared with SRAM, DRAM is denser."
        let timings = try XCTUnwrap(ReadAloudWordAlignment.align(
            passage: passage, recognized: heard([("Compared", 0.1), ("with", 0.5), ("SRAM", 0.8), ("DRAM", 1.4), ("is", 1.9), ("denser", 2.1)]),
            audioDurationSeconds: 3))
        XCTAssertEqual(timings.map { (passage as NSString).substring(with: $0.range) }, ["Compared", "with", "SRAM", "DRAM", "is", "denser"])
        XCTAssertEqual(timings.map(\.startSeconds), [0.1, 0.5, 0.8, 1.4, 1.9, 2.1])
    }

    func testMissedAndMisheardWordsShareTheGapBetweenTheirNeighbors() throws {
        let passage = "The delay scales as R times C, so halving it helps."
        // "R" and "C" are often heard as "are" and "see", and "halving" as "having".
        let timings = try XCTUnwrap(ReadAloudWordAlignment.align(
            passage: passage,
            recognized: heard([("the", 0), ("delay", 0.3), ("scales", 0.7), ("as", 1.1), ("are", 1.3), ("times", 1.6), ("see", 2.0),
                               ("so", 2.4), ("having", 2.7), ("it", 3.1), ("helps", 3.3)]),
            audioDurationSeconds: 4))
        let words = timings.map { (passage as NSString).substring(with: $0.range) }
        XCTAssertEqual(words, ["The", "delay", "scales", "as", "R", "times", "C", "so", "halving", "it", "helps"])
        XCTAssertEqual(timings[5].startSeconds, 1.6, accuracy: 0.001)
        XCTAssertEqual(timings[8].startSeconds, 2.7, accuracy: 0.001, "a near match keeps its own time")
        XCTAssertGreaterThan(timings[4].startSeconds, timings[3].startSeconds, "an unmatched word falls between its neighbors")
        XCTAssertLessThan(timings[4].startSeconds, timings[5].startSeconds)
        XCTAssertEqual(timings.map(\.startSeconds), timings.map(\.startSeconds).sorted(), "the highlight only moves forward")
    }

    func testAlignmentIsRefusedWhenTooFewWordsMatch() {
        XCTAssertNil(ReadAloudWordAlignment.align(passage: "Memory arrays are partitioned into banks.",
                                                  recognized: heard([("hello", 0), ("world", 0.5)]), audioDurationSeconds: 2))
        XCTAssertNil(ReadAloudWordAlignment.align(passage: "Words.", recognized: [], audioDurationSeconds: 2))
        XCTAssertNil(ReadAloudWordAlignment.align(passage: "", recognized: heard([("a", 0)]), audioDurationSeconds: 2))
    }

    func testPlaybackTimeFindsTheWordBeingSaidAndOffsetsResumeOnAWordBoundary() throws {
        let timings = [ReadAloudTimedWord(location: 0, length: 3, startSeconds: 0.2, endSeconds: 0.5),
                       ReadAloudTimedWord(location: 4, length: 5, startSeconds: 0.6, endSeconds: 1.0),
                       ReadAloudTimedWord(location: 10, length: 4, startSeconds: 1.1, endSeconds: 1.5)]
        XCTAssertNil(ReadAloudWordAlignment.word(at: 0.1, in: timings))
        XCTAssertEqual(ReadAloudWordAlignment.word(at: 0.7, in: timings)?.location, 4)
        XCTAssertEqual(ReadAloudWordAlignment.word(at: 9, in: timings)?.location, 10)
        XCTAssertEqual(ReadAloudWordAlignment.startSeconds(forOffset: 0, in: timings), 0.2)
        XCTAssertEqual(ReadAloudWordAlignment.startSeconds(forOffset: 6, in: timings), 0.6, "an offset inside a word starts at that word")
        XCTAssertEqual(ReadAloudWordAlignment.startSeconds(forOffset: 9, in: timings), 1.1)
    }

    func testNormalizationIgnoresCaseAccentsAndPunctuation() {
        XCTAssertEqual(ReadAloudWordAlignment.normalize("Résumé,"), "resume")
        XCTAssertEqual(ReadAloudWordAlignment.normalize("50%"), "50")
        XCTAssertEqual(ReadAloudWordAlignment.similarityScore("operand", "operands"), 1)
        XCTAssertEqual(ReadAloudWordAlignment.similarityScore("cat", "cats"), 0, "short words must match exactly")
    }
}

final class ReadAloudQualityModeTests: XCTestCase {
    func testHighQualityIsTheDefaultOnceAVoiceIsDownloadedAndQuickRemainsAChoice() {
        XCTAssertEqual(ReadAloudQualityMode.effective(chosen: nil, hasDownloadedVoice: false), .quick)
        XCTAssertEqual(ReadAloudQualityMode.effective(chosen: .highQuality, hasDownloadedVoice: false), .quick)
        XCTAssertEqual(ReadAloudQualityMode.effective(chosen: nil, hasDownloadedVoice: true), .highQuality)
        XCTAssertEqual(ReadAloudQualityMode.effective(chosen: .quick, hasDownloadedVoice: true), .quick)
    }

    func testUnpreparedPassagesWaitUnlessThePersonAllowedTheSystemVoiceToFillIn() {
        XCTAssertEqual(ReadAloudPassageAudioPolicy.decision(isRendered: true, readsUnpreparedPassagesQuickly: false), .playRendered)
        XCTAssertEqual(ReadAloudPassageAudioPolicy.decision(isRendered: true, readsUnpreparedPassagesQuickly: true), .playRendered)
        XCTAssertEqual(ReadAloudPassageAudioPolicy.decision(isRendered: false, readsUnpreparedPassagesQuickly: false), .waitForRendering)
        XCTAssertEqual(ReadAloudPassageAudioPolicy.decision(isRendered: false, readsUnpreparedPassagesQuickly: true), .speakWithSystemVoice)
    }

    func testPreparedShareCountsCharacters() {
        XCTAssertEqual(ReadAloudPassageAudioPolicy.preparedShare(passageLengths: [10, 30, 60], renderedPassages: [0, 1]), 0.4, accuracy: 0.0001)
        XCTAssertEqual(ReadAloudPassageAudioPolicy.preparedShare(passageLengths: [], renderedPassages: []), 1)
    }
}

import XCTest
import GraphiteCore
@testable import GraphiteVoices

/// A voice that renders a tone and remembers who was asked to say what, with which seed.
private final class RecordingPassageRenderer: NeuralPassageRendering, @unchecked Sendable {
    struct Call: Equatable {
        let voiceIdentifier: String
        let text: String
        let hasSeed: Bool
    }

    private let lock = NSLock()
    private var recordedCalls: [Call] = []

    var calls: [Call] { lock.withLock { recordedCalls } }

    func render(_ text: String, voice: NeuralVoiceDescription, voiceFolder: URL, seed: UInt64?) async throws -> RenderedSpeech {
        lock.withLock { recordedCalls.append(Call(voiceIdentifier: voice.id, text: text, hasSeed: seed != nil)) }
        let sampleRate = 24_000
        return RenderedSpeech(samples: (0..<sampleRate).map { index in sin(Float(index) * 0.06) * 0.3 }, sampleRate: sampleRate)
    }

    func releaseResources() async {}
}

/// Speech recognition that hears nothing until the attempt number it is told to accept, then
/// hears the passage's words one after another.
private final class AcceptingFromAttemptAlignment: ReadAloudSpeechAligning, @unchecked Sendable {
    private let lock = NSLock()
    private var attemptCount = 0
    private let acceptedAttempt: Int
    private let heardWords: [String]

    init(acceptedAttempt: Int, heardWords: [String]) {
        self.acceptedAttempt = acceptedAttempt
        self.heardWords = heardWords
    }

    func recognizedWords(in audioFile: URL, language: String) async -> [ReadAloudRecognizedWord]? {
        let attempt = lock.withLock { () -> Int in attemptCount += 1; return attemptCount }
        guard attempt >= acceptedAttempt else { return [] }
        return heardWords.enumerated().map { index, word in
            ReadAloudRecognizedWord(text: word, startSeconds: Double(index) * 0.25, endSeconds: Double(index) * 0.25 + 0.2)
        }
    }
}

/// Which voice says a passage, in which order the attempts go, and the revision that names
/// the cached audio.
@MainActor
final class ReadAloudPassagePreparationRenderAttemptTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("RenderAttempts-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder) // Best-effort removal of a temporary folder.
    }

    private let voiceText = "Hello there world, spoken."
    private let passageText = "Hello there world."
    private let heardWords = ["Hello", "there", "world"]

    private func makeVoice(identifier: String, revisions: [String]) -> ReadAloudPassagePreparation.Voice {
        let description = NeuralVoiceDescription(
            id: identifier, name: identifier, modelName: "Test model", modelFamily: .pocketTTS, speaker: nil, language: "en",
            qualityNote: "A test voice.", license: NeuralVoiceLicense(name: "Test", address: URL(string: "https://example.com/license")!),
            sources: revisions.enumerated().map { index, revision in
                NeuralVoiceSource(repository: "test/source\(index)", revision: revision, files: [])
            },
            platforms: ["macOS", "iOS"], minimumPhysicalMemoryBytes: 0)
        return ReadAloudPassagePreparation.Voice(description: description, folder: folder.appendingPathComponent(identifier))
    }

    private func makePreparation(renderer: RecordingPassageRenderer, acceptedAttempt: Int) -> (ReadAloudPassagePreparation, ReadAloudAudioCache) {
        let cache = ReadAloudAudioCache(folder: folder.appendingPathComponent("Audio", isDirectory: true))
        let preparation = ReadAloudPassagePreparation(cache: cache, renderer: renderer,
                                                      aligner: AcceptingFromAttemptAlignment(acceptedAttempt: acceptedAttempt, heardWords: heardWords))
        return (preparation, cache)
    }

    func testAPassageIsCachedUnderTheRevisionsOfAVoiceSourcesJoinedWithPlusInManifestOrder() async throws {
        let renderer = RecordingPassageRenderer()
        let (preparation, cache) = makePreparation(renderer: renderer, acceptedAttempt: 1)
        let voice = makeVoice(identifier: "two-source-voice", revisions: ["r1", "r2"])

        preparation.prepare([ReadAloudPassagePreparation.Item(voiceText: passageText, passageText: passageText)], from: 0, voice: voice, language: "en")
        let prepared = await preparation.waitForPassage(passageText, voice: voice)

        XCTAssertNotNil(prepared)
        let joinedRevision = ReadAloudAudioCacheKey(text: passageText, voiceIdentifier: "two-source-voice", voiceRevision: "r1+r2")
        let reversedRevision = ReadAloudAudioCacheKey(text: passageText, voiceIdentifier: "two-source-voice", voiceRevision: "r2+r1")
        let firstRevisionOnly = ReadAloudAudioCacheKey(text: passageText, voiceIdentifier: "two-source-voice", voiceRevision: "r1")
        let cachedUnderJoined = await cache.contains(joinedRevision)
        let cachedUnderReversed = await cache.contains(reversedRevision)
        let cachedUnderFirstOnly = await cache.contains(firstRevisionOnly)
        XCTAssertTrue(cachedUnderJoined)
        XCTAssertFalse(cachedUnderReversed)
        XCTAssertFalse(cachedUnderFirstOnly)
    }

    func testAPassageTheChosenVoiceSaysCleanlyIsRenderedOnceWithTheModelsOwnSeed() async throws {
        let renderer = RecordingPassageRenderer()
        let (preparation, _) = makePreparation(renderer: renderer, acceptedAttempt: 1)
        let voice = makeVoice(identifier: "chosen", revisions: ["r1"])
        let fallback = makeVoice(identifier: "fallback", revisions: ["r1"])

        preparation.prepare([ReadAloudPassagePreparation.Item(voiceText: voiceText, passageText: passageText, writtenText: passageText)],
                            from: 0, voice: voice, fallbackVoice: fallback, language: "en")
        let preparedOrNil = await preparation.waitForPassage(voiceText, voice: voice)
        let prepared = try XCTUnwrap(preparedOrNil)

        XCTAssertEqual(renderer.calls, [.init(voiceIdentifier: "chosen", text: voiceText, hasSeed: false)])
        XCTAssertFalse(prepared.readsPassageText)
    }

    func testARejectedFirstRenderIsTriedAgainWithARandomSeedByTheSameVoice() async throws {
        let renderer = RecordingPassageRenderer()
        let (preparation, _) = makePreparation(renderer: renderer, acceptedAttempt: 2)
        let voice = makeVoice(identifier: "chosen", revisions: ["r1"])
        let fallback = makeVoice(identifier: "fallback", revisions: ["r1"])

        preparation.prepare([ReadAloudPassagePreparation.Item(voiceText: voiceText, passageText: passageText, writtenText: passageText)],
                            from: 0, voice: voice, fallbackVoice: fallback, language: "en")
        let preparedOrNil = await preparation.waitForPassage(voiceText, voice: voice)
        let prepared = try XCTUnwrap(preparedOrNil)

        XCTAssertEqual(renderer.calls, [.init(voiceIdentifier: "chosen", text: voiceText, hasSeed: false),
                                        .init(voiceIdentifier: "chosen", text: voiceText, hasSeed: true)])
        XCTAssertFalse(prepared.readsPassageText)
    }

    func testAfterTwoRejectionsTheInstalledFallbackVoiceReadsThePassagesOwnTextAndTheCacheSaysSo() async throws {
        let renderer = RecordingPassageRenderer()
        let (preparation, _) = makePreparation(renderer: renderer, acceptedAttempt: 3)
        let voice = makeVoice(identifier: "chosen", revisions: ["r1"])
        let fallback = makeVoice(identifier: "fallback", revisions: ["r1"])

        preparation.prepare([ReadAloudPassagePreparation.Item(voiceText: voiceText, passageText: passageText, writtenText: passageText)],
                            from: 0, voice: voice, fallbackVoice: fallback, language: "en")
        let preparedOrNil = await preparation.waitForPassage(voiceText, voice: voice)
        let prepared = try XCTUnwrap(preparedOrNil)

        XCTAssertEqual(renderer.calls, [.init(voiceIdentifier: "chosen", text: voiceText, hasSeed: false),
                                        .init(voiceIdentifier: "chosen", text: voiceText, hasSeed: true),
                                        .init(voiceIdentifier: "fallback", text: passageText, hasSeed: false)])
        XCTAssertTrue(prepared.readsPassageText)
        XCTAssertEqual(prepared.wordTimings?.map(\.location), [0, 6, 12], "The timings index the passage's own text.")
        XCTAssertTrue(preparation.systemVoiceTexts.isEmpty)
    }

    func testWithoutAFallbackVoiceTwoRejectionsLeaveThePassageToTheSystemVoice() async throws {
        let renderer = RecordingPassageRenderer()
        let (preparation, cache) = makePreparation(renderer: renderer, acceptedAttempt: 3)
        let voice = makeVoice(identifier: "chosen", revisions: ["r1"])

        preparation.prepare([ReadAloudPassagePreparation.Item(voiceText: voiceText, passageText: passageText, writtenText: passageText)],
                            from: 0, voice: voice, language: "en")
        let prepared = await preparation.waitForPassage(voiceText, voice: voice)

        XCTAssertNil(prepared)
        XCTAssertEqual(renderer.calls.map(\.voiceIdentifier), ["chosen", "chosen"])
        XCTAssertEqual(preparation.systemVoiceTexts, [voiceText])
        XCTAssertNotNil(preparation.failureMessage)
        let cachedAnything = await cache.contains(voice.cacheKey(for: voiceText))
        XCTAssertFalse(cachedAnything, "Audio nobody should hear is not kept.")
    }
}

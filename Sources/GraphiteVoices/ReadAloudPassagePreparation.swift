import Foundation
import Observation
import GraphiteCore

/// Turns passage text into speech with a downloaded voice. A protocol so hosted tests can use
/// a tiny generated tone instead of a model of several hundred megabytes.
public protocol NeuralPassageRendering: Sendable {
    func render(_ text: String, voice: NeuralVoiceDescription, voiceFolder: URL) async throws -> RenderedSpeech
    /// Frees the model's memory; the next render loads it again.
    func releaseResources() async
}

/// The MLX models on the graphics processor. Loads the voice on first use and keeps it while
/// the same voice is used; `releaseResources` frees it once the queue is done. The main
/// processor is not used: on an iPad Pro M1 MLX ran there several times slower than real time
/// and failed outright, so rendering happens only while Graphite is on screen.
public final class MLXPassageRenderer: NeuralPassageRendering {
    private let engine = NeuralSpeechEngine(diaVoicePrompt: NeuralVoiceCatalog.diaVoicePrompt())

    public init() {}

    public func render(_ text: String, voice: NeuralVoiceDescription, voiceFolder: URL) async throws -> RenderedSpeech {
        if await engine.loadedVoice?.id != voice.id {
            try await engine.load(voice, from: voiceFolder)
        }
        return try await engine.render(text, on: .graphics)
    }

    public func releaseResources() async {
        await engine.unload()
    }
}

/// Renders a document's passages ahead of playback, one at a time in reading order, keeping
/// each in the audio cache with its word timings. Already cached passages are skipped, so an
/// edited note re-renders only the passages whose text changed. Starting another document
/// replaces the queue; a passage the reader needs now jumps to the front.
@MainActor @Observable
public final class ReadAloudPassagePreparation {
    public struct Voice: Sendable {
        public let description: NeuralVoiceDescription
        public let folder: URL

        public init(description: NeuralVoiceDescription, folder: URL) {
            self.description = description
            self.folder = folder
        }

        var revision: String { description.sources.map(\.revision).joined(separator: "+") }

        func cacheKey(for text: String) -> ReadAloudAudioCacheKey {
            ReadAloudAudioCacheKey(text: text, voiceIdentifier: description.id, voiceRevision: revision)
        }
    }

    /// The share of the queued text that is ready, from 0 to 1, while preparing.
    public private(set) var preparedShare: Double = 1
    public private(set) var isPreparing = false
    /// Why the last passage could not be rendered, in words for the person.
    public private(set) var failureMessage: String?

    @ObservationIgnored private let cache: ReadAloudAudioCache
    @ObservationIgnored private let renderer: any NeuralPassageRendering
    @ObservationIgnored private let aligner: any ReadAloudSpeechAligning
    @ObservationIgnored private var voice: Voice?
    @ObservationIgnored private var language = "en"
    @ObservationIgnored private var queue: [String] = []
    @ObservationIgnored private var readyTexts: Set<String> = []
    @ObservationIgnored private var worker: Task<Void, Never>?
    @ObservationIgnored private var waiters: [String: [CheckedContinuation<CachedReadAloudPassage?, Never>]] = [:]
    /// True while Graphite is in the background; see `suspend`.
    public private(set) var isSuspended = false

    public init(cache: ReadAloudAudioCache, renderer: any NeuralPassageRendering, aligner: any ReadAloudSpeechAligning) {
        self.cache = cache
        self.renderer = renderer
        self.aligner = aligner
    }

    /// Queues the passages from `startIndex` to the end for `voice`. Passages before the start
    /// are not rendered: reading began later in the note.
    public func prepare(_ passageTexts: [String], from startIndex: Int, voice: Voice, language: String) {
        let upcoming = Array(passageTexts.dropFirst(max(0, startIndex)))
        // Reading moving on to the next passage asks again with one passage fewer; the queue
        // already holds those, so rendering continues undisturbed.
        let isAlreadyQueued = self.voice?.description.id == voice.description.id && self.language == language
            && queue.count >= upcoming.count && Array(queue.suffix(upcoming.count)) == upcoming
        guard !isAlreadyQueued else { return }
        cancel()
        self.voice = voice
        self.language = language
        queue = upcoming
        readyTexts = []
        preparedShare = upcoming.isEmpty ? 1 : 0
        failureMessage = nil
        startWorker()
    }

    private func startWorker() {
        guard let voice, !isSuspended else { return }
        let keys = Set(queue.map(voice.cacheKey(for:)))
        worker = Task { [weak self] in
            await self?.cache.protect(keys)
            await self?.renderQueue(voice)
        }
    }

    /// iOS refuses graphics work from an app in the background, and a model on the main
    /// processor is too slow to help, so rendering stops while Graphite is off screen and
    /// continues where it left off when it returns. Playback of rendered passages goes on.
    public func suspend() {
        guard !isSuspended else { return }
        isSuspended = true
        worker?.cancel()
        worker = nil
    }

    public func resumeAfterSuspension() {
        guard isSuspended else { return }
        isSuspended = false
        if !queue.isEmpty, worker == nil { startWorker() }
    }

    /// Stops rendering. Audio already rendered stays in the cache.
    public func cancel() {
        worker?.cancel()
        worker = nil
        isPreparing = false
        preparedShare = 1
        queue = []
        for (_, continuations) in waiters { for continuation in continuations { continuation.resume(returning: nil) } }
        waiters = [:]
    }

    /// The rendered passage if it is ready now.
    public func readyPassage(_ text: String, voice: Voice) async -> CachedReadAloudPassage? {
        await cache.passage(for: voice.cacheKey(for: text))
    }

    /// Waits until the passage is rendered, moving it to the front of the queue; nil when
    /// rendering was cancelled or failed.
    public func waitForPassage(_ text: String, voice: Voice) async -> CachedReadAloudPassage? {
        if let ready = await cache.passage(for: voice.cacheKey(for: text)) { return ready }
        // Finished without audio: rendering it failed, and failureMessage says why.
        if readyTexts.contains(text), self.voice?.description.id == voice.description.id { return nil }
        if !queue.contains(text) || self.voice?.description.id != voice.description.id {
            prepare([text] + queue.filter { queued in queued != text }, from: 0, voice: voice, language: language)
        } else if let index = queue.firstIndex(of: text), index > 0, !readyTexts.contains(text) {
            queue.remove(at: index)
            queue.insert(text, at: 0)
        }
        if worker == nil { startWorker() }
        return await withCheckedContinuation { continuation in waiters[text, default: []].append(continuation) }
    }

    private func renderQueue(_ voice: Voice) async {
        isPreparing = true
        while !Task.isCancelled, let text = nextUnrenderedText() {
            let key = voice.cacheKey(for: text)
            if let cached = await cache.passage(for: key) {
                finish(text, with: cached)
                continue
            }
            do {
                let speech = try await renderWithRetry(text, voice: voice)
                try Task.checkCancellation()
                let audioFile = try await cache.writeAudio(speech, for: key)
                let recognized = await aligner.recognizedWords(in: audioFile, language: language)
                let timings = recognized.flatMap { words in
                    ReadAloudWordAlignment.align(passage: text, recognized: words, audioDurationSeconds: speech.durationSeconds)
                }
                try await cache.commit(key, durationSeconds: speech.durationSeconds, wordTimings: timings)
                guard !Task.isCancelled else { break }
                finish(text, with: await cache.passage(for: key))
            } catch is CancellationError {
                break
            } catch {
                guard !Task.isCancelled else { break }
                failureMessage = "The voice could not prepare a passage: \(error.localizedDescription)"
                finish(text, with: nil)
            }
        }
        guard !Task.isCancelled else { return }
        isPreparing = false
        worker = nil
        for (_, continuations) in waiters { for continuation in continuations { continuation.resume(returning: nil) } }
        waiters = [:]
        // A loaded model holds from a quarter of a gigabyte (Pocket TTS) to over three
        // (Qwen3-TTS 1.7B); it is freed as soon as nothing is left to render.
        await renderer.releaseResources()
    }

    /// Renders, trying once more after a failure. On a hot iPad iOS sometimes cancels a long
    /// graphics command ("Impacting Interactivity"); the same passage then renders fine.
    private func renderWithRetry(_ text: String, voice: Voice) async throws -> RenderedSpeech {
        do {
            return try await renderer.render(text, voice: voice.description, voiceFolder: voice.folder)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            try await Task.sleep(for: .seconds(1))
            return try await renderer.render(text, voice: voice.description, voiceFolder: voice.folder)
        }
    }

    /// The first queued passage not yet ready, looking again from the front each time so a
    /// passage moved there by `waitForPassage` goes next.
    private func nextUnrenderedText() -> String? {
        queue.first { text in !readyTexts.contains(text) }
    }

    private func finish(_ text: String, with passage: CachedReadAloudPassage?) {
        readyTexts.insert(text)
        let readyIndices = Set(queue.indices.filter { index in readyTexts.contains(queue[index]) })
        preparedShare = ReadAloudPassageAudioPolicy.preparedShare(passageLengths: queue.map(\.count), renderedPassages: readyIndices)
        for continuation in waiters.removeValue(forKey: text) ?? [] { continuation.resume(returning: passage) }
    }
}

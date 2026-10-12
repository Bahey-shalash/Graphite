import Foundation
@preconcurrency import MLX
@preconcurrency import MLXAudioTTS
@preconcurrency import MLXLMCommon
import GraphiteCore

/// Audio a voice rendered for one passage: mono 32-bit float samples.
public struct RenderedSpeech: Sendable {
    public let samples: [Float]
    public let sampleRate: Int

    public init(samples: [Float], sampleRate: Int) {
        self.samples = samples
        self.sampleRate = sampleRate
    }

    public var durationSeconds: Double { sampleRate > 0 ? Double(samples.count) / Double(sampleRate) : 0 }
}

/// Where a model's arithmetic runs. The graphics processor is several times faster, but iOS
/// refuses graphics work from an app in the background, so rendering that continues while
/// the screen is locked has to use the main processor.
public enum NeuralSpeechProcessor: String, Sendable, Codable {
    case graphics
    case central
}

public enum NeuralSpeechEngineError: Error, LocalizedError, Equatable {
    case noVoiceLoaded
    case missingFile(String)
    case producedNoAudio
    case needsDevice

    public var errorDescription: String? {
        switch self {
        case .noVoiceLoaded: "No voice is loaded."
        case .missingFile(let path): "The voice is missing \(path). Download it again."
        case .producedNoAudio: "The voice produced no audio for this passage."
        case .needsDevice: "Downloaded voices need the graphics processor of a real iPad, iPhone or Mac; the Simulator cannot run them."
        }
    }
}

/// A loaded MLX model. `@unchecked Sendable` because MLX models are reference types without
/// locks: the invariant is that only `NeuralSpeechEngine` holds this box and the actor runs
/// one load or render at a time, so the model is never used from two threads at once.
private final class LoadedSpeechModel: @unchecked Sendable {
    let model: any SpeechGenerationModel
    let voice: NeuralVoiceDescription

    init(model: any SpeechGenerationModel, voice: NeuralVoiceDescription) {
        self.model = model
        self.voice = voice
    }
}

/// Runs one downloaded voice on the device. Loading reads the voice's folder only; nothing
/// is fetched from the network. The actor serializes every use of the model.
public actor NeuralSpeechEngine {
    private var loaded: LoadedSpeechModel?
    /// MLX keeps freed buffers for reuse; a small cap keeps the app's footprint near what the
    /// model needs instead of growing to the largest passage ever rendered.
    private static let reusableBufferCacheBytes = 64 * 1_024 * 1_024

    /// Touches no MLX state: on the Simulator, which has no usable Metal device for MLX,
    /// merely setting a memory limit ends the app.
    public init(diaVoicePrompt: DiaVoicePrompt? = nil) {
        self.diaVoicePrompt = diaVoicePrompt
    }

    /// The clip that keeps Dia on one voice; see `DiaVoicePrompt`.
    private let diaVoicePrompt: DiaVoicePrompt?

    public var loadedVoice: NeuralVoiceDescription? { loaded?.voice }

    /// Loads a voice from its folder, replacing any loaded voice first so two models never
    /// share memory.
    public func load(_ voice: NeuralVoiceDescription, from folder: URL) async throws {
        unload()
        #if targetEnvironment(simulator)
        throw NeuralSpeechEngineError.needsDevice
        #else
        Memory.cacheLimit = Self.reusableBufferCacheBytes
        for file in voice.files where !FileManager.default.fileExists(atPath: folder.appendingPathComponent(file.localPath).path) {
            throw NeuralSpeechEngineError.missingFile(file.localPath)
        }
        let model = try await withError { try await Self.makeModel(voice, from: folder) }
        (model as? DiaTTSModel)?.voicePrompt = diaVoicePrompt
        loaded = LoadedSpeechModel(model: model, voice: voice)
        #endif
    }

    private static func makeModel(_ voice: NeuralVoiceDescription, from folder: URL) async throws -> any SpeechGenerationModel {
        let model: any SpeechGenerationModel
        switch voice.modelFamily {
        case .pocketTTS:
            model = try await PocketTTSModel.fromModelDirectory(folder)
        case .qwen3TTS:
            model = try await Qwen3TTSModel.fromModelDirectory(folder)
        case .chatterboxTurbo:
            model = try await ChatterboxModel.fromModelDirectory(folder, hfToken: nil)
        case .dia:
            model = try DiaTTSModel.fromModelDirectory(folder, codecDirectory: folder.appendingPathComponent(Self.diaCodecFolderName))
        }
        return model
    }

    /// The subfolder of a Dia voice that holds the Descript audio codec.
    public static let diaCodecFolderName = "codec"

    public func unload() {
        guard loaded != nil else { return }
        loaded = nil
        Memory.clearCache()
    }

    /// Renders one passage. The text is spoken as given: pronunciation respelling and any
    /// cleanup happen before this call. `seed` makes sampling repeatable; a second attempt at a
    /// passage that came out wrong uses another seed.
    public func render(_ text: String, on processor: NeuralSpeechProcessor = .graphics, seed: UInt64? = nil) async throws -> RenderedSpeech {
        guard let loaded else { throw NeuralSpeechEngineError.noVoiceLoaded }
        let device: Device = processor == .graphics ? .gpu : .cpu
        if let seed { MLXRandom.seed(seed) }
        // Autoregressive models drift on long inputs, so they get one sentence group at a time,
        // joined with a short breath; Pocket TTS splits sentences itself.
        let pieces = loaded.voice.modelFamily == .pocketTTS ? [text] : Self.sentenceGroups(of: text)
        var samples: [Float] = []
        let breath = [Float](repeating: 0, count: loaded.model.sampleRate * 12 / 100)
        for (index, piece) in pieces.enumerated() {
            try Task.checkCancellation()
            // MLX reports failures (an allocation it cannot make, an unsupported operation) to an
            // error handler that ends the process by default; inside `withError` they become a
            // thrown error, so one failed passage cannot close Graphite.
            let pieceSamples = try await withError { errors in
                try await Device.withDefaultDevice(device) {
                    try await Self.generateSamples(loaded, text: piece, errors: errors)
                }
            }
            if index > 0 { samples += breath }
            samples += pieceSamples
        }
        Memory.clearCache()
        guard !samples.isEmpty else { throw NeuralSpeechEngineError.producedNoAudio }
        return RenderedSpeech(samples: samples, sampleRate: loaded.model.sampleRate)
    }

    /// The longest piece an autoregressive voice is given at once, in characters.
    static let maximumPieceCharacters = 260

    /// Sentences gathered into pieces of at most `maximumPieceCharacters`; a single longer
    /// sentence is split at commas, then at spaces.
    static func sentenceGroups(of text: String) -> [String] {
        var sentences: [String] = []
        text.enumerateSubstrings(in: text.startIndex..<text.endIndex, options: .bySentences) { sentence, _, _, _ in
            guard let sentence = sentence?.trimmingCharacters(in: .whitespacesAndNewlines), !sentence.isEmpty else { return }
            sentences += Self.split(sentence, separator: ",")
        }
        var groups: [String] = []
        for sentence in sentences {
            if let last = groups.last, last.count + 1 + sentence.count <= maximumPieceCharacters {
                groups[groups.count - 1] = last + " " + sentence
            } else {
                groups.append(sentence)
            }
        }
        return groups.isEmpty ? [text] : groups
    }

    private static func split(_ sentence: String, separator: Character) -> [String] {
        guard sentence.count > maximumPieceCharacters else { return [sentence] }
        var pieces: [String] = []
        var current = ""
        for word in sentence.split(separator: " ", omittingEmptySubsequences: true) {
            if !current.isEmpty, current.count + 1 + word.count > maximumPieceCharacters {
                pieces.append(current)
                current = ""
            }
            current += (current.isEmpty ? "" : " ") + word
            if separator == ",", word.hasSuffix(","), current.count > maximumPieceCharacters / 2 {
                pieces.append(current)
                current = ""
            }
        }
        if !current.isEmpty { pieces.append(current) }
        return pieces
    }

    /// Sampling kept conservative and bounded: a lower temperature and top-p, a penalty on
    /// repeated tokens, and at most about twice the tokens the text should need, so a voice
    /// that starts to babble stops instead of running on for a minute.
    static func generationParameters(for family: NeuralVoiceModelFamily, text: String,
                                     defaults: GenerateParameters) -> GenerateParameters {
        let expectedSeconds = ReadAloudRenderCheck.expectedDurationSeconds(for: text)
        switch family {
        case .pocketTTS:
            return defaults
        case .qwen3TTS:
            // 12.5 codec frames a second.
            return GenerateParameters(maxTokens: max(60, Int(expectedSeconds * 12.5 * 2)), temperature: 0.7, topP: 0.9,
                                      repetitionPenalty: 1.1)
        case .chatterboxTurbo:
            // Chatterbox caps its own speech tokens by text length and penalizes repeats.
            return GenerateParameters(temperature: 0.7, topP: 0.9)
        case .dia:
            // About 86 codec frames a second.
            return GenerateParameters(maxTokens: max(200, Int(expectedSeconds * 86 * 2)), temperature: 1.1, topP: 0.9)
        }
    }

    /// How much audio a streaming model decodes at a time. One second keeps each graphics
    /// command short: on a thermally throttled iPad Pro M1, iOS cancelled two-second decodes
    /// as "Impacting Interactivity" for about one passage in five.
    private static let streamingChunkSeconds = 1.0

    /// `errors.check()` runs before samples are read: reading an array whose computation
    /// failed (iOS refused the graphics work) dereferences a missing buffer and ends the app.
    private static func generateSamples(_ loaded: LoadedSpeechModel, text: String, errors: ErrorBox) async throws -> [Float] {
        let voice = loaded.voice
        let model = loaded.model
        let parameters = generationParameters(for: voice.modelFamily, text: text, defaults: model.defaultGenerationParameters)
        let audio: MLXArray
        switch voice.modelFamily {
        case .pocketTTS:
            audio = try await model.generate(text: text, voice: voice.speaker, refAudio: nil, refText: nil,
                                             language: nil, generationParameters: parameters)
        case .qwen3TTS:
            // Streaming decodes the speech codes a second at a time. Decoding a whole passage
            // at once needs memory that grows with its length: a 20-second passage passed the
            // iPad Pro M1's 5.4 GB limit and iOS ended the app.
            var samples: [Float] = []
            let stream = model.generateStream(text: text, voice: voice.speaker, refAudio: nil, refText: nil,
                                              language: "english", generationParameters: parameters,
                                              streamingInterval: Self.streamingChunkSeconds)
            for try await event in stream {
                guard case .audio(let chunk) = event else { continue }
                try errors.check()
                samples += chunk.asType(.float32).reshaped(-1).asArray(Float.self)
            }
            return samples
        case .chatterboxTurbo:
            audio = try await model.generate(text: text, voice: nil, refAudio: nil, refText: nil,
                                             language: nil, generationParameters: parameters)
        case .dia:
            audio = try await model.generate(text: "[S1] " + text, voice: nil, refAudio: nil, refText: nil,
                                             language: nil, generationParameters: parameters)
        }
        let flattened = audio.asType(.float32).reshaped(-1)
        eval(flattened)
        try errors.check()
        return flattened.asArray(Float.self)
    }
}

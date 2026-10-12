import Foundation
import HuggingFace
@preconcurrency import MLX
import MLXAudioCodecs
import MLXAudioCore
@preconcurrency import MLXLMCommon
import MLXNN
import MLXRandom

public enum DiaError: Error {
    case invalidRepo(String)
    case noAudio
}

/// GRAPHITE PATCH: a fixed speaker for Dia. Dia picks a new random voice for every request;
/// conditioning each request on a short clip of one voice, with its transcript, keeps that
/// voice, as Dia's own audio-prompt mechanism does in the Python implementation. The codes are
/// the clip's Descript codec codes, one row of `channels` codes per frame, without the delay.
public struct DiaVoicePrompt: Codable, Sendable {
    public let transcript: String
    public let frames: [[Int32]]

    public init(transcript: String, frames: [[Int32]]) {
        self.transcript = transcript
        self.frames = frames
    }
}

public final class DiaTTSModel: SpeechGenerationModel, @unchecked Sendable {
    /// GRAPHITE PATCH: when set, every request speaks in the prompt's voice.
    public var voicePrompt: DiaVoicePrompt?

    /// GRAPHITE PATCH: the codec codes of a 44.1 kHz mono clip, to build a `DiaVoicePrompt`.
    public func encodeVoicePrompt(samples: [Float], transcript: String) -> DiaVoicePrompt {
        let waveform = MLXArray(samples).reshaped([1, samples.count, 1])
        let codes = dac.encode(dac.preprocess(waveform)).1 // [1, codebooks, frames]
        let channels = config.data.channels
        let codeRows = codes[0, 0 ..< channels].asType(.int32)
        eval(codeRows)
        let flat = codeRows.asArray(Int32.self)
        let frameCount = codeRows.shape[1]
        let frames = (0 ..< frameCount).map { frame in (0 ..< channels).map { channel in flat[channel * frameCount + frame] } }
        return DiaVoicePrompt(transcript: transcript, frames: frames)
    }

    private let model: DiaModel
    private let dac: DescriptDAC
    private let config: DiaConfig

    public let sampleRate: Int

    private let cfgScale: Float = 3.0
    private let cfgFilterTopK: Int = 35

    init(model: DiaModel, dac: DescriptDAC, config: DiaConfig) {
        self.model = model
        self.dac = dac
        self.config = config
        self.sampleRate = config.model.sampleRate
    }

    public var defaultGenerationParameters: GenerateParameters {
        GenerateParameters(maxTokens: 3072, temperature: 1.3, topP: 0.95)
    }

    public static func fromPretrained(_ modelRepo: String, cache: HubCache = .default) async throws -> DiaTTSModel {
        guard let repoID = Repo.ID(rawValue: modelRepo) else { throw DiaError.invalidRepo(modelRepo) }
        let dir = try await ModelUtils.resolveOrDownloadModel(
            repoID: repoID, requiredExtension: ".safetensors",
            additionalMatchingPatterns: ["*.json"], cache: cache)

        let config = try JSONDecoder().decode(
            DiaConfig.self, from: Data(contentsOf: dir.appendingPathComponent("config.json")))
        let model = DiaModel(config)
        let weights = try MLX.loadArrays(url: dir.appendingPathComponent("model.safetensors"))
        try model.update(parameters: ModuleParameters.unflattened(weights), verify: .none)

        let dac = try await DescriptDAC.fromPretrained("mlx-community/descript-audio-codec-44khz", cache: cache)
        eval(model)
        return DiaTTSModel(model: model, dac: dac, config: config)
    }

    /// GRAPHITE PATCH: loads Dia and its Descript codec from folders already on disk, with no
    /// network access, so Graphite can use the files it downloaded and checked itself.
    public static func fromModelDirectory(_ modelDirectory: URL, codecDirectory: URL) throws -> DiaTTSModel {
        let config = try JSONDecoder().decode(
            DiaConfig.self, from: Data(contentsOf: modelDirectory.appendingPathComponent("config.json")))
        let model = DiaModel(config)
        let weights = try MLX.loadArrays(url: modelDirectory.appendingPathComponent("model.safetensors"))
        try model.update(parameters: ModuleParameters.unflattened(weights), verify: .none)
        let dac = try DescriptDAC.fromModelDirectory(codecDirectory)
        eval(model)
        return DiaTTSModel(model: model, dac: dac, config: config)
    }

    private func createAttnMask(_ qPad: MLXArray, _ kPad: MLXArray, causal: Bool) -> MLXArray {
        let pq = qPad.expandedDimensions(axis: 2)
        let pk = kPad.expandedDimensions(axis: 1)
        let bothNonPad = MLX.logicalAnd(pq, pk)
        let bothPad = MLX.logicalAnd(MLX.logicalNot(pq), MLX.logicalNot(pk))
        var mask = MLX.logicalOr(bothNonPad, bothPad)
        if causal {
            let tq = mask.shape[1], tk = mask.shape[2]
            let causal2d = MLX.tril(MLXArray.ones([tq, tk], dtype: .bool))
            mask = MLX.logicalAnd(mask, causal2d)
        }
        return mask.expandedDimensions(axis: 1)
    }

    private func prepareTextInput(_ text: String) -> (MLXArray, MLXArray, MLXArray, MLXArray) {
        let maxLen = config.data.textLength
        let pad = Int32(config.data.textPadValue)
        let replaced = text.replacingOccurrences(of: "[S1]", with: "\u{01}")
            .replacingOccurrences(of: "[S2]", with: "\u{02}")
        var tokens = Array(replaced.utf8).map { Int32($0) }
        if tokens.count >= maxLen {
            tokens = Array(tokens.prefix(maxLen))
        } else {
            tokens += Array(repeating: pad, count: maxLen - tokens.count)
        }
        let src = MLXArray(tokens).reshaped([1, maxLen])
        let positions = MLXArray((0 ..< maxLen).map { Int32($0) }).reshaped([1, maxLen])
        let paddingMask = MLX.notEqual(src, MLXArray(pad))
        let encMask = createAttnMask(paddingMask, paddingMask, causal: false)
        return (src, positions, paddingMask, encMask)
    }

    // Includes BOS and every generated frame; delay removal happens in DiaAudio.
    func generateCodes(_ text: String, temperature: Float, topP: Float, topK: Int, maxTokens: Int,
                       promptFrames: [[Int32]] = []) throws -> MLXArray {
        let numChannels = config.data.channels
        let bos = Int32(config.data.audioBosValue)
        let eos = Int32(config.data.audioEosValue)
        let padV = Int32(config.data.audioPadValue)
        let delay = config.data.delayPattern
        let maxDelay = delay.max() ?? 0

        let (condSrc, condPos, condPad, condEncMask) = prepareTextInput(text)
        let uncondSrc = MLXArray.zeros(like: condSrc)
        let src = MLX.concatenated([uncondSrc, condSrc], axis: 0)
        let positions = MLX.concatenated([condPos, condPos], axis: 0)
        let srcPad = MLX.concatenated([condPad, condPad], axis: 0)
        let encMask = MLX.concatenated([condEncMask, condEncMask], axis: 0)

        let encoderOut = model.encoder(src, srcPositions: positions, attnMask: encMask)
        let crossCache = model.decoder.precomputeCrossAttentionKV(encoderOut: encoderOut, srcPositions: positions)
        let selfCache = (0 ..< model.decoder.numLayers).map { _ in DiaKVCache() }

        var frames = [[Int32]]()
        frames.append([Int32](repeating: bos, count: numChannels))

        let tgtPad = MLXArray.ones([2, 1], dtype: .bool)
        let crossAttnMask = createAttnMask(tgtPad, srcPad, causal: false)

        // GRAPHITE PATCH: the voice prompt's frames, delayed per channel as generated frames
        // are, follow the BOS frame. All but the last are run through the decoder in one pass
        // to fill its self-attention cache; the loop then continues from the last one.
        var firstStep = 0
        if !promptFrames.isEmpty {
            let promptLength = promptFrames.count
            for time in 0 ..< promptLength {
                frames.append((0 ..< numChannels).map { channel in
                    time - delay[channel] >= 0 ? promptFrames[time - delay[channel]][channel] : bos
                })
            }
            let prefillCount = frames.count - 1
            let prefillFlat = frames[0 ..< prefillCount].flatMap { $0 }
            let prefillInput = MLX.concatenated([MLXArray(prefillFlat).reshaped([1, prefillCount, numChannels]),
                                                 MLXArray(prefillFlat).reshaped([1, prefillCount, numChannels])], axis: 0)
            let prefillPositions = MLXArray((0 ..< prefillCount).map { Int32($0) }).reshaped([1, prefillCount])
            let bothPositions = MLX.concatenated([prefillPositions, prefillPositions], axis: 0)
            let prefillPad = MLXArray.ones([2, prefillCount], dtype: .bool)
            let selfMask = createAttnMask(prefillPad, prefillPad, causal: true)
            let prefillCrossMask = createAttnMask(prefillPad, srcPad, causal: false)
            _ = model.decoder(prefillInput, encoderOut: encoderOut, tgtPositions: bothPositions, srcPositions: positions,
                              selfAttnMask: selfMask, crossAttnMask: prefillCrossMask,
                              selfAttentionCache: selfCache, crossAttentionCache: crossCache)
            for cache in selfCache { if let k = cache.k, let v = cache.v { eval(k, v) } }
            firstStep = prefillCount
        }

        var eosStep: Int?

        for step in firstStep ..< firstStep + maxTokens {
            try Task.checkCancellation()
            let currentFrame = frames[step]
            let inputFrame = MLXArray(currentFrame + currentFrame).reshaped([2, 1, numChannels])
            let tgtPos = MLXArray([Int32(step), Int32(step)]).reshaped([2, 1])

            let logits = model.decoder.decodeStep(
                inputFrame, tgtPos: tgtPos, encoderOut: encoderOut, crossAttnMask: crossAttnMask,
                selfAttentionCache: selfCache, crossAttentionCache: crossCache)

            let last = logits[0..., -1, 0..., 0...]
            let uncond = last[0]
            let cond = last[1]
            var cfg = cond + cfgScale * (cond - uncond)
            let v = cfg.shape[1]
            cfg = MLX.concatenated(
                [cfg[0..., 0 ..< 1025], MLXArray.full([numChannels, v - 1025], values: MLXArray(-Float.infinity))],
                axis: 1)

            let predArr = diaSampleChannels(cfg, temperature: temperature, topP: topP, topK: topK)
            eval(predArr)
            var frame = predArr.asArray(Int32.self)

            for c in 0 ..< numChannels where step - firstStep < delay[c] && promptFrames.isEmpty { frame[c] = bos }

            if eosStep == nil && frame[0] == eos { eosStep = step }
            if let eosStep {
                let stepAfterEos = step - eosStep
                for (i, d) in delay.enumerated() {
                    if stepAfterEos == d { frame[i] = eos } else if stepAfterEos > d { frame[i] = padV }
                }
            }

            frames.append(frame)
            if let eosStep, step - eosStep >= maxDelay { break }
        }

        let outCount = frames.count
        var flat = [Int32]()
        flat.reserveCapacity(outCount * numChannels)
        for c in 0..<numChannels {
            for frame in frames { flat.append(frame[c]) }
        }
        return MLXArray(flat).reshaped([numChannels, outCount])
    }

    public func generate(
        text: String, voice: String?, refAudio: sending MLXArray?, refText: String?,
        language: String?, generationParameters: GenerateParameters
    ) async throws -> sending MLXArray {
        let temperature = Float(generationParameters.temperature)
        let requested = generationParameters.maxTokens ?? config.data.audioLength
        let promptFrames = voicePrompt?.frames ?? []
        let maxTokens = max(1, min(requested, config.data.audioLength - promptFrames.count))
        let fullText = voicePrompt.map { prompt in prompt.transcript + " " + text } ?? text
        let codes = try generateCodes(
            fullText, temperature: temperature, topP: generationParameters.topP,
            topK: cfgFilterTopK, maxTokens: maxTokens, promptFrames: promptFrames)
        var codebook = try diaRevertCodebookDelay(
            codes, delayPattern: config.data.delayPattern,
            maxT: config.data.audioLength + promptFrames.count, channels: config.data.channels,
            eosValue: config.data.audioEosValue)
        // GRAPHITE PATCH: the prompt's own frames are not part of the answer.
        if !promptFrames.isEmpty {
            guard codebook.shape[2] > promptFrames.count else { throw DiaError.noAudio }
            codebook = codebook[0..., 0..., promptFrames.count...]
        }
        let audio = dac.decodeFromCodes(codebook)
        eval(audio)
        return audio.squeezed()
    }

    public func generateStream(
        text: String, voice: String?, refAudio: sending MLXArray?, refText: String?,
        language: String?, generationParameters: GenerateParameters
    ) -> sending AsyncThrowingStream<AudioGeneration, Error> {
        generateStream(
            text: text, voice: voice, refAudio: refAudio, refText: refText,
            language: language, generationParameters: generationParameters, streamingInterval: 2.0)
    }

    public func generateStream(
        text: String, voice: String?, refAudio: sending MLXArray?, refText: String?,
        language: String?, generationParameters: GenerateParameters, streamingInterval: Double
    ) -> sending AsyncThrowingStream<AudioGeneration, Error> {
        let (stream, continuation) = AsyncThrowingStream<AudioGeneration, Error>.makeStream()
        let refAudio = SendingBox(refAudio)
        let task = Task { @Sendable [weak self] in
            let refAudio = refAudio.take()
            guard let self else { continuation.finish(); return }
            do {
                let audio = try await self.generate(
                    text: text, voice: voice, refAudio: refAudio, refText: refText,
                    language: language, generationParameters: generationParameters)
                continuation.yield(.audio(audio))
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
        continuation.onTermination = { _ in task.cancel() }
        return stream
    }
}

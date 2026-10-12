import Foundation
import GraphiteCore

/// What a benchmark launch measures, read from the launch arguments
/// `-GraphiteVoiceBenchmark <passages|sustained|background>`,
/// `-GraphiteVoiceBenchmarkVoices <identifier,identifier>` and
/// `-GraphiteVoiceBenchmarkProcessor <graphics|central>`. It exists to measure voices on a
/// device; nothing in the ordinary app starts it.
public struct NeuralVoiceBenchmarkConfiguration: Sendable, Equatable {
    public enum Mode: String, Sendable, Codable {
        /// The three audition passages, once each, after a warm-up sentence.
        case passages
        /// A five-minute lecture note, passage by passage, to watch heat and speed over time.
        case sustained
        /// The lecture note on a loop while the app is sent to the background.
        case background
        /// One passage rendered, encoded as the audio cache does, and run through on-device
        /// speech recognition, to see whether word alignment works on this device.
        case alignment
    }

    public let mode: Mode
    public let voiceIdentifiers: [String]
    public let processor: NeuralSpeechProcessor

    public init(mode: Mode, voiceIdentifiers: [String], processor: NeuralSpeechProcessor) {
        self.mode = mode
        self.voiceIdentifiers = voiceIdentifiers
        self.processor = processor
    }

    public init?(arguments: [String]) {
        func value(after flag: String) -> String? {
            guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
            return arguments[index + 1]
        }
        guard let modeName = value(after: "-GraphiteVoiceBenchmark"), let mode = Mode(rawValue: modeName) else { return nil }
        self.mode = mode
        voiceIdentifiers = (value(after: "-GraphiteVoiceBenchmarkVoices") ?? "pocket-tts-alba")
            .split(separator: ",").map(String.init)
        processor = value(after: "-GraphiteVoiceBenchmarkProcessor").flatMap(NeuralSpeechProcessor.init(rawValue:)) ?? .graphics
    }
}

/// One rendered passage.
public struct NeuralVoicePassageMeasurement: Codable, Sendable {
    public var name: String
    public var characterCount: Int
    public var audioSeconds: Double
    public var wallSeconds: Double
    /// Rendering time divided by audio length; below 1 is faster than real time.
    public var realTimeFactor: Double
    public var peakFootprintBytes: UInt64
    public var availableBytesAfter: UInt64?
    public var thermalState: String
    public var applicationState: String
    public var secondsSinceStart: Double
    public var errorDescription: String?
}

/// One voice's run: loading, warm-up and every passage, written to disk after each step so a
/// termination for memory or heat still leaves the numbers up to that point.
public struct NeuralVoiceRunMeasurement: Codable, Sendable {
    public var voiceIdentifier: String
    public var mode: NeuralVoiceBenchmarkConfiguration.Mode
    public var processor: NeuralSpeechProcessor
    public var deviceModel: String
    public var physicalMemoryBytes: UInt64
    public var footprintAtStartBytes: UInt64
    public var availableBytesAtStart: UInt64?
    public var loadSeconds: Double?
    public var peakFootprintDuringLoadBytes: UInt64?
    public var footprintAfterLoadBytes: UInt64?
    public var warmUpSeconds: Double?
    public var passages: [NeuralVoicePassageMeasurement] = []
    public var stage: String
    public var errorDescription: String?
}

/// Measures voices on the device and writes the results and the audio into a folder that
/// `devicectl device copy from` can read.
public final class NeuralVoiceBenchmark: Sendable {
    public static let auditionPassages: [(name: String, text: String)] = [
        ("a_lecture", "Modern GPUs use SIMD execution, while a multi-core CPU is closer to MIMD. In SIMDRAM, the DRAM itself performs bulk bitwise operations, which avoids moving data across the memory bus. Compared with SRAM, DRAM is denser but slower, and ROM keeps its contents without power."),
        ("b_math", "The delay scales as R times C, so halving the resistance cuts the delay in half."),
        ("c_expressive", "Okay, here's the trick: instead of fetching every operand, we let the memory do the work. Sounds weird? It's actually how SIMDRAM gets its speed.")
    ]

    private let configuration: NeuralVoiceBenchmarkConfiguration
    private let manifest: NeuralVoiceManifest
    private let voicesFolder: URL
    private let outputFolder: URL
    private let applicationState: @Sendable () async -> String
    private let deviceModel: String

    public init(configuration: NeuralVoiceBenchmarkConfiguration, manifest: NeuralVoiceManifest, voicesFolder: URL,
                outputFolder: URL, deviceModel: String, applicationState: @escaping @Sendable () async -> String) {
        self.configuration = configuration
        self.manifest = manifest
        self.voicesFolder = voicesFolder
        self.outputFolder = outputFolder
        self.deviceModel = deviceModel
        self.applicationState = applicationState
    }

    /// Runs every requested voice in turn; `report` receives one line per step for the screen.
    public func run(report: @escaping @Sendable (String) -> Void) async {
        try? FileManager.default.createDirectory(at: outputFolder, withIntermediateDirectories: true)
        for identifier in configuration.voiceIdentifiers {
            guard let voice = manifest.voice(identifier: identifier) else {
                report("Unknown voice \(identifier)")
                continue
            }
            await run(voice, report: report)
        }
        appendLog("finished all voices")
        report("Finished.")
    }

    private func runAlignment(_ voice: NeuralVoiceDescription, report: @escaping @Sendable (String) -> Void) async {
        let text = Self.auditionPassages[0].text
        do {
            let engine = NeuralSpeechEngine()
            try await engine.load(voice, from: voicesFolder.appendingPathComponent(voice.id))
            let speech = try await engine.render(text)
            await engine.unload()
            let cache = ReadAloudAudioCache(folder: outputFolder.appendingPathComponent("alignment-cache"))
            let key = ReadAloudAudioCacheKey(text: text, voiceIdentifier: voice.id, voiceRevision: "benchmark")
            let file = try await cache.writeAudio(speech, for: key)
            let start = Date()
            switch await OnDeviceSpeechAlignment().recognize(file, language: "en") {
            case .success(let words):
                let timings = ReadAloudWordAlignment.align(passage: text, recognized: words, audioDurationSeconds: speech.durationSeconds)
                let line = "alignment: \(words.count) words heard in \(String(format: "%.1f", Date().timeIntervalSince(start))) s, \(timings == nil ? "not matched" : "matched \(timings?.count ?? 0) words"); first: \(words.prefix(6).map { "\($0.text)@\(String(format: "%.2f", $0.startSeconds))" }.joined(separator: " "))"
                appendLog(line); report(line)
            case .failure(let failure):
                appendLog("alignment failed: \(failure)"); report("alignment failed: \(failure)")
            }
        } catch {
            appendLog("alignment run failed: \(error)"); report("alignment run failed: \(error)")
        }
    }

    private func run(_ voice: NeuralVoiceDescription, report: @escaping @Sendable (String) -> Void) async {
        if configuration.mode == .alignment { await runAlignment(voice, report: report); return }
        let runName = "\(configuration.mode.rawValue)-\(voice.id)-\(configuration.processor.rawValue)"
        let audioFolder = outputFolder.appendingPathComponent(runName)
        try? FileManager.default.createDirectory(at: audioFolder, withIntermediateDirectories: true)
        var measurement = NeuralVoiceRunMeasurement(
            voiceIdentifier: voice.id, mode: configuration.mode, processor: configuration.processor,
            deviceModel: deviceModel, physicalMemoryBytes: ProcessResources.physicalMemoryBytes,
            footprintAtStartBytes: ProcessResources.footprintBytes(),
            availableBytesAtStart: ProcessResources.availableBytesBeforeTermination(), stage: "loading")
        let resultFile = outputFolder.appendingPathComponent("\(runName).json")
        save(measurement, to: resultFile)
        appendLog("\(runName): loading")
        report("\(voice.name): loading…")

        let engine = NeuralSpeechEngine()
        let sampler = PeakFootprintSampler()
        let start = Date()
        do {
            let loadStart = Date()
            try await engine.load(voice, from: voicesFolder.appendingPathComponent(voice.id))
            measurement.loadSeconds = Date().timeIntervalSince(loadStart)
            measurement.peakFootprintDuringLoadBytes = sampler.takePeakBytes()
            measurement.footprintAfterLoadBytes = ProcessResources.footprintBytes()
            measurement.stage = "warming up"
            save(measurement, to: resultFile)
            report("\(voice.name): loaded in \(String(format: "%.1f", measurement.loadSeconds ?? 0)) s")

            let warmUpStart = Date()
            _ = try await engine.render("Hello there.", on: configuration.processor)
            measurement.warmUpSeconds = Date().timeIntervalSince(warmUpStart)
            measurement.stage = "rendering"
            save(measurement, to: resultFile)

            for (name, text) in passages() {
                let passageStart = Date()
                var passage = NeuralVoicePassageMeasurement(
                    name: name, characterCount: text.count, audioSeconds: 0, wallSeconds: 0, realTimeFactor: 0,
                    peakFootprintBytes: 0, availableBytesAfter: nil, thermalState: ProcessResources.thermalStateName,
                    applicationState: await applicationState(), secondsSinceStart: 0)
                do {
                    let speech = try await engine.render(text, on: configuration.processor)
                    passage.wallSeconds = Date().timeIntervalSince(passageStart)
                    passage.audioSeconds = speech.durationSeconds
                    passage.realTimeFactor = speech.durationSeconds > 0 ? passage.wallSeconds / speech.durationSeconds : 0
                    try? PCMWaveFile.encode(samples: speech.samples, sampleRate: speech.sampleRate)
                        .write(to: audioFolder.appendingPathComponent("\(name).wav"))
                } catch {
                    passage.wallSeconds = Date().timeIntervalSince(passageStart)
                    passage.errorDescription = String(describing: error)
                }
                passage.peakFootprintBytes = sampler.takePeakBytes()
                passage.availableBytesAfter = ProcessResources.availableBytesBeforeTermination()
                passage.thermalState = ProcessResources.thermalStateName
                passage.secondsSinceStart = Date().timeIntervalSince(start)
                measurement.passages.append(passage)
                save(measurement, to: resultFile)
                let line = "\(name): audio \(String(format: "%.1f", passage.audioSeconds)) s, real-time factor \(String(format: "%.2f", passage.realTimeFactor)), \(passage.thermalState), \(passage.applicationState)\(passage.errorDescription.map { " error \($0)" } ?? "")"
                appendLog("\(runName): \(line)")
                report("\(voice.name) \(line)")
            }
            measurement.stage = "finished"
        } catch {
            measurement.errorDescription = String(describing: error)
            measurement.stage = "failed"
            appendLog("\(runName): failed \(error)")
            report("\(voice.name) failed: \(error)")
        }
        save(measurement, to: resultFile)
        await engine.unload()
    }

    /// The passages for the configured mode. The sustained and background note comes from
    /// `sustained-note.txt` in the output folder, one passage per line, copied there with the
    /// voices; the background run repeats it to keep rendering for about ten minutes.
    private func passages() -> [(name: String, text: String)] {
        switch configuration.mode {
        case .passages, .alignment:
            return Self.auditionPassages
        case .sustained, .background:
            let noteFile = outputFolder.appendingPathComponent("sustained-note.txt")
            let lines = ((try? String(contentsOf: noteFile, encoding: .utf8)) ?? "")
                .split(separator: "\n").map(String.init).filter { line in !line.isEmpty }
            let repetitions = configuration.mode == .background ? 3 : 1
            return (0..<repetitions).flatMap { repetition in
                lines.enumerated().map { index, line in (String(format: "note_%d_%02d", repetition, index), line) }
            }
        }
    }

    private func save(_ measurement: NeuralVoiceRunMeasurement, to file: URL) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? encoder.encode(measurement).write(to: file, options: .atomic)
    }

    private func appendLog(_ line: String) {
        let logFile = outputFolder.appendingPathComponent("log.txt")
        let stamped = "\(ISO8601DateFormatter().string(from: Date())) \(line)\n"
        if let handle = try? FileHandle(forWritingTo: logFile) {
            handle.seekToEndOfFile()
            handle.write(Data(stamped.utf8))
            try? handle.close()
        } else {
            try? Data(stamped.utf8).write(to: logFile)
        }
    }
}

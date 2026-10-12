import Foundation
import AVFoundation
import CoreMedia
import Speech
import GraphiteCore

/// Finds the words in rendered speech and when they are said, for the word highlight.
public protocol ReadAloudSpeechAligning: Sendable {
    /// The recognized words with their times, or nil when recognition is not available here.
    func recognizedWords(in audioFile: URL, language: String) async -> [ReadAloudRecognizedWord]?
}

/// Apple's on-device speech recognition (SpeechAnalyzer, iOS and macOS 26 and later) run on a
/// rendered passage. Nothing leaves the device. On earlier systems, or when the language's
/// recognition model is not installed and cannot be installed, it returns nil and the reader
/// highlights whole passages.
public struct OnDeviceSpeechAlignment: ReadAloudSpeechAligning {
    public init() {}

    public func recognizedWords(in audioFile: URL, language: String) async -> [ReadAloudRecognizedWord]? {
        switch await recognize(audioFile, language: language) {
        case .success(let words): words
        case .failure: nil
        }
    }

    /// Why recognition gave no words, for the measuring screen and the logs.
    public enum Failure: Error, CustomStringConvertible {
        case needsNewerSystem
        case transcriberUnavailable
        case unsupportedLanguage(String)
        case failed(String)

        public var description: String {
            switch self {
            case .needsNewerSystem: "needs iOS or macOS 26"
            case .transcriberUnavailable: "SpeechTranscriber is not available on this device"
            case .unsupportedLanguage(let language): "no recognition model for \(language)"
            case .failed(let message): message
            }
        }
    }

    public func recognize(_ audioFile: URL, language: String) async -> Result<[ReadAloudRecognizedWord], Failure> {
        guard #available(iOS 26, macOS 26, *) else { return .failure(.needsNewerSystem) }
        do {
            return .success(try await Self.transcribe(audioFile, language: language))
        } catch let failure as Failure {
            return .failure(failure)
        } catch {
            return .failure(.failed(String(describing: error)))
        }
    }

    @available(iOS 26, macOS 26, *)
    private static func transcribe(_ audioFile: URL, language: String) async throws -> [ReadAloudRecognizedWord] {
        // "en" alone matched Singapore English on a Mac; a region is added from the device
        // when it speaks the language, otherwise the language's main region.
        let requested = Self.regionalLocale(for: language)
        if SpeechTranscriber.isAvailable {
            guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: requested) else {
                throw Failure.unsupportedLanguage(language)
            }
            let transcriber = SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [], attributeOptions: [.audioTimeRange])
            return try await analyze(audioFile, module: transcriber, results: transcriber.results.map(\.text))
        }
        // Devices without the newer transcription model still have dictation's, which also
        // reports when each word was said.
        guard let locale = await DictationTranscriber.supportedLocale(equivalentTo: requested) else {
            throw Failure.transcriberUnavailable
        }
        let transcriber = DictationTranscriber(locale: locale, contentHints: [], transcriptionOptions: [], reportingOptions: [], attributeOptions: [.audioTimeRange])
        return try await analyze(audioFile, module: transcriber, results: transcriber.results.map(\.text))
    }

    @available(iOS 26, macOS 26, *)
    private static func analyze<Results: AsyncSequence>(_ audioFile: URL, module: any SpeechModule, results: Results) async throws
        -> [ReadAloudRecognizedWord] where Results.Element == AttributedString {
        // The recognition model for a language is a system download shared by every app; it is
        // fetched once if missing, from Apple, like a keyboard dictionary.
        if let installation = try await AssetInventory.assetInstallationRequest(supporting: [module]) {
            try await installation.downloadAndInstall()
        }
        let file = try AVAudioFile(forReading: audioFile)
        let analyzer = try await SpeechAnalyzer(inputAudioFile: file, modules: [module], finishAfterFile: true)
        var words: [ReadAloudRecognizedWord] = []
        for try await text in results {
            for run in text.runs {
                guard let timeRange = run.audioTimeRange else { continue }
                words += split(String(text[run.range].characters), start: timeRange.start.seconds, end: timeRange.end.seconds)
            }
        }
        _ = analyzer
        return words
    }

    static func regionalLocale(for language: String) -> Locale {
        let requested = Locale(identifier: language)
        guard requested.region == nil, let code = requested.language.languageCode?.identifier else { return requested }
        if Locale.current.language.languageCode?.identifier == code, let region = Locale.current.region?.identifier {
            return Locale(identifier: "\(code)_\(region)")
        }
        return Locale(identifier: code == "en" ? "en_US" : code)
    }

    /// A timed run can hold more than one word; its time is shared out by word length.
    static func split(_ text: String, start: Double, end: Double) -> [ReadAloudRecognizedWord] {
        let parts = text.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !parts.isEmpty, start.isFinite, end.isFinite else { return [] }
        let totalLength = Double(parts.reduce(0) { total, part in total + part.count })
        var cursor = start
        return parts.map { part in
            let share = totalLength > 0 ? (end - start) * Double(part.count) / totalLength : 0
            defer { cursor += share }
            return ReadAloudRecognizedWord(text: part, startSeconds: cursor, endSeconds: cursor + share)
        }
    }
}

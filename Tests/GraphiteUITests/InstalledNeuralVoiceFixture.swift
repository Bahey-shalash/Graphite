import XCTest
import GraphiteCore
import GraphiteApple
@testable import GraphiteVoices

/// The system voice behind High Quality reading, with the answers a test chooses.
@MainActor
final class ScriptedQuickSpeech: ReadAloudSpeaking {
    var eventHandler: (@MainActor (ReadAloudSpeechEvent) -> Void)?
    let voices = [ReadAloudVoice(id: "test", name: "Test", language: "en-US", quality: 3)]
    var assistiveSpeechSettingsMayApply = false
    func speak(_ text: String, voiceIdentifier: String, speed: Double, requestIdentifier: UUID) throws {}
    func pause() -> Bool { true }
    func resume() -> Bool { true }
    func stop() {}
}

/// A neural voice that counts as installed, in a temporary folder, with a library, a
/// preparation that renders with `renderer`, and the High Quality speech built from them.
@MainActor
struct InstalledNeuralVoiceFixture {
    let folder: URL
    let voice: ReadAloudPassagePreparation.Voice
    let library: NeuralVoiceLibrary
    let preparation: ReadAloudPassagePreparation
    let quickSpeech: ScriptedQuickSpeech
    let speech: NeuralReadAloudSpeech

    /// With `isInstalled` false the library holds no downloaded voice, so reading is Quick.
    init(isInstalled: Bool = true, renderer: any NeuralPassageRendering = UnusedPassageRenderer(),
         testCase: XCTestCase) throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("NeuralVoiceFixture-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let folderToRemove = folder
        testCase.addTeardownBlock { try? FileManager.default.removeItem(at: folderToRemove) }
        let description = NeuralVoiceDescription(
            id: "test-voice", name: "Test Voice", modelName: "Test model", modelFamily: .pocketTTS, speaker: nil, language: "en",
            qualityNote: "A test voice.", license: NeuralVoiceLicense(name: "Test", address: URL(string: "https://example.com/license")!),
            sources: [NeuralVoiceSource(repository: "test/voice", revision: "r1", files: [])],
            platforms: ["macOS", "iOS"], minimumPhysicalMemoryBytes: 0)
        let manifest = NeuralVoiceManifest(downloadHost: URL(string: "https://example.com")!, voices: [description])
        let installation = NeuralVoiceInstallation(voicesFolder: folder.appendingPathComponent("Voices", isDirectory: true))
        if isInstalled {
            try FileManager.default.createDirectory(at: installation.stagingFolder(of: description), withIntermediateDirectories: true)
            try installation.finishInstalling(description)
        }
        let preferences = try XCTUnwrap(UserDefaults(suiteName: "NeuralVoiceFixture-\(UUID().uuidString)"))
        library = NeuralVoiceLibrary(manifest: manifest, installation: installation,
                                     audioCache: ReadAloudAudioCache(folder: folder.appendingPathComponent("Audio", isDirectory: true)),
                                     preferences: preferences, platform: "macOS", physicalMemoryBytes: 8 * 1_024 * 1_024 * 1_024,
                                     startsDownloader: false)
        voice = ReadAloudPassagePreparation.Voice(description: description, folder: installation.folder(of: description))
        preparation = ReadAloudPassagePreparation(cache: library.audioCache, renderer: renderer, aligner: NoSpeechAlignment())
        quickSpeech = ScriptedQuickSpeech()
        speech = NeuralReadAloudSpeech(quick: quickSpeech, library: library, preparation: preparation)
    }
}

/// For tests that never render.
struct UnusedPassageRenderer: NeuralPassageRendering {
    func render(_ text: String, voice: NeuralVoiceDescription, voiceFolder: URL, seed: UInt64?) async throws -> RenderedSpeech {
        throw CocoaError(.featureUnsupported)
    }
    func releaseResources() async {}
}

struct NoSpeechAlignment: ReadAloudSpeechAligning {
    func recognizedWords(in audioFile: URL, language: String) async -> [ReadAloudRecognizedWord]? { nil }
}

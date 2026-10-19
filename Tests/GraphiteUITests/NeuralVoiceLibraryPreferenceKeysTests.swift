import XCTest
import GraphiteCore
import GraphiteApple
@testable import GraphiteVoices

/// What `NeuralVoiceLibrary` keeps on the device: the voice chosen, the quality mode and
/// whether unprepared passages are read quickly, under these names.
@MainActor
final class NeuralVoiceLibraryPreferenceKeysTests: XCTestCase {
    private var suiteName = ""
    private var preferences: UserDefaults!
    private var folder: URL!

    override func setUp() async throws {
        suiteName = "NeuralVoiceLibraryPreferenceKeysTests-\(UUID().uuidString)"
        preferences = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("NeuralVoiceLibraryPreferenceKeysTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() async throws {
        preferences.removePersistentDomain(forName: suiteName)
        preferences = nil
        try? FileManager.default.removeItem(at: folder) // Best-effort removal of a temporary folder.
    }

    /// The library over one installed voice; calling it again gives a new library over the same folder and store.
    private func makeLibrary() throws -> NeuralVoiceLibrary {
        let description = Self.voiceDescription
        let manifest = NeuralVoiceManifest(downloadHost: URL(string: "https://example.com")!, voices: [description])
        let installation = NeuralVoiceInstallation(voicesFolder: folder.appendingPathComponent("Voices", isDirectory: true))
        if !FileManager.default.fileExists(atPath: installation.folder(of: description).path) {
            try FileManager.default.createDirectory(at: installation.stagingFolder(of: description), withIntermediateDirectories: true)
            try installation.finishInstalling(description)
        }
        return NeuralVoiceLibrary(manifest: manifest, installation: installation,
                                  audioCache: ReadAloudAudioCache(folder: folder.appendingPathComponent("Audio", isDirectory: true)),
                                  preferences: preferences, platform: "macOS", physicalMemoryBytes: 8 * 1_024 * 1_024 * 1_024,
                                  startsDownloader: false)
    }

    private static let voiceDescription = NeuralVoiceDescription(
        id: "test-voice", name: "Test Voice", modelName: "Test model", modelFamily: .pocketTTS, speaker: nil, language: "en",
        qualityNote: "A test voice.", license: NeuralVoiceLicense(name: "Test", address: URL(string: "https://example.com/license")!),
        sources: [NeuralVoiceSource(repository: "test/voice", revision: "r1", files: [])],
        platforms: ["macOS", "iOS"], minimumPhysicalMemoryBytes: 0)

    func testAnEmptyStoreChoosesNoModeNoVoiceAndReadsNothingQuickly() throws {
        let library = try makeLibrary()

        XCTAssertNil(library.chosenMode)
        XCTAssertFalse(library.readsUnpreparedPassagesQuickly)
        XCTAssertEqual(library.mode, .highQuality, "With a downloaded voice and no choice, reading is High Quality.")
    }

    func testTheQualityModeIsStoredAsItsRawValueAndReadBack() throws {
        XCTAssertEqual(ReadAloudQualityMode.allCases.map(\.rawValue), ["highQuality", "quick"])
        let library = try makeLibrary()

        library.chooseMode(.quick)

        XCTAssertEqual(preferences.string(forKey: "GraphiteReadAloudQualityMode"), "quick")
        XCTAssertEqual(try makeLibrary().chosenMode, .quick)
    }

    func testReadingUnpreparedPassagesQuicklyIsStoredAsABoolean() throws {
        let library = try makeLibrary()

        library.readsUnpreparedPassagesQuickly = true

        XCTAssertEqual(preferences.object(forKey: "GraphiteReadAloudReadsUnpreparedPassagesQuickly") as? Bool, true)
        XCTAssertTrue(try makeLibrary().readsUnpreparedPassagesQuickly)
    }

    func testTheChosenVoiceIsStoredAsItsIdentifierAndRemovedWhenTheVoiceIsDeleted() throws {
        let library = try makeLibrary()
        let description = Self.voiceDescription

        library.selectVoice(description)

        XCTAssertEqual(preferences.string(forKey: "GraphiteReadAloudNeuralVoice"), "test-voice")
        XCTAssertEqual(try makeLibrary().selectedVoiceIdentifier, "test-voice")
        library.delete(description)
        XCTAssertNil(preferences.object(forKey: "GraphiteReadAloudNeuralVoice"))
    }
}

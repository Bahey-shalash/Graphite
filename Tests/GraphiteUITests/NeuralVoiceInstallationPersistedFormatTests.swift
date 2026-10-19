import XCTest
import GraphiteCore
import GraphiteVoices

/// Where a downloaded voice's files sit and how the app knows a voice is complete: one folder
/// per voice identifier, a `.partial` staging folder beside it while downloading, and a marker
/// file naming `repository@revision` per source. Voices installed by earlier builds are
/// recognized by this marker, so its text never changes.
final class NeuralVoiceInstallationPersistedFormatTests: XCTestCase {
    private var voicesFolder: URL!

    override func setUpWithError() throws {
        voicesFolder = FileManager.default.temporaryDirectory.appendingPathComponent("NeuralVoiceInstallation-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: voicesFolder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: voicesFolder) // Best-effort removal of a temporary folder.
    }

    private func makeVoice(identifier: String = "test-voice") -> NeuralVoiceDescription {
        NeuralVoiceDescription(
            id: identifier, name: "Test Voice", modelName: "Test model", modelFamily: .pocketTTS, speaker: nil, language: "en",
            qualityNote: "A test voice.", license: NeuralVoiceLicense(name: "Test", address: URL(string: "https://example.com/license")!),
            sources: [
                NeuralVoiceSource(repository: "owner/model", revision: "abc123", files: [
                    NeuralVoiceFile(path: "weights.safetensors", byteCount: 4, sha256: String(repeating: "0", count: 64))
                ]),
                NeuralVoiceSource(repository: "owner/codec", revision: "def456", files: [
                    NeuralVoiceFile(path: "codec.safetensors", byteCount: 4, sha256: String(repeating: "1", count: 64),
                                    destinationPath: "codec/model.safetensors")
                ])
            ],
            platforms: ["macOS", "iOS"], minimumPhysicalMemoryBytes: 0)
    }

    private func stageEveryFile(of voice: NeuralVoiceDescription, in installation: NeuralVoiceInstallation) throws {
        for file in voice.files {
            let location = installation.stagingFolder(of: voice).appendingPathComponent(file.localPath)
            try FileManager.default.createDirectory(at: location.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("data".utf8).write(to: location)
        }
    }

    func testAVoiceLivesInAFolderNamedByItsIdentifierAndDownloadsIntoAPartialFolderBesideIt() {
        let installation = NeuralVoiceInstallation(voicesFolder: voicesFolder)
        let voice = makeVoice()

        XCTAssertEqual(installation.folder(of: voice), voicesFolder.appendingPathComponent("test-voice", isDirectory: true))
        XCTAssertEqual(installation.stagingFolder(of: voice), voicesFolder.appendingPathComponent("test-voice.partial", isDirectory: true))
    }

    func testInstallingMovesTheStagedFilesIntoPlaceAndWritesTheRepositoryAtRevisionMarker() throws {
        let installation = NeuralVoiceInstallation(voicesFolder: voicesFolder)
        let voice = makeVoice()
        try stageEveryFile(of: voice, in: installation)
        XCTAssertFalse(installation.isInstalled(voice), "A staged voice is not installed.")

        try installation.finishInstalling(voice)

        let marker = try String(contentsOf: installation.folder(of: voice).appendingPathComponent(".graphite-installed"), encoding: .utf8)
        XCTAssertEqual(marker, "owner/model@abc123\nowner/codec@def456")
        XCTAssertTrue(installation.isInstalled(voice))
        XCTAssertTrue(FileManager.default.fileExists(atPath: installation.folder(of: voice).appendingPathComponent("weights.safetensors").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: installation.folder(of: voice).appendingPathComponent("codec/model.safetensors").path),
                      "A file with a destination path is installed there.")
        XCTAssertFalse(FileManager.default.fileExists(atPath: installation.stagingFolder(of: voice).path))
    }

    func testAVoiceWhoseMarkerNamesOtherRevisionsIsNotInstalled() throws {
        let installation = NeuralVoiceInstallation(voicesFolder: voicesFolder)
        let voice = makeVoice()
        try stageEveryFile(of: voice, in: installation)
        try installation.finishInstalling(voice)
        let markerLocation = installation.folder(of: voice).appendingPathComponent(".graphite-installed")

        try Data("owner/model@abc123".utf8).write(to: markerLocation)
        XCTAssertFalse(installation.isInstalled(voice), "A marker of the first source alone is not the voice's marker.")
        try Data("owner/model@abc123\nowner/codec@def456\n".utf8).write(to: markerLocation)
        XCTAssertFalse(installation.isInstalled(voice), "A trailing line break is not part of the marker.")
        try Data("owner/model@abc123\nowner/codec@def456".utf8).write(to: markerLocation)
        XCTAssertTrue(installation.isInstalled(voice))
    }

    func testAVoiceMissingOneOfItsFilesIsNotInstalled() throws {
        let installation = NeuralVoiceInstallation(voicesFolder: voicesFolder)
        let voice = makeVoice()
        try stageEveryFile(of: voice, in: installation)
        try installation.finishInstalling(voice)

        try FileManager.default.removeItem(at: installation.folder(of: voice).appendingPathComponent("codec/model.safetensors"))

        XCTAssertFalse(installation.isInstalled(voice))
    }

    func testInstallingRefusesAStagingFolderThatLacksAFile() throws {
        let installation = NeuralVoiceInstallation(voicesFolder: voicesFolder)
        let voice = makeVoice()
        try stageEveryFile(of: voice, in: installation)
        try FileManager.default.removeItem(at: installation.stagingFolder(of: voice).appendingPathComponent("weights.safetensors"))

        XCTAssertThrowsError(try installation.finishInstalling(voice))
        XCTAssertFalse(installation.isInstalled(voice))
        XCTAssertTrue(FileManager.default.fileExists(atPath: installation.stagingFolder(of: voice).path), "What was downloaded stays to be completed.")
    }
}

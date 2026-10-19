import XCTest
import AVFoundation
import GraphiteCore
@testable import GraphiteIndex
@testable import GraphiteApple
@testable import GraphiteUI

/// The name a recording gets when it is saved from the recovery folder and no one knows
/// where it was meant to go.
@MainActor
final class WorkspaceRecordingRecoveryNamingTests: XCTestCase {
    private var temporaryFolders: [URL] = []

    override func tearDown() async throws {
        for folder in temporaryFolders { try? FileManager.default.removeItem(at: folder) }
        temporaryFolders = []
    }

    private func makeFolder(_ prefix: String) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        temporaryFolders.append(folder)
        return folder.resolvingSymlinksInPath()
    }

    private func makeWorkspace(_ vault: URL) async throws -> WorkspaceModel {
        let workspace = WorkspaceModel()
        workspace.folderAccess = FolderAccess(root: vault)
        let store = VaultStore(root: vault)
        workspace.store = store
        workspace.vaultSettings = try await store.settings()
        workspace.index = try VaultIndex(databaseURL: try makeFolder("RecoveryNamingIndex").appendingPathComponent("index.sqlite"))
        return workspace
    }

    /// A second of silence in an audio file the recovery folder keeps while recording.
    private func makeUnfinishedAudio(in folder: URL) throws -> URL {
        let location = folder.appendingPathComponent("\(UUID().uuidString).caf")
        let format = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 44_100, channels: 1, interleaved: true))
        let file = try AVAudioFile(forWriting: location, settings: format.settings, commonFormat: .pcmFormatInt16, interleaved: true)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 44_100))
        buffer.frameLength = 44_100
        try file.write(from: buffer)
        return location
    }

    /// 2026-03-05 23:30:00 UTC: a later calendar day in every time zone east of Greenwich.
    private let lateEveningInGreenwich = Date(timeIntervalSinceReferenceDate: 794_446_200)

    func testARecordingWithNoKnownDestinationIsNamedAfterTheIsoDateItStartedOnInUniversalTime() async throws {
        let vault = try makeFolder("RecoveryNamingVault")
        let workspace = try await makeWorkspace(vault)
        let unfinished = RecoverableRecording(mediaLocation: try makeUnfinishedAudio(in: try makeFolder("RecoveryNamingFolder")), manifest: nil,
                                              startedAt: lateEveningInGreenwich, byteCount: 100_000)

        await workspace.recover(unfinished)

        XCTAssertNil(workspace.errorMessage)
        XCTAssertEqual(workspace.selection?.name, "Recovered recording 2026-03-05.m4a")
        let savedPath = try XCTUnwrap(workspace.selection)
        XCTAssertTrue(FileManager.default.fileExists(atPath: try savedPath.url(in: vault).path))
    }

    func testASecondRecoveryOfTheSameDayIsNamedBesideTheFirst() async throws {
        let vault = try makeFolder("RecoveryNamingVault")
        let workspace = try await makeWorkspace(vault)
        let folder = try makeFolder("RecoveryNamingFolder")
        for _ in 0..<2 {
            let unfinished = RecoverableRecording(mediaLocation: try makeUnfinishedAudio(in: folder), manifest: nil,
                                                  startedAt: lateEveningInGreenwich, byteCount: 100_000)
            await workspace.recover(unfinished)
        }

        XCTAssertNil(workspace.errorMessage)
        XCTAssertEqual(workspace.selection?.name, "Recovered recording 2026-03-05 1.m4a")
    }
}

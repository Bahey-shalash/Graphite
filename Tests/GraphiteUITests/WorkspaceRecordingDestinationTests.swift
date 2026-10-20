import XCTest
import CoreMedia
import GraphiteCore
@testable import GraphiteIndex
@testable import GraphiteApple
@testable import GraphiteUI
import GraphiteTestSupport

/// A camera and microphone that start without delivering anything: enough for a video
/// recording to begin, so the workspace's choice of destination can be seen.
private final class SilentCaptureSource: VideoCaptureSource, @unchecked Sendable {
    func start(camera: CameraPosition, deliveringOn deliveryQueue: DispatchQueue,
               samples: @escaping @Sendable (CMSampleBuffer, CaptureMediaKind) -> Void,
               events: @escaping @Sendable (VideoCaptureEvent) -> Void) async throws {}
    func availableCameras() async -> [CameraPosition] { [.back] }
    func switchCamera(to camera: CameraPosition) async throws {}
    func resumeAfterInterruption() async throws {}
    func stop() async {}
}

/// Where a lecture recording goes and what is inserted into the note it was started from: the
/// note's attachment folder (the current folder when no note is open), under a name made of the
/// note and the start time, and an embed in that note when it is still open.
@MainActor
final class WorkspaceRecordingDestinationTests: XCTestCase {

    private func makeFolder(_ prefix: String) throws -> URL {
        let folder = try TemporaryVault.make(prefix: prefix, for: self).root
        return folder.resolvingSymlinksInPath()
    }

    private func makeVault(attachmentFolderPath: String?) throws -> URL {
        let vault = try makeFolder("RecordingDestinationVault")
        try FileManager.default.createDirectory(at: vault.appendingPathComponent("Course"), withIntermediateDirectories: true)
        try Data("# Lecture\n\nNotes.\n".utf8).write(to: vault.appendingPathComponent("Course/Lecture.md"))
        if let attachmentFolderPath {
            try FileManager.default.createDirectory(at: vault.appendingPathComponent(".obsidian"), withIntermediateDirectories: true)
            try Data(#"{"attachmentFolderPath": "\#(attachmentFolderPath)"}"#.utf8).write(to: vault.appendingPathComponent(".obsidian/app.json"))
        }
        return vault
    }

    private struct Fixture {
        let workspace: WorkspaceModel
        let vault: URL
        let recoveryFolder: URL
    }

    private func makeFixture(attachmentFolderPath: String?, opensTheNote: Bool = true) async throws -> Fixture {
        let vault = try makeVault(attachmentFolderPath: attachmentFolderPath)
        let index = try VaultIndex(databaseURL: try makeFolder("RecordingDestinationIndex").appendingPathComponent("index.sqlite"))
        _ = try await index.reconcile(root: vault)
        let workspace = WorkspaceModel()
        workspace.folderAccess = FolderAccess(root: vault)
        let store = VaultStore(root: vault)
        workspace.store = store
        workspace.index = index
        workspace.vaultSettings = try await store.settings()
        workspace.hasCompletedIndexScan = true
        let recoveryFolder = try makeFolder("RecordingDestinationRecovery")
        workspace.recording.recoveryFolderLocation = { recoveryFolder }
        workspace.recording.makeVideoCaptureSource = { SilentCaptureSource() }
        if opensTheNote { _ = await workspace.open(try VaultPath("Course/Lecture.md")) }
        return Fixture(workspace: workspace, vault: vault, recoveryFolder: recoveryFolder)
    }

    private func relativePath(of location: URL?, in vault: URL) throws -> String {
        let path = try XCTUnwrap(location?.resolvingSymlinksInPath().path)
        return String(path.dropFirst(vault.path.count + 1))
    }

    private func assertNamedAfterTheNoteAndTheStartTime(_ path: String, directory: String, file: StaticString = #filePath, line: UInt = #line) {
        let pattern = "^" + NSRegularExpression.escapedPattern(for: directory) + #"Lecture Recording \d{4}-\d{2}-\d{2} \d{2}-\d{2}\.mp4$"#
        XCTAssertNotNil(path.range(of: pattern, options: .regularExpression), path, file: file, line: line)
    }

    private func storedManifest(in recoveryFolder: URL) throws -> [String: Any] {
        let manifests = try FileManager.default.contentsOfDirectory(at: recoveryFolder, includingPropertiesForKeys: nil).filter { $0.pathExtension == "json" }
        XCTAssertEqual(manifests.count, 1)
        let data = try Data(contentsOf: try XCTUnwrap(manifests.first))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testARecordingFromANoteGoesToTheFolderTheVaultSettingNamesForAttachments() async throws {
        let fixture = try await makeFixture(attachmentFolderPath: "Recordings")

        await fixture.workspace.startRecording(.video)

        XCTAssertEqual(fixture.workspace.recording.state, .recording)
        assertNamedAfterTheNoteAndTheStartTime(try relativePath(of: fixture.workspace.recording.destination, in: fixture.vault), directory: "Recordings/")
        XCTAssertEqual(fixture.workspace.recordingNotePath, try VaultPath("Course/Lecture.md"))
    }

    func testARecordingFromANoteWithASubfolderSettingGoesBesideTheNote() async throws {
        let fixture = try await makeFixture(attachmentFolderPath: "./attachments")

        await fixture.workspace.startRecording(.video)

        assertNamedAfterTheNoteAndTheStartTime(try relativePath(of: fixture.workspace.recording.destination, in: fixture.vault), directory: "Course/attachments/")
    }

    func testARecordingFromANoteInAVaultWithoutAnAttachmentSettingGoesToTheVaultFolder() async throws {
        let fixture = try await makeFixture(attachmentFolderPath: nil)

        await fixture.workspace.startRecording(.video)

        assertNamedAfterTheNoteAndTheStartTime(try relativePath(of: fixture.workspace.recording.destination, in: fixture.vault), directory: "")
    }

    func testARecordingWithNoNoteOpenGoesToTheCurrentFolderAndRemembersNoNote() async throws {
        let fixture = try await makeFixture(attachmentFolderPath: "Recordings", opensTheNote: false)

        await fixture.workspace.startRecording(.video)

        XCTAssertEqual(fixture.workspace.recording.state, .recording)
        let path = try relativePath(of: fixture.workspace.recording.destination, in: fixture.vault)
        XCTAssertNotNil(path.range(of: #"^[^/]+ Recording \d{4}-\d{2}-\d{2} \d{2}-\d{2}\.mp4$"#, options: .regularExpression), path)
        XCTAssertNil(fixture.workspace.recordingNotePath)
    }

    func testTheRecoveryManifestNamesTheDestinationAndTheNoteTheRecordingStartedFrom() async throws {
        let fixture = try await makeFixture(attachmentFolderPath: "./attachments")

        await fixture.workspace.startRecording(.video)

        let manifest = try storedManifest(in: fixture.recoveryFolder)
        XCTAssertEqual(Set(manifest.keys), ["destinationPath", "notePath", "startedAt"], "The vault identifier is left out when the vault has none.")
        XCTAssertEqual(manifest["notePath"] as? String, "Course/Lecture.md")
        let destinationPath = try XCTUnwrap(manifest["destinationPath"] as? String)
        assertNamedAfterTheNoteAndTheStartTime(destinationPath, directory: "Course/attachments/")
        XCTAssertEqual(destinationPath, try relativePath(of: fixture.workspace.recording.destination, in: fixture.vault))
    }

    func testAFinishedRecordingIsEmbeddedInTheNoteItWasStartedFromWhileThatNoteIsOpen() async throws {
        let fixture = try await makeFixture(attachmentFolderPath: "Recordings")
        await fixture.workspace.startRecording(.video)
        let destination = try XCTUnwrap(fixture.workspace.recording.destination)
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("video".utf8).write(to: destination)
        let session = try XCTUnwrap(fixture.workspace.markdownSession)

        await fixture.workspace.recordingDidFinish(at: destination)

        XCTAssertTrue(session.text.contains("![[\(destination.lastPathComponent)]]"), session.text)
        XCTAssertNil(fixture.workspace.recordingNotePath)
        XCTAssertNil(fixture.workspace.errorMessage)
    }

    func testAFinishedRecordingIsNotEmbeddedWhenItsNoteHasBeenClosed() async throws {
        let fixture = try await makeFixture(attachmentFolderPath: "Recordings")
        let openedTab = await fixture.workspace.open(try VaultPath("Course/Lecture.md"))
        let tabID = try XCTUnwrap(openedTab)
        await fixture.workspace.startRecording(.video)
        let destination = try XCTUnwrap(fixture.workspace.recording.destination)
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("video".utf8).write(to: destination)
        await fixture.workspace.closeTab(tabID)
        XCTAssertNil(fixture.workspace.openMarkdownSession(at: try VaultPath("Course/Lecture.md")))

        await fixture.workspace.recordingDidFinish(at: destination)

        XCTAssertEqual(try String(contentsOf: fixture.vault.appendingPathComponent("Course/Lecture.md"), encoding: .utf8), "# Lecture\n\nNotes.\n")
        XCTAssertNil(fixture.workspace.errorMessage, "The recording is saved; only the embed is skipped.")
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))
    }
}

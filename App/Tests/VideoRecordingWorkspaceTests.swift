#if os(iOS)
import XCTest
import SwiftUI
import AVFoundation
@testable import GraphiteApple
import GraphiteCore
import GraphiteIndex
@testable import GraphiteUI

/// A video recording in the running app, with frames and sound from
/// `SyntheticCaptureSource` in place of the simulator's missing camera: the recording
/// control, the floating preview, recording on while the person moves between
/// documents, and the saved MP4 played by Graphite's own media player.
@MainActor
final class VideoRecordingWorkspaceTests: XCTestCase {
    private var window: UIWindow?
    private var temporaryFolders: [URL] = []

    override func tearDown() async throws {
        window?.isHidden = true
        window?.rootViewController = nil
        window = nil
        for folder in temporaryFolders { try? FileManager.default.removeItem(at: folder) }
        temporaryFolders = []
    }

    func testAVideoRecordsWhileThePersonMovesBetweenDocumentsAndPlaysBackAfterwards() async throws {
        let (workspace, vault) = try await makeWorkspace(files: [
            "Course/Lecture 3.md": "# Lecture 3\n\nNotes taken during the lecture.\n",
            "Course/Exercises.md": "# Exercises\n",
            ".obsidian/app.json": "{\"attachmentFolderPath\": \"./attachments\"}",
        ])
        let source = SyntheticCaptureSource()
        workspace.recording.makeVideoCaptureSource = { source }
        let recoveryFolder = try makeFolder("VideoRecovery")
        workspace.recording.recoveryFolderLocation = { recoveryFolder }
        workspace.recording.videoStorage = RecordingStorage { _ in nil }
        let lecturePath = try VaultPath("Course/Lecture 3.md")
        await workspace.open(lecturePath)
        let controller = try host(workspace)
        let editor = try await visibleEditor(in: controller)
        let middleOfNote = editor.convert(CGPoint(x: editor.bounds.midX, y: editor.bounds.minY + 120), to: nil)
        XCTAssertTrue(touchReachesEditor(at: middleOfNote), "The preview's space takes no touches while there is no preview.")

        await workspace.startRecording(.video)
        XCTAssertEqual(workspace.recording.state, .recording, workspace.recording.message ?? "")
        XCTAssertEqual(workspace.recording.kind, .video)
        source.deliverInRealTime()

        // The preview floats over the documents and shows the camera's frames.
        try await waitUntil { self.previewLayer(in: controller)?.isReadyForDisplay == true }
        attachScreenshot(named: "Recording a video, with its preview")
        XCTAssertTrue(touchReachesEditor(at: middleOfNote), "Writing goes on beside the preview.")
        let previewView = try XCTUnwrap(descendants(of: controller.view, matching: CameraPreviewLayerView.self).first { view in view.window != nil })
        let middleOfPreview = previewView.convert(CGPoint(x: previewView.bounds.midX, y: previewView.bounds.midY), to: nil)
        XCTAssertFalse(touchReachesEditor(at: middleOfPreview), "The preview itself takes its touches, to be moved.")

        // Moving to another document and back does not touch the recording.
        let elapsedBeforeMoving = workspace.recording.elapsedSeconds
        await workspace.open(try VaultPath("Course/Exercises.md"), placement: .newTab)
        try await Task.sleep(for: .milliseconds(600))
        await workspace.open(lecturePath)
        XCTAssertEqual(workspace.recording.state, .recording)
        XCTAssertGreaterThan(workspace.recording.elapsedSeconds, elapsedBeforeMoving + 0.4)

        // Hiding the preview does not stop the recording either.
        workspace.showsRecordingPreview = false
        try await waitUntil { self.previewLayer(in: controller) == nil }
        let elapsedWhenHidden = workspace.recording.elapsedSeconds
        try await Task.sleep(for: .milliseconds(600))
        XCTAssertGreaterThan(workspace.recording.elapsedSeconds, elapsedWhenHidden + 0.4)
        attachScreenshot(named: "Recording with the preview hidden")
        workspace.showsRecordingPreview = true
        try await waitUntil { self.previewLayer(in: controller)?.isReadyForDisplay == true }

        workspace.recording.stop()
        try await waitUntil(timeoutSeconds: 30) { workspace.recording.state == .idle }
        XCTAssertNil(workspace.recording.message)
        try await waitUntil { self.previewLayer(in: controller) == nil }

        // Saved as an ordinary MP4, named and placed as audio recordings are.
        let saved = try XCTUnwrap(workspace.recording.lastCompletedURL)
        XCTAssertEqual(saved.pathExtension, "mp4")
        XCTAssertTrue(saved.lastPathComponent.hasPrefix("Lecture 3 Recording "), saved.lastPathComponent)
        XCTAssertEqual(saved.deletingLastPathComponent().lastPathComponent, "attachments")
        XCTAssertEqual(saved.deletingLastPathComponent().deletingLastPathComponent().resolvingSymlinksInPath(), vault.appendingPathComponent("Course").resolvingSymlinksInPath())
        let movie = try await MovieInspection.of(saved)
        XCTAssertGreaterThan(movie.durationSeconds, 1.5)
        XCTAssertEqual(movie.videoCodec, "avc1")
        XCTAssertEqual(movie.audioCodec, "aac")
        XCTAssertFalse(movie.containsFragments)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: recoveryFolder.path), [], "Nothing is left in the recovery folder.")

        // Embedded where the note's cursor was, as audio recordings are: the root view calls
        // this when a recording is saved. The index has not read this vault, so the embed
        // names the file by its path.
        await workspace.recordingDidFinish(at: saved)
        let note = try XCTUnwrap(workspace.openMarkdownSession(at: lecturePath))
        try await waitUntil { note.text.contains("![[") && note.text.contains("\(saved.lastPathComponent)]]") }

        // Graphite's own player plays it.
        let playback = EmbeddedMediaPlayback(location: saved)
        playback.player.isMuted = true
        playback.player.play()
        try await waitUntil { playback.player.currentItem?.status == .readyToPlay && playback.player.currentTime().seconds > 0.3 }
        playback.player.pause()
        let savedPath = try XCTUnwrap(workspace.vaultPath(for: saved))
        await workspace.open(savedPath, placement: .newTab)
        try await Task.sleep(for: .seconds(1))
        attachScreenshot(named: "The saved video in its tab")
    }

    func testAVideoInterruptedByLeavingTheScreenGoesOnAndIsSavedAsOneFile() async throws {
        let (workspace, _) = try await makeWorkspace(files: ["Lecture.md": "# Lecture\n"])
        let source = SyntheticCaptureSource()
        workspace.recording.makeVideoCaptureSource = { source }
        let recoveryFolder = try makeFolder("VideoRecovery")
        workspace.recording.recoveryFolderLocation = { recoveryFolder }
        workspace.recording.videoStorage = RecordingStorage { _ in nil }
        await workspace.open(try VaultPath("Lecture.md"))
        let controller = try host(workspace)

        await workspace.startRecording(.video)
        await source.deliver(seconds: 2)
        await source.interrupt(.applicationOffScreen)
        try await waitUntil { workspace.recording.state == .interrupted }
        XCTAssertEqual(workspace.recording.message, CaptureInterruptionReason.applicationOffScreen.explanation)
        attachScreenshot(named: "Video paused while Graphite was off screen")

        await source.endInterruption()
        try await waitUntil { workspace.recording.state == .recording }
        XCTAssertTrue(try XCTUnwrap(workspace.recording.message).contains("recording again"))
        await source.deliver(seconds: 2)
        workspace.recording.stop()
        try await waitUntil(timeoutSeconds: 30) { workspace.recording.state == .idle }

        let movie = try await MovieInspection.of(try XCTUnwrap(workspace.recording.lastCompletedURL))
        XCTAssertEqual(movie.durationSeconds, 4, accuracy: 0.25)
        XCTAssertFalse(movie.containsFragments)
        _ = controller
    }

    func testTheSimulatorsMissingCameraIsExplained() async throws {
        let (workspace, vault) = try await makeWorkspace(files: ["Lecture.md": "# Lecture\n"])
        let recoveryFolder = try makeFolder("VideoRecovery")
        workspace.recording.recoveryFolderLocation = { recoveryFolder }
        await workspace.open(try VaultPath("Lecture.md"))
        _ = try host(workspace)

        // The real camera source: the simulator has none, and is not asked for access to one.
        await workspace.startRecording(.video)

        XCTAssertEqual(workspace.recording.state, .failed)
        XCTAssertEqual(workspace.recording.accessProblem, .noCamera, workspace.recording.message ?? "")
        XCTAssertEqual(workspace.recording.message, "This device has no camera Graphite can record with.")
        XCTAssertEqual(workspace.recording.accessProblem?.canBeChangedInSettings, false, "No Settings button is offered for hardware that is missing.")
        XCTAssertTrue(workspace.recording.canStartRecording, "Another recording, such as audio, can still start.")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: recoveryFolder.path), [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: vault.appendingPathComponent("attachments").path))
        attachScreenshot(named: "No camera in the simulator")
    }

    // MARK: Helpers

    private func makeFolder(_ prefix: String) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        temporaryFolders.append(folder)
        return folder
    }

    private func makeWorkspace(files: [String: String]) async throws -> (WorkspaceModel, URL) {
        let vault = try makeFolder("VideoRecordingVault")
        for (relativePath, contents) in files {
            let location = vault.appendingPathComponent(relativePath)
            try FileManager.default.createDirectory(at: location.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(contents.utf8).write(to: location)
        }
        let workspace = WorkspaceModel()
        workspace.folderAccess = FolderAccess(root: vault)
        let store = VaultStore(root: vault)
        workspace.store = store
        workspace.vaultSettings = try await store.settings()
        workspace.index = try VaultIndex(databaseURL: try makeFolder("VideoRecordingIndex").appendingPathComponent("index.sqlite"))
        return (workspace, vault)
    }

    /// The documents with the recording control in the toolbar and the preview over
    /// them, as the root view arranges them.
    private func host(_ workspace: WorkspaceModel) throws -> UIHostingController<AnyView> {
        let controller = UIHostingController(rootView: AnyView(NavigationStack {
            WorkspacePanes(workspace: workspace, showsLinksInspector: .constant(false), create: { _ in }, showQuickSwitcher: {})
                .overlay { RecordingPreviewOverlay(workspace: workspace) }
                .toolbar { ToolbarItem(placement: .primaryAction) { RecordingControl(workspace: workspace) } }
        }))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        window.rootViewController = controller
        window.makeKeyAndVisible()
        self.window = window
        return controller
    }

    private func visibleEditor(in controller: UIViewController) async throws -> MarkdownTextView {
        try await waitUntil { self.descendants(of: controller.view, matching: MarkdownTextView.self).contains { editor in editor.window != nil && editor.bounds.width > 0 } }
        return try XCTUnwrap(descendants(of: controller.view, matching: MarkdownTextView.self).first { editor in editor.window != nil })
    }

    /// Whether a touch at a point of the window goes to the note's text view.
    private func touchReachesEditor(at windowPoint: CGPoint) -> Bool {
        guard let window, let touchedView = window.hitTest(windowPoint, with: nil) else { return false }
        return sequence(first: touchedView, next: \.superview).contains { view in view is MarkdownTextView }
    }

    private func previewLayer(in controller: UIViewController) -> AVSampleBufferDisplayLayer? {
        descendants(of: controller.view, matching: CameraPreviewLayerView.self).first { view in view.window != nil }?.layer as? AVSampleBufferDisplayLayer
    }

    private func descendants<View: UIView>(of parent: UIView, matching type: View.Type) -> [View] {
        parent.subviews.flatMap { child in ((child as? View).map { [$0] } ?? []) + descendants(of: child, matching: type) }
    }

    private func attachScreenshot(named name: String) {
        guard let window else { return }
        let screenshot = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func waitUntil(timeoutSeconds: Double = 10, file: StaticString = #filePath, line: UInt = #line, _ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while !condition(), Date() < deadline { try await Task.sleep(for: .milliseconds(25)) }
        XCTAssertTrue(condition(), "The hosted workspace did not reach the expected state.", file: file, line: line)
    }
}
#endif

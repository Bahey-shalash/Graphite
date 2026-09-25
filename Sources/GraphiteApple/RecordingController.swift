import Foundation
import AVFoundation
import Observation
import GraphiteCore

private actor RecordingPublisher {
    func publish(source: URL, destination: URL, filePresenter: (any NSFilePresenter & Sendable)?) throws {
        let folder = destination.deletingLastPathComponent()
        var isDirectory: ObjCBool = false
        // Checked first because copying into a missing folder reports that the source file is missing.
        guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw GraphiteError.unavailable("The folder “\(folder.lastPathComponent)” for this recording no longer exists.")
        }
        do {
            try AtomicFileWriter(filePresenter: filePresenter).replace(destination, expecting: .absent) { staging in
                try FileManager.default.copyItem(at: source, to: staging)
            }
        } catch GraphiteError.conflict {
            throw GraphiteError.unavailable("“\(folder.lastPathComponent)” already contains a file named “\(destination.lastPathComponent)”.")
        }
        // The vault holds the recording now. Failing to delete the recovery copy must not
        // report it as unsaved: a retry could never succeed, because its name is taken. The
        // leftover copy only uses space in Graphite's private recovery folder.
        try? FileManager.default.removeItem(at: source)
    }
}

@MainActor @Observable
public final class RecordingController: NSObject, AVAudioRecorderDelegate {
    public private(set) var state: RecordingState = .idle
    public private(set) var message: String?
    public private(set) var destination: URL?
    public private(set) var lastCompletedURL: URL?
    public private(set) var recoveryURL: URL?
    private var recorder: AVAudioRecorder?
    /// The presenter of the vault that `destination` is in, so publishing the recording is
    /// not reported back to Graphite as an external change.
    @ObservationIgnored private var filePresenter: (any NSFilePresenter & Sendable)?
    private let publisher = RecordingPublisher()
    /// True while a recording is being copied into the vault, so a late recorder callback
    /// or the finalization timeout cannot publish the same recording a second time.
    @ObservationIgnored private var isPublishing = false
    /// How long to wait for the recorder to report that it finished after `stop()`. Without
    /// that report (for example after iOS restarts its audio services) the controller would
    /// stay in `.finalizing`, which offers no control and blocks switching vaults.
    @ObservationIgnored var finalizationTimeout: Duration = .seconds(30)
    private var retainedElapsedSeconds: TimeInterval = 0
    /// The start under way; a start that is cancelled, or overtaken, leaves nothing behind.
    private var startAttempt: UUID?
    /// A stopped recorder reports 0, so the recorder's clock is read only while it runs;
    /// otherwise the time saved when it last stopped running is shown.
    public var elapsedSeconds: TimeInterval {
        guard state == .recording, let recorder else { return retainedElapsedSeconds }
        return recorder.currentTime
    }
    /// A recording that could not be saved into the vault is the only copy of that lecture,
    /// so a new recording cannot start until it is saved or discarded.
    public var canStartRecording: Bool { state.canStart && recoveryURL == nil }

    public override init() {
        super.init()
        #if os(iOS)
        // AVAudioSession posts these on its own threads. The handlers are nonisolated and hop
        // to the main actor; a main-actor selector would trap on entry off the main thread.
        NotificationCenter.default.addObserver(self, selector: #selector(handleInterruption), name: AVAudioSession.interruptionNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleRouteChange), name: AVAudioSession.routeChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleMediaServicesReset), name: AVAudioSession.mediaServicesWereResetNotification, object: nil)
        #endif
    }

    /// Starts recording. The audio goes to a recovery folder first, as IMA4 in a CAF file,
    /// which stays playable up to its last second if Graphite stops without finishing it
    /// (an M4A written by `AVAudioRecorder` does not); `manifest` says where it belongs.
    /// Stopping converts it to M4A at `destination`. `filePresenter` is the presenter of the
    /// vault that contains `destination`.
    public func start(destination: URL, manifest: RecordingRecoveryManifest, filePresenter: (any NSFilePresenter & Sendable)? = nil) async {
        guard canStartRecording else { return }
        state = .requestingPermission; message = nil; retainedElapsedSeconds = 0
        let attempt = UUID()
        startAttempt = attempt
        guard await AVCaptureDevice.requestAccess(for: .audio) else {
            state = .failed; message = "Microphone access is required. Enable it in system privacy settings."; return
        }
        var recordingURL: URL?
        do {
            let location = try RecordingRecoveryFolder.location().appendingPathComponent("\(UUID().uuidString).caf")
            recordingURL = location
            try RecordingRecoveryFolder.write(manifest, for: location)
            // Audio hardware can take seconds to answer (or never, as in a simulator without
            // a microphone); waiting for it on the main thread would freeze Graphite.
            let started = try await Task.detached(priority: .userInitiated) { try Self.startedRecorder(at: location) }.value
            guard startAttempt == attempt else {
                // Cancelled while the hardware was answering.
                started.recorder.stop()
                started.recorder.deleteRecording()
                try? FileManager.default.removeItem(at: RecordingRecoveryFolder.manifestLocation(for: location))
                return
            }
            startAttempt = nil
            started.recorder.delegate = self
            recorder = started.recorder; self.destination = destination; self.filePresenter = filePresenter; recoveryURL = location
            state = .recording
        } catch {
            // A recording that never started holds nothing to recover.
            if let recordingURL {
                try? FileManager.default.removeItem(at: recordingURL)
                try? FileManager.default.removeItem(at: RecordingRecoveryFolder.manifestLocation(for: recordingURL))
            }
            guard startAttempt == attempt else { return }
            startAttempt = nil
            // Nothing was recorded, so other apps' audio resumes.
            deactivateAudioSession()
            state = .failed; message = error.localizedDescription
        }
    }

    /// Gives up on a start that is waiting, for the permission prompt or for audio hardware
    /// that does not answer.
    public func cancelStart() {
        guard state == .requestingPermission else { return }
        startAttempt = nil
        state = .idle; message = nil
    }

    /// A recorder handed from the thread that started it to the main actor, which alone
    /// uses it from then on.
    private struct StartedRecorder: @unchecked Sendable {
        let recorder: AVAudioRecorder
    }

    private nonisolated static func startedRecorder(at location: URL) throws -> StartedRecorder {
        #if os(iOS)
        try activateAudioSession()
        #endif
        let audioRecorder = try AVAudioRecorder(url: location, settings: recordingSettings)
        guard audioRecorder.prepareToRecord(), audioRecorder.record() else { throw GraphiteError.unavailable("The microphone could not start recording.") }
        return StartedRecorder(recorder: audioRecorder)
    }

    #if os(iOS)
    private nonisolated static func activateAudioSession() throws {
        try AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP])
        try AVAudioSession.sharedInstance().setActive(true)
    }
    #endif

    public func pause() {
        guard state == .recording else { return }
        retainElapsedSeconds()
        recorder?.pause(); state = .paused
    }
    public func resume() {
        guard state.canResume, let recorder else { return }
        let handedOver = StartedRecorder(recorder: recorder)
        Task {
            do {
                // Off the main thread, as when starting.
                try await Task.detached(priority: .userInitiated) {
                    #if os(iOS)
                    try Self.activateAudioSession()
                    #endif
                    guard handedOver.recorder.record() else { throw GraphiteError.unavailable("The microphone could not resume. You can still stop and save this recording.") }
                }.value
                state = .recording; message = nil
            } catch { message = error.localizedDescription }
        }
    }
    public func stop() {
        guard state.canStop else { return }
        retainElapsedSeconds()
        state = .finalizing
        recorder?.stop()
        finishIfFinalizationStalls()
    }
    public nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        let finishedRecorder = ObjectIdentifier(recorder)
        Task { @MainActor [weak self] in
            // A recorder already given up on (abandoned, or its recording already failed)
            // must not finish whatever recording is current by the time this runs.
            guard let self, self.recorder.map(ObjectIdentifier.init) == finishedRecorder else { return }
            await finish(successfully: flag)
        }
    }
    public nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        let description = error?.localizedDescription ?? "Audio encoding failed."
        Task { @MainActor [weak self] in self?.abandonRecorder(reason: description) }
    }

    /// Stops a recorder that can no longer record, after an encoding error or when iOS
    /// restarts its audio services. Stopping writes what was recorded so far as a playable
    /// file, which stays available to Try Saving Again, and lets other apps' audio resume.
    func abandonRecorder(reason: String) {
        guard state.canStop || (state == .finalizing && !isPublishing) else { return }
        retainElapsedSeconds()
        // The recorder's own finish callback that follows finds `.failed` and is ignored.
        state = .failed
        recorder?.stop(); recorder = nil
        deactivateAudioSession()
        message = recoveryURL == nil ? reason : "\(reason) The audio recorded so far has been kept."
    }

    private func finish(successfully: Bool) async {
        // The recorder also finishes on its own, for example when storage runs out.
        guard state.canStop || state == .finalizing, !isPublishing else { return }
        retainElapsedSeconds()
        state = .finalizing
        guard successfully, let source = recoveryURL, let destination else {
            recorder = nil; deactivateAudioSession()
            state = .failed; message = "Recording did not finalize successfully. Any recovery audio has been retained."; return
        }
        isPublishing = true
        defer { isPublishing = false }
        do {
            try await Self.saveAsM4A(source, to: destination, publisher: publisher, filePresenter: filePresenter)
            lastCompletedURL = destination; recoveryURL = nil; recorder = nil; message = nil; state = .idle
            deactivateAudioSession()
        } catch {
            recorder = nil; deactivateAudioSession()
            state = .failed; message = "\(error.localizedDescription) Your recording remains at \(source.path)."
        }
    }
    /// Deactivation can fail while other audio is playing. The recording is already
    /// saved at that point, so this must never be reported as a recording failure.
    private func deactivateAudioSession() {
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }
    /// Saves the running recorder's time before it stops running. A recorder that already
    /// stopped on its own reports 0, and the elapsed time of one recording never decreases,
    /// so the larger value is kept.
    private func retainElapsedSeconds() {
        guard state == .recording, let recorder else { return }
        retainedElapsedSeconds = max(retainedElapsedSeconds, recorder.currentTime)
    }
    /// Publishes the recovery file anyway if the recorder never reports that it finished.
    /// Publication checks that the file holds playable audio, and keeps it for Try Saving
    /// Again when it does not.
    private func finishIfFinalizationStalls() {
        let stoppedRecordingURL = recoveryURL
        let timeout = finalizationTimeout
        Task { [weak self] in
            try? await Task.sleep(for: timeout)
            guard let self, state == .finalizing, recoveryURL == stoppedRecordingURL, !isPublishing else { return }
            await finish(successfully: true)
        }
    }

    /// Mono IMA4 at 44.1 kHz: a quarter of plain PCM's size (about 86 MB an hour), with
    /// every block readable on its own.
    nonisolated(unsafe) static let recordingSettings: [String: Any] = [
        AVFormatIDKey: kAudioFormatAppleIMA4,
        AVSampleRateKey: 44_100,
        AVNumberOfChannelsKey: 1,
    ]

    /// Recordings Graphite did not finish, other than the one being made.
    public func unfinishedRecordings() -> [RecoverableRecording] {
        guard let folder = try? RecordingRecoveryFolder.location() else { return [] }
        return RecordingRecoveryFolder.recordings(in: folder, excluding: state.isActive || state == .failed ? recoveryURL : nil)
    }

    /// Saves an unfinished recording as M4A at `destination`, then removes it from the
    /// recovery folder. `filePresenter` is the presenter of the vault that contains `destination`.
    public func recover(_ recording: RecoverableRecording, to destination: URL, filePresenter: (any NSFilePresenter & Sendable)? = nil) async throws {
        try await Self.saveAsM4A(recording.audioLocation, to: destination, publisher: publisher, filePresenter: filePresenter)
        try? RecordingRecoveryFolder.remove(recording)
    }

    /// Converts a recording to M4A (AAC) and publishes it at `destination`, which must not
    /// exist. The source is removed only once the file is in place.
    private static func saveAsM4A(_ source: URL, to destination: URL, publisher: RecordingPublisher, filePresenter: (any NSFilePresenter & Sendable)?) async throws {
        let converted = try await convertedToM4A(source)
        try await publisher.publish(source: converted, destination: destination, filePresenter: filePresenter)
        if converted != source { try? FileManager.default.removeItem(at: source) }
        try? FileManager.default.removeItem(at: RecordingRecoveryFolder.manifestLocation(for: source))
    }

    /// An M4A of `source` beside it, or `source` itself when it is already a playable M4A.
    /// Throws when it holds no playable audio.
    static func convertedToM4A(_ source: URL) async throws -> URL {
        let duration = try await AVURLAsset(url: source).load(.duration).seconds
        guard duration.isFinite, duration > 0 else { throw GraphiteError.invalidFile("The recording contains no playable audio.") }
        if source.pathExtension.lowercased() == "m4a" { return source }
        let output = source.deletingPathExtension().appendingPathExtension("m4a")
        // A conversion that stopped halfway is started again.
        try? FileManager.default.removeItem(at: output)
        guard let session = AVAssetExportSession(asset: AVURLAsset(url: source), presetName: AVAssetExportPresetAppleM4A) else {
            throw GraphiteError.unavailable("The recording could not be converted to M4A.")
        }
        try await session.export(to: output, as: .m4a)
        let convertedDuration = try await AVURLAsset(url: output).load(.duration).seconds
        guard convertedDuration.isFinite, convertedDuration > 0 else {
            try? FileManager.default.removeItem(at: output)
            throw GraphiteError.invalidFile("The converted recording contains no playable audio. The original is kept.")
        }
        return output
    }

    /// Publishes a recording that could not be saved into the vault. `replacementDestination`,
    /// when given, is used instead of the original destination, for example because its folder
    /// was renamed or its name was taken meanwhile; `filePresenter` is then the presenter of
    /// the vault that contains it.
    public func retryPublication(to replacementDestination: URL? = nil, filePresenter replacementFilePresenter: (any NSFilePresenter & Sendable)? = nil) async {
        guard state == .failed, recoveryURL != nil else { return }
        if let replacementDestination {
            destination = replacementDestination; filePresenter = replacementFilePresenter
        }
        state = .finalizing
        await finish(successfully: true)
    }

    /// Deletes a recording that could not be saved into the vault. It is the only copy, so
    /// the caller confirms with the user first.
    public func discardRecoveredRecording() {
        guard state == .failed, let recoveryURL else { return }
        do {
            try FileManager.default.removeItem(at: recoveryURL)
        } catch let error where FileManager.default.fileExists(atPath: recoveryURL.path) {
            message = "Graphite couldn't delete the recording. \(error.localizedDescription)"; return
        } catch {
            // Already gone, which is what discarding asked for.
        }
        // Its manifest, and an M4A converted from it before saving failed, would otherwise
        // be offered again as an unfinished recording.
        try? FileManager.default.removeItem(at: RecordingRecoveryFolder.manifestLocation(for: recoveryURL))
        if recoveryURL.pathExtension.lowercased() != "m4a" {
            try? FileManager.default.removeItem(at: recoveryURL.deletingPathExtension().appendingPathExtension("m4a"))
        }
        self.recoveryURL = nil; destination = nil; filePresenter = nil; recorder = nil
        retainedElapsedSeconds = 0; message = nil; state = .idle
    }

    /// Puts the controller in `state` for audio already recorded at `recoveryURL`, as if it had
    /// been recording to `destination`. Tests use it to reach finalization and publication
    /// without a microphone.
    func adoptRecording(at recoveryURL: URL, destination: URL, state: RecordingState, message: String? = nil, filePresenter: (any NSFilePresenter & Sendable)? = nil) {
        self.recoveryURL = recoveryURL; self.destination = destination; self.filePresenter = filePresenter
        self.state = state; self.message = message
    }

    #if os(iOS)
    @objc private nonisolated func handleInterruption(_ notification: Notification) {
        guard let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              AVAudioSession.InterruptionType(rawValue: rawType) == .began else { return }
        Task { @MainActor [weak self] in self?.interruptRecording(message: "Recording was interrupted. Resume when you are ready.") }
    }
    @objc private nonisolated func handleRouteChange(_ notification: Notification) {
        guard let reason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
              reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue else { return }
        Task { @MainActor [weak self] in self?.interruptRecording(message: "The microphone route changed. Check your microphone, then resume.") }
    }
    /// After a reset every audio object is invalid, so the recorder can never resume or report finishing.
    @objc private nonisolated func handleMediaServicesReset(_ notification: Notification) {
        Task { @MainActor [weak self] in self?.abandonRecorder(reason: "Audio services restarted, so the recording stopped.") }
    }
    private func interruptRecording(message interruptionMessage: String) {
        guard state == .recording else { return }
        retainElapsedSeconds()
        recorder?.pause(); state = .interrupted; message = interruptionMessage
    }
    #endif
}

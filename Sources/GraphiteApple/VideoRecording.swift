import Foundation
import AVFoundation
import CoreMedia
import Synchronization
import GraphiteCore

/// How much room a video recording needs on the volume it is written to.
struct RecordingStorage: Sendable {
    /// Below this a recording does not start: about a quarter of an hour of video.
    static let minimumBytesToStart: Int64 = 500 * 1_048_576
    /// Below this a recording stops itself, while there is room left to close its file.
    static let minimumBytesWhileRecording: Int64 = 250 * 1_048_576

    /// The free space of the volume that holds a folder; nil when the system does not say.
    var availableBytes: @Sendable (URL) -> Int64?

    static let system = RecordingStorage { folder in
        (try? folder.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?.volumeAvailableCapacityForImportantUsage
    }
}

/// One video recording, from its start to the files it leaves: samples from a capture
/// source go to a `MoviePartWriter`, and to the preview.
///
/// A recording is one file for as long as the camera stays with Graphite. A pause leaves
/// the file open and closes the gap in its timeline. When the camera is taken away (the app
/// leaves the screen, a call, another app) the file is closed at once, so it is a complete
/// MP4 whatever happens next, and the next frame after the camera returns starts a new part;
/// the system can end a suspended app, and a video encoder does not survive the background.
///
/// `@unchecked Sendable`: every mutable property is read and written only on `queue`, where
/// the source also delivers its samples and events. `recordedSecondsStorage` is a mutex.
final class VideoRecording: @unchecked Sendable {
    enum Notice: Sendable, Equatable {
        /// The size of the camera's frames, when the first arrives and when it changes.
        case frameSize(width: Int, height: Int)
        case interrupted(CaptureInterruptionReason)
        case interruptionEnded
        /// Storage ran low or out. Nothing more is written; what was written is kept.
        case stoppedForLackOfStorage
        /// Writing failed. Nothing more is written; what reached the file is kept.
        case stoppedAfterWritingFailed(String)
    }

    private static let framesBetweenStorageChecks = 60

    private let queue = DispatchQueue(label: "Graphite.VideoRecording", qos: .userInitiated)
    private let source: any VideoCaptureSource
    private let firstPartLocation: URL
    private let storage: RecordingStorage
    private let notify: @Sendable (Notice) -> Void
    private var currentPart: MoviePartWriter?
    private var partLocations: [URL] = []
    /// False while paused, interrupted, or stopped: samples then only reach the preview.
    private var acceptsSamples = false
    private var isInterrupted = false
    private var hasStopped = false
    private var finishedPartsSeconds: TimeInterval = 0
    private var framesSinceStorageCheck = 0
    private struct FrameSize: Equatable { let width: Int, height: Int }
    private var lastFrameSize: FrameSize?
    /// Parts being closed; `finish` waits for them.
    private let closingParts = DispatchGroup()
    private var previewRenderer: AVSampleBufferVideoRenderer?
    private let recordedSecondsStorage = Mutex<TimeInterval>(0)

    /// How much has been recorded, not counting pauses and interruptions.
    var recordedSeconds: TimeInterval { recordedSecondsStorage.withLock { seconds in seconds } }

    init(source: any VideoCaptureSource, firstPartLocation: URL, storage: RecordingStorage = .system, notify: @escaping @Sendable (Notice) -> Void) {
        self.source = source; self.firstPartLocation = firstPartLocation; self.storage = storage; self.notify = notify
    }

    /// Starts the camera and microphone, and records from the first frame they deliver.
    func start(camera: CameraPosition) async throws {
        if let availableBytes = storage.availableBytes(firstPartLocation.deletingLastPathComponent()), availableBytes < RecordingStorage.minimumBytesToStart {
            throw GraphiteError.unavailable("There is not enough free storage to record video. Free some space, then try again.")
        }
        await onQueue { recording in recording.acceptsSamples = true }
        try await source.start(camera: camera, deliveringOn: queue,
                               samples: { [weak self] sampleBuffer, kind in self?.receive(sampleBuffer, kind: kind) },
                               events: { [weak self] event in self?.handle(event) })
    }

    func availableCameras() async -> [CameraPosition] { await source.availableCameras() }

    func switchCamera(to camera: CameraPosition) async throws { try await source.switchCamera(to: camera) }

    func pause() {
        queue.async {
            self.acceptsSamples = false
            self.currentPart?.closeGapAtNextSample()
        }
    }

    /// Records again after a pause, or after an interruption, for which the source is
    /// asked to deliver again in case the system has not restarted it.
    func resume() async throws {
        if await onQueue({ recording in recording.isInterrupted }) {
            try await source.resumeAfterInterruption()
        }
        await onQueue { recording in
            guard !recording.hasStopped else { return }
            recording.isInterrupted = false
            recording.acceptsSamples = true
        }
    }

    /// Waits until the parts being closed are complete files.
    func waitForClosingParts() async {
        await withCheckedContinuation { continuation in
            closingParts.notify(queue: queue) { continuation.resume() }
        }
    }

    /// Stops the camera and microphone, closes the file, and returns the recording's
    /// parts in order.
    func finish() async -> [URL] {
        await onQueue { recording in
            recording.hasStopped = true
            recording.acceptsSamples = false
            recording.closeCurrentPart()
        }
        await source.stop()
        await waitForClosingParts()
        return await onQueue { recording in recording.partLocations }
    }

    /// Shows the camera's frames in `renderer`, or in nothing.
    func setPreviewRenderer(_ renderer: AVSampleBufferVideoRenderer?) {
        let handedOver = UncheckedRenderer(renderer: renderer)
        queue.async { self.previewRenderer = handedOver.renderer }
    }

    /// A renderer handed from the main actor to `queue`, which alone enqueues frames in it.
    private struct UncheckedRenderer: @unchecked Sendable {
        let renderer: AVSampleBufferVideoRenderer?
    }

    private func onQueue<Value: Sendable>(_ work: @escaping @Sendable (VideoRecording) -> Value) async -> Value {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: work(self)) }
        }
    }

    // MARK: On the queue

    private func receive(_ sampleBuffer: CMSampleBuffer, kind: CaptureMediaKind) {
        if kind == .video {
            reportFrameSize(of: sampleBuffer)
            showInPreview(sampleBuffer)
        }
        guard acceptsSamples else { return }
        if let currentPart {
            if case .failed(let error) = currentPart.append(sampleBuffer, kind: kind) { stopAfterWritingFailed(error) }
        } else {
            // A part starts with a frame, which gives the video its size.
            guard kind == .video else { return }
            let partLocation = RecordingRecoveryFolder.partLocation(partLocations.count + 1, ofRecordingAt: firstPartLocation)
            do {
                currentPart = try MoviePartWriter(location: partLocation, firstVideoFrame: sampleBuffer)
                partLocations.append(partLocation)
            } catch {
                try? FileManager.default.removeItem(at: partLocation)
                stopAfterWritingFailed(error)
            }
        }
        recordedSecondsStorage.withLock { seconds in seconds = finishedPartsSeconds + (currentPart?.writtenSeconds ?? 0) }
        if kind == .video { stopIfStorageIsLow() }
    }

    private func reportFrameSize(of sampleBuffer: CMSampleBuffer) {
        guard let imageBuffer = sampleBuffer.imageBuffer else { return }
        let frameSize = FrameSize(width: CVPixelBufferGetWidth(imageBuffer), height: CVPixelBufferGetHeight(imageBuffer))
        guard frameSize != lastFrameSize else { return }
        lastFrameSize = frameSize
        notify(.frameSize(width: frameSize.width, height: frameSize.height))
    }

    private func handle(_ event: VideoCaptureEvent) {
        guard !hasStopped else { return }
        switch event {
        case .interrupted(let reason):
            isInterrupted = true
            acceptsSamples = false
            closeCurrentPart()
            notify(.interrupted(reason))
        case .interruptionEnded:
            notify(.interruptionEnded)
        }
    }

    private func closeCurrentPart() {
        guard let part = currentPart else { return }
        currentPart = nil
        finishedPartsSeconds += part.writtenSeconds
        closingParts.enter()
        part.finish { [closingParts] in closingParts.leave() }
    }

    private func stopIfStorageIsLow() {
        framesSinceStorageCheck += 1
        guard framesSinceStorageCheck >= Self.framesBetweenStorageChecks else { return }
        framesSinceStorageCheck = 0
        guard let availableBytes = storage.availableBytes(firstPartLocation.deletingLastPathComponent()),
              availableBytes < RecordingStorage.minimumBytesWhileRecording else { return }
        stopWriting()
        notify(.stoppedForLackOfStorage)
    }

    private func stopAfterWritingFailed(_ error: Error?) {
        stopWriting()
        if MoviePartWriter.isStorageFull(error) {
            notify(.stoppedForLackOfStorage)
        } else {
            notify(.stoppedAfterWritingFailed(error?.localizedDescription ?? "The video file could not be written."))
        }
    }

    private func stopWriting() {
        hasStopped = true
        acceptsSamples = false
        closeCurrentPart()
    }

    private func showInPreview(_ sampleBuffer: CMSampleBuffer) {
        guard let previewRenderer else { return }
        // A renderer that lost its decoder, as after the app was off screen, starts again.
        if previewRenderer.status == .failed || previewRenderer.requiresFlushToResumeDecoding { previewRenderer.flush() }
        guard previewRenderer.isReadyForMoreMediaData, let frame = try? CMSampleBuffer(copying: sampleBuffer) else { return }
        // The renderer has no clock of its own here: each frame is shown as it arrives.
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(frame, createIfNecessary: true), CFArrayGetCount(attachments) > 0 {
            let frameAttachments = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
            CFDictionarySetValue(frameAttachments, Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                                 Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
        }
        previewRenderer.enqueue(frame)
    }
}

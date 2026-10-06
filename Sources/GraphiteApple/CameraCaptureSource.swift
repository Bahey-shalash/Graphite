import Foundation
import AVFoundation
import CoreMedia
import Synchronization
import GraphiteCore

/// The device's camera and microphone, through one `AVCaptureSession`.
///
/// Frames come out upright: the video connection rotates them to keep the horizon level,
/// following the device as it turns, and the writer fits a frame of another shape inside
/// the video's size. On an iPad that offers it, the session is set to keep the camera
/// while Graphite shares the screen; otherwise the system interrupts it there, which is
/// reported like every other interruption.
///
/// One source serves one recording. `@unchecked Sendable`: the session, its inputs and the
/// rotation tracking are touched only on `sessionQueue`; the handlers are behind a mutex,
/// since the system's notifications arrive on threads of its own.
public final class CameraCaptureSource: NSObject, VideoCaptureSource, @unchecked Sendable,
                                        AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {
    private struct Handlers: Sendable {
        let deliveryQueue: DispatchQueue
        let samples: @Sendable (CMSampleBuffer, CaptureMediaKind) -> Void
        let events: @Sendable (VideoCaptureEvent) -> Void
    }

    private let sessionQueue = DispatchQueue(label: "Graphite.CameraCaptureSource", qos: .userInitiated)
    private let session = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let audioOutput = AVCaptureAudioDataOutput()
    private var cameraInput: AVCaptureDeviceInput?
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private var rotationObservation: NSKeyValueObservation?
    private var notificationObservers: [any NSObjectProtocol] = []
    private let handlers = Mutex<Handlers?>(nil)

    public override init() {
        super.init()
    }

    public func start(camera: CameraPosition, deliveringOn deliveryQueue: DispatchQueue,
                      samples: @escaping @Sendable (CMSampleBuffer, CaptureMediaKind) -> Void,
                      events: @escaping @Sendable (VideoCaptureEvent) -> Void) async throws {
        // Hardware first, so a device without a camera is never asked for access to one.
        guard Self.camera(at: camera) != nil else { throw CaptureAccessProblem.noCamera }
        guard AVCaptureDevice.default(for: .audio) != nil else { throw CaptureAccessProblem.noMicrophone }
        try await Self.requireAccess(to: .video, denied: .cameraDenied, restricted: .cameraRestricted)
        try await Self.requireAccess(to: .audio, denied: .microphoneDenied, restricted: .microphoneRestricted)
        handlers.withLock { handlers in handlers = Handlers(deliveryQueue: deliveryQueue, samples: samples, events: events) }
        try await onSessionQueue { source in
            try source.configureSession(camera: camera, deliveryQueue: deliveryQueue)
            source.observeSession()
            // Starting waits for the hardware, which is why it is not on the main thread.
            source.session.startRunning()
            guard source.session.isRunning else { throw GraphiteError.unavailable("The camera could not start.") }
        }
    }

    public func availableCameras() async -> [CameraPosition] {
        #if os(macOS)
        Self.camera(at: .front) == nil ? [] : [.front]
        #else
        CameraPosition.allCases.filter { position in Self.camera(at: position) != nil }
        #endif
    }

    public func switchCamera(to camera: CameraPosition) async throws {
        try await onSessionQueue { source in
            guard let newCamera = Self.camera(at: camera) else { throw CaptureAccessProblem.noCamera }
            guard newCamera.uniqueID != source.cameraInput?.device.uniqueID else { return }
            let newInput = try AVCaptureDeviceInput(device: newCamera)
            source.session.beginConfiguration()
            defer { source.session.commitConfiguration() }
            let previousInput = source.cameraInput
            if let previousInput { source.session.removeInput(previousInput) }
            guard source.session.canAddInput(newInput) else {
                // The recording goes on with the camera it had.
                if let previousInput, source.session.canAddInput(previousInput) { source.session.addInput(previousInput) }
                throw GraphiteError.unavailable("The other camera could not be used.")
            }
            source.session.addInput(newInput)
            source.cameraInput = newInput
            source.chooseResolution(for: newCamera)
            source.followRotation(of: newCamera)
        }
    }

    public func resumeAfterInterruption() async throws {
        try await onSessionQueue { source in
            if !source.session.isRunning { source.session.startRunning() }
            guard source.session.isRunning else {
                throw GraphiteError.unavailable("The camera is still not available. What was recorded before is safe; try again in a moment, or stop to save it.")
            }
        }
    }

    public func stop() async {
        handlers.withLock { handlers in handlers = nil }
        try? await onSessionQueue { source in
            source.notificationObservers.forEach(NotificationCenter.default.removeObserver)
            source.notificationObservers = []
            source.rotationObservation = nil
            source.rotationCoordinator = nil
            source.videoOutput.setSampleBufferDelegate(nil, queue: nil)
            source.audioOutput.setSampleBufferDelegate(nil, queue: nil)
            if source.session.isRunning { source.session.stopRunning() }
        }
    }

    private func onSessionQueue(_ work: @escaping @Sendable (CameraCaptureSource) throws -> Void) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            sessionQueue.async { continuation.resume(with: Result { try work(self) }) }
        }
    }

    // MARK: Access

    private static func requireAccess(to mediaType: AVMediaType, denied: CaptureAccessProblem, restricted: CaptureAccessProblem) async throws {
        switch AVCaptureDevice.authorizationStatus(for: mediaType) {
        case .authorized: return
        case .notDetermined: guard await AVCaptureDevice.requestAccess(for: mediaType) else { throw denied }
        case .restricted: throw restricted
        case .denied: throw denied
        @unknown default: throw denied
        }
    }

    private static func camera(at position: CameraPosition) -> AVCaptureDevice? {
        #if os(macOS)
        // A Mac has one camera to speak of, built in or plugged in, and it reports no
        // position; it is used whichever camera was asked for.
        AVCaptureDevice.default(for: .video)
        #else
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position == .front ? .front : .back)
        #endif
    }

    // MARK: On the session queue

    private func configureSession(camera: CameraPosition, deliveryQueue: DispatchQueue) throws {
        guard let cameraDevice = Self.camera(at: camera) else { throw CaptureAccessProblem.noCamera }
        guard let microphone = AVCaptureDevice.default(for: .audio) else { throw CaptureAccessProblem.noMicrophone }
        let newCameraInput = try AVCaptureDeviceInput(device: cameraDevice)
        let microphoneInput = try AVCaptureDeviceInput(device: microphone)
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        guard session.canAddInput(newCameraInput), session.canAddInput(microphoneInput),
              session.canAddOutput(videoOutput), session.canAddOutput(audioOutput) else {
            throw GraphiteError.unavailable("The camera and microphone could not be set up for recording.")
        }
        session.addInput(newCameraInput); session.addInput(microphoneInput)
        cameraInput = newCameraInput
        // A frame the writer has no time for is dropped here, not queued.
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(self, queue: deliveryQueue)
        audioOutput.setSampleBufferDelegate(self, queue: deliveryQueue)
        session.addOutput(videoOutput); session.addOutput(audioOutput)
        #if os(iOS)
        // Must be set before the session runs. Without it the system takes the camera
        // away while another app is on screen beside Graphite.
        if session.isMultitaskingCameraAccessSupported { session.isMultitaskingCameraAccessEnabled = true }
        #endif
        chooseResolution(for: cameraDevice)
        followRotation(of: cameraDevice)
    }

    /// 1080p where the camera offers it, which keeps a board readable; else the best it has.
    private func chooseResolution(for camera: AVCaptureDevice) {
        let preferredPresets: [AVCaptureSession.Preset] = [.hd1920x1080, .hd1280x720, .high]
        guard let preset = preferredPresets.first(where: { preset in camera.supportsSessionPreset(preset) && session.canSetSessionPreset(preset) }) else { return }
        session.sessionPreset = preset
    }

    private func followRotation(of camera: AVCaptureDevice) {
        let coordinator = AVCaptureDevice.RotationCoordinator(device: camera, previewLayer: nil)
        rotationCoordinator = coordinator
        applyRotation(coordinator.videoRotationAngleForHorizonLevelCapture)
        // Reported on the main queue as the device turns.
        rotationObservation = coordinator.observe(\.videoRotationAngleForHorizonLevelCapture, options: [.new]) { [weak self] _, change in
            guard let self, let angle = change.newValue else { return }
            sessionQueue.async { self.applyRotation(angle) }
        }
    }

    private func applyRotation(_ angle: CGFloat) {
        guard let connection = videoOutput.connection(with: .video), connection.isVideoRotationAngleSupported(angle) else { return }
        connection.videoRotationAngle = angle
    }

    private func observeSession() {
        let notificationCenter = NotificationCenter.default
        notificationObservers = [
            notificationCenter.addObserver(forName: AVCaptureSession.wasInterruptedNotification, object: session, queue: nil) { [weak self] notification in
                self?.report(.interrupted(Self.interruptionReason(in: notification)))
            },
            notificationCenter.addObserver(forName: AVCaptureSession.interruptionEndedNotification, object: session, queue: nil) { [weak self] _ in
                self?.report(.interruptionEnded)
            },
            // After a runtime error, such as the system restarting its media services, the
            // session no longer runs and is started again by resuming.
            notificationCenter.addObserver(forName: AVCaptureSession.runtimeErrorNotification, object: session, queue: nil) { [weak self] _ in
                self?.report(.interrupted(.captureStopped))
            },
        ]
    }

    private static func interruptionReason(in notification: Notification) -> CaptureInterruptionReason {
        #if os(iOS)
        guard let rawReason = notification.userInfo?[AVCaptureSessionInterruptionReasonKey] as? Int,
              let reason = AVCaptureSession.InterruptionReason(rawValue: rawReason) else { return .unknown }
        switch reason {
        case .videoDeviceNotAvailableInBackground: return .applicationOffScreen
        case .audioDeviceInUseByAnotherClient: return .microphoneInUseByAnotherApplication
        case .videoDeviceInUseByAnotherClient: return .cameraInUseByAnotherApplication
        case .videoDeviceNotAvailableWithMultipleForegroundApps: return .cameraUnavailableWhileSharingScreen
        case .videoDeviceNotAvailableDueToSystemPressure: return .systemPressure
        default: return .unknown
        }
        #else
        return .unknown
        #endif
    }

    private func report(_ event: VideoCaptureEvent) {
        guard let handlers = handlers.withLock({ handlers in handlers }) else { return }
        handlers.deliveryQueue.async { handlers.events(event) }
    }

    // MARK: Samples, on the delivery queue

    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let handlers = handlers.withLock({ handlers in handlers }) else { return }
        handlers.samples(sampleBuffer, output is AVCaptureAudioDataOutput ? .audio : .video)
    }
}

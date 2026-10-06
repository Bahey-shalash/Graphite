import Foundation
import AVFoundation
import CoreMedia
import GraphiteCore

public enum CameraPosition: String, Sendable, CaseIterable {
    case back, front
}

/// Whether a captured sample is a video frame or a run of audio.
public enum CaptureMediaKind: Sendable {
    case video, audio
}

/// Why the camera and microphone stopped delivering samples while a video was recorded.
public enum CaptureInterruptionReason: Sendable, Equatable {
    /// The app left the screen. The system lets no ordinary app use the camera there.
    case applicationOffScreen
    case cameraInUseByAnotherApplication
    case microphoneInUseByAnotherApplication
    /// The app shares the screen (Split View, Slide Over, Stage Manager) on an iPad that
    /// gives the camera to one app at a time.
    case cameraUnavailableWhileSharingScreen
    /// The device is too hot or too busy to run the camera.
    case systemPressure
    /// The capture session stopped with an error, as when the system restarts its media services.
    case captureStopped
    case unknown

    /// What the person is told while the recording waits.
    public var explanation: String {
        switch self {
        case .applicationOffScreen:
            "The video paused when Graphite left the screen, because apps cannot use the camera there. Nothing is recorded meanwhile, not even sound. What was recorded before is safe."
        case .cameraInUseByAnotherApplication:
            "Another app is using the camera, so the video is paused. What was recorded before is safe."
        case .microphoneInUseByAnotherApplication:
            "A call or another app is using the microphone, so the video is paused. What was recorded before is safe."
        case .cameraUnavailableWhileSharingScreen:
            "This iPad cannot use the camera while Graphite shares the screen with another app, so the video is paused. Give Graphite the whole screen to continue."
        case .systemPressure:
            "The device is too hot or too busy to use the camera, so the video is paused. What was recorded before is safe."
        case .captureStopped, .unknown:
            "The camera stopped, so the video is paused. What was recorded before is safe."
        }
    }
}

/// Why a video recording cannot use the camera or the microphone.
public enum CaptureAccessProblem: Error, LocalizedError, Equatable, Sendable {
    case cameraDenied, cameraRestricted, microphoneDenied, microphoneRestricted
    case noCamera, noMicrophone

    public var errorDescription: String? {
        switch self {
        case .cameraDenied: "Graphite is not allowed to use the camera. Allow it in Settings to record video."
        case .microphoneDenied: "Graphite is not allowed to use the microphone. Allow it in Settings to record video with sound."
        case .cameraRestricted: "Camera use is restricted on this device, for example by Screen Time or by the organization that manages it, so Graphite cannot record video."
        case .microphoneRestricted: "Microphone use is restricted on this device, for example by Screen Time or by the organization that manages it, so Graphite cannot record video with sound."
        case .noCamera: "This device has no camera Graphite can record with."
        case .noMicrophone: "This device has no microphone Graphite can record with."
        }
    }

    /// Whether the person can change this in the system's settings for Graphite.
    public var canBeChangedInSettings: Bool {
        switch self {
        case .cameraDenied, .microphoneDenied, .cameraRestricted, .microphoneRestricted: true
        case .noCamera, .noMicrophone: false
        }
    }
}

/// What a capture source reports besides samples.
public enum VideoCaptureEvent: Sendable, Equatable {
    case interrupted(CaptureInterruptionReason)
    /// The camera and microphone deliver samples again.
    case interruptionEnded
}

/// The camera and microphone of a video recording: the one place that touches capture
/// hardware. `CameraCaptureSource` is the real one; tests use a source that makes its own
/// frames and sound, which go through the same writer.
///
/// Samples and events are delivered on the queue given to `start`, one at a time, so the
/// recording that receives them needs no lock. Video frames are uncompressed pixel
/// buffers, upright as the person sees the scene; audio is linear PCM. Both carry
/// presentation times on one clock.
public protocol VideoCaptureSource: AnyObject, Sendable {
    /// Asks for camera and microphone access when needed, then starts delivering samples.
    /// Throws `CaptureAccessProblem` when access is refused or the hardware is missing.
    func start(camera: CameraPosition, deliveringOn deliveryQueue: DispatchQueue,
               samples: @escaping @Sendable (CMSampleBuffer, CaptureMediaKind) -> Void,
               events: @escaping @Sendable (VideoCaptureEvent) -> Void) async throws
    /// The cameras the running source can switch between.
    func availableCameras() async -> [CameraPosition]
    /// Changes camera while samples keep their clock. Frames pause for a moment.
    func switchCamera(to camera: CameraPosition) async throws
    /// Starts delivering again after an interruption, when the system has not done so itself.
    func resumeAfterInterruption() async throws
    func stop() async
}

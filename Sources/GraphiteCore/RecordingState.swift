import Foundation

public enum RecordingState: String, Sendable {
    case idle, requestingPermission, recording, paused, interrupted, finalizing, failed
    public var canStart: Bool { self == .idle || self == .failed }
    public var canResume: Bool { self == .paused || self == .interrupted }
    public var canStop: Bool { self == .recording || self == .paused || self == .interrupted }
    public var isActive: Bool { self != .idle && self != .failed }
}

/// What a lecture recording holds, which decides the ordinary file it becomes.
public enum RecordingKind: String, Codable, Sendable, CaseIterable {
    /// Sound only, saved as AAC in an M4A file.
    case audio
    /// Camera and sound, saved as H.264 and AAC in an MP4 file.
    case video

    /// The extension of the file a finished recording is saved as.
    public var fileExtension: String {
        switch self {
        case .audio: "m4a"
        case .video: "mp4"
        }
    }

    /// The kind of recording a file with this extension in the recovery folder holds.
    public init?(recoveryFileExtension: String) {
        switch recoveryFileExtension.lowercased() {
        case "caf", "m4a": self = .audio
        case "mp4": self = .video
        default: return nil
        }
    }
}

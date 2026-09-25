import Foundation

public enum RecordingState: String, Sendable {
    case idle, requestingPermission, recording, paused, interrupted, finalizing, failed
    public var canStart: Bool { self == .idle || self == .failed }
    public var canResume: Bool { self == .paused || self == .interrupted }
    public var canStop: Bool { self == .recording || self == .paused || self == .interrupted }
    public var isActive: Bool { self != .idle && self != .failed }
}

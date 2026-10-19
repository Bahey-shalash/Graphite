import Foundation

/// An audio recording listed in `Recordings/library.plist`.
public struct NotabilityRecording: Sendable, Equatable {
    /// The identifier playback events name the recording by.
    public let identifier: Int?
    /// The audio file relative to the note's folder: `Recordings/<filepath>`.
    public let relativePath: String
    public let durationSeconds: Double?
    public let name: String?

    public init(identifier: Int?, relativePath: String, durationSeconds: Double?, name: String?) {
        self.identifier = identifier
        self.relativePath = relativePath
        self.durationSeconds = durationSeconds
        self.name = name
    }
}

/// When a curve was written during a recording (`contentPlaybackEventManager`).
public struct NotabilityPlaybackEvent: Sendable, Equatable {
    /// The curve whose UUID the event names; nil when no curve has it (reported as `playbackEventWithoutCurve`).
    public let curveIndex: Int?
    public let curveUUID: UUID
    public let recordingIdentifier: Int
    public let secondsFromRecordingStart: Double
    /// How long the curve took to write.
    public let durationSeconds: Double

    public init(curveIndex: Int?, curveUUID: UUID, recordingIdentifier: Int, secondsFromRecordingStart: Double, durationSeconds: Double) {
        self.curveIndex = curveIndex
        self.curveUUID = curveUUID
        self.recordingIdentifier = recordingIdentifier
        self.secondsFromRecordingStart = secondsFromRecordingStart
        self.durationSeconds = durationSeconds
    }
}

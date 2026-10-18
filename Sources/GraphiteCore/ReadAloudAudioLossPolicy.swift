import Foundation

/// What happened to the audio output while Read Aloud was reading.
public enum ReadAloudAudioOutputChange: Equatable, Sendable {
    /// The output the sound was going to went away: headphones unplugged, a Bluetooth device disconnected.
    case previousOutputUnavailable
    /// The audio engine stopped itself because its output changed.
    case engineConfigurationChanged
    /// Another output was connected and takes over the sound.
    case newOutputAvailable
}

public enum ReadAloudAudioLossPolicy {
    /// Whether rendered reading pauses after `change`. Losing the output pauses it, so a lecture
    /// does not play out loud through the speaker or stall silently; a newly connected output
    /// takes over without interrupting. Nothing pauses when no rendered passage is playing:
    /// the system voice reports its own route changes.
    public static func pausesReading(after change: ReadAloudAudioOutputChange, isPlayingRenderedAudio: Bool) -> Bool {
        guard isPlayingRenderedAudio else { return false }
        switch change {
        case .previousOutputUnavailable, .engineConfigurationChanged: return true
        case .newOutputAvailable: return false
        }
    }
}

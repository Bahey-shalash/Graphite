import Foundation
import MediaPlayer
import GraphiteApple

/// Shows the passage being read on the lock screen and in Control Center, and lets the
/// headphone, lock screen and keyboard media controls pause, resume and move by sentence.
/// The controls answer only while a passage is loaded, so they never take over another
/// app's audio when Graphite is not reading.
@MainActor
final class ReadAloudNowPlaying {
    struct Commands {
        let play: () -> Bool
        let pause: () -> Bool
        let nextSentence: () -> Bool
        let previousSentence: () -> Bool
    }

    private var commandTargets: [(MPRemoteCommand, Any)] = []
    /// The listening queue's next and previous item, for the next and previous track buttons
    /// of headphones and the lock screen; each returns false when there is no such item.
    static var queueCommands: (next: @MainActor () -> Bool, previous: @MainActor () -> Bool)?

    /// Publishes the title and state; nil clears the lock screen and stops answering controls.
    func update(title: String?, detail: String, state: ReadAloudSession.State, progress: Double?, commands: Commands) {
        guard let title else { clear(); return }
        if commandTargets.isEmpty { register(commands) }
        var information: [String: Any] = [
            MPMediaItemPropertyTitle: title,
            MPMediaItemPropertyArtist: detail,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
            MPNowPlayingInfoPropertyPlaybackRate: state == .speaking ? 1.0 : 0.0
        ]
        if let progress { information[MPNowPlayingInfoPropertyPlaybackProgress] = Float(min(1, max(0, progress))) }
        let center = MPNowPlayingInfoCenter.default()
        center.nowPlayingInfo = information
        #if os(macOS)
        center.playbackState = state == .speaking ? .playing : .paused
        #endif
    }

    func clear() {
        for (command, target) in commandTargets { command.removeTarget(target) }
        commandTargets.removeAll()
        let center = MPNowPlayingInfoCenter.default()
        center.nowPlayingInfo = nil
        #if os(macOS)
        center.playbackState = .stopped
        #endif
    }

    private func register(_ commands: Commands) {
        let center = MPRemoteCommandCenter.shared()
        func add(_ command: MPRemoteCommand, _ action: @escaping () -> Bool) {
            command.isEnabled = true
            let target = command.addTarget { _ in
                MainActor.assumeIsolated { action() } ? .success : .commandFailed
            }
            commandTargets.append((command, target))
        }
        add(center.playCommand, commands.play)
        add(center.pauseCommand, commands.pause)
        add(center.togglePlayPauseCommand) { commands.pause() || commands.play() }
        // Next and previous track move through the listening queue when there is one; the
        // skip buttons (and the track buttons without a queue) move by sentence.
        add(center.nextTrackCommand) { Self.queueCommands?.next() ?? false || commands.nextSentence() }
        add(center.previousTrackCommand) { Self.queueCommands?.previous() ?? false || commands.previousSentence() }
        center.skipForwardCommand.preferredIntervals = [10]
        center.skipBackwardCommand.preferredIntervals = [10]
        add(center.skipForwardCommand, commands.nextSentence)
        add(center.skipBackwardCommand, commands.previousSentence)
    }
}

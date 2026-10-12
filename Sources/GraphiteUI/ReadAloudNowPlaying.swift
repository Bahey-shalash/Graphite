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
        add(center.nextTrackCommand, commands.nextSentence)
        add(center.previousTrackCommand, commands.previousSentence)
    }
}

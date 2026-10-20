import Foundation
import AVFoundation
import GraphiteApple
import GraphiteCore

/// Plays rendered passages through `AVAudioEngine`. Speed goes through a time-pitch unit, so a
/// faster reading keeps the voice's pitch, and pausing holds the exact place within a passage.
///
/// On the silent route (`AudioOutputRoute.silent`, every test run) there is no engine: nothing is made that could open the audio
/// output, not even at zero volume (a running engine holds the device open). A passage is then "played" by the clock: its
/// position advances at the passage's rate, it can be paused, resumed and sped up, and `finished` runs when its last sample
/// would have been heard, so the screens that follow it see the same sequence of events.
@MainActor
final class RenderedPassagePlayer {
    /// The real audio path, made only for the speakers.
    private struct AudioPath {
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        let timePitch = AVAudioUnitTimePitch()
    }

    /// A passage playing by the clock instead of through an engine.
    private struct SilentPlayback {
        let token: UUID
        let segmentStartSeconds: Double
        let totalFileSeconds: Double
        var rate: Double
        /// File seconds played before the last change of rate or pause.
        var playedFileSeconds = 0.0
        /// When it last began running at `rate`; nil while paused.
        var runningSince: Duration?
    }

    private let output: AudioOutputRoute
    private let clock: any ApplicationClock
    private let audioPath: AudioPath?
    private var silentPlayback: SilentPlayback?
    private var silentTimer: Task<Void, Never>?
    private var silentFinished: (@MainActor () -> Void)?
    private var connectedFormat: AVAudioFormat?
    /// Where in the file the current segment began, so the playback time is file time.
    private var segmentStartSeconds = 0.0
    private var sampleRate = 24_000.0
    /// Changes with every play or stop; a completion from an earlier segment is ignored.
    private var playbackToken = UUID()
    private(set) var isPaused = false

    /// Whether this player is of the silent route: it has no engine and holds no audio device.
    var isSilent: Bool { audioPath == nil }

    /// Called when the engine stopped itself because its output changed (headphones unplugged,
    /// a Bluetooth device disconnected, a new sample rate), which ends the playing passage's sound.
    var engineConfigurationDidChange: (@MainActor () -> Void)?

    init(output: AudioOutputRoute = .thisProcess, clock: any ApplicationClock = LiveApplicationClock()) {
        self.output = output
        self.clock = clock
        guard output == .speakers else {
            audioPath = nil
            return
        }
        let path = AudioPath()
        audioPath = path
        path.engine.attach(path.player)
        path.engine.attach(path.timePitch)
        // The player lives as long as the speech does; the observer holds it weakly.
        NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: path.engine, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.engineConfigurationDidChange?() }
        }
    }

    /// The time-pitch rate that plays at `speed`, held to the speeds the controls offer so the
    /// audio plays at the speed the controls show. The unit accepts rates from 1/32 to 32.
    static func timePitchRate(forSpeed speed: Double) -> Float {
        Float(min(ReadAloudSession.speedRange.upperBound, max(ReadAloudSession.speedRange.lowerBound, speed)))
    }

    /// Plays `file` from `startSeconds` at `rate`, a speed from `ReadAloudSession.speedRange`; `finished` runs on the main
    /// actor when the last sample has been heard, unless playback was stopped or replaced.
    func play(_ file: URL, from startSeconds: Double, rate: Double, finished: @escaping @MainActor () -> Void) throws {
        stop()
        let audioFile = try AVAudioFile(forReading: file)
        let format = audioFile.processingFormat
        sampleRate = format.sampleRate
        let startFrame = AVAudioFramePosition(max(0, startSeconds) * format.sampleRate)
        let remainingFrames = audioFile.length - startFrame
        guard remainingFrames > 0 else { finished(); return }
        segmentStartSeconds = Double(startFrame) / format.sampleRate
        let token = UUID()
        playbackToken = token
        guard let audioPath else {
            silentPlayback = SilentPlayback(token: token, segmentStartSeconds: segmentStartSeconds,
                                            totalFileSeconds: Double(remainingFrames) / format.sampleRate, rate: Self.clampedRate(rate),
                                            runningSince: clock.now)
            silentFinished = finished
            isPaused = false
            scheduleSilentFinish()
            return
        }
        if connectedFormat != format {
            audioPath.engine.disconnectNodeOutput(audioPath.player)
            audioPath.engine.disconnectNodeOutput(audioPath.timePitch)
            // Set again only when both connections hold, so a failed one is retried next time.
            connectedFormat = nil
            try connect(audioPath.player, to: audioPath.timePitch, format: format, in: audioPath.engine)
            try connect(audioPath.timePitch, to: audioPath.engine.mainMixerNode, format: format, in: audioPath.engine)
            connectedFormat = format
        }
        audioPath.timePitch.rate = Self.timePitchRate(forSpeed: rate)
        audioPath.player.scheduleSegment(audioFile, startingFrame: startFrame, frameCount: AVAudioFrameCount(remainingFrames), at: nil,
                                         completionCallbackType: .dataPlayedBack) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.playbackToken == token else { return }
                finished()
            }
        }
        if !audioPath.engine.isRunning { try audioPath.engine.start() }
        try startPlayer(audioPath.player)
        isPaused = false
    }

    /// Seconds into the file being heard now, or nil when nothing plays.
    var currentSeconds: Double? {
        if audioPath == nil {
            guard let playback = silentPlayback else { return nil }
            return playback.segmentStartSeconds + min(playback.totalFileSeconds, playedFileSeconds(of: playback))
        }
        guard let player = audioPath?.player, let nodeTime = player.lastRenderTime,
              let playerTime = player.playerTime(forNodeTime: nodeTime) else { return nil }
        return segmentStartSeconds + Double(playerTime.sampleTime) / playerTime.sampleRate
    }

    func setRate(_ rate: Double) {
        guard let audioPath else {
            guard var playback = silentPlayback else { return }
            playback.playedFileSeconds = playedFileSeconds(of: playback)
            if playback.runningSince != nil { playback.runningSince = clock.now }
            playback.rate = Self.clampedRate(rate)
            silentPlayback = playback
            if !isPaused { scheduleSilentFinish() }
            return
        }
        audioPath.timePitch.rate = Self.timePitchRate(forSpeed: rate)
    }

    func pause() {
        if let audioPath {
            audioPath.player.pause()
        } else if var playback = silentPlayback {
            playback.playedFileSeconds = playedFileSeconds(of: playback)
            playback.runningSince = nil
            silentPlayback = playback
            silentTimer?.cancel()
        }
        isPaused = true
    }

    func resume() throws {
        if let audioPath {
            if !audioPath.engine.isRunning { try audioPath.engine.start() }
            try startPlayer(audioPath.player)
        } else if var playback = silentPlayback {
            playback.runningSince = clock.now
            silentPlayback = playback
            scheduleSilentFinish()
        }
        isPaused = false
    }

    func stop() {
        playbackToken = UUID()
        audioPath?.player.stop()
        silentTimer?.cancel()
        silentTimer = nil
        silentPlayback = nil
        silentFinished = nil
        isPaused = false
    }

    /// Stops the engine so the audio hardware is released once reading ends.
    func shutDown() {
        stop()
        audioPath?.engine.stop()
    }

    // MARK: Playing by the clock

    private static func clampedRate(_ rate: Double) -> Double {
        min(ReadAloudSession.speedRange.upperBound, max(ReadAloudSession.speedRange.lowerBound, rate))
    }

    private func playedFileSeconds(of playback: SilentPlayback) -> Double {
        guard let runningSince = playback.runningSince else { return playback.playedFileSeconds }
        let elapsed = clock.now - runningSince
        let elapsedSeconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
        return playback.playedFileSeconds + elapsedSeconds * playback.rate
    }

    /// Waits out what is left of the passage on the clock and then reports it finished.
    private func scheduleSilentFinish() {
        silentTimer?.cancel()
        guard let playback = silentPlayback else { return }
        let remainingSeconds = max(0, (playback.totalFileSeconds - playedFileSeconds(of: playback)) / playback.rate)
        silentTimer = Task { @MainActor [weak self, clock] in
            do { try await clock.sleep(for: .seconds(remainingSeconds)) } catch { return } // Paused, rate changed or replaced.
            guard let self, let current = self.silentPlayback, current.token == playback.token else { return }
            let finished = self.silentFinished
            self.silentPlayback = nil
            self.silentFinished = nil
            self.silentTimer = nil
            finished?()
        }
    }

    // Connecting and starting report failures as errors.

    private func connect(_ node: AVAudioNode, to destination: AVAudioNode, format: AVAudioFormat, in engine: AVAudioEngine) throws {
        try engine.connectNode(node, to: destination, format: format)
    }

    private func startPlayer(_ player: AVAudioPlayerNode) throws {
        try player.playAudio()
    }
}

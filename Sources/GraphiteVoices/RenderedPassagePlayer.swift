import Foundation
import AVFoundation
import GraphiteApple
import GraphiteCore

/// Plays rendered passages through `AVAudioEngine`. Speed goes through a time-pitch unit, so a
/// faster reading keeps the voice's pitch, and pausing holds the exact place within a passage.
@MainActor
final class RenderedPassagePlayer {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let timePitch = AVAudioUnitTimePitch()
    private var connectedFormat: AVAudioFormat?
    /// Where in the file the current segment began, so the playback time is file time.
    private var segmentStartSeconds = 0.0
    private var sampleRate = 24_000.0
    /// Changes with every play or stop; a completion from an earlier segment is ignored.
    private var playbackToken = UUID()
    private(set) var isPaused = false
    /// Whether nothing the engine plays is heard (`AudioOutputRoute.silent`).
    var isSilent: Bool { engine.mainMixerNode.outputVolume == 0 }

    /// Called when the engine stopped itself because its output changed (headphones unplugged,
    /// a Bluetooth device disconnected, a new sample rate), which ends the playing passage's sound.
    var engineConfigurationDidChange: (@MainActor () -> Void)?

    /// `.silent` plays at zero volume: the engine, the timing and the completions are the real ones.
    init(output: AudioOutputRoute = .thisProcess) {
        if output == .silent { engine.mainMixerNode.outputVolume = 0 }
        engine.attach(player)
        engine.attach(timePitch)
        // The player lives as long as the speech does; the observer holds it weakly.
        NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
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
        if connectedFormat != format {
            engine.disconnectNodeOutput(player)
            engine.disconnectNodeOutput(timePitch)
            // Set again only when both connections hold, so a failed one is retried next time.
            connectedFormat = nil
            try connect(player, to: timePitch, format: format)
            try connect(timePitch, to: engine.mainMixerNode, format: format)
            connectedFormat = format
        }
        timePitch.rate = Self.timePitchRate(forSpeed: rate)
        sampleRate = format.sampleRate
        let startFrame = AVAudioFramePosition(max(0, startSeconds) * format.sampleRate)
        let remainingFrames = audioFile.length - startFrame
        guard remainingFrames > 0 else { finished(); return }
        segmentStartSeconds = Double(startFrame) / format.sampleRate
        let token = UUID()
        playbackToken = token
        player.scheduleSegment(audioFile, startingFrame: startFrame, frameCount: AVAudioFrameCount(remainingFrames), at: nil,
                               completionCallbackType: .dataPlayedBack) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.playbackToken == token else { return }
                finished()
            }
        }
        if !engine.isRunning { try engine.start() }
        try startPlayer()
        isPaused = false
    }

    /// Seconds into the file being heard now, or nil when nothing plays.
    var currentSeconds: Double? {
        guard let nodeTime = player.lastRenderTime, let playerTime = player.playerTime(forNodeTime: nodeTime) else { return nil }
        return segmentStartSeconds + Double(playerTime.sampleTime) / playerTime.sampleRate
    }

    func setRate(_ rate: Double) {
        timePitch.rate = Self.timePitchRate(forSpeed: rate)
    }

    func pause() {
        player.pause()
        isPaused = true
    }

    func resume() throws {
        if !engine.isRunning { try engine.start() }
        try startPlayer()
        isPaused = false
    }

    func stop() {
        playbackToken = UUID()
        player.stop()
        isPaused = false
    }

    /// Stops the engine so the audio hardware is released once reading ends.
    func shutDown() {
        stop()
        engine.stop()
    }

    // Connecting and starting report failures as errors.

    private func connect(_ node: AVAudioNode, to destination: AVAudioNode, format: AVAudioFormat) throws {
        try engine.connectNode(node, to: destination, format: format)
    }

    private func startPlayer() throws {
        try player.playAudio()
    }
}

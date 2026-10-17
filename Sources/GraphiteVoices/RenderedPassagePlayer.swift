import Foundation
import AVFoundation

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

    init() {
        engine.attach(player)
        engine.attach(timePitch)
    }

    /// Plays `file` from `startSeconds` at `rate` (0.5 to 1.5); `finished` runs on the main
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
        timePitch.rate = Float(min(1.5, max(0.5, rate)))
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
        timePitch.rate = Float(min(1.5, max(0.5, rate)))
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

    // From macOS 27 and iOS 27 connecting and starting report failures as errors; before,
    // they could only raise an exception.

    private func connect(_ node: AVAudioNode, to destination: AVAudioNode, format: AVAudioFormat) throws {
        if #available(iOS 27, *) {
            try engine.connectNode(node, to: destination, format: format)
        } else {
            engine.connect(node, to: destination, format: format)
        }
    }

    private func startPlayer() throws {
        if #available(iOS 27, *) {
            try player.playAudio()
        } else {
            player.play()
        }
    }
}

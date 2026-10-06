import Foundation
import AVFoundation
import CoreMedia
import GraphiteCore

/// Writes one part of a video recording: an MP4 with H.264 video and AAC sound. The file
/// is written as movie fragments, so if nobody closes it (the app is ended, the device
/// loses power) it stays playable up to its last whole fragment; closing it turns it into
/// an ordinary MP4 with one index. Used from one queue at a time.
final class MoviePartWriter {
    /// A cut-off file loses at most the fragment being filled, so about this much.
    static let fragmentInterval = CMTime(value: 1, timescale: 1)
    /// How long an append waits for the encoder before the sample is dropped. The wait
    /// holds up the capture queue, which makes the camera drop frames instead of piling them up.
    static let maximumReadinessWaitSeconds = 0.1
    private static let readinessPollSeconds = 0.002
    /// Bits per pixel and second: about 4.5 Mbit/s for 1080p, 2 Mbit/s for 720p.
    private static let videoBitsPerPixel = 2.2
    private static let expectedFramesPerSecond = 30
    private static let nominalFrameDuration = CMTime(value: 1, timescale: CMTimeScale(expectedFramesPerSecond))
    private static let maximumSecondsBetweenKeyFrames = 2
    /// Mono AAC at 44.1 kHz, as audio recordings are; the writer converts what the
    /// microphone delivers.
    private static var audioSettings: [String: Any] { [
        AVFormatIDKey: kAudioFormatMPEG4AAC,
        AVSampleRateKey: 44_100,
        AVNumberOfChannelsKey: 1,
        AVEncoderBitRateKey: 96_000,
    ] }

    enum AppendOutcome {
        case appended
        /// Left out: the encoder was busy, or the sample overlaps one already written.
        case dropped
        /// The writer failed, with its error. The file holds what was written before.
        case failed(Error?)
    }

    let location: URL
    private let writer: AVAssetWriter
    private let videoInput: AVAssetWriterInput
    private let audioInput: AVAssetWriterInput
    private let startTime: CMTime
    /// Subtracted from incoming times, so the file has no gap where recording was paused.
    private var timeOffset = CMTime.zero
    /// The time of the last frame written, and where the video and the sound end, all in
    /// the file's own timeline.
    private var lastVideoTime: CMTime?
    private var videoEndTime: CMTime
    private var audioEndTime: CMTime
    private var closesGapAtNextSample = false
    private(set) var droppedSampleCount = 0
    /// Microphone buffers follow each other to within a sample or two; sound that starts
    /// further back than this overlaps what is written.
    private static let audioOverlapTolerance = CMTime(value: 5, timescale: 1_000)

    /// The length of what was written, in seconds.
    var writtenSeconds: TimeInterval { max(max(videoEndTime, audioEndTime) - startTime, .zero).seconds }

    /// Opens the file and writes `firstVideoFrame`, whose size the video keeps. Frames of
    /// another shape, as after the device is turned, are fitted inside that size.
    init(location: URL, firstVideoFrame: CMSampleBuffer) throws {
        guard let imageBuffer = firstVideoFrame.imageBuffer, firstVideoFrame.presentationTimeStamp.isNumeric else {
            throw GraphiteError.unavailable("The camera delivered a frame Graphite cannot record.")
        }
        // H.264 encodes whole blocks of two pixels.
        let width = CVPixelBufferGetWidth(imageBuffer) / 2 * 2, height = CVPixelBufferGetHeight(imageBuffer) / 2 * 2
        guard width > 0, height > 0 else { throw GraphiteError.unavailable("The camera delivered a frame Graphite cannot record.") }
        self.location = location
        writer = try AVAssetWriter(outputURL: location, fileType: .mp4)
        writer.movieFragmentInterval = Self.fragmentInterval
        videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoScalingModeKey: AVVideoScalingModeResizeAspect,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: Int(Double(width * height) * Self.videoBitsPerPixel),
                AVVideoExpectedSourceFrameRateKey: Self.expectedFramesPerSecond,
                AVVideoMaxKeyFrameIntervalDurationKey: Self.maximumSecondsBetweenKeyFrames,
                // With reordered frames the fragment writer fails (-16341) as soon as two
                // frames are not evenly spaced, which a dropped frame or a pause causes.
                AVVideoAllowFrameReorderingKey: false,
            ],
        ])
        videoInput.expectsMediaDataInRealTime = true
        audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: Self.audioSettings)
        audioInput.expectsMediaDataInRealTime = true
        guard writer.canAdd(videoInput), writer.canAdd(audioInput) else {
            throw GraphiteError.unavailable("This device cannot write H.264 video with AAC sound.")
        }
        writer.add(videoInput); writer.add(audioInput)
        startTime = firstVideoFrame.presentationTimeStamp
        videoEndTime = startTime; audioEndTime = startTime
        guard writer.startWriting() else { throw writer.error ?? GraphiteError.unavailable("The video file could not be created.") }
        writer.startSession(atSourceTime: startTime)
        if case .failed(let error) = append(firstVideoFrame, kind: .video) {
            writer.cancelWriting()
            throw error ?? GraphiteError.unavailable("The video file could not be written.")
        }
    }

    /// Makes the next sample follow the last one written, whatever time passed between
    /// them, as after a pause.
    func closeGapAtNextSample() {
        closesGapAtNextSample = true
    }

    func append(_ sampleBuffer: CMSampleBuffer, kind: CaptureMediaKind) -> AppendOutcome {
        guard writer.status == .writing else { return .failed(writer.error) }
        let capturedTime = sampleBuffer.presentationTimeStamp
        guard capturedTime.isNumeric else { return .dropped }
        if closesGapAtNextSample {
            // Where the file ends: a frame carries no length, so the picture ends one frame
            // after the last one. The sound goes on without a gap when it ends last.
            let pictureEndTime = max(videoEndTime, (lastVideoTime ?? startTime) + Self.nominalFrameDuration)
            timeOffset = capturedTime - max(pictureEndTime, audioEndTime)
            closesGapAtNextSample = false
        }
        let time = capturedTime - timeOffset
        // The writer fails on a frame that does not follow the last one, and on sound from
        // before the part's first frame or overlapping what its track holds, as the first
        // buffer delivered after a pause can.
        switch kind {
        case .video: guard lastVideoTime.map({ lastVideoTime in time > lastVideoTime }) ?? true else { return .dropped }
        case .audio: guard time >= startTime, time >= audioEndTime - Self.audioOverlapTolerance else { return .dropped }
        }
        let retimedBuffer: CMSampleBuffer
        if timeOffset == .zero {
            retimedBuffer = sampleBuffer
        } else {
            do {
                let timings = try sampleBuffer.sampleTimingInfos().map { timing in
                    CMSampleTimingInfo(duration: timing.duration, presentationTimeStamp: timing.presentationTimeStamp - timeOffset,
                                       decodeTimeStamp: timing.decodeTimeStamp.isNumeric ? timing.decodeTimeStamp - timeOffset : timing.decodeTimeStamp)
                }
                retimedBuffer = try CMSampleBuffer(copying: sampleBuffer, withNewTiming: timings)
            } catch {
                droppedSampleCount += 1
                return .dropped
            }
        }
        let input = kind == .video ? videoInput : audioInput
        var waitedSeconds = 0.0
        while !input.isReadyForMoreMediaData {
            guard waitedSeconds < Self.maximumReadinessWaitSeconds, writer.status == .writing else {
                droppedSampleCount += 1
                return writer.status == .writing ? .dropped : .failed(writer.error)
            }
            Thread.sleep(forTimeInterval: Self.readinessPollSeconds)
            waitedSeconds += Self.readinessPollSeconds
        }
        guard input.append(retimedBuffer) else { return .failed(writer.error) }
        let duration = sampleBuffer.duration
        let endTime = duration.isNumeric ? time + duration : time
        switch kind {
        case .video: lastVideoTime = time; videoEndTime = max(videoEndTime, endTime)
        case .audio: audioEndTime = max(audioEndTime, endTime)
        }
        return .appended
    }

    /// Closes the file, which makes it an ordinary MP4. A writer that already failed has
    /// nothing to close; its file keeps its fragments.
    func finish(completion: @escaping @Sendable () -> Void) {
        guard writer.status == .writing else { completion(); return }
        videoInput.markAsFinished(); audioInput.markAsFinished()
        writer.finishWriting(completionHandler: completion)
    }

    /// Whether an error means the volume has no room left.
    static func isStorageFull(_ error: Error?) -> Bool {
        var remainingError = error as NSError?
        // The writer wraps the file system's error; a few levels cover every case seen.
        for _ in 0..<4 {
            guard let examinedError = remainingError else { return false }
            if examinedError.domain == AVFoundationErrorDomain, examinedError.code == AVError.Code.diskFull.rawValue { return true }
            if examinedError.domain == NSPOSIXErrorDomain, examinedError.code == Int(ENOSPC) { return true }
            if examinedError.domain == NSCocoaErrorDomain, examinedError.code == NSFileWriteOutOfSpaceError { return true }
            remainingError = examinedError.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        return false
    }
}

/// The parts of one video recording, made into the single MP4 that is saved into the vault.
enum RecordedMovie {
    /// One ordinary MP4 holding the playable parts in order: the part itself when it is the
    /// only one and was closed properly, otherwise a new file beside the first part, with
    /// the same encoded video and sound (nothing is encoded again). A part that was cut off
    /// contributes what it holds up to its last fragment. Throws when no part can be played.
    static func playableMovie(from partLocations: [URL]) async throws -> URL {
        var playableParts: [(asset: AVURLAsset, duration: CMTime)] = []
        for partLocation in partLocations {
            let asset = AVURLAsset(url: partLocation)
            guard let duration = try? await asset.load(.duration), duration.isNumeric, duration > .zero,
                  let videoTracks = try? await asset.loadTracks(withMediaType: .video), !videoTracks.isEmpty else { continue }
            playableParts.append((asset, duration))
        }
        guard let firstPart = playableParts.first, let firstPartLocation = partLocations.first else {
            throw GraphiteError.invalidFile("The recording contains no playable video.")
        }
        if playableParts.count == 1, (try? await firstPart.asset.load(.containsFragments)) == false { return firstPart.asset.url }

        let composition = AVMutableComposition()
        guard let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
              let audioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw GraphiteError.unavailable("The parts of the recording could not be joined.")
        }
        var partStart = CMTime.zero
        var hasAudio = false
        for part in playableParts {
            for (mediaType, compositionTrack) in [(AVMediaType.video, videoTrack), (AVMediaType.audio, audioTrack)] {
                guard let track = try await part.asset.loadTracks(withMediaType: mediaType).first else { continue }
                let timeRange = try await track.load(.timeRange)
                guard timeRange.duration > .zero else { continue }
                try compositionTrack.insertTimeRange(timeRange, of: track, at: partStart)
                if mediaType == .audio { hasAudio = true }
            }
            partStart = partStart + part.duration
        }
        // A track with nothing in it cannot be exported.
        if !hasAudio { composition.removeTrack(audioTrack) }

        let combinedLocation = RecordingRecoveryFolder.combinedMovieLocation(forRecordingAt: firstPartLocation)
        // A join that stopped halfway is started again.
        try? FileManager.default.removeItem(at: combinedLocation)
        guard let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough) else {
            throw GraphiteError.unavailable("The parts of the recording could not be joined.")
        }
        do {
            try await session.export(to: combinedLocation, as: .mp4)
            let combinedDuration = try await AVURLAsset(url: combinedLocation).load(.duration)
            guard combinedDuration.isNumeric, combinedDuration > .zero else {
                throw GraphiteError.invalidFile("The joined recording contains no playable video. Its parts are kept.")
            }
        } catch {
            try? FileManager.default.removeItem(at: combinedLocation)
            if MoviePartWriter.isStorageFull(error) {
                throw GraphiteError.unavailable("There is not enough free storage to save the video. Free some space, then try saving again. The recording is kept.")
            }
            throw error
        }
        return combinedLocation
    }
}

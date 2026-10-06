import Foundation
import AVFoundation
import CoreMedia
import CoreVideo
import GraphiteCore
@testable import GraphiteApple

/// A capture source without hardware: it makes real pixel buffers and PCM sound on a clock
/// the test moves, and delivers them like a camera and microphone would. Everything after
/// the source (the writer, the parts, the published MP4) is the code the app runs.
///
/// Frames are one flat colour per camera, so a reader can tell which camera a frame came
/// from, with a bright bar that moves across the top, so no two frames are alike. `@unchecked Sendable`: state is behind `lock`.
final class SyntheticCaptureSource: VideoCaptureSource, @unchecked Sendable {
    static let framesPerSecond = 30
    /// Ticks of the source's clock in a second, which is also the sound's sample rate.
    static let clockRate: CMTimeScale = 48_000
    private static let ticksPerFrame = Int(clockRate) / framesPerSecond
    /// Blue, green, red: what a frame from each camera is filled with.
    static let backCameraColor: [UInt8] = [200, 60, 40]
    static let frontCameraColor: [UInt8] = [40, 200, 60]

    private struct Delivery {
        let queue: DispatchQueue
        let samples: @Sendable (CMSampleBuffer, CaptureMediaKind) -> Void
        let events: @Sendable (VideoCaptureEvent) -> Void
    }

    private let lock = NSLock()
    private var delivery: Delivery?
    private var camera = CameraPosition.back
    /// The clock, in ticks; it starts well after zero, as a device's clock does.
    private var clockTicks = 1_000 * Int(clockRate)
    private var frameWidth = 640
    private var frameHeight = 360
    private var realTimeTimer: DispatchSourceTimer?
    private var problemOnStart: (any Error)?
    private var problemOnResume: (any Error)?
    private var cameras: [CameraPosition] = [.back, .front]
    private var isInterrupted = false
    private var holdsStart = false
    private var startRelease: CheckedContinuation<Void, Never>?
    private(set) var startCount = 0
    private(set) var stopCount = 0

    init(problemOnStart: (any Error)? = nil, cameras: [CameraPosition] = [.back, .front]) {
        self.problemOnStart = problemOnStart
        self.cameras = cameras
    }

    func start(camera: CameraPosition, deliveringOn deliveryQueue: DispatchQueue,
               samples: @escaping @Sendable (CMSampleBuffer, CaptureMediaKind) -> Void,
               events: @escaping @Sendable (VideoCaptureEvent) -> Void) async throws {
        lock.withLock { startCount += 1 }
        if lock.withLock({ holdsStart }) {
            await withCheckedContinuation { continuation in
                let isAlreadyReleased = lock.withLock { () -> Bool in
                    guard holdsStart else { return true }
                    startRelease = continuation
                    return false
                }
                if isAlreadyReleased { continuation.resume() }
            }
        }
        try lock.withLock {
            if let problemOnStart { throw problemOnStart }
            self.camera = camera
            delivery = Delivery(queue: deliveryQueue, samples: samples, events: events)
        }
    }

    /// Makes `start` wait, as a camera or a permission prompt that takes its time does.
    func holdStart() {
        lock.withLock { holdsStart = true }
    }

    func releaseStart() {
        let continuation = lock.withLock { () -> CheckedContinuation<Void, Never>? in
            holdsStart = false
            defer { startRelease = nil }
            return startRelease
        }
        continuation?.resume()
    }

    func availableCameras() async -> [CameraPosition] { lock.withLock { cameras } }

    func switchCamera(to camera: CameraPosition) async throws {
        try lock.withLock {
            guard cameras.contains(camera) else { throw CaptureAccessProblem.noCamera }
            self.camera = camera
        }
    }

    func resumeAfterInterruption() async throws {
        try lock.withLock {
            if let problemOnResume { throw problemOnResume }
            isInterrupted = false
        }
    }

    func stop() async {
        lock.withLock {
            stopCount += 1
            realTimeTimer?.cancel(); realTimeTimer = nil
            delivery = nil
        }
    }

    // MARK: What a test does to the source

    /// Delivers `seconds` of frames and sound at once, and returns when they are handled.
    /// Nothing is delivered while the source is interrupted, as with a real camera.
    func deliver(seconds: Double) async {
        let frameCount = Int((seconds * Double(Self.framesPerSecond)).rounded())
        for _ in 0..<frameCount { deliverOneFrame() }
        await waitUntilDelivered()
    }

    /// Lets time pass without delivering anything.
    func advanceClock(bySeconds seconds: Double) {
        lock.withLock { clockTicks += Int(seconds * Double(Self.clockRate)) }
    }

    /// Frames come out turned a quarter, as when the device is turned.
    func turnDevice() {
        lock.withLock { swap(&frameWidth, &frameHeight) }
    }

    func interrupt(_ reason: CaptureInterruptionReason) async {
        let delivery = lock.withLock { isInterrupted = true; return self.delivery }
        delivery?.queue.async { delivery?.events(.interrupted(reason)) }
        await waitUntilDelivered()
    }

    /// The system gives the camera back. `resuming: false` is a system that leaves
    /// restarting to the app.
    func endInterruption(resuming: Bool = true) async {
        let delivery = lock.withLock { if resuming { isInterrupted = false }; return self.delivery }
        delivery?.queue.async { delivery?.events(.interruptionEnded) }
        await waitUntilDelivered()
    }

    func failResuming(with problem: (any Error)?) {
        lock.withLock { problemOnResume = problem }
    }

    /// Delivers frames and sound as the clock runs, until the source stops, for tests
    /// that show the preview on screen.
    func deliverInRealTime() {
        lock.withLock {
            guard realTimeTimer == nil, let delivery else { return }
            let timer = DispatchSource.makeTimerSource(queue: delivery.queue)
            timer.schedule(deadline: .now(), repeating: 1 / Double(Self.framesPerSecond))
            timer.setEventHandler { [weak self] in self?.deliverOneFrame() }
            realTimeTimer = timer
            timer.resume()
        }
    }

    private func waitUntilDelivered() async {
        guard let queue = lock.withLock({ delivery?.queue }) else { return }
        await withCheckedContinuation { continuation in queue.async { continuation.resume() } }
    }

    private func deliverOneFrame() {
        let (delivery, ticks, camera, width, height): (Delivery?, Int, CameraPosition, Int, Int) = lock.withLock {
            let ticks = clockTicks
            clockTicks += Self.ticksPerFrame
            return (isInterrupted ? nil : self.delivery, ticks, self.camera, frameWidth, frameHeight)
        }
        guard let delivery, let frame = Self.videoFrame(atTicks: ticks, camera: camera, width: width, height: height),
              let sound = Self.sound(atTicks: ticks) else { return }
        let frameBox = UncheckedSampleBuffer(buffer: frame), soundBox = UncheckedSampleBuffer(buffer: sound)
        delivery.queue.async {
            delivery.samples(frameBox.buffer, .video)
            delivery.samples(soundBox.buffer, .audio)
        }
    }

    /// A sample handed to the delivery queue, which alone uses it from then on.
    private struct UncheckedSampleBuffer: @unchecked Sendable {
        let buffer: CMSampleBuffer
    }

    private static func videoFrame(atTicks ticks: Int, camera: CameraPosition, width: Int, height: Int) -> CMSampleBuffer? {
        var createdBuffer: CVPixelBuffer?
        let attributes = [kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary] as CFDictionary
        guard CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, attributes, &createdBuffer) == kCVReturnSuccess,
              let pixelBuffer = createdBuffer else { return nil }
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        if let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) {
            let pixels = baseAddress.assumingMemoryBound(to: UInt8.self)
            let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
            let color = camera == .back ? backCameraColor : frontCameraColor
            let barStart = (ticks / ticksPerFrame * 4) % max(width - 16, 1)
            for row in 0..<height {
                for column in 0..<width {
                    let offset = row * bytesPerRow + column * 4
                    let isInBar = row < height / 4 && column >= barStart && column < barStart + 16
                    pixels[offset] = isInBar ? 255 : color[0]
                    pixels[offset + 1] = isInBar ? 255 : color[1]
                    pixels[offset + 2] = isInBar ? 255 : color[2]
                    pixels[offset + 3] = 255
                }
            }
        }
        CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
        var formatDescription: CMVideoFormatDescription?
        guard CMVideoFormatDescriptionCreateForImageBuffer(allocator: nil, imageBuffer: pixelBuffer, formatDescriptionOut: &formatDescription) == noErr,
              let formatDescription else { return nil }
        // A camera's frames carry a time and no length.
        var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: CMTime(value: CMTimeValue(ticks), timescale: clockRate), decodeTimeStamp: .invalid)
        var sampleBuffer: CMSampleBuffer?
        CMSampleBufferCreateReadyWithImageBuffer(allocator: nil, imageBuffer: pixelBuffer, formatDescription: formatDescription,
                                                 sampleTiming: &timing, sampleBufferOut: &sampleBuffer)
        return sampleBuffer
    }

    /// One frame's worth of a quiet tone: 16-bit stereo PCM at the clock's rate.
    private static func sound(atTicks ticks: Int) -> CMSampleBuffer? {
        let channelCount = 2
        var streamDescription = AudioStreamBasicDescription(
            mSampleRate: Float64(clockRate), mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
            mBytesPerPacket: UInt32(2 * channelCount), mFramesPerPacket: 1, mBytesPerFrame: UInt32(2 * channelCount),
            mChannelsPerFrame: UInt32(channelCount), mBitsPerChannel: 16, mReserved: 0)
        var formatDescription: CMAudioFormatDescription?
        guard CMAudioFormatDescriptionCreate(allocator: nil, asbd: &streamDescription, layoutSize: 0, layout: nil, magicCookieSize: 0,
                                             magicCookie: nil, extensions: nil, formatDescriptionOut: &formatDescription) == noErr,
              let formatDescription else { return nil }
        var samples = [Int16](repeating: 0, count: ticksPerFrame * channelCount)
        for frameIndex in 0..<ticksPerFrame {
            let level = Int16(sin(Double(ticks + frameIndex) * 0.06) * 6_000)
            for channel in 0..<channelCount { samples[frameIndex * channelCount + channel] = level }
        }
        let byteCount = samples.count * MemoryLayout<Int16>.size
        var blockBuffer: CMBlockBuffer?
        guard CMBlockBufferCreateWithMemoryBlock(allocator: nil, memoryBlock: nil, blockLength: byteCount, blockAllocator: nil, customBlockSource: nil,
                                                 offsetToData: 0, dataLength: byteCount, flags: 0, blockBufferOut: &blockBuffer) == noErr,
              let blockBuffer else { return nil }
        let copyStatus = samples.withUnsafeBytes { bytes -> OSStatus in
            guard let baseAddress = bytes.baseAddress else { return -1 }
            return CMBlockBufferReplaceDataBytes(with: baseAddress, blockBuffer: blockBuffer, offsetIntoDestination: 0, dataLength: byteCount)
        }
        guard copyStatus == noErr else { return nil }
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: clockRate),
                                        presentationTimeStamp: CMTime(value: CMTimeValue(ticks), timescale: clockRate), decodeTimeStamp: .invalid)
        var sampleBuffer: CMSampleBuffer?
        CMSampleBufferCreate(allocator: nil, dataBuffer: blockBuffer, dataReady: true, makeDataReadyCallback: nil, refcon: nil,
                             formatDescription: formatDescription, sampleCount: ticksPerFrame, sampleTimingEntryCount: 1, sampleTimingArray: &timing,
                             sampleSizeEntryCount: 0, sampleSizeArray: nil, sampleBufferOut: &sampleBuffer)
        return sampleBuffer
    }
}

/// What an independent reader (`AVAsset` and `AVAssetReader`, which share nothing with
/// the writer under test) finds in a movie file.
struct MovieInspection {
    var durationSeconds = 0.0
    var isPlayable = false
    /// True for a file still in fragments, as a recording nobody closed is.
    var containsFragments = false
    var videoCodec = ""
    var audioCodec = ""
    var videoWidth = 0
    var videoHeight = 0
    var audioSampleRate = 0.0
    var audioChannelCount = 0
    /// Frames the reader could decode, and the longest time between two of them.
    var decodedFrameCount = 0
    var longestSecondsBetweenFrames = 0.0
    var decodedAudioSampleCount = 0
    /// Blue, green, red in the middle of the first and the last frame, and at the middle
    /// of the last frame's left edge.
    var firstFrameColor: [UInt8] = []
    var lastFrameColor: [UInt8] = []
    var lastFrameLeftEdgeColor: [UInt8] = []
    /// The file's top-level boxes, in order.
    var boxNames: [String] = []

    static func of(_ location: URL) async throws -> MovieInspection {
        var inspection = MovieInspection()
        inspection.boxNames = topLevelBoxNames(of: location)
        let asset = AVURLAsset(url: location)
        inspection.durationSeconds = try await asset.load(.duration).seconds
        inspection.isPlayable = try await asset.load(.isPlayable)
        inspection.containsFragments = try await asset.load(.containsFragments)
        let reader = try AVAssetReader(asset: asset)
        var videoOutput: AVAssetReaderTrackOutput?
        var audioOutput: AVAssetReaderTrackOutput?
        if let videoTrack = try await asset.loadTracks(withMediaType: .video).first {
            let size = try await videoTrack.load(.naturalSize)
            inspection.videoWidth = Int(size.width); inspection.videoHeight = Int(size.height)
            inspection.videoCodec = try await codecName(of: videoTrack)
            let output = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
            reader.add(output); videoOutput = output
        }
        if let audioTrack = try await asset.loadTracks(withMediaType: .audio).first {
            inspection.audioCodec = try await codecName(of: audioTrack)
            if let description = try await audioTrack.load(.formatDescriptions).first,
               let streamDescription = CMAudioFormatDescriptionGetStreamBasicDescription(description)?.pointee {
                inspection.audioSampleRate = streamDescription.mSampleRate
                inspection.audioChannelCount = Int(streamDescription.mChannelsPerFrame)
            }
            let output = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: [AVFormatIDKey: kAudioFormatLinearPCM])
            reader.add(output); audioOutput = output
        }
        guard reader.startReading() else { throw reader.error ?? GraphiteError.invalidFile("The reader could not start.") }
        var previousFrameSeconds: Double?
        while let frame = videoOutput?.copyNextSampleBuffer() {
            let frameSeconds = frame.presentationTimeStamp.seconds
            if let previousFrameSeconds { inspection.longestSecondsBetweenFrames = max(inspection.longestSecondsBetweenFrames, frameSeconds - previousFrameSeconds) }
            previousFrameSeconds = frameSeconds
            if let pixelBuffer = frame.imageBuffer {
                let width = CVPixelBufferGetWidth(pixelBuffer), height = CVPixelBufferGetHeight(pixelBuffer)
                if inspection.decodedFrameCount == 0 { inspection.firstFrameColor = color(in: pixelBuffer, column: width / 2, row: height - 8) }
                inspection.lastFrameColor = color(in: pixelBuffer, column: width / 2, row: height - 8)
                inspection.lastFrameLeftEdgeColor = color(in: pixelBuffer, column: 6, row: height / 2)
            }
            inspection.decodedFrameCount += 1
        }
        while let sound = audioOutput?.copyNextSampleBuffer() { inspection.decodedAudioSampleCount += sound.numSamples }
        guard reader.status == .completed else { throw reader.error ?? GraphiteError.invalidFile("The reader did not reach the end of the file.") }
        return inspection
    }

    private static func codecName(of track: AVAssetTrack) async throws -> String {
        guard let description = try await track.load(.formatDescriptions).first else { return "" }
        let code = CMFormatDescriptionGetMediaSubType(description)
        let bytes = [UInt8(code >> 24 & 0xFF), UInt8(code >> 16 & 0xFF), UInt8(code >> 8 & 0xFF), UInt8(code & 0xFF)]
        return String(decoding: bytes, as: UTF8.self).trimmingCharacters(in: .whitespaces)
    }

    private static func color(in pixelBuffer: CVPixelBuffer, column: Int, row: Int) -> [UInt8] {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else { return [] }
        let offset = row * CVPixelBufferGetBytesPerRow(pixelBuffer) + column * 4
        let pixels = baseAddress.assumingMemoryBound(to: UInt8.self)
        return [pixels[offset], pixels[offset + 1], pixels[offset + 2]]
    }

    /// Reads the size and name of each top-level box of an ISO media file.
    static func topLevelBoxNames(of location: URL) -> [String] {
        guard let handle = try? FileHandle(forReadingFrom: location), let fileSize = try? handle.seekToEnd() else { return [] }
        defer { try? handle.close() }
        var names: [String] = []
        var offset: UInt64 = 0
        while offset + 8 <= fileSize {
            guard (try? handle.seek(toOffset: offset)) != nil, let header = try? handle.read(upToCount: 16), header.count >= 8 else { break }
            let headerBytes = [UInt8](header)
            var boxSize = headerBytes[0..<4].reduce(UInt64(0)) { size, byte in size << 8 | UInt64(byte) }
            if boxSize == 1, headerBytes.count >= 16 { boxSize = headerBytes[8..<16].reduce(UInt64(0)) { size, byte in size << 8 | UInt64(byte) } }
            names.append(String(decoding: headerBytes[4..<8], as: UTF8.self))
            guard boxSize >= 8 else { break }
            offset += boxSize
        }
        return names
    }

    /// Whether two colours are the same to within what H.264 changes.
    static func colors(_ first: [UInt8], match second: [UInt8], tolerance: Int = 40) -> Bool {
        first.count == second.count && zip(first, second).allSatisfy { firstComponent, secondComponent in abs(Int(firstComponent) - Int(secondComponent)) <= tolerance }
    }
}

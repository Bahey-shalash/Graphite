import Foundation
import AVFoundation
import GraphiteCore

/// A rendered passage ready to play: its audio file and, when alignment worked, its words' times.
public struct CachedReadAloudPassage: Sendable {
    public let audioFile: URL
    public let durationSeconds: Double
    /// Nil when speech recognition could not match the passage; the reader then highlights
    /// the whole passage.
    public let wordTimings: [ReadAloudTimedWord]?
}

/// What is stored beside each audio file.
private struct CachedPassageDetails: Codable {
    var durationSeconds: Double
    var wordTimings: [ReadAloudTimedWord]?
}

/// Rendered passages in Graphite's caches folder, never in the vault: an AAC file and a small
/// JSON file of word timings per passage, named by the passage's cache key, plus an index of
/// sizes and last use. When the folder grows past its limit the least recently used passages
/// are removed, except those of the document being read. The system may also empty the
/// folder when storage runs low; a missing passage is simply rendered again.
public actor ReadAloudAudioCache {
    private let folder: URL
    private let capacityBytes: Int64
    private var entries: [ReadAloudAudioCacheKey: ReadAloudAudioCacheEntry]
    private var protectedKeys: Set<ReadAloudAudioCacheKey> = []

    public static func defaultFolder() throws -> URL {
        try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("ReadAloudAudio", isDirectory: true)
    }

    public init(folder: URL, capacityBytes: Int64 = ReadAloudAudioCacheEviction.defaultCapacityBytes) {
        self.folder = folder
        self.capacityBytes = capacityBytes
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let indexData = try? Data(contentsOf: folder.appendingPathComponent(Self.indexFileName))
        let stored = indexData.flatMap { data in try? JSONDecoder().decode([ReadAloudAudioCacheEntry].self, from: data) } ?? []
        entries = Dictionary(stored.map { entry in (entry.key, entry) }, uniquingKeysWith: { first, _ in first })
    }

    private static let indexFileName = "index.json"
    private func audioFile(_ key: ReadAloudAudioCacheKey) -> URL { folder.appendingPathComponent("\(key.value).m4a") }
    private func detailsFile(_ key: ReadAloudAudioCacheKey) -> URL { folder.appendingPathComponent("\(key.value).json") }

    /// The passages of the document being read, which eviction leaves alone.
    public func protect(_ keys: Set<ReadAloudAudioCacheKey>) {
        protectedKeys = keys
    }

    public func contains(_ key: ReadAloudAudioCacheKey) -> Bool {
        entries[key] != nil && FileManager.default.fileExists(atPath: audioFile(key).path)
    }

    /// The passage, marked as just used, or nil when it was never rendered or was removed.
    public func passage(for key: ReadAloudAudioCacheKey) -> CachedReadAloudPassage? {
        guard entries[key] != nil,
              FileManager.default.fileExists(atPath: audioFile(key).path),
              let data = try? Data(contentsOf: detailsFile(key)),
              let details = try? JSONDecoder().decode(CachedPassageDetails.self, from: data) else {
            entries[key] = nil
            return nil
        }
        entries[key]?.lastUsed = Date()
        saveIndex()
        return CachedReadAloudPassage(audioFile: audioFile(key), durationSeconds: details.durationSeconds, wordTimings: details.wordTimings)
    }

    /// Encodes rendered speech as AAC into a file the caller can analyze before `commit`.
    public func writeAudio(_ speech: RenderedSpeech, for key: ReadAloudAudioCacheKey) throws -> URL {
        let destination = audioFile(key)
        try? FileManager.default.removeItem(at: destination)
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Double(speech.sampleRate), channels: 1, interleaved: false),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(speech.samples.count)) else {
            throw CocoaError(.fileWriteUnknown)
        }
        buffer.frameLength = AVAudioFrameCount(speech.samples.count)
        if let channel = buffer.floatChannelData?[0] {
            speech.samples.withUnsafeBufferPointer { samples in
                if let base = samples.baseAddress { channel.update(from: base, count: samples.count) }
            }
        }
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: Double(speech.sampleRate),
                                       AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 64_000]
        do {
            let file = try AVAudioFile(forWriting: destination, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
            try file.write(from: buffer)
        }
        return destination
    }

    /// Records a passage whose audio `writeAudio` wrote, with its word timings, and removes old
    /// passages if the cache is now over its limit.
    public func commit(_ key: ReadAloudAudioCacheKey, durationSeconds: Double, wordTimings: [ReadAloudTimedWord]?) throws {
        let details = CachedPassageDetails(durationSeconds: durationSeconds, wordTimings: wordTimings)
        try JSONEncoder().encode(details).write(to: detailsFile(key), options: .atomic)
        let byteCount = [audioFile(key), detailsFile(key)].reduce(Int64(0)) { total, file in
            total + Int64((try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        entries[key] = ReadAloudAudioCacheEntry(key: key, byteCount: byteCount, lastUsed: Date())
        evictIfNeeded()
        saveIndex()
    }

    public var totalBytes: Int64 { entries.values.reduce(0) { total, entry in total + entry.byteCount } }

    /// Removes every cached passage.
    public func removeAll() {
        entries = [:]
        if let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) {
            for file in files { try? FileManager.default.removeItem(at: file) }
        }
    }

    private func evictIfNeeded() {
        for key in ReadAloudAudioCacheEviction.keysToRemove(from: Array(entries.values), capacityBytes: capacityBytes, protectedKeys: protectedKeys) {
            entries[key] = nil
            try? FileManager.default.removeItem(at: audioFile(key))
            try? FileManager.default.removeItem(at: detailsFile(key))
        }
    }

    private func saveIndex() {
        guard let data = try? JSONEncoder().encode(Array(entries.values)) else { return }
        try? data.write(to: folder.appendingPathComponent(Self.indexFileName), options: .atomic)
    }
}

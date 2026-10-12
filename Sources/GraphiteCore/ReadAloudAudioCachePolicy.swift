import Foundation
import CryptoKit

/// Identifies one rendered passage. Audio is reused only when the spoken text, the voice and
/// every setting that changes the sound are the same, so editing one paragraph re-renders
/// that paragraph and nothing else. Speed is not part of the key: it is applied at playback
/// with a time-pitch effect, so changing it never discards audio.
public struct ReadAloudAudioCacheKey: Hashable, Sendable, Codable, CustomStringConvertible {
    /// Raise when rendering changes in a way that makes earlier audio wrong: new respelling
    /// rules, other model parameters, a different audio format.
    public static let renderSettingsVersion = 1

    /// 64 hexadecimal digits, also the file name of the cached audio.
    public let value: String

    public init(text: String, voiceIdentifier: String, voiceRevision: String,
                renderSettingsVersion: Int = ReadAloudAudioCacheKey.renderSettingsVersion) {
        // Fields are separated by a byte that never occurs in text, so "ab" + "c" and
        // "a" + "bc" cannot produce the same key.
        let separator = "\u{0}"
        let material = ["graphite-read-aloud", String(renderSettingsVersion), voiceIdentifier, voiceRevision, text]
            .joined(separator: separator)
        value = SHA256.hash(data: Data(material.utf8)).map { byte in String(format: "%02x", byte) }.joined()
    }

    public init?(fileName: String) {
        let stem = fileName.split(separator: ".").first.map(String.init) ?? fileName
        guard stem.count == 64, stem.allSatisfy(\.isHexDigit) else { return nil }
        value = stem
    }

    public var description: String { value }
}

/// One cached passage as the cache's index records it.
public struct ReadAloudAudioCacheEntry: Codable, Equatable, Sendable {
    public let key: ReadAloudAudioCacheKey
    /// The audio and its word timings together.
    public var byteCount: Int64
    public var lastUsed: Date

    public init(key: ReadAloudAudioCacheKey, byteCount: Int64, lastUsed: Date) {
        self.key = key
        self.byteCount = byteCount
        self.lastUsed = lastUsed
    }
}

/// Which cached passages to remove when the cache grows past its size limit.
public enum ReadAloudAudioCacheEviction {
    /// The default limit: about eight hours of speech at 64 kbit/s, a few long lectures.
    public static let defaultCapacityBytes: Int64 = 250 * 1_024 * 1_024

    /// The least recently used entries, oldest first, until the rest fits in the capacity.
    /// Protected entries (the document being read) are never removed, even if they alone
    /// exceed the capacity: deleting audio that is about to play would only render it again.
    public static func keysToRemove(from entries: [ReadAloudAudioCacheEntry], capacityBytes: Int64,
                                    protectedKeys: Set<ReadAloudAudioCacheKey> = []) -> [ReadAloudAudioCacheKey] {
        var totalBytes = entries.reduce(Int64(0)) { total, entry in total + max(0, entry.byteCount) }
        guard totalBytes > capacityBytes else { return [] }
        var removed: [ReadAloudAudioCacheKey] = []
        let oldestFirst = entries.sorted { first, second in
            first.lastUsed != second.lastUsed ? first.lastUsed < second.lastUsed : first.key.value < second.key.value
        }
        for entry in oldestFirst where totalBytes > capacityBytes && !protectedKeys.contains(entry.key) {
            removed.append(entry.key)
            totalBytes -= max(0, entry.byteCount)
        }
        return removed
    }
}

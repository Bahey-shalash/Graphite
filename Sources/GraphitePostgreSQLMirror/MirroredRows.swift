import CryptoKit
import Foundation

/// JSON as the mirror writes it: keys sorted, so equal rows give equal digests, and dates as
/// ISO 8601, which PostgreSQL reads as `timestamptz`.
enum MirrorJSON {
    static func encoded(_ value: some Encodable) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(value)
    }

    static func encodedText(_ value: some Encodable) throws -> String {
        String(decoding: try encoded(value), as: UTF8.self)
    }

    /// The first 128 bits of the SHA-256 of `value`'s JSON, in hexadecimal.
    static func digest(of value: some Encodable) throws -> String {
        SHA256.hash(data: try encoded(value)).prefix(16).map { byte in String(format: "%02x", byte) }.joined()
    }
}

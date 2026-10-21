import Foundation
import CryptoKit

/// Whether a downloaded file is the one that was asked for: the right size and the right
/// SHA-256. Read Aloud's voices and add-on packs both check their files with it.
public enum DownloadedFileCheck {
    /// Reads the file in chunks of a megabyte, so a large file is never held in memory whole.
    public static func matches(_ fileURL: URL, byteCount: Int64, sha256: String) -> Bool {
        guard let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize, Int64(size) == byteCount,
              let handle = try? FileHandle(forReadingFrom: fileURL) else { return false }
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let chunk: Data
            do { chunk = try handle.read(upToCount: 1_024 * 1_024) ?? Data() } catch { return false }
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { byte in String(format: "%02x", byte) }.joined() == sha256.lowercased()
    }
}

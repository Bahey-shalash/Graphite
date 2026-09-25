import Foundation
import CryptoKit

/// Obsidian's File recovery: copies of notes taken while they are edited, kept outside the
/// vault so they never sync or clutter it, and so a note can be recovered after a bad edit,
/// an external overwrite, or its deletion.
///
/// Each note has a folder named after a hash of its vault path, holding `path.txt` (the
/// note's path) and one ordinary Markdown file per snapshot, named by its time. Snapshots
/// are user content: they live in Application Support, never in a cache folder.
public struct FileRecoveryStore: Sendable {
    public struct Snapshot: Identifiable, Equatable, Sendable {
        public let location: URL
        public let date: Date
        public var id: URL { location }
    }

    /// A note with snapshots, which may no longer be in the vault.
    public struct RecoverableNote: Identifiable, Equatable, Sendable {
        public let path: VaultPath
        public let latestSnapshotDate: Date
        public var id: VaultPath { path }
    }

    public static let maximumSnapshotsPerNote = 200
    /// Notes larger than this are not copied, to keep the history small.
    public static let maximumSnapshotBytes = 2 * 1_048_576

    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// The store for a vault, in the app's Application Support folder.
    public static func forVault(identifier: UUID) throws -> FileRecoveryStore {
        let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return FileRecoveryStore(directory: support.appendingPathComponent("Graphite/File Recovery", isDirectory: true)
            .appendingPathComponent(identifier.uuidString, isDirectory: true))
    }

    /// Saves a snapshot of `text` for `path`, unless the latest snapshot is newer than
    /// `minimumInterval` or holds the same text. Blank text, as in a note just created, has
    /// nothing to recover and is not copied. Returns whether one was written.
    @discardableResult
    public func takeSnapshot(of text: String, for path: VaultPath, at date: Date = .now, minimumInterval: TimeInterval) throws -> Bool {
        let data = Data(text.utf8)
        guard data.count <= Self.maximumSnapshotBytes, !text.allSatisfy(\.isWhitespace) else { return false }
        let noteDirectory = directory(for: path)
        let existing = try snapshots(inNoteDirectory: noteDirectory)
        if let latest = existing.first {
            // A copy dated in the future, after the clock was changed, does not hold new ones back.
            let elapsed = date.timeIntervalSince(latest.date)
            if elapsed >= 0, elapsed < minimumInterval { return false }
            if (try? Data(contentsOf: latest.location)) == data { return false }
        }
        try FileManager.default.createDirectory(at: noteDirectory, withIntermediateDirectories: true)
        try Data(path.rawValue.utf8).write(to: noteDirectory.appendingPathComponent("path.txt"), options: .atomic)
        let name = Self.fileName(for: date)
        try data.write(to: noteDirectory.appendingPathComponent(name), options: .atomic)
        // The oldest go first once a note has too many.
        for old in try snapshots(inNoteDirectory: noteDirectory).dropFirst(Self.maximumSnapshotsPerNote) {
            try? FileManager.default.removeItem(at: old.location)
        }
        return true
    }

    /// A note's snapshots, newest first.
    public func snapshots(for path: VaultPath) throws -> [Snapshot] {
        try snapshots(inNoteDirectory: directory(for: path))
    }

    public func text(of snapshot: Snapshot) throws -> String {
        guard let text = String(data: try Data(contentsOf: snapshot.location), encoding: .utf8) else {
            throw GraphiteError.invalidFile("This snapshot is not UTF-8 text.")
        }
        return text
    }

    /// Every note with snapshots, most recently copied first.
    public func recoverableNotes() throws -> [RecoverableNote] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]).compactMap { noteDirectory in
            guard let rawPath = try? String(contentsOf: noteDirectory.appendingPathComponent("path.txt"), encoding: .utf8),
                  let path = try? VaultPath(rawPath), let latest = try? snapshots(inNoteDirectory: noteDirectory).first else { return nil }
            return RecoverableNote(path: path, latestSnapshotDate: latest.date)
        }.sorted { first, second in first.latestSnapshotDate > second.latestSnapshotDate }
    }

    /// Removes snapshots older than `historyLength`, and notes left without any.
    public func pruneSnapshots(olderThan historyLength: TimeInterval, now: Date = .now) throws {
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        for noteDirectory in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
            let snapshots = (try? snapshots(inNoteDirectory: noteDirectory)) ?? []
            for snapshot in snapshots where now.timeIntervalSince(snapshot.date) > historyLength {
                try? FileManager.default.removeItem(at: snapshot.location)
            }
            if ((try? self.snapshots(inNoteDirectory: noteDirectory)) ?? []).isEmpty {
                try? FileManager.default.removeItem(at: noteDirectory)
            }
        }
    }

    /// Keeps snapshots with their notes when a note or a folder is renamed or moved.
    public func followMove(from oldPath: VaultPath, to newPath: VaultPath) throws {
        for note in try recoverableNotes() where note.path.isInside(oldPath) {
            try moveSnapshots(from: note.path, to: try note.path.replacingPrefix(oldPath, with: newPath))
        }
    }

    /// Keeps a note's snapshots with it when it is renamed or moved.
    public func moveSnapshots(from oldPath: VaultPath, to newPath: VaultPath) throws {
        let source = directory(for: oldPath)
        guard FileManager.default.fileExists(atPath: source.path), oldPath != newPath else { return }
        let destination = directory(for: newPath)
        if FileManager.default.fileExists(atPath: destination.path) {
            for snapshot in try snapshots(inNoteDirectory: source) {
                let target = destination.appendingPathComponent(snapshot.location.lastPathComponent)
                if !FileManager.default.fileExists(atPath: target.path) { try FileManager.default.moveItem(at: snapshot.location, to: target) }
            }
            try FileManager.default.removeItem(at: source)
        } else {
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: source, to: destination)
        }
        try Data(newPath.rawValue.utf8).write(to: destination.appendingPathComponent("path.txt"), options: .atomic)
    }

    public func removeAllSnapshots() throws {
        if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
    }

    // MARK: Private

    private func directory(for path: VaultPath) -> URL {
        let digest = SHA256.hash(data: Data(path.rawValue.utf8)).map { byte in String(format: "%02x", byte) }.joined()
        return directory.appendingPathComponent(String(digest.prefix(32)), isDirectory: true)
    }

    private func snapshots(inNoteDirectory noteDirectory: URL) throws -> [Snapshot] {
        guard FileManager.default.fileExists(atPath: noteDirectory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: noteDirectory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]).compactMap { location in
            guard location.pathExtension == "md", let date = Self.date(fromFileName: location.lastPathComponent) else { return nil }
            return Snapshot(location: location, date: date)
        }.sorted { first, second in first.date > second.date }
    }

    private static func fileName(for date: Date) -> String {
        // Milliseconds since 1970: sortable, and unambiguous across time zones.
        String(format: "%013.0f", (date.timeIntervalSince1970 * 1000).rounded()) + ".md"
    }

    private static func date(fromFileName name: String) -> Date? {
        guard let milliseconds = Double((name as NSString).deletingPathExtension) else { return nil }
        return Date(timeIntervalSince1970: milliseconds / 1000)
    }
}

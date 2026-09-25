import Foundation
import CryptoKit

public struct FileRevision: Codable, Equatable, Sendable {
    public let digest: String
    public let size: UInt64
    public static func of(_ data: Data) -> Self {
        Self(digest: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(), size: UInt64(data.count))
    }
    public static func read(_ url: URL) throws -> Self {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hash = SHA256()
        var size: UInt64 = 0
        while let bytes = try handle.read(upToCount: 1_048_576), !bytes.isEmpty {
            hash.update(data: bytes)
            size += UInt64(bytes.count)
        }
        return Self(digest: hash.finalize().map { String(format: "%02x", $0) }.joined(), size: size)
    }
}

public struct FileSnapshot: Sendable {
    public let data: Data
    public let revision: FileRevision
}

public enum WriteExpectation: Sendable { case absent, revision(FileRevision) }

/// All synchronous work belongs on a worker actor, never the main actor.
/// Revision comparison and replacement share one coordinated write accessor.
public struct AtomicFileWriter: Sendable {
    /// Graphite's own vault presenter. Coordinating with it keeps Graphite's writes
    /// from being reported back to Graphite as external changes.
    private let filePresenter: (any NSFilePresenter & Sendable)?

    public init(filePresenter: (any NSFilePresenter & Sendable)? = nil) {
        self.filePresenter = filePresenter
    }

    public func makeCoordinator() -> NSFileCoordinator { NSFileCoordinator(filePresenter: filePresenter) }

    public func read(_ url: URL, maximumBytes: Int? = nil) throws -> FileSnapshot {
        var coordinationError: NSError?
        var readResult: Result<FileSnapshot, Error>?
        makeCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { location in
            readResult = Result {
                if let maximumBytes {
                    let size = try location.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                    guard size <= maximumBytes else { throw GraphiteError.oversized("This file exceeds the current editor's memory budget.") }
                }
                let data = try Data(contentsOf: location)
                return FileSnapshot(data: data, revision: FileRevision.of(data))
            }
        }
        if let coordinationError { throw coordinationError }
        guard let readResult else { throw GraphiteError.unavailable("The file provider did not grant access.") }
        return try readResult.get()
    }

    @discardableResult
    public func write(_ data: Data, to url: URL, expecting: WriteExpectation) throws -> FileRevision {
        try replace(url, expecting: expecting) { staging in try data.write(to: staging) }
    }

    @discardableResult
    public func replace(_ url: URL, expecting: WriteExpectation, produce: (URL) throws -> Void) throws -> FileRevision {
        let stagingDirectory = Self.stagingDirectory(for: url)
        let staging = (stagingDirectory ?? url.deletingLastPathComponent()).appendingPathComponent(".\(UUID().uuidString).tmp")
        defer { try? FileManager.default.removeItem(at: stagingDirectory ?? staging) }
        try produce(staging)
        try Self.flushBeforeLaterWrites(staging)
        let revision = try FileRevision.read(staging)
        var coordinationError: NSError?
        var replacementResult: Result<Void, Error>?
        makeCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { destination in
            replacementResult = Result {
                let exists = FileManager.default.fileExists(atPath: destination.path)
                switch expecting {
                case .absent: guard !exists else { throw GraphiteError.conflict }
                case .revision(let previous):
                    guard exists, try FileRevision.read(destination) == previous else { throw GraphiteError.conflict }
                }
                if exists {
                    _ = try FileManager.default.replaceItemAt(destination, withItemAt: staging)
                } else {
                    try FileManager.default.moveItem(at: staging, to: destination)
                }
                Self.flushToPermanentStorage(directoryOf: destination)
            }
        }
        if let coordinationError { throw coordinationError }
        guard let replacementResult else { throw GraphiteError.unavailable("The file provider did not grant write access.") }
        try replacementResult.get()
        return revision
    }

    /// A private folder on the destination's volume, so the staged file moves into place by
    /// renaming. Outside the vault, a staged file left by a crash or a terminated app never
    /// syncs to other devices, and it needs no coordination with the vault's file provider.
    /// Nil when the system offers none there (some network volumes); staging then falls
    /// back to a hidden file beside the destination.
    private static func stagingDirectory(for url: URL) -> URL? {
        try? FileManager.default.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: url, create: true)
    }

    /// Orders the staged bytes before the rename that publishes them (`F_BARRIERFSYNC`), so
    /// after a power loss the destination holds the old or the new file, never a truncated
    /// one. Plain `fsync` leaves the data in the drive's cache on Apple platforms. File
    /// systems without barriers fall back to `fsync`.
    private static func flushBeforeLaterWrites(_ staging: URL) throws {
        let handle = try FileHandle(forWritingTo: staging)
        defer { try? handle.close() }
        if fcntl(handle.fileDescriptor, F_BARRIERFSYNC) == -1 { try handle.synchronize() }
    }

    /// Flushes the drive's cache after the rename (`F_FULLFSYNC` on the folder), so a save is
    /// on permanent storage when it is reported. It costs a few milliseconds per save, off
    /// the main thread. Best effort: the replacement has already happened, and a file system
    /// that cannot flush this way keeps the new file all the same.
    private static func flushToPermanentStorage(directoryOf location: URL) {
        let directoryDescriptor = open(location.deletingLastPathComponent().path, O_RDONLY)
        guard directoryDescriptor >= 0 else { return }
        _ = fcntl(directoryDescriptor, F_FULLFSYNC)
        close(directoryDescriptor)
    }
}

public extension AtomicFileWriter {
    /// Copies another file into place, reading the source under coordination too.
    @discardableResult
    func copy(from source: URL, to destination: URL, expecting: WriteExpectation) throws -> FileRevision {
        try replace(destination, expecting: expecting) { staging in
            var coordinationError: NSError?
            var copyResult: Result<Void, Error>?
            makeCoordinator().coordinate(readingItemAt: source, options: [], error: &coordinationError) { coordinatedSource in
                copyResult = Result { try FileManager.default.copyItem(at: coordinatedSource, to: staging) }
            }
            if let coordinationError { throw coordinationError }
            guard let copyResult else { throw GraphiteError.unavailable("Cannot read the file to copy.") }
            try copyResult.get()
        }
    }

    func createDirectory(at url: URL) throws {
        var coordinationError: NSError?
        var creationResult: Result<Void, Error>?
        makeCoordinator().coordinate(writingItemAt: url, options: [], error: &coordinationError) { location in
            creationResult = Result { try FileManager.default.createDirectory(at: location, withIntermediateDirectories: true) }
        }
        if let coordinationError { throw coordinationError }
        guard let creationResult else { throw GraphiteError.unavailable("The file provider did not allow creating the folder.") }
        try creationResult.get()
    }
}

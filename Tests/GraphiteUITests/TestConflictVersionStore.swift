import Foundation
import GraphiteCore
import GraphiteApple

/// Conflict versions of a test's own making, since no file provider produces one on
/// demand. It keeps each version's contents in a file of the same type, and does with a
/// version what `FileProviderConflictVersions` does: it replaces the file only when it is
/// as it was listed, writes a separate copy only where nothing is, and removes only the
/// versions named. It also records what it was asked, so tests can check that files are
/// asked about off the main thread and no more often than they should be.
///
/// `@unchecked Sendable`: every mutable property is behind `lock`.
final class TestConflictVersionStore: ConflictVersionStore, @unchecked Sendable {
    private struct StoredVersion {
        let version: FileConflictVersion
        let contentsLocation: URL
    }

    private let lock = NSLock()
    private let versionsFolder: URL
    private var versionsByFilePath: [String: [StoredVersion]] = [:]
    private var askedPaths: [String] = []
    private var wasAskedOnMainThread = false
    /// How long each `hasConflictVersions` takes, as a slow provider would.
    private var secondsPerAnswer = 0.0

    init() throws {
        versionsFolder = FileManager.default.temporaryDirectory.appendingPathComponent("TestConflictVersions-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: versionsFolder, withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(at: versionsFolder) }

    private static func key(_ location: URL) -> String { location.standardizedFileURL.resolvingSymlinksInPath().path }

    /// Keeps `contents` as a version of the file at `location`, as a provider would after
    /// the file was changed on `deviceName` too.
    @discardableResult
    func addVersion(of location: URL, contents: Data, deviceName: String?, modified: Date?, savedBy: String? = nil) throws -> FileConflictVersion {
        let identifier = UUID().uuidString
        let contentsLocation = versionsFolder.appendingPathComponent(identifier).appendingPathExtension(location.pathExtension)
        try contents.write(to: contentsLocation)
        let version = FileConflictVersion(id: identifier, deviceName: deviceName, savedBy: savedBy, modified: modified, byteCount: contents.count)
        lock.withLock { versionsByFilePath[Self.key(location), default: []].append(StoredVersion(version: version, contentsLocation: contentsLocation)) }
        return version
    }

    /// The files `hasConflictVersions` was asked about, in order.
    var pathsAskedAbout: [String] { lock.withLock { askedPaths } }
    var wasEverAskedOnTheMainThread: Bool { lock.withLock { wasAskedOnMainThread } }

    func answerSlowly(secondsPerAnswer: Double) {
        lock.withLock { self.secondsPerAnswer = secondsPerAnswer }
    }

    func hasConflictVersions(at location: URL) -> Bool {
        let (hasVersions, delay) = lock.withLock { () -> (Bool, Double) in
            askedPaths.append(Self.key(location))
            if Thread.isMainThread { wasAskedOnMainThread = true }
            return (!(versionsByFilePath[Self.key(location)] ?? []).isEmpty, secondsPerAnswer)
        }
        if delay > 0 { Thread.sleep(forTimeInterval: delay) }
        return hasVersions
    }

    func conflictVersions(of location: URL) throws -> [FileConflictVersion] {
        lock.withLock { (versionsByFilePath[Self.key(location)] ?? []).map(\.version) }
            .sorted { first, second in (first.modified ?? .distantPast) > (second.modified ?? .distantPast) }
    }

    func contentsLocation(ofVersion versionIdentifier: String, ofFileAt location: URL) throws -> URL {
        try storedVersion(versionIdentifier, of: location).contentsLocation
    }

    @discardableResult
    func replaceFile(at location: URL, withVersion versionIdentifier: String, expecting expectedStamp: FileChangeStamp?, using writer: AtomicFileWriter) throws -> URL {
        let stored = try storedVersion(versionIdentifier, of: location)
        var coordinationError: NSError?
        var outcome: Result<Void, Error>?
        writer.makeCoordinator().coordinate(writingItemAt: location, options: .forReplacing, error: &coordinationError) { coordinatedLocation in
            outcome = Result {
                if let expectedStamp, FileChangeStamp.of(coordinatedLocation) != expectedStamp { throw GraphiteError.conflict }
                try Data(contentsOf: stored.contentsLocation).write(to: coordinatedLocation, options: .atomic)
            }
        }
        if let coordinationError { throw coordinationError }
        try outcome?.get()
        remove([versionIdentifier], of: location)
        return location
    }

    func keepVersion(_ versionIdentifier: String, ofFileAt location: URL, asSeparateFileAt destination: URL, using writer: AtomicFileWriter) throws {
        let stored = try storedVersion(versionIdentifier, of: location)
        try writer.copy(from: stored.contentsLocation, to: destination, expecting: .absent)
        remove([versionIdentifier], of: location)
    }

    func removeVersions(_ versionIdentifiers: [String], ofFileAt location: URL, using writer: AtomicFileWriter) throws {
        remove(versionIdentifiers, of: location)
    }

    private func storedVersion(_ versionIdentifier: String, of location: URL) throws -> StoredVersion {
        guard let stored = lock.withLock({ versionsByFilePath[Self.key(location)]?.first { stored in stored.version.id == versionIdentifier } }) else {
            throw GraphiteError.unavailable("That version is no longer kept. It may have been resolved on another device.")
        }
        return stored
    }

    private func remove(_ versionIdentifiers: [String], of location: URL) {
        let removed = lock.withLock { () -> [StoredVersion] in
            let removed = (versionsByFilePath[Self.key(location)] ?? []).filter { stored in versionIdentifiers.contains(stored.version.id) }
            versionsByFilePath[Self.key(location)]?.removeAll { stored in versionIdentifiers.contains(stored.version.id) }
            return removed
        }
        for stored in removed { try? FileManager.default.removeItem(at: stored.contentsLocation) }
    }
}

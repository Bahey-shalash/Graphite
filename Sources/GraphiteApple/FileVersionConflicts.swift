import Foundation
import GraphiteCore

/// The versions of a file that a file provider keeps after it was changed in two places:
/// the one place that touches `NSFileVersion`. `FileProviderConflictVersions` is the real
/// one; tests of the workspace use a store with versions of their own making, since no
/// provider produces a conflict on demand.
///
/// Except for `hasConflictVersions`, the methods can wait for the provider, for file
/// coordination, or for a download, and belong off the main thread. Nothing is removed
/// except by `replaceFile`, `keepVersion`, and `removeVersions`, each for the versions named.
public protocol ConflictVersionStore: Sendable {
    /// Whether the provider keeps versions of the file for the person to decide about.
    /// Reads metadata only: it never downloads the file or a version of it.
    func hasConflictVersions(at location: URL) -> Bool
    /// The versions kept beside the current file, as the provider lists them.
    func conflictVersions(of location: URL) throws -> [FileConflictVersion]
    /// Where a version's contents can be read, after downloading them when the provider
    /// had not.
    func contentsLocation(ofVersion versionIdentifier: String, ofFileAt location: URL) throws -> URL
    /// Replaces the file's contents with a version's, which is then no longer kept beside
    /// it. Other versions stay. Throws `GraphiteError.conflict` when the file is not as
    /// `expectedStamp` found it. Returns where the file is afterwards.
    @discardableResult
    func replaceFile(at location: URL, withVersion versionIdentifier: String, expecting expectedStamp: FileChangeStamp?, using writer: AtomicFileWriter) throws -> URL
    /// Writes a version's contents to a new file at `destination`, which must not exist,
    /// and no longer keeps it as a version. The current file is untouched.
    func keepVersion(_ versionIdentifier: String, ofFileAt location: URL, asSeparateFileAt destination: URL, using writer: AtomicFileWriter) throws
    /// Marks the versions resolved and removes them. The current file is untouched.
    func removeVersions(_ versionIdentifiers: [String], ofFileAt location: URL, using writer: AtomicFileWriter) throws
}

/// Conflict versions through `NSFileVersion`, under file coordination as Apple documents:
/// a version is marked resolved and removed inside a coordinated write of its file.
public struct FileProviderConflictVersions: ConflictVersionStore {
    /// Which of the provider's versions are listed.
    public enum Listing: Sendable {
        /// The versions in conflict with the current file that nobody has resolved.
        case unresolvedConflicts
        /// Every version but the current one. On a local volume no version is ever marked
        /// as a conflict, so tests that make real versions there list them this way.
        case everyOtherVersion
    }

    private let listing: Listing

    public init(listing: Listing = .unresolvedConflicts) {
        self.listing = listing
    }

    public func hasConflictVersions(at location: URL) -> Bool {
        if listing == .unresolvedConflicts {
            var freshLocation = location
            freshLocation.removeAllCachedResourceValues()
            // iCloud answers from the file's metadata, for placeholders too.
            if let values = try? freshLocation.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemHasUnresolvedConflictsKey]),
               values.isUbiquitousItem == true, let hasUnresolvedConflicts = values.ubiquitousItemHasUnresolvedConflicts {
                return hasUnresolvedConflicts
            }
            // A placeholder of another provider is left alone, so that asking can never
            // start a download. Its versions show once the file is on the device.
            guard !Self.isPlaceholder(location) else { return false }
        }
        return !providerVersions(of: location).isEmpty
    }

    public func conflictVersions(of location: URL) throws -> [FileConflictVersion] {
        providerVersions(of: location).map { version in
            let contentsLocation = version.url
            let byteCount = (try? contentsLocation.resourceValues(forKeys: [.fileSizeKey]))?.fileSize
                ?? (try? contentsLocation.promisedItemResourceValues(forKeys: [.fileSizeKey]))?.fileSize
            let savedBy = version.originatorNameComponents.map { nameComponents in PersonNameComponentsFormatter.localizedString(from: nameComponents, style: .default) }
            return FileConflictVersion(id: Self.identifier(of: version), deviceName: version.localizedNameOfSavingComputer,
                                       savedBy: savedBy?.isEmpty == false ? savedBy : nil, modified: version.modificationDate,
                                       byteCount: byteCount, hasLocalContents: version.hasLocalContents)
        }
        .sorted { first, second in (first.modified ?? .distantPast) > (second.modified ?? .distantPast) }
    }

    public func contentsLocation(ofVersion versionIdentifier: String, ofFileAt location: URL) throws -> URL {
        let version = try providerVersion(versionIdentifier, of: location)
        guard !version.hasLocalContents else { return version.url }
        // A coordinated read of a version the provider has not downloaded downloads it.
        var coordinationError: NSError?
        var downloadedLocation: URL?
        NSFileCoordinator(filePresenter: nil).coordinate(readingItemAt: version.url, options: [], error: &coordinationError) { coordinatedLocation in
            downloadedLocation = coordinatedLocation
        }
        if let coordinationError { throw coordinationError }
        guard let downloadedLocation else { throw GraphiteError.unavailable("The file provider did not give access to this version.") }
        return downloadedLocation
    }

    @discardableResult
    public func replaceFile(at location: URL, withVersion versionIdentifier: String, expecting expectedStamp: FileChangeStamp?, using writer: AtomicFileWriter) throws -> URL {
        let version = try providerVersion(versionIdentifier, of: location)
        return try coordinateWriting(at: location, options: .forReplacing, using: writer) { coordinatedLocation in
            if let expectedStamp, FileChangeStamp.of(coordinatedLocation) != expectedStamp { throw GraphiteError.conflict }
            let replacedLocation = try version.replaceItem(at: coordinatedLocation, options: [])
            try Self.markResolvedAndRemove(version)
            return replacedLocation
        }
    }

    public func keepVersion(_ versionIdentifier: String, ofFileAt location: URL, asSeparateFileAt destination: URL, using writer: AtomicFileWriter) throws {
        let version = try providerVersion(versionIdentifier, of: location)
        // Downloads the version when the provider had not.
        _ = try contentsLocation(ofVersion: versionIdentifier, ofFileAt: location)
        // The version writes itself out, with the file's own permissions: its stored copy
        // is read-only and carries the version store's attributes, so a plain file copy
        // would put a read-only file in the vault. The copy is staged and moved into place
        // only when nothing is there, and the version is removed only after that.
        try writer.replace(destination, expecting: .absent) { stagingLocation in
            // The version gives the file it writes its own extension, whatever was asked for.
            let writtenLocation = try version.replaceItem(at: stagingLocation, options: [])
            if writtenLocation.standardizedFileURL.path != stagingLocation.standardizedFileURL.path {
                try FileManager.default.moveItem(at: writtenLocation, to: stagingLocation)
            }
        }
        try coordinateWriting(at: location, options: [], using: writer) { _ in try Self.markResolvedAndRemove(version) }
    }

    public func removeVersions(_ versionIdentifiers: [String], ofFileAt location: URL, using writer: AtomicFileWriter) throws {
        let identifiers = Set(versionIdentifiers)
        let versions = providerVersions(of: location).filter { version in identifiers.contains(Self.identifier(of: version)) }
        guard !versions.isEmpty else { return }
        try coordinateWriting(at: location, options: [], using: writer) { _ in
            for version in versions { try Self.markResolvedAndRemove(version) }
        }
    }

    // MARK: NSFileVersion

    private func providerVersions(of location: URL) -> [NSFileVersion] {
        switch listing {
        case .unresolvedConflicts: NSFileVersion.unresolvedConflictVersionsOfItem(at: location) ?? []
        case .everyOtherVersion: NSFileVersion.otherVersionsOfItem(at: location) ?? []
        }
    }

    private func providerVersion(_ versionIdentifier: String, of location: URL) throws -> NSFileVersion {
        guard let version = providerVersions(of: location).first(where: { version in Self.identifier(of: version) == versionIdentifier }) else {
            throw GraphiteError.unavailable("That version is no longer kept. It may have been resolved on another device.")
        }
        return version
    }

    /// The provider's persistent identifier as text. Versions are found again by listing
    /// them, so the identifier never has to be decoded.
    private static func identifier(of version: NSFileVersion) -> String {
        String(describing: version.persistentIdentifier)
    }

    private static func markResolvedAndRemove(_ version: NSFileVersion) throws {
        version.isResolved = true
        try version.remove()
    }

    private func coordinateWriting<Value>(at location: URL, options: NSFileCoordinator.WritingOptions, using writer: AtomicFileWriter,
                                          _ work: (URL) throws -> Value) throws -> Value {
        var coordinationError: NSError?
        var outcome: Result<Value, Error>?
        writer.makeCoordinator().coordinate(writingItemAt: location, options: options, error: &coordinationError) { coordinatedLocation in
            outcome = Result { try work(coordinatedLocation) }
        }
        if let coordinationError { throw coordinationError }
        guard let outcome else { throw GraphiteError.unavailable("The file provider did not grant write access.") }
        return try outcome.get()
    }

    /// Whether the file's contents are not on the device (`SF_DATALESS`). Reading the flag
    /// reads metadata only.
    private static func isPlaceholder(_ location: URL) -> Bool {
        var fileStatus = stat()
        guard lstat(location.path, &fileStatus) == 0 else { return false }
        return fileStatus.st_flags & UInt32(SF_DATALESS) != 0
    }
}

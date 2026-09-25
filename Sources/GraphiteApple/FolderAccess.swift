import Foundation
import Synchronization
import GraphiteCore

/// Keeps a vault folder readable and writable while it is open. The security scope may
/// belong to a folder that contains the vault, when the vault was created inside it.
/// Immutable, so it can be created off the main thread; access ends when it is released.
public final class FolderAccess: Sendable {
    /// The vault folder.
    public let root: URL
    private let scopedFolder: URL
    private let isScoped: Bool

    public init(root: URL, scopedFolder: URL? = nil) {
        self.root = root
        self.scopedFolder = scopedFolder ?? root
        isScoped = self.scopedFolder.startAccessingSecurityScopedResource()
    }

    deinit { if isScoped { scopedFolder.stopAccessingSecurityScopedResource() } }
}

/// Turns saved vault locations into folder access, and folders into saved locations.
/// It holds no state, so resolving a location can run off the main thread.
public enum VaultLocator {
    /// The location to remember for a folder the user picked. A folder inside Graphite's
    /// own Documents folder, or that folder itself, is remembered by its path there, because
    /// iOS moves the app's container, and with it that folder, when the app is updated.
    public static func location(forPickedFolder folder: URL, applicationDocumentsFolder: URL? = nil) throws -> VaultLocation {
        let isScoped = folder.startAccessingSecurityScopedResource()
        defer { if isScoped { folder.stopAccessingSecurityScopedResource() } }
        #if !os(macOS)
        if let relativePath = relativePath(of: folder, inside: try applicationDocumentsFolder ?? Self.applicationDocumentsFolder()) {
            return VaultLocation(anchor: .applicationDocuments, relativePath: relativePath)
        }
        #endif
        return VaultLocation(anchor: .bookmark(try bookmarkData(for: folder)))
    }

    /// `folder`'s path inside `enclosingFolder`: empty for `enclosingFolder` itself, and nil
    /// for a folder outside it.
    static func relativePath(of folder: URL, inside enclosingFolder: URL) -> String? {
        let enclosingPath = enclosingFolder.standardizedFileURL.resolvingSymlinksInPath().path
        let folderPath = folder.standardizedFileURL.resolvingSymlinksInPath().path
        if folderPath == enclosingPath { return "" }
        guard folderPath.hasPrefix(enclosingPath + "/") else { return nil }
        return String(folderPath.dropFirst(enclosingPath.count + 1))
    }

    /// `access(_:)` run off the main thread. Resolving a bookmark to a file provider's folder
    /// can wait on that provider, which may still be starting at launch.
    public static func accessInBackground(_ location: VaultLocation) async throws -> (access: FolderAccess, refreshedLocation: VaultLocation?) {
        try await Task.detached(priority: .userInitiated) { try access(location) }.value
    }

    /// Access to the vault's folder, and a replacement location when the saved bookmark
    /// has gone stale (the folder moved), so the next launch still finds it.
    public static func access(_ location: VaultLocation) throws -> (access: FolderAccess, refreshedLocation: VaultLocation?) {
        let anchorFolder: URL
        var isStale = false
        switch location.anchor {
        case .applicationDocuments:
            anchorFolder = try applicationDocumentsFolder()
        case .bookmark(let bookmark):
            #if os(macOS)
            anchorFolder = try URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &isStale)
            #else
            anchorFolder = try URL(resolvingBookmarkData: bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &isStale)
            #endif
        }
        let root = location.relativePath.isEmpty ? anchorFolder : anchorFolder.appendingPathComponent(location.relativePath, isDirectory: true)
        let access = FolderAccess(root: root, scopedFolder: anchorFolder)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw GraphiteError.unavailable("Graphite can't find the folder “\(root.lastPathComponent)”. It may have been moved, renamed, or deleted, or its storage may be unavailable. Open it again with Open Folder as Vault.")
        }
        var refreshedLocation: VaultLocation?
        if isStale, let bookmark = try? bookmarkData(for: anchorFolder) {
            refreshedLocation = VaultLocation(anchor: .bookmark(bookmark), relativePath: location.relativePath)
        }
        return (access, refreshedLocation)
    }

    /// Creates an empty folder for a new vault inside `parentFolder`, or inside Graphite's
    /// own Documents folder when it is nil. Nothing else is written; like Obsidian, any
    /// settings folder appears only once a setting is changed. `applicationDocumentsFolder`,
    /// when given, stands for Graphite's Documents folder.
    public static func createVaultFolder(named proposedName: String, in parentFolder: URL?, applicationDocumentsFolder: URL? = nil) throws -> VaultLocation {
        let name = try VaultList.validatedFolderName(proposedName)
        let isScoped = parentFolder?.startAccessingSecurityScopedResource() ?? false
        defer { if isScoped { parentFolder?.stopAccessingSecurityScopedResource() } }
        let enclosingFolder = try parentFolder ?? applicationDocumentsFolder ?? Self.applicationDocumentsFolder()
        let vaultFolder = enclosingFolder.appendingPathComponent(name, isDirectory: true)
        guard !FileManager.default.fileExists(atPath: vaultFolder.path) else {
            throw GraphiteError.invalidFile("“\(enclosingFolder.lastPathComponent)” already contains an item named “\(name)”. Choose another name, or open that folder as a vault.")
        }
        // Decided before the folder exists, so a failure here leaves no empty folder behind
        // that would make a second attempt with the same name fail.
        let vaultLocation = try location(forVaultNamed: name, in: parentFolder, applicationDocumentsFolder: applicationDocumentsFolder)
        try AtomicFileWriter().createDirectory(at: vaultFolder)
        return vaultLocation
    }

    private static func location(forVaultNamed name: String, in parentFolder: URL?, applicationDocumentsFolder: URL?) throws -> VaultLocation {
        guard let parentFolder else { return VaultLocation(anchor: .applicationDocuments, relativePath: name) }
        #if !os(macOS)
        // Remembered by path for the same reason as a picked folder inside Graphite's folder.
        if let parentPath = relativePath(of: parentFolder, inside: try applicationDocumentsFolder ?? Self.applicationDocumentsFolder()) {
            return VaultLocation(anchor: .applicationDocuments, relativePath: parentPath.isEmpty ? name : parentPath + "/" + name)
        }
        #endif
        // The bookmark is for the folder the user granted, which reliably carries its
        // permission across launches; the vault is found inside it by name.
        return VaultLocation(anchor: .bookmark(try bookmarkData(for: parentFolder)), relativePath: name)
    }

    /// Graphite's Documents folder, which the Files app lists under Graphite's name.
    public static func applicationDocumentsFolder() throws -> URL {
        try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
    }

    private static func bookmarkData(for folder: URL) throws -> Data {
        #if os(macOS)
        try folder.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
        #else
        try folder.bookmarkData(options: [.minimalBookmark], includingResourceValuesForKeys: nil, relativeTo: nil)
        #endif
    }
}

/// Foundation invokes the callbacks on the serial operation queue, and reads
/// `presentedItemURL` from any thread. The vault's current URL is the only mutable state,
/// and it is guarded by a mutex; the callbacks and the queue never change. No document
/// state is accessed here. Consumers hop to their actor.
public final class VaultMonitor: NSObject, NSFilePresenter, @unchecked Sendable {
    public var presentedItemURL: URL? { vaultURL.withLock { url in url } }
    public let presentedItemOperationQueue: OperationQueue
    private let vaultURL: Mutex<URL>
    private let onChange: @Sendable (URL?) -> Void
    private let onVaultMove: (@Sendable (URL?) -> Void)?
    /// `onChange` receives changed items inside the vault. `onVaultMove` receives the vault
    /// folder's new URL when it is moved or renamed, or nil when it is deleted; changes
    /// inside it keep being reported at its new place.
    public init(root: URL, onChange: @escaping @Sendable (URL?) -> Void, onVaultMove: (@Sendable (URL?) -> Void)? = nil) {
        vaultURL = Mutex(root)
        self.onChange = onChange
        self.onVaultMove = onVaultMove
        let operationQueue = OperationQueue()
        operationQueue.maxConcurrentOperationCount = 1
        operationQueue.qualityOfService = .utility
        presentedItemOperationQueue = operationQueue
        super.init()
        NSFileCoordinator.addFilePresenter(self)
    }
    public func stop() { NSFileCoordinator.removeFilePresenter(self) }
    public func presentedItemDidChange() { onChange(presentedItemURL) }
    public func presentedItemDidMove(to newURL: URL) {
        vaultURL.withLock { url in url = newURL }
        onVaultMove?(newURL)
    }
    public func accommodatePresentedItemDeletion(completionHandler: @escaping (Error?) -> Void) {
        onVaultMove?(nil); completionHandler(nil)
    }
    public func presentedSubitemDidChange(at url: URL) { report(url) }
    public func presentedSubitemDidAppear(at url: URL) { report(url) }
    public func presentedSubitem(at oldURL: URL, didMoveTo newURL: URL) { report(oldURL); report(newURL) }
    public func accommodatePresentedSubitemDeletion(at url: URL, completionHandler: @escaping (Error?) -> Void) {
        report(url); completionHandler(nil)
    }

    private func report(_ url: URL) {
        guard !Self.isGraphiteStagingFile(url) else { return }
        onChange(url)
    }

    /// Graphite's atomic writes stage content in a hidden `.<UUID>.tmp` file next to the
    /// destination (`AtomicFileWriter.replace`). That staging is not coordinated, and on
    /// macOS presenters hear about it anyway; it is never vault content.
    static func isGraphiteStagingFile(_ url: URL) -> Bool {
        let name = url.lastPathComponent
        let stagingSuffix = ".tmp"
        guard name.hasPrefix("."), name.hasSuffix(stagingSuffix) else { return false }
        return UUID(uuidString: String(name.dropFirst().dropLast(stagingSuffix.count))) != nil
    }
}

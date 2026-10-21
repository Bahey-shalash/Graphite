import Foundation
import CoreGraphics
import Observation
import GraphiteCore
import GraphiteApple

/// The library of one window: the folder shown as a grid, its listing, the filter, the
/// folders' colors, and the previews of the tiles on screen.
@MainActor @Observable
final class LibraryModel {
    /// What the listing and previews are read from; replaced when the vault changes.
    struct Source {
        let vaultIdentifier: UUID
        let store: VaultStore
        /// Finder's looks of the vault's folders, read on every platform and written on the Mac.
        let finderAttributes: FinderFolderAttributes
        /// Makes a tile's preview, as `LibraryPreviewLoader.preview` does. It runs inside the
        /// tile's own task, off the main actor, so cancelling the tile reaches it.
        let renderPreview: @Sendable (VaultPath, _ longerSidePixels: Int) async -> LibraryTilePreview
    }

    /// Recently shown previews kept for scrolling back; on-screen tiles keep theirs in
    /// `visiblePreviews`. The cache gives memory back on its own under pressure.
    static let cachedPreviewCount = 240
    /// The cache's memory budget: the decoded pixels of the previews it keeps.
    static let cachedPreviewBytes = 64 * 1024 * 1024
    /// Previews drawn at the same time; tiles beyond wait their turn in `waitingPreviews`.
    static let maximumConcurrentRenders = 4
    /// A tile's preview, longer side in pixels: enough for a tile of about 180 points at 3x.
    static let previewPixels = 540

    /// Whether the library covers the first side's documents as the window's home, as
    /// Goodnotes shows its library until a document tab is chosen.
    private(set) var isShownAsHome = true
    private(set) var folder: VaultPath = .root
    private(set) var items: [VaultEntry] = []
    private(set) var failure: LibraryFailure?
    var filter: LibraryFilter = .all { didSet { applyFilter() } }
    /// The folders' looks: Graphite's styles and Finder's; replaced with the vault.
    private(set) var folderLooks = LibraryFolderLooks(attributes: nil) { _, _ in nil }
    /// Previews of the tiles on screen; a tile's entry goes when it scrolls away.
    private(set) var visiblePreviews: [VaultPath: LibraryTilePreview] = [:]

    @ObservationIgnored private var source: Source?
    @ObservationIgnored private var listedEntries: [VaultEntry] = []
    @ObservationIgnored private var sortOrder = FileSortOrder.alphabetical
    /// The renders running now, by file; never more than `maximumConcurrentRenders`.
    @ObservationIgnored private var previewTasks: [VaultPath: Task<Void, Never>] = [:]
    /// Tiles on screen whose preview waits for a render to finish, oldest first.
    @ObservationIgnored private var waitingPreviews: [VaultEntry] = []
    /// The file version each on-screen tile's preview was made or asked for, so a listing
    /// that shows the file changed asks again.
    @ObservationIgnored private var requestedPreviewKeys: [VaultPath: LibraryPreviewCache.Key] = [:]
    /// How many tiles of each file are on screen. SwiftUI shows a rebuilt grid's tile before
    /// it removes the old one, so a file's preview goes only when its last tile does.
    @ObservationIgnored private var visibleTileCounts: [VaultPath: Int] = [:]
    @ObservationIgnored private var previewCache = LibraryModel.makePreviewCache()

    /// Lists the folder again, from a new vault's root when the vault changed.
    func reload(source newSource: Source?, sortOrder newSortOrder: FileSortOrder) async {
        if newSource?.vaultIdentifier != source?.vaultIdentifier {
            cancelPreviews()
            previewCache = Self.makePreviewCache()
            folderLooks = Self.makeFolderLooks(for: newSource)
            folder = .root
        }
        source = newSource
        sortOrder = newSortOrder
        await listFolder()
    }

    /// The house button, as a tab bar's tab: from a document it brings the library back at
    /// the folder it was showing; on the library it goes up to the vault's root.
    func showHome() async {
        guard isShownAsHome else {
            isShownAsHome = true
            return
        }
        await show(.root)
    }

    /// A document tab was chosen or a file opened: the library steps back.
    func leaveHome() {
        if isShownAsHome { isShownAsHome = false }
    }

    func show(_ shownFolder: VaultPath) async {
        guard shownFolder != folder else { return }
        cancelPreviews()
        folder = shownFolder
        filter = .all
        await listFolder()
    }

    /// Lists the folder shown. The folder's files and the vault's folder colors are read
    /// apart, so a style file that cannot be read never hides the folder.
    private func listFolder() async {
        guard let source else {
            listedEntries = []; items = []; failure = nil
            return
        }
        let listedFolder = folder
        let entries: [VaultEntry]
        do {
            entries = try await source.store.children(of: listedFolder, sortedBy: sortOrder)
        } catch {
            guard listedFolder == folder else { return }
            // A folder deleted or moved while shown: the library goes up to one that exists.
            if !listedFolder.rawValue.isEmpty, (try? await source.store.fileExists(listedFolder)) == false { // An unanswerable check counts as present.
                folder = listedFolder.parent
                await listFolder()
            } else {
                failure = .folderUnreadable
            }
            return
        }
        guard listedFolder == folder else { return }
        listedEntries = entries
        if failure == .folderUnreadable { failure = nil }
        applyFilter()
        refreshChangedPreviews()
        await loadFolderStyles(from: source.store)
        await folderLooks.readFinderLooks(of: entries.filter(\.isDirectory).map(\.path))
    }

    /// Reads the folder colors. A file that is not Graphite's format is moved aside under a
    /// name of its own, never written over, and the folders show plain; a read that fails
    /// for another reason (the provider, a file not yet downloaded) keeps the colors shown.
    private func loadFolderStyles(from store: VaultStore) async {
        do {
            folderLooks.replaceStyles(try await store.folderStyles())
        } catch is FolderStyleListError {
            folderLooks.replaceStyles(FolderStyleList())
            do {
                let keptCopy = try await store.moveFolderStylesAside()
                failure = .folderStylesSetAside(keptCopyName: keptCopy.name)
            } catch {
                failure = .folderStylesUnreadable
            }
        } catch {
            return
        }
    }

    private func applyFilter() {
        let filteredItems = LibraryListing.items(of: listedEntries, filter: filter, sortOrder: sortOrder)
        if filteredItems != items { items = filteredItems }
    }

    /// Saves a folder's look in the vault, then on the Mac where Finder reads it. A failure
    /// to save leaves the folder as it was; each failure is reported.
    func setStyle(_ style: FolderStyle?, for styledFolder: VaultPath) async {
        guard let source else { return }
        do {
            folderLooks.replaceStyles(try await source.store.updateFolderStyles { @Sendable styles in styles.setStyle(style, for: styledFolder) })
        } catch {
            failure = .styleNotSaved
            return
        }
        if await !folderLooks.writeFinderLook(style, of: styledFolder) { failure = .finderLookNotWritten }
    }

    /// Makes a framed picture the folder's look: saved as a PNG in the vault, then the style
    /// that points at it. Returns the new look, nil when the picture could not be saved.
    func setPicture(_ framedPicture: CGImage, layout: FolderPictureLayout, color: FolderColor?, for styledFolder: VaultPath) async -> FolderStyle? {
        guard let source else { return nil }
        do {
            let pngData = try await Task.detached(priority: .userInitiated) { try FolderIconRenderer.pngData(of: framedPicture) }.value
            let picturePath = try await source.store.saveFolderPicture(pngData)
            let style = FolderStyle(color: color, mark: .picture(FolderPicture(path: picturePath, layout: layout)))
            await setStyle(style, for: styledFolder)
            return failure == .styleNotSaved ? nil : style
        } catch {
            failure = .styleNotSaved
            return nil
        }
    }

    /// A picture of the vault chosen for a folder, bounded as a picked file is.
    func pictureData(at path: VaultPath) async throws -> Data {
        guard let source else { throw CancellationError() }
        return try await source.store.read(path, maximumBytes: PickedImageFiles.maximumImageBytes).data
    }

    func dismissFailure() { failure = nil }

    // MARK: Previews

    /// Starts the preview of a tile that came on screen, from the cache when it is current.
    func tileAppeared(_ entry: VaultEntry) {
        guard source != nil else { return }
        guard !entry.isDirectory else { return folderLooks.tileAppeared(entry.path) }
        visibleTileCounts[entry.path, default: 0] += 1
        // A tile of the same file already asked for this version.
        let isRequested = requestedPreviewKeys[entry.path] == LibraryPreviewCache.Key(entry: entry)
        if isRequested, visiblePreviews[entry.path] != nil || isPreviewPending(entry.path) { return }
        requestPreview(of: entry)
    }

    /// Stops a tile's preview work and lets go of its picture once it leaves the screen.
    func tileDisappeared(_ entry: VaultEntry) {
        guard !entry.isDirectory else { return folderLooks.tileDisappeared(entry.path) }
        let remainingTiles = max(visibleTileCounts[entry.path, default: 0] - 1, 0)
        visibleTileCounts[entry.path] = remainingTiles == 0 ? nil : remainingTiles
        guard remainingTiles == 0 else { return }
        cancelPreview(of: entry.path)
        visiblePreviews[entry.path] = nil
        requestedPreviewKeys[entry.path] = nil
        startWaitingPreviews()
    }

    /// Asks again for the preview of every tile on screen whose file the new listing shows
    /// changed. The old picture stays until the new one is drawn.
    private func refreshChangedPreviews() {
        for entry in listedEntries where visibleTileCounts[entry.path] != nil && !entry.isDirectory {
            if let requestedKey = requestedPreviewKeys[entry.path], requestedKey != LibraryPreviewCache.Key(entry: entry) {
                requestPreview(of: entry)
            }
        }
    }

    /// Shows the cached preview of this version, or queues a render of it.
    private func requestPreview(of entry: VaultEntry) {
        let key = LibraryPreviewCache.Key(entry: entry)
        requestedPreviewKeys[entry.path] = key
        cancelPreview(of: entry.path)
        if let cached = previewCache.preview(for: key) {
            visiblePreviews[entry.path] = cached
            return
        }
        waitingPreviews.append(entry)
        startWaitingPreviews()
    }

    /// Starts waiting renders while fewer than `maximumConcurrentRenders` run.
    private func startWaitingPreviews() {
        while previewTasks.count < Self.maximumConcurrentRenders, !waitingPreviews.isEmpty, let source {
            let entry = waitingPreviews.removeFirst()
            let key = LibraryPreviewCache.Key(entry: entry)
            let renderPreview = source.renderPreview
            previewTasks[entry.path] = Task { [weak self] in
                // Awaited in this task, so cancelling the tile cancels the render.
                let preview = await renderPreview(entry.path, Self.previewPixels)
                self?.finishPreview(preview, of: entry.path, key: key, wasCancelled: Task.isCancelled)
            }
        }
    }

    private func finishPreview(_ preview: LibraryTilePreview, of path: VaultPath, key: LibraryPreviewCache.Key, wasCancelled: Bool) {
        guard !wasCancelled else { return }
        previewTasks[path] = nil
        previewCache.store(preview, for: key)
        if requestedPreviewKeys[path] == key { visiblePreviews[path] = preview }
        startWaitingPreviews()
    }

    private func isPreviewPending(_ path: VaultPath) -> Bool {
        previewTasks[path] != nil || waitingPreviews.contains { entry in entry.path == path }
    }

    /// Takes a file's render off the queue, or cancels it while it runs and frees its slot.
    private func cancelPreview(of path: VaultPath) {
        waitingPreviews.removeAll { entry in entry.path == path }
        previewTasks.removeValue(forKey: path)?.cancel()
    }

    private func cancelPreviews() {
        for task in previewTasks.values { task.cancel() }
        previewTasks = [:]
        waitingPreviews = []
        requestedPreviewKeys = [:]
        visiblePreviews = [:]
        visibleTileCounts = [:]
    }

    /// A folder's picture is a PNG in the vault, read as a picture tile's preview is.
    private static func makeFolderLooks(for source: Source?) -> LibraryFolderLooks {
        let renderPreview = source?.renderPreview
        return LibraryFolderLooks(attributes: source?.finderAttributes) { picturePath, longerSidePixels in
            guard case .picture(let image) = await renderPreview?(picturePath, longerSidePixels) else { return nil }
            return image
        }
    }

    private static func makePreviewCache() -> LibraryPreviewCache {
        LibraryPreviewCache(countLimit: cachedPreviewCount, totalCostLimitBytes: cachedPreviewBytes)
    }
}

/// Previews by file and version, bounded by count and by the bytes of their decoded pixels;
/// `NSCache` also empties itself when the system is short of memory.
final class LibraryPreviewCache {
    /// A file at one modification date and size: an edited file gets a new preview.
    struct Key: Hashable {
        let path: VaultPath
        let modified: Date
        let size: Int

        init(entry: VaultEntry) {
            path = entry.path; modified = entry.modified; size = entry.size
        }
    }

    private final class Entry {
        let preview: LibraryTilePreview
        init(_ preview: LibraryTilePreview) { self.preview = preview }
    }

    private final class KeyBox: NSObject {
        let key: Key
        init(_ key: Key) { self.key = key }
        override var hash: Int {
            var hasher = Hasher()
            hasher.combine(key)
            return hasher.finalize()
        }
        override func isEqual(_ object: Any?) -> Bool { (object as? KeyBox)?.key == key }
    }

    private let cache = NSCache<KeyBox, Entry>()

    init(countLimit: Int, totalCostLimitBytes: Int) {
        cache.countLimit = countLimit
        cache.totalCostLimit = totalCostLimitBytes
    }

    func preview(for key: Key) -> LibraryTilePreview? { cache.object(forKey: KeyBox(key))?.preview }

    func store(_ preview: LibraryTilePreview, for key: Key) {
        // A file in the cloud gets its preview once it is downloaded; it is not remembered.
        if case .notDownloaded = preview { return }
        cache.setObject(Entry(preview), forKey: KeyBox(key), cost: Self.costBytes(of: preview))
    }

    /// The memory a preview holds: its pictures' decoded pixels. A note's text is small
    /// beside them and is not counted.
    static func costBytes(of preview: LibraryTilePreview) -> Int {
        switch preview {
        case .picture(let image): image.bytesPerRow * image.height
        case .note(_, let picture): picture.map { image in image.bytesPerRow * image.height } ?? 0
        case .notDownloaded, .kindIcon: 0
        }
    }
}

/// What went wrong in the library, for the view to word.
enum LibraryFailure: Equatable {
    case folderUnreadable
    case styleNotSaved
    /// The look was saved in the vault, but Finder's copy of it on the folder was not written.
    case finderLookNotWritten
    /// The vault's folder-color file was not Graphite's format; it was kept under this name
    /// beside it, and the folders show plain.
    case folderStylesSetAside(keptCopyName: String)
    /// The folder-color file was not Graphite's format and could not be moved aside either.
    case folderStylesUnreadable
}

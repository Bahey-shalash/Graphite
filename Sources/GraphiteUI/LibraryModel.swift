import Foundation
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
        let loader: LibraryPreviewLoader
    }

    /// Recently shown previews kept for scrolling back; on-screen tiles keep theirs in
    /// `visiblePreviews`. The cache gives memory back on its own under pressure.
    static let cachedPreviewCount = 240
    /// A tile's preview, longer side in pixels: enough for a tile of about 180 points at 3x.
    static let previewPixels = 540

    /// Whether the library covers the first side's documents as the window's home, as
    /// Goodnotes shows its library until a document tab is chosen.
    private(set) var isShownAsHome = true
    private(set) var folder: VaultPath = .root
    private(set) var items: [VaultEntry] = []
    private(set) var failure: LibraryFailure?
    var filter: LibraryFilter = .all { didSet { applyFilter() } }
    private(set) var folderStyles = FolderStyleList()
    /// Previews of the tiles on screen; a tile's entry goes when it scrolls away.
    private(set) var visiblePreviews: [VaultPath: LibraryTilePreview] = [:]

    @ObservationIgnored private var source: Source?
    @ObservationIgnored private var listedEntries: [VaultEntry] = []
    @ObservationIgnored private var sortOrder = FileSortOrder.alphabetical
    @ObservationIgnored private var previewTasks: [VaultPath: Task<Void, Never>] = [:]
    /// How many tiles of each file are on screen. SwiftUI shows a rebuilt grid's tile before
    /// it removes the old one, so a file's preview goes only when its last tile does.
    @ObservationIgnored private var visibleTileCounts: [VaultPath: Int] = [:]
    @ObservationIgnored private var previewCache = LibraryPreviewCache(countLimit: cachedPreviewCount)

    /// Lists the folder again, from a new vault's root when the vault changed.
    func reload(source newSource: Source?, sortOrder newSortOrder: FileSortOrder) async {
        if newSource?.vaultIdentifier != source?.vaultIdentifier {
            cancelPreviews()
            previewCache = LibraryPreviewCache(countLimit: Self.cachedPreviewCount)
            folder = .root
        }
        source = newSource
        sortOrder = newSortOrder
        await listFolder()
    }

    func showHome() { isShownAsHome = true }

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

    private func listFolder() async {
        guard let source else {
            listedEntries = []; items = []; failure = nil
            return
        }
        let listedFolder = folder
        do {
            let entries = try await source.store.children(of: listedFolder, sortedBy: sortOrder)
            let styles = try await source.store.folderStyles()
            guard listedFolder == folder else { return }
            listedEntries = entries
            if styles != folderStyles { folderStyles = styles }
            if failure == .folderUnreadable { failure = nil }
            applyFilter()
        } catch {
            guard listedFolder == folder else { return }
            // A folder deleted or moved while shown: the library goes up to one that exists.
            if !listedFolder.rawValue.isEmpty, (try? await source.store.fileExists(listedFolder)) == false { // An unanswerable check counts as present.
                folder = listedFolder.parent
                await listFolder()
            } else {
                failure = .folderUnreadable
            }
        }
    }

    private func applyFilter() {
        let filteredItems = LibraryListing.items(of: listedEntries, filter: filter, sortOrder: sortOrder)
        if filteredItems != items { items = filteredItems }
    }

    func style(of folder: VaultPath) -> FolderStyle? { folderStyles.style(for: folder) }

    /// Saves a folder's look in the vault; a failure leaves the folder as it was and is reported.
    func setStyle(_ style: FolderStyle?, for styledFolder: VaultPath) async {
        guard let source else { return }
        do {
            folderStyles = try await source.store.updateFolderStyles { @Sendable styles in styles.setStyle(style, for: styledFolder) }
        } catch {
            failure = .styleNotSaved
        }
    }

    func dismissFailure() { failure = nil }

    // MARK: Previews

    /// Starts the preview of a tile that came on screen, from the cache when it is current.
    func tileAppeared(_ entry: VaultEntry) {
        guard !entry.isDirectory, let source else { return }
        visibleTileCounts[entry.path, default: 0] += 1
        let key = LibraryPreviewCache.Key(entry: entry)
        if let cached = previewCache.preview(for: key) {
            visiblePreviews[entry.path] = cached
            return
        }
        // A tile of the same file already asked for this version.
        if previewTasks[entry.path] != nil, visibleTileCounts[entry.path, default: 0] > 1 { return }
        previewTasks[entry.path]?.cancel()
        let loader = source.loader
        previewTasks[entry.path] = Task { [weak self] in
            let preview = await Task.detached(priority: .utility) { await loader.preview(of: entry.path, longerSidePixels: Self.previewPixels) }.value
            guard !Task.isCancelled, let self else { return }
            self.previewCache.store(preview, for: key)
            self.visiblePreviews[entry.path] = preview
            self.previewTasks[entry.path] = nil
        }
    }

    /// Stops a tile's preview work and lets go of its picture once it leaves the screen.
    func tileDisappeared(_ entry: VaultEntry) {
        guard !entry.isDirectory else { return }
        let remainingTiles = max(visibleTileCounts[entry.path, default: 0] - 1, 0)
        visibleTileCounts[entry.path] = remainingTiles == 0 ? nil : remainingTiles
        guard remainingTiles == 0 else { return }
        previewTasks.removeValue(forKey: entry.path)?.cancel()
        visiblePreviews[entry.path] = nil
    }

    private func cancelPreviews() {
        for task in previewTasks.values { task.cancel() }
        previewTasks = [:]
        visiblePreviews = [:]
        visibleTileCounts = [:]
    }
}

/// Previews by file and version, bounded by count; `NSCache` also empties itself when the
/// system is short of memory.
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

    init(countLimit: Int) {
        cache.countLimit = countLimit
    }

    func preview(for key: Key) -> LibraryTilePreview? { cache.object(forKey: KeyBox(key))?.preview }

    func store(_ preview: LibraryTilePreview, for key: Key) {
        // A file in the cloud gets its preview once it is downloaded; it is not remembered.
        if case .notDownloaded = preview { return }
        cache.setObject(Entry(preview), forKey: KeyBox(key))
    }
}

/// What went wrong in the library, for the view to word.
enum LibraryFailure: Equatable {
    case folderUnreadable
    case styleNotSaved
}

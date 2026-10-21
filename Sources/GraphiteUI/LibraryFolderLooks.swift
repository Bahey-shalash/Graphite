import Foundation
import CoreGraphics
import Observation
import GraphiteCore
import GraphiteApple

/// The looks of one vault's folders as the library shows them: Graphite's styles from the
/// vault, Finder's own looks of the folders listed, and the pictures of the folder tiles on
/// screen (a folder's own picture, and on the Mac the system's icon wherever Finder draws the
/// look). A new vault gets a new instance.
@MainActor @Observable
final class LibraryFolderLooks {
    /// Reads a picture of the vault, scaled to a longer side in pixels, off the main actor.
    typealias PictureLoader = @Sendable (VaultPath, _ longerSidePixels: Int) async -> CGImage?

    /// The tile pictures' side in pixels: a 120-point tile at 3x.
    static let tileImagePixels = 384

    private(set) var styles = FolderStyleList()
    /// Finder's looks of the folders listed, read with the listing.
    private(set) var finderLooks: [VaultPath: FinderFolderLook] = [:]
    /// The pictures of the folder tiles on screen; a tile's picture goes when it scrolls away.
    private(set) var tileImages: [VaultPath: CGImage] = [:]
    /// The Mac's plain folder, drawn once.
    private(set) var plainFolderIcon: CGImage?

    @ObservationIgnored private let attributes: FinderFolderAttributes?
    @ObservationIgnored private let loadPicture: PictureLoader
    /// How many tiles of each folder are on screen. SwiftUI shows a rebuilt grid's tile before
    /// it removes the old one, so a folder's picture goes only when its last tile does.
    @ObservationIgnored private var visibleTileCounts: [VaultPath: Int] = [:]
    /// Folder tiles on screen whose picture waits to be drawn, oldest first.
    @ObservationIgnored private var waitingImages: [VaultPath] = []
    /// Draws the waiting pictures one at a time; nil while none waits.
    @ObservationIgnored private var imageTask: Task<Void, Never>?

    init(attributes: FinderFolderAttributes?, loadPicture: @escaping PictureLoader) {
        self.attributes = attributes
        self.loadPicture = loadPicture
    }

    func shownLook(of folder: VaultPath) -> ShownFolderLook {
        ShownFolderLook.resolve(stored: styles.style(for: folder), finder: finderLooks[folder] ?? .plain)
    }

    func replaceStyles(_ newStyles: FolderStyleList) {
        guard newStyles != styles else { return }
        let changedFolders = Set(styles.styles.keys).union(newStyles.styles.keys)
            .filter { folder in styles.style(for: folder) != newStyles.style(for: folder) }
        styles = newStyles
        redrawImages(of: changedFolders)
    }

    /// Reads Finder's looks of the listed folders off the main actor: three small reads of
    /// metadata each, which never download a file.
    func readFinderLooks(of folders: [VaultPath]) async {
        guard let attributes else { return }
        let looks = await Task.detached(priority: .userInitiated) {
            Dictionary(folders.map { folder in (folder, attributes.look(of: folder)) }, uniquingKeysWith: { first, _ in first })
        }.value
        guard looks != finderLooks else { return }
        let changedFolders = Set(looks.keys).union(finderLooks.keys).filter { folder in looks[folder] != finderLooks[folder] }
        finderLooks = looks
        redrawImages(of: changedFolders)
    }

    /// On the Mac, writes a folder's look where Finder reads it, then reads back what Finder
    /// shows now. Returns false when the write failed. iOS writes nothing: there Graphite's
    /// style in the vault is the look's only copy Graphite writes.
    func writeFinderLook(_ style: FolderStyle?, of folder: VaultPath) async -> Bool {
        #if os(macOS)
        guard let attributes else { return true }
        let colorTagNames = FinderFolderAttributes.colorTagNames()
        let (isWritten, look) = await Task.detached(priority: .userInitiated) {
            let change = FinderFolderLookChange.change(for: style, from: attributes.look(of: folder), colorTagNames: colorTagNames)
            let isWritten = (try? attributes.write(change, to: folder)) != nil // The caller reports a failed write.
            return (isWritten, attributes.look(of: folder))
        }.value
        if finderLooks[folder] != look {
            finderLooks[folder] = look
        }
        // The system's icon changes even when the look reads the same, as with a new picture.
        redrawImages(of: [folder])
        return isWritten
        #else
        return true
        #endif
    }

    // MARK: Tile pictures

    /// The folder's own picture as its tile shows it, when one is drawn.
    func picture(of folder: VaultPath) -> CGImage? {
        guard case .picture = imageSource(of: folder) else { return nil }
        return tileImages[folder]
    }

    func tileAppeared(_ folder: VaultPath) {
        visibleTileCounts[folder, default: 0] += 1
        requestImage(of: folder)
    }

    func tileDisappeared(_ folder: VaultPath) {
        let remainingTiles = max(visibleTileCounts[folder, default: 0] - 1, 0)
        visibleTileCounts[folder] = remainingTiles == 0 ? nil : remainingTiles
        guard remainingTiles == 0 else { return }
        waitingImages.removeAll { waitingFolder in waitingFolder == folder }
        tileImages[folder] = nil
    }

    private func isVisible(_ folder: VaultPath) -> Bool { visibleTileCounts[folder] != nil }

    /// What a tile's picture is drawn from: on the Mac the system's icon wherever Finder draws
    /// the look, otherwise the folder's own picture; nil when the tile is drawn without one.
    private func imageSource(of folder: VaultPath) -> FolderTileImageSource? {
        let look = shownLook(of: folder)
        #if os(macOS)
        if case .drawnByFinder = look { return .systemIcon }
        #endif
        return look.style?.picture.map { picture in .picture(picture.path) }
    }

    /// Draws again the pictures of folders whose look changed; the old picture shows until then.
    private func redrawImages(of changedFolders: Set<VaultPath>) {
        for folder in changedFolders where isVisible(folder) {
            waitingImages.removeAll { waitingFolder in waitingFolder == folder }
            if imageSource(of: folder) == nil { tileImages[folder] = nil } else { requestImage(of: folder, redrawing: true) }
        }
    }

    /// Queues a tile's picture, and on the Mac draws the plain folder once.
    private func requestImage(of folder: VaultPath, redrawing: Bool = false) {
        if imageSource(of: folder) != nil {
            guard redrawing || tileImages[folder] == nil, !waitingImages.contains(folder) else { return }
            waitingImages.append(folder)
        } else {
            #if os(macOS)
            guard case .plain = shownLook(of: folder), plainFolderIcon == nil else { return }
            #else
            return
            #endif
        }
        guard imageTask == nil else { return }
        imageTask = Task { [weak self] in
            await self?.drawImagesUntilNoneWaits()
            self?.imageTask = nil
        }
    }

    private func drawImagesUntilNoneWaits() async {
        let pixels = Self.tileImagePixels
        #if os(macOS)
        if plainFolderIcon == nil, let attributes {
            plainFolderIcon = await Task.detached(priority: .userInitiated) { attributes.systemIcon(of: nil, pixels: pixels) }.value
        }
        #endif
        while !waitingImages.isEmpty, !Task.isCancelled {
            let folder = waitingImages.removeFirst()
            guard let source = imageSource(of: folder) else { continue }
            let image = await drawImage(from: source, of: folder, pixels: pixels)
            // A tile that scrolled away, or whose look changed while it was drawn, waits again or needs none.
            if isVisible(folder), !waitingImages.contains(folder) { tileImages[folder] = image }
        }
    }

    private func drawImage(from source: FolderTileImageSource, of folder: VaultPath, pixels: Int) async -> CGImage? {
        switch source {
        case .picture(let picturePath):
            return await loadPicture(picturePath, pixels)
        case .systemIcon:
            #if os(macOS)
            guard let attributes else { return nil }
            return await Task.detached(priority: .userInitiated) { attributes.systemIcon(of: folder, pixels: pixels) }.value
            #else
            return nil
            #endif
        }
    }
}

/// What a folder tile's picture is drawn from.
enum FolderTileImageSource: Equatable {
    /// The system's own icon of the folder, as Finder draws it; on the Mac only.
    case systemIcon
    /// The folder's picture in the vault.
    case picture(VaultPath)
}

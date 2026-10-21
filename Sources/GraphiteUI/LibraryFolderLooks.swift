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
    private(set) var tileImages: [VaultPath: FolderTileImage] = [:]
    /// The Mac's plain folder, drawn once.
    private(set) var plainFolderIcon: CGImage?

    @ObservationIgnored private let attributes: FinderFolderAttributes?
    /// Folders whose attributes could not be written, as on a provider that refuses them.
    @ObservationIgnored private var unwritableFolders: Set<VaultPath> = []
    @ObservationIgnored private let loadPicture: PictureLoader
    @ObservationIgnored private let appleArt: AppleFolderArt
    /// How many tiles of each folder are on screen. SwiftUI shows a rebuilt grid's tile before
    /// it removes the old one, so a folder's picture goes only when its last tile does.
    @ObservationIgnored private var visibleTileCounts: [VaultPath: Int] = [:]
    /// Folder tiles on screen whose picture waits to be drawn, oldest first.
    @ObservationIgnored private var waitingImages: [VaultPath] = []
    /// Whether the plain folder was asked for; it is drawn once, or left to Graphite's drawing when the system gives none.
    @ObservationIgnored private var isPlainFolderIconRequested = false
    /// Draws the waiting pictures one at a time; nil while none waits.
    @ObservationIgnored private var imageTask: Task<Void, Never>?

    init(attributes: FinderFolderAttributes?, appleArt: AppleFolderArt, loadPicture: @escaping PictureLoader) {
        self.attributes = attributes
        self.appleArt = appleArt
        self.loadPicture = loadPicture
    }

    /// A look drawn with Apple's folder art, for a preview; the bare picture, or nothing, when
    /// the system gives no art.
    func image(for style: FolderStyle) async -> FolderTileImage? {
        await drawImage(from: .appleArt(style), of: .root, pixels: Self.tileImagePixels)
    }

    /// Apple's folder art in a color, at the icon maker's export size, for its folder templates.
    func folderArt(color: FolderColor?) async -> CGImage? {
        let appleArt = appleArt
        return await Task.detached(priority: .userInitiated) {
            await appleArt.art(for: FolderStyle(color: color), picture: nil, pixels: FolderIconMakerRenders.exportPixels)
        }.value
    }

    func shownLook(of folder: VaultPath) -> ShownFolderLook {
        ShownFolderLook.resolve(stored: styles.style(for: folder), finder: finderLooks[folder] ?? .plain,
                                canWritePictures: FinderFolderAttributes.canWriteCustomIcons)
    }

    /// The listed folders whose style and attributes differ, and what brings them together.
    /// A folder whose attributes could not be written is not tried again while this vault is open.
    func reconciliations() -> [(folder: VaultPath, action: FolderLookReconciliation)] {
        guard attributes != nil else { return [] }
        return finderLooks.keys.sorted().compactMap { folder in
            guard !unwritableFolders.contains(folder), let finder = finderLooks[folder] else { return nil }
            let action = FolderLookReconciliation.action(stored: styles.style(for: folder), finder: finder,
                                                         canWritePictures: FinderFolderAttributes.canWriteCustomIcons)
            return action == .none ? nil : (folder, action)
        }
    }

    /// The colors of a folder's tags, as Finder and Files show them as dots beside its name.
    func tagColors(of folder: VaultPath) -> [FolderColor] {
        (finderLooks[folder]?.tags ?? []).compactMap { tag in tag.color?.folderColor }
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

    /// Writes a folder's look where Finder and the Files app read it, then reads back what
    /// they show now. Returns false when the write failed.
    func writeFinderLook(_ style: FolderStyle?, of folder: VaultPath) async -> Bool {
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
        if !isWritten { unwritableFolders.insert(folder) }
        // The system's icon changes even when the look reads the same, as with a new picture.
        redrawImages(of: [folder])
        return isWritten
    }

    // MARK: Tile pictures

    /// The folder's own picture as its tile shows it, when one is drawn.

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

    /// What a tile's picture is drawn from: the system's icon wherever Finder and Files draw
    /// the look, Apple's art for a look Graphite draws; nil for a plain folder, which shares one.
    private func imageSource(of folder: VaultPath) -> FolderTileImageSource? {
        switch shownLook(of: folder) {
        case .drawnByFinder: .systemIcon
        case .drawnByGraphite(let style): .appleArt(style)
        case .plain: nil
        }
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
        } else if isPlainFolderIconRequested {
            return
        }
        guard imageTask == nil else { return }
        imageTask = Task { [weak self] in
            await self?.drawImagesUntilNoneWaits()
            self?.imageTask = nil
        }
    }

    private func drawImagesUntilNoneWaits() async {
        let pixels = Self.tileImagePixels
        if !isPlainFolderIconRequested {
            isPlainFolderIconRequested = true
            plainFolderIcon = await Task.detached(priority: .userInitiated) { await FinderFolderAttributes.plainFolderIcon(pixels: pixels) }.value
        }
        while !waitingImages.isEmpty, !Task.isCancelled {
            let folder = waitingImages.removeFirst()
            guard let source = imageSource(of: folder) else { continue }
            let image = await drawImage(from: source, of: folder, pixels: pixels)
            // A tile that scrolled away, or whose look changed while it was drawn, waits again or needs none.
            if isVisible(folder), !waitingImages.contains(folder) { tileImages[folder] = image }
        }
    }

    private func drawImage(from source: FolderTileImageSource, of folder: VaultPath, pixels: Int) async -> FolderTileImage? {
        switch source {
        case .systemIcon:
            guard let attributes else { return nil }
            let icon = await Task.detached(priority: .userInitiated) { await attributes.systemIcon(of: folder, pixels: pixels) }.value
            return icon.map(FolderTileImage.appleArt)
        case .appleArt(let style):
            let picture: CGImage? = if let picturePath = style.picture?.path { await loadPicture(picturePath, pixels) } else { nil }
            return await drawArt(for: style, picture: picture, pixels: pixels)
        }
    }

    private func drawArt(for style: FolderStyle, picture: CGImage?, pixels: Int) async -> FolderTileImage? {
        let appleArt = appleArt
        let art = await Task.detached(priority: .userInitiated) { await appleArt.art(for: style, picture: picture, pixels: pixels) }.value
        return art.map(FolderTileImage.appleArt) ?? picture.map(FolderTileImage.picture)
    }
}

/// What a folder tile's picture is drawn from.
enum FolderTileImageSource: Equatable {
    /// The system's own icon of the folder, as Finder and the Files app draw it.
    case systemIcon
    /// A look Graphite draws, made from Apple's folder art.
    case appleArt(FolderStyle)
}

/// A folder tile's picture.
enum FolderTileImage {
    /// The whole folder in Apple's art, with its look.
    case appleArt(CGImage)
    /// Only the folder's own picture, for Graphite's drawing where the system gave no art.
    case picture(CGImage)
}

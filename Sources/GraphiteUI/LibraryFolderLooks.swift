import Foundation
import CoreGraphics
import Observation
import GraphiteCore
import GraphiteApple

/// The looks of one vault's folders as the library shows them: Graphite's styles from the
/// vault, Finder's own looks of the folders listed, and on the Mac the system's icons of the
/// folder tiles on screen. A new vault gets a new instance.
@MainActor @Observable
final class LibraryFolderLooks {
    /// The icons' width in pixels: a 120-point tile on the Mac's 2x screens.
    static let systemIconPixels = 256

    private(set) var styles = FolderStyleList()
    /// Finder's looks of the folders listed, read with the listing.
    private(set) var finderLooks: [VaultPath: FinderFolderLook] = [:]
    /// The Mac's icons of the folder tiles on screen that Finder draws; a tile's icon goes
    /// when it scrolls away. Always empty on iOS, which has no API for the Files app's icons.
    private(set) var systemIcons: [VaultPath: CGImage] = [:]
    /// The Mac's plain folder, drawn once.
    private(set) var plainFolderIcon: CGImage?

    @ObservationIgnored private let attributes: FinderFolderAttributes?
    @ObservationIgnored private var visibleFolders: Set<VaultPath> = []
    /// Folder tiles on screen whose icon waits to be drawn, oldest first.
    @ObservationIgnored private var waitingIcons: [VaultPath] = []
    /// Draws the waiting icons one at a time; nil while none waits.
    @ObservationIgnored private var iconTask: Task<Void, Never>?

    init(attributes: FinderFolderAttributes?) {
        self.attributes = attributes
    }

    func shownLook(of folder: VaultPath) -> ShownFolderLook {
        ShownFolderLook.resolve(stored: styles.style(for: folder), finder: finderLooks[folder] ?? .plain)
    }

    func replaceStyles(_ newStyles: FolderStyleList) {
        guard newStyles != styles else { return }
        let changedFolders = Set(styles.styles.keys).union(newStyles.styles.keys)
            .filter { folder in styles.style(for: folder) != newStyles.style(for: folder) }
        styles = newStyles
        redrawIcons(of: changedFolders)
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
        redrawIcons(of: changedFolders)
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
            redrawIcons(of: [folder])
        }
        return isWritten
        #else
        return true
        #endif
    }

    // MARK: System icons

    func tileAppeared(_ folder: VaultPath) {
        visibleFolders.insert(folder)
        requestIcon(of: folder)
    }

    func tileDisappeared(_ folder: VaultPath) {
        visibleFolders.remove(folder)
        waitingIcons.removeAll { waitingFolder in waitingFolder == folder }
        systemIcons[folder] = nil
    }

    /// Draws again the icons of folders whose look changed; the old icon shows until then.
    private func redrawIcons(of changedFolders: Set<VaultPath>) {
        for folder in changedFolders where visibleFolders.contains(folder) {
            waitingIcons.removeAll { waitingFolder in waitingFolder == folder }
            if case .drawnByFinder = shownLook(of: folder) { requestIcon(of: folder, redrawing: true) } else { systemIcons[folder] = nil }
        }
    }

    /// Queues the system icon of a tile Finder draws, or draws the plain folder once; on the
    /// Mac only, since iOS has no such icons.
    private func requestIcon(of folder: VaultPath, redrawing: Bool = false) {
        #if os(macOS)
        switch shownLook(of: folder) {
        case .drawnByFinder:
            guard redrawing || systemIcons[folder] == nil, !waitingIcons.contains(folder) else { return }
            waitingIcons.append(folder)
        case .plain:
            guard plainFolderIcon == nil else { return }
        case .drawnByGraphite:
            return
        }
        guard iconTask == nil, let attributes else { return }
        iconTask = Task { [weak self] in
            await self?.drawIconsUntilNoneWaits(with: attributes)
            self?.iconTask = nil
        }
        #endif
    }

    #if os(macOS)
    private func drawIconsUntilNoneWaits(with attributes: FinderFolderAttributes) async {
        let pixels = Self.systemIconPixels
        if plainFolderIcon == nil {
            plainFolderIcon = await Task.detached(priority: .userInitiated) { attributes.systemIcon(of: nil, pixels: pixels) }.value
        }
        while !waitingIcons.isEmpty, !Task.isCancelled {
            let folder = waitingIcons.removeFirst()
            let icon = await Task.detached(priority: .userInitiated) { attributes.systemIcon(of: folder, pixels: pixels) }.value
            // A tile that scrolled away, or whose look changed while it was drawn, waits again or needs none.
            if visibleFolders.contains(folder), !waitingIcons.contains(folder) { systemIcons[folder] = icon }
        }
    }
    #endif
}

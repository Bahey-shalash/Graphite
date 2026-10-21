import Foundation
import GraphiteCore
import GraphiteApple

/// The values and actions a `LibraryView` needs, made from the workspace by the views that
/// hold it, so the library itself depends on no workspace.
extension WorkspaceModel {
    var libraryVault: LibraryVault {
        LibraryVault(source: librarySource, title: title, sortOrder: vaultSettings.fileSortOrder, listingVersion: directoryVersion,
                     firstCreatedKind: preferences.library.firstCreatedKind, isPluginEnabled: preferences.isEnabled,
                     presentation: preferences.library.presentation)
    }

    private var librarySource: LibraryModel.Source? {
        guard let vaultIdentifier = currentVaultIdentifier, let store, let root = folderAccess?.root else { return nil }
        let index = index
        let loader = LibraryPreviewLoader(root: root) { target, notePath in
            // An unresolved or ambiguous picture leaves the note's tile without one.
            guard let index else { return nil }
            let matches = try? await index.resolve(target, from: notePath) // A failed lookup is no picture.
            guard let matches, matches.count == 1 else { return nil }
            return matches[0]
        }
        let finderAttributes = FinderFolderAttributes(root: root)
        return LibraryModel.Source(vaultIdentifier: vaultIdentifier, store: store, finderAttributes: finderAttributes) { path, longerSidePixels in
            await loader.preview(of: path, longerSidePixels: longerSidePixels)
        }
    }

    func libraryActions(openFile: @escaping (VaultPath) -> Void, requestCreation: @escaping (CreationKind, VaultPath?) -> Void) -> LibraryActions {
        LibraryActions(openFile: openFile, requestCreation: requestCreation,
                       openDailyNote: { [weak self] in Task { await self?.openDailyNote() } },
                       newFolder: { [weak self] folder in self?.fileSheet = .newFolder(in: folder) },
                       importFiles: { [weak self] sources, folder in Task { await self?.importFiles(from: sources, into: folder) } },
                       moveItems: { [weak self] paths, folder in Task { for path in paths { await self?.move(path, into: folder) } } },
                       setSortOrder: { [weak self] sortOrder in self?.setFileSortOrder(sortOrder) },
                       setPresentation: { [weak self] presentation in self?.preferences.library.presentation = presentation },
                       findPictures: { [weak self] query in await self?.vaultPictures(matching: query) ?? [] })
    }

    func libraryEntryPresentation(requestCreation: @escaping (CreationKind, VaultPath) -> Void) -> LibraryEntryPresentation {
        LibraryEntryPresentation(displayName: preferences.displayName(for:),
                                 isBookmarked: { [weak self] path in
                                     guard let self else { return false }
                                     return preferences.isEnabled(.bookmarks) && isBookmarked(path)
                                 },
                                 menu: { [unowned self] entry in VaultEntryMenu(entry: entry, workspace: self, requestCreation: requestCreation) })
    }

    /// Pictures of the vault whose name matches `query`, from the index; the recent ones for an
    /// empty query. A failed search finds none.
    private func vaultPictures(matching query: String) async -> [VaultPath] {
        guard !query.isEmpty else {
            return existingRecentFiles(limit: Self.recentPictureCount).filter(Self.isPicture)
        }
        let matches = (try? await index?.quickSwitcherMatches(for: query, limit: Self.pictureMatchLimit)) ?? [] // A failed search finds none.
        var seenPaths: Set<VaultPath> = []
        return matches.map(\.path).filter { path in Self.isPicture(path) && seenPaths.insert(path).inserted }
    }

    private static func isPicture(_ path: VaultPath) -> Bool {
        if case .image = DocumentKind(path: path) { true } else { false }
    }

    private static let recentPictureCount = 30
    private static let pictureMatchLimit = 200

    /// The file list's and the library's sort order, Obsidian's "Sort order" setting.
    func setFileSortOrder(_ sortOrder: FileSortOrder) {
        var settings = vaultSettings
        settings.fileSortOrder = sortOrder
        Task { await updateVaultSettings(settings) }
    }
}

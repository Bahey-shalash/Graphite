import Foundation
import GraphiteCore
import GraphiteApple

/// The values and actions a `LibraryView` needs, made from the workspace by the views that
/// hold it, so the library itself depends on no workspace.
extension WorkspaceModel {
    var libraryVault: LibraryVault {
        LibraryVault(source: librarySource, title: title, sortOrder: vaultSettings.fileSortOrder, listingVersion: directoryVersion,
                     firstCreatedKind: preferences.library.firstCreatedKind, isPluginEnabled: preferences.isEnabled,
                     presentation: preferences.library.presentation, confirmsDeletion: vaultSettings.confirmsDeletion,
                     deletionMethod: vaultSettings.deletionMethod)
    }

    /// Makes the previews of the vault's files that the library's tiles and the tab overview's
    /// cards show.
    var libraryPreviewLoader: LibraryPreviewLoader? {
        guard let root = folderAccess?.root else { return nil }
        let index = index
        return LibraryPreviewLoader(root: root) { target, notePath in
            // An unresolved or ambiguous picture leaves the note's tile without one.
            guard let index else { return nil }
            let matches = try? await index.resolve(target, from: notePath) // A failed lookup is no picture.
            guard let matches, matches.count == 1 else { return nil }
            return matches[0]
        }
    }

    private var librarySource: LibraryModel.Source? {
        guard let vaultIdentifier = currentVaultIdentifier, let store, let root = folderAccess?.root, let loader = libraryPreviewLoader else { return nil }
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
                       receiveDrop: { [weak self] providers, folder in self?.receiveDrop(providers, into: folder) ?? false },
                       saveScannedNotebook: scannedNotebookSaver(),
                       reportProblem: { [weak self] message in self?.errorMessage = message },
                       savePicture: pictureSaver(), canTakePhoto: Self.canTakePhotos,
                       moveItems: { [weak self] paths, folder in Task { for path in paths { await self?.move(path, into: folder) } } },
                       setSortOrder: { [weak self] sortOrder in self?.setFileSortOrder(sortOrder) },
                       setPresentation: { [weak self] presentation in self?.preferences.library.presentation = presentation },
                       findPictures: { [weak self] query in await self?.vaultPictures(matching: query) ?? [] },
                       deleteItems: { [weak self] paths in Task { for path in paths { await self?.delete(path) } } },
                       duplicateItems: { [weak self] paths in Task { await self?.duplicate(paths) } },
                       requestMove: { [weak self] paths in self?.fileSheet = .moveItems(paths) })
    }

    func libraryEntryPresentation(requestCreation: @escaping (CreationKind, VaultPath) -> Void) -> LibraryEntryPresentation {
        LibraryEntryPresentation(displayName: preferences.displayName(for:),
                                 isBookmarked: { [weak self] path in
                                     guard let self else { return false }
                                     return preferences.isEnabled(.bookmarks) && isBookmarked(path)
                                 },
                                 menu: { [unowned self] entry in VaultEntryMenu(entry: entry, workspace: self, requestCreation: requestCreation) },
                                 accessibilityActions: { [weak self] entry in
                                     guard let self else { return [] }
                                     return entryActions(for: entry).map { action in
                                         LibraryEntryAction(action: action, title: action.title(otherSideTitle: openOnOtherSideTitle),
                                                            perform: { [weak self] in self?.perform(action, on: entry.path) })
                                     }
                                 },
                                 fileLocation: { [weak self] path in
                                     guard let root = self?.folderAccess?.root else { return nil }
                                     return try? path.url(in: root) // A path outside the vault has no location to share.
                                 })
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

    /// Takes a drop on the library, a folder tile or the back button: vault items move into the
    /// folder through `move(_:into:)` (the file tree's own moves) and files from other apps are
    /// copied in through `importFiles`, whose staged copies are removed afterwards.
    func receiveDrop(_ providers: [NSItemProvider], into folder: VaultPath) -> Bool {
        guard LibraryDropReader.canRead(providers) else { return false }
        Task {
            let plan = LibraryDropPlan.make(from: await LibraryDropReader.read(providers), into: folder)
            for path in plan.movedPaths { await move(path, into: folder) }
            guard !plan.droppedFiles.isEmpty else { return }
            let batch = DroppedFileBatch(files: plan.droppedFiles)
            await importFiles(from: batch.locations, into: folder)
            batch.discard()
        }
        return true
    }

    /// The file list's and the library's sort order, Obsidian's "Sort order" setting.
    func setFileSortOrder(_ sortOrder: FileSortOrder) {
        var settings = vaultSettings
        settings.fileSortOrder = sortOrder
        Task { await updateVaultSettings(settings) }
    }
}

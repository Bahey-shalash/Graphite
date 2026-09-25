import Foundation
import GraphiteCore

/// Obsidian's Bookmarks core plugin, kept in the vault's `.obsidian/bookmarks.json` so the
/// same bookmarks show in Obsidian.
extension WorkspaceModel {
    func reloadBookmarks() async {
        guard let store else { bookmarks = BookmarkList(); return }
        do { bookmarks = try await store.bookmarks() }
        catch { errorMessage = error.localizedDescription }
    }

    /// Changes the bookmarks as they are in the file now, then shows the result.
    func updateBookmarks(_ change: @escaping @Sendable (inout BookmarkList) -> Void) async {
        guard let store else { return }
        do { bookmarks = try await store.updateBookmarks(change) }
        catch { errorMessage = error.localizedDescription }
    }

    func isBookmarked(_ path: VaultPath) -> Bool {
        (isDirectory(path) ? bookmarks.folderBookmark(for: path) : bookmarks.fileBookmark(for: path)) != nil
    }

    /// Bookmarks a file or folder, or removes its bookmark, as Obsidian's "Bookmark" does.
    func toggleBookmark(_ path: VaultPath) async {
        let isFolder = isDirectory(path)
        if let existing = isFolder ? bookmarks.folderBookmark(for: path) : bookmarks.fileBookmark(for: path) {
            let id = existing.id
            await updateBookmarks { bookmarks in bookmarks.remove(id: id) }
        } else {
            let bookmark = isFolder ? Bookmark.folder(path) : Bookmark.file(path)
            await updateBookmarks { bookmarks in bookmarks.add(bookmark) }
        }
    }

    /// Obsidian's "Bookmark current search".
    func bookmarkSearch(_ query: String) async {
        let trimmedQuery = query.trimmingCharacters(in: .whitespaces)
        guard !trimmedQuery.isEmpty, bookmarks.searchBookmark(for: trimmedQuery) == nil else { return }
        await updateBookmarks { bookmarks in bookmarks.add(.search(trimmedQuery)) }
    }

    func removeBookmark(_ bookmark: Bookmark) async {
        let id = bookmark.id
        await updateBookmarks { bookmarks in bookmarks.remove(id: id) }
    }

    func renameBookmark(_ bookmark: Bookmark, to title: String) async {
        let id = bookmark.id
        await updateBookmarks { bookmarks in bookmarks.rename(id: id, to: title) }
    }

    func addBookmarkGroup(named title: String) async {
        let trimmedTitle = title.trimmingCharacters(in: .whitespaces)
        guard !trimmedTitle.isEmpty else { errorMessage = "A group needs a name."; return }
        await updateBookmarks { bookmarks in bookmarks.add(.group(trimmedTitle)) }
    }

    /// Opens what a bookmark points to: a note at its heading or block, a folder in the
    /// file list, or a search in the sidebar.
    func open(_ bookmark: Bookmark, placement: TabPlacement = .currentTab) async {
        switch bookmark.type {
        case "file":
            guard let path = bookmark.vaultPath else { return }
            guard isInVault(path) else { errorMessage = "“\(bookmark.displayTitle)” is no longer in this vault."; return }
            guard let tabID = await open(path, placement: placement, takesFocus: true) else { return }
            guard let subpath = bookmark.subpath, let target = subpath.split(separator: "#").last.map(String.init) else { return }
            if target.hasPrefix("^") { showBlock(String(target.dropFirst()), inTab: tabID) }
            else { document(for: tabID).headingScrollRequest = HeadingScrollRequest(anchor: NotePreviewDocument.anchor(forHeading: target)) }
        case "folder":
            guard let path = bookmark.vaultPath else { return }
            guard isInVault(path) else { errorMessage = "The folder “\(bookmark.displayTitle)” is no longer in this vault."; return }
            reveal(folder: path)
        case "search":
            searchQuery = bookmark.query ?? ""
        default:
            break
        }
    }

    /// Shows a folder, open, in the sidebar's file list.
    func reveal(folder: VaultPath) {
        UserDefaults.standard.set(SidebarPanel.files.rawValue, forKey: SidebarPanelSettingKey.panel)
        searchQuery = ""
        var folderToOpen = folder
        while !folderToOpen.rawValue.isEmpty {
            expandedFolders.insert(folderToOpen)
            folderToOpen = folderToOpen.parent
        }
    }

    /// Bookmarks on renamed or moved files and folders follow them, as in Obsidian.
    func followMoveInBookmarks(from oldPath: VaultPath, to newPath: VaultPath) {
        guard bookmarks.allBookmarks.contains(where: { bookmark in bookmark.vaultPath?.isInside(oldPath) == true }) else { return }
        Task { await updateBookmarks { bookmarks in bookmarks.followMove(from: oldPath, to: newPath) } }
    }
}

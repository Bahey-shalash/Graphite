import Foundation
import GraphiteCore

/// One action on a file or folder that the tree's menu, the library's menu and VoiceOver's
/// custom actions all offer, declared once here (`FR-23`).
enum VaultEntryAction: Hashable, Identifiable, CaseIterable {
    case openInNewTab
    case openOnOtherSide
    case rename
    case moveTo
    case makeCopy
    case bookmark
    case removeBookmark
    case delete

    var id: Self { self }

    /// `otherSideTitle` is the workspace's own wording for the other side of a split window.
    func title(otherSideTitle: String) -> String {
        switch self {
        case .openInNewTab: "Open in New Tab"
        case .openOnOtherSide: otherSideTitle
        case .rename: "Rename…"
        case .moveTo: "Move to…"
        case .makeCopy: "Make a Copy"
        case .bookmark: "Bookmark"
        case .removeBookmark: "Remove Bookmark"
        case .delete: "Delete"
        }
    }

    var systemImage: String {
        switch self {
        case .openInNewTab: "plus.rectangle.on.rectangle"
        case .openOnOtherSide: "rectangle.split.2x1"
        case .rename: "pencil"
        case .moveTo: "folder"
        case .makeCopy: "plus.square.on.square"
        case .bookmark: "bookmark"
        case .removeBookmark: "bookmark.slash"
        case .delete: "trash"
        }
    }

    var isDestructive: Bool { self == .delete }

    /// The actions an item offers, in menu order: files open in tabs, folders do not; bookmarks only while that core plugin is on.
    static func offered(isDirectory: Bool, bookmarksAreEnabled: Bool, isBookmarked: Bool) -> [VaultEntryAction] {
        var actions: [VaultEntryAction] = isDirectory ? [] : [.openInNewTab, .openOnOtherSide]
        actions += [.rename, .moveTo, .makeCopy]
        if bookmarksAreEnabled { actions.append(isBookmarked ? .removeBookmark : .bookmark) }
        actions.append(.delete)
        return actions
    }
}

extension WorkspaceModel {
    func entryActions(for entry: VaultEntry) -> [VaultEntryAction] {
        VaultEntryAction.offered(isDirectory: entry.isDirectory, bookmarksAreEnabled: preferences.isEnabled(.bookmarks), isBookmarked: isBookmarked(entry.path))
    }

    func perform(_ action: VaultEntryAction, on path: VaultPath) {
        switch action {
        case .openInNewTab: Task { await open(path, placement: .newTab) }
        case .openOnOtherSide: Task { await open(path, placement: .otherGroup) }
        case .rename: fileSheet = .rename(path)
        case .moveTo: fileSheet = .move(path)
        case .makeCopy: Task { await duplicate(path) }
        case .bookmark, .removeBookmark: Task { await toggleBookmark(path) }
        case .delete: Task { await requestDeletion(of: path) }
        }
    }
}

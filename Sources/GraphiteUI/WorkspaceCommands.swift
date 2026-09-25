import SwiftUI
import GraphiteCore

/// What commands need from the window that shows them.
struct WindowActions {
    let showQuickSwitcher: () -> Void
    let showSettings: () -> Void
    let showVaultManager: () -> Void
    let toggleLinksInspector: () -> Void
    let toggleSidebar: () -> Void
    /// Shows the left sidebar if it is hidden.
    let showSidebar: () -> Void
    /// Shows the right sidebar if it is hidden.
    let showLinksInspector: () -> Void
    let create: (CreationKind) -> Void
    /// Lists the Templates folder's notes to insert one into the current note.
    let showTemplatePicker: () -> Void
}

/// The command palette's commands, named as Obsidian names them where they match.
@MainActor
enum WorkspaceCommandList {
    static func commands(for workspace: WorkspaceModel, window: WindowActions) -> [PaletteCommand] {
        var commands: [PaletteCommand] = [
            PaletteCommand(id: "switcher", title: "Quick switcher: Open quick switcher", systemImage: "doc.text.magnifyingglass", shortcut: "⌘O", run: window.showQuickSwitcher),
            PaletteCommand(id: "search", title: "Search: Search in all files", systemImage: "magnifyingglass", shortcut: "⇧⌘F") { workspace.searchFocusRequest += 1 },
            PaletteCommand(id: "new-note", title: "Create new note", systemImage: "square.and.pencil", shortcut: "⌘N") { window.create(.note) },
            PaletteCommand(id: "new-notebook", title: "Create new notebook", systemImage: "book.closed") { window.create(.notebook) },
            PaletteCommand(id: "new-folder", title: "Files: Create new folder", systemImage: "folder.badge.plus") { workspace.fileSheet = .newFolder(in: workspace.newFileDirectory(nil)) },
            PaletteCommand(id: "toggle-left-sidebar", title: "Toggle left sidebar", systemImage: "sidebar.left", run: window.toggleSidebar),
            PaletteCommand(id: "settings", title: "Open settings", systemImage: "gearshape", shortcut: "⌘,", run: window.showSettings),
            PaletteCommand(id: "vaults", title: "Open another vault", systemImage: "building.columns", run: window.showVaultManager),
            PaletteCommand(id: "collapse-folders", title: "Files: Collapse all folders", systemImage: "arrow.down.right.and.arrow.up.left") { workspace.collapseAllFolders() },
        ]
        if workspace.preferences.isEnabled(.bases) {
            commands.append(PaletteCommand(id: "new-base", title: "Bases: Create new base", systemImage: "tablecells") { window.create(.base) })
        }
        if workspace.history.canGoBack {
            commands.append(PaletteCommand(id: "back", title: "Navigate back", systemImage: "chevron.left", shortcut: "⌘[") { Task { await workspace.goBack() } })
        }
        if workspace.history.canGoForward {
            commands.append(PaletteCommand(id: "forward", title: "Navigate forward", systemImage: "chevron.right", shortcut: "⌘]") { Task { await workspace.goForward() } })
        }
        commands += tabCommands(for: workspace)
        if workspace.preferences.isEnabled(.fileRecovery) {
            commands.append(PaletteCommand(id: "file-recovery-all", title: "File recovery: Browse all snapshots", systemImage: "clock.arrow.circlepath") {
                workspace.fileRecoveryRequest = FileRecoveryRequest(path: nil)
            })
            if let path = workspace.selection, DocumentKind(path: path) == .markdown {
                commands.append(PaletteCommand(id: "file-recovery-note", title: "File recovery: Open local history", systemImage: "clock.arrow.circlepath") {
                    workspace.fileRecoveryRequest = FileRecoveryRequest(path: path)
                })
            }
        }
        if let path = workspace.selection {
            commands.append(PaletteCommand(id: "copy-url", title: "Copy Graphite URL", systemImage: "link") { Pasteboard.copy(workspace.openingLink(to: path)) })
        }
        if workspace.preferences.isEnabled(.graph) {
            commands.append(PaletteCommand(id: "graph-open", title: "Graph view: Open graph view", systemImage: "point.3.connected.trianglepath.dotted") {
                workspace.isGraphPresented = true
            })
            if workspace.markdownSession != nil {
                commands.append(PaletteCommand(id: "graph-local", title: "Graph view: Open local graph", systemImage: "point.3.filled.connected.trianglepath.dotted") {
                    UserDefaults.standard.set(NoteLinksInspector.InspectorPanel.graph.rawValue, forKey: "GraphiteInspectorPanel")
                    window.showLinksInspector()
                })
            }
        }
        if workspace.preferences.isEnabled(.bookmarks) {
            commands.append(PaletteCommand(id: "bookmarks-show", title: "Bookmarks: Show bookmarks", systemImage: "bookmark") {
                UserDefaults.standard.set(SidebarPanel.bookmarks.rawValue, forKey: SidebarPanelSettingKey.panel)
                workspace.searchQuery = ""
                window.showSidebar()
            })
            if let path = workspace.selection {
                let isBookmarked = workspace.isBookmarked(path)
                commands.append(PaletteCommand(id: "bookmarks-file", title: isBookmarked ? "Bookmarks: Remove bookmark" : "Bookmarks: Bookmark current file",
                                               systemImage: isBookmarked ? "bookmark.slash" : "bookmark") { Task { await workspace.toggleBookmark(path) } })
            }
            let query = workspace.searchQuery.trimmingCharacters(in: .whitespaces)
            if !query.isEmpty, workspace.bookmarks.searchBookmark(for: query) == nil {
                commands.append(PaletteCommand(id: "bookmarks-search", title: "Bookmarks: Bookmark current search", systemImage: "magnifyingglass") {
                    Task { await workspace.bookmarkSearch(query) }
                })
            }
        }
        if workspace.preferences.isEnabled(.dailyNotes) {
            commands += [
                PaletteCommand(id: "daily-today", title: "Daily notes: Open today's daily note", systemImage: "calendar") { Task { await workspace.openDailyNote() } },
                PaletteCommand(id: "daily-previous", title: "Daily notes: Open previous daily note", systemImage: "chevron.backward.circle") {
                    Task { await workspace.openAdjacentDailyNote(forward: false) }
                },
                PaletteCommand(id: "daily-next", title: "Daily notes: Open next daily note", systemImage: "chevron.forward.circle") {
                    Task { await workspace.openAdjacentDailyNote(forward: true) }
                },
            ]
        }
        if let path = workspace.selection {
            commands += [
                PaletteCommand(id: "rename", title: "Rename file", systemImage: "pencil") { workspace.fileSheet = .rename(path) },
                PaletteCommand(id: "move", title: "Move file to another folder", systemImage: "folder") { workspace.fileSheet = .move(path) },
                PaletteCommand(id: "copy", title: "Make a copy of the current file", systemImage: "plus.square.on.square") { Task { await workspace.duplicate(path) } },
                PaletteCommand(id: "delete", title: "Delete current file", systemImage: "trash") { Task { await workspace.requestDeletion(of: path) } },
                PaletteCommand(id: "reveal", title: "Files: Reveal current file in navigation", systemImage: "scope") { workspace.revealCurrentFile() },
            ]
        }
        if let session = workspace.markdownSession {
            commands += noteCommands(session: session, workspace: workspace, window: window)
        }
        if workspace.preferences.isEnabled(.audioRecorder) {
            if workspace.recording.canStartRecording {
                commands.append(PaletteCommand(id: "record", title: "Audio recorder: Start recording", systemImage: "mic") { Task { await workspace.startRecording() } })
            } else if workspace.recording.state.canStop {
                commands.append(PaletteCommand(id: "stop-recording", title: "Audio recorder: Stop recording", systemImage: "stop.fill") { workspace.recording.stop() })
            }
        }
        return commands
    }

    /// Obsidian's tab and split commands.
    private static func tabCommands(for workspace: WorkspaceModel) -> [PaletteCommand] {
        let layout = workspace.layout
        let tab = layout.activeTab
        var commands = [
            PaletteCommand(id: "new-tab", title: "New tab", systemImage: "plus", shortcut: "⌘T") { workspace.openNewTab() },
            PaletteCommand(id: "close-tab", title: "Close current tab", systemImage: "xmark", shortcut: "⌘W") { Task { await workspace.closeTab(tab.id) } },
            PaletteCommand(id: "pin-tab", title: tab.isPinned ? "Unpin current tab" : "Pin current tab", systemImage: tab.isPinned ? "pin.slash" : "pin") {
                workspace.togglePin(tab.id)
            },
        ]
        if layout.focusedGroup.tabs.count > 1 {
            commands += [
                PaletteCommand(id: "close-other-tabs", title: "Close all other tabs", systemImage: "xmark.square") { Task { await workspace.closeOtherTabs(keeping: tab.id) } },
                PaletteCommand(id: "next-tab", title: "Go to next tab", systemImage: "arrow.right.square", shortcut: "⌃⇥") { workspace.activateNeighborTab(forward: true) },
                PaletteCommand(id: "previous-tab", title: "Go to previous tab", systemImage: "arrow.left.square", shortcut: "⌃⇧⇥") { workspace.activateNeighborTab(forward: false) },
            ]
        }
        if !layout.closedPaths.isEmpty {
            commands.append(PaletteCommand(id: "reopen-tab", title: "Reopen closed tab", systemImage: "arrow.uturn.backward", shortcut: "⇧⌘T") {
                Task { await workspace.reopenClosedTab() }
            })
        }
        if layout.isSplit {
            let focusedGroupID = layout.focusedGroupID
            commands += [
                PaletteCommand(id: "focus-other-side", title: "Focus the other side of the split", systemImage: "arrow.left.arrow.right") {
                    if let other = layout.otherGroup(than: focusedGroupID) { workspace.focusGroup(other.id) }
                },
                PaletteCommand(id: "close-side", title: "Close this side of the split", systemImage: "xmark.rectangle") { Task { await workspace.closeGroup(focusedGroupID) } },
            ]
        } else {
            commands.append(PaletteCommand(id: "split-right", title: "Split right", systemImage: "rectangle.split.2x1") { workspace.splitRight() })
        }
        if tab.path != nil || layout.focusedGroup.tabs.count > 1 || layout.isSplit {
            let isLeftSide = layout.groups.first?.id == layout.focusedGroupID
            commands.append(PaletteCommand(id: "move-tab", title: isLeftSide ? "Move current tab to the right" : "Move current tab to the left",
                                           systemImage: isLeftSide ? "rectangle.righthalf.inset.filled.arrow.right" : "rectangle.lefthalf.inset.filled.arrow.left") {
                workspace.moveTabToOtherGroup(tab.id)
            })
        }
        return commands
    }

    private static func noteCommands(session: MarkdownSession, workspace: WorkspaceModel, window: WindowActions) -> [PaletteCommand] {
        let editingMode = workspace.preferences.defaultEditingMode
        var commands = [
            PaletteCommand(id: "toggle-reading", title: "Toggle reading view", systemImage: "book", shortcut: "⌘E") { session.toggleReadingView(editingMode: editingMode) },
            PaletteCommand(id: "toggle-source", title: "Toggle Live Preview/Source mode", systemImage: "chevron.left.forwardslash.chevron.right") {
                session.viewMode = session.viewMode == .source ? .livePreview : .source
            },
            PaletteCommand(id: "toggle-right-sidebar", title: "Toggle right sidebar", systemImage: "sidebar.right", run: window.toggleLinksInspector),
            PaletteCommand(id: "find-in-note", title: "Search current file", systemImage: "text.magnifyingglass", shortcut: "⌘F") {
                session.requestFind(.find, editingMode: editingMode)
            },
            PaletteCommand(id: "replace-in-note", title: "Search & replace in current file", systemImage: "arrow.left.arrow.right", shortcut: "⌥⌘F") {
                session.requestFind(.findAndReplace, editingMode: editingMode)
            },
            PaletteCommand(id: "toggle-fold", title: "Toggle fold on the current line", systemImage: "chevron.down") {
                session.toggleFold(atLine: session.selection.location)
            },
            PaletteCommand(id: "fold-all", title: "Fold all headings and lists", systemImage: "rectangle.compress.vertical") { session.foldAll() },
            PaletteCommand(id: "unfold-all", title: "Unfold all headings and lists", systemImage: "rectangle.expand.vertical") { session.unfoldAll() },
        ]
        if workspace.preferences.isEnabled(.templates) {
            commands.append(PaletteCommand(id: "insert-template", title: "Templates: Insert template", systemImage: "doc.on.doc", run: window.showTemplatePicker))
        }
        guard session.viewMode != .reading else { return commands }
        let text = { session.text as NSString }
        commands += (1...6).map { level in
            PaletteCommand(id: "heading-\(level)", title: "Set as heading \(level)", systemImage: "number") {
                session.apply(MarkdownEditing.settingHeading(level: level, in: text(), selection: session.selection))
            }
        }
        commands += [
            PaletteCommand(id: "task", title: "Insert task", systemImage: "checklist") { session.insertBlock("- [ ] ") },
            PaletteCommand(id: "table", title: "Insert table", systemImage: "tablecells") { session.insertBlock("| Column | Column |\n| --- | --- |\n|  |  |") },
            PaletteCommand(id: "math", title: "Insert math block", systemImage: "function") { session.insertBlock("$$\n\n$$") },
            PaletteCommand(id: "callout", title: "Insert callout", systemImage: "text.bubble") { session.insertBlock("> [!note]\n> ") },
        ]
        #if canImport(UIKit)
        if workspace.preferences.isEnabled(.drawings) {
            commands.append(PaletteCommand(id: "draw", title: "Pencil drawings: Insert drawing", systemImage: "pencil.tip.crop.circle.badge.plus") { workspace.beginNewDrawing(in: session) })
        }
        #endif
        return commands
    }
}

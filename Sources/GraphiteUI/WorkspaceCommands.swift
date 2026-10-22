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
    var toggleFocusMode: (() -> Void)? = nil
}

extension WindowActions {
    /// Shows a panel of the note's right sidebar, as the local graph and the local map open.
    func showLinksInspector(_ panel: NoteLinksInspector.InspectorPanel, deviceDefaults: UserDefaults) {
        deviceDefaults.set(panel.rawValue, forKey: NoteLinksInspector.panelSettingKey)
        showLinksInspector()
    }
}

/// The command palette's commands, named as Obsidian names them where they match.
@MainActor
enum WorkspaceCommandList {
    static func commands(for workspace: WorkspaceModel, window: WindowActions) -> [PaletteCommand] {
        var commands: [PaletteCommand] = [
            PaletteCommand(id: "switcher", command: .quickSwitcher, systemImage: "doc.text.magnifyingglass", run: window.showQuickSwitcher),
            PaletteCommand(id: "search", command: .searchAllFiles, systemImage: "magnifyingglass") { workspace.searchFocusRequest += 1 },
            PaletteCommand(id: "new-note", command: .newNote, systemImage: "square.and.pencil") { window.create(.note) },
            PaletteCommand(id: "new-notebook", command: .newNotebook, systemImage: "book.closed") { window.create(.notebook) },
            PaletteCommand(id: "new-folder", command: .newFolder, systemImage: "folder.badge.plus") { workspace.fileSheet = .newFolder(in: workspace.newFileDirectory(nil)) },
            PaletteCommand(id: "toggle-left-sidebar", command: .toggleLeftSidebar, systemImage: "sidebar.left", run: window.toggleSidebar),
            PaletteCommand(id: "settings", command: .openSettings, systemImage: "gearshape", run: window.showSettings),
            PaletteCommand(id: "vaults", command: .openVault, systemImage: "building.columns", run: window.showVaultManager),
            PaletteCommand(id: "collapse-folders", command: .collapseFolders, systemImage: "arrow.down.right.and.arrow.up.left") { workspace.collapseAllFolders() },
        ]
        if workspace.preferences.isEnabled(.bases) {
            commands.append(PaletteCommand(id: "new-base", command: .newBase, systemImage: "tablecells") { window.create(.base) })
        }
        if workspace.preferences.isEnabled(.canvas) {
            commands.append(PaletteCommand(id: "new-canvas", command: .newCanvas, systemImage: "rectangle.3.group") { window.create(.canvas) })
        }
        if workspace.history.canGoBack {
            commands.append(PaletteCommand(id: "back", command: .goBack, systemImage: "chevron.left") { Task { await workspace.goBack() } })
        }
        if workspace.history.canGoForward {
            commands.append(PaletteCommand(id: "forward", command: .goForward, systemImage: "chevron.right") { Task { await workspace.goForward() } })
        }
        commands += tabCommands(for: workspace)
        if workspace.preferences.isEnabled(.fileRecovery) {
            commands.append(PaletteCommand(id: "file-recovery-all", command: .browseSnapshots, systemImage: "clock.arrow.circlepath") {
                workspace.fileRecoveryRequest = FileRecoveryRequest(path: nil)
            })
            if let path = workspace.selection, DocumentKind(path: path) == .markdown {
                commands.append(PaletteCommand(id: "file-recovery-note", command: .openLocalHistory, systemImage: "clock.arrow.circlepath") {
                    workspace.fileRecoveryRequest = FileRecoveryRequest(path: path)
                })
            }
        }
        if let path = workspace.selection {
            commands.append(PaletteCommand(id: "copy-url", command: .copyURL, systemImage: "link") { Pasteboard.copy(workspace.openingLink(to: path)) })
        }
        if let toggleFocusMode = window.toggleFocusMode {
            commands.append(PaletteCommand(id: "workspace-focus", command: .toggleFocusMode, systemImage: "arrow.up.left.and.arrow.down.right", run: toggleFocusMode))
        }
        if workspace.preferences.isEnabled(.graph) {
            commands.append(PaletteCommand(id: "graph-open", command: .openGraph, systemImage: "point.3.connected.trianglepath.dotted") {
                workspace.showGraph()
            })
            if workspace.markdownSession != nil {
                commands.append(PaletteCommand(id: "graph-local", command: .openLocalGraph, systemImage: "point.3.filled.connected.trianglepath.dotted") {
                    window.showLinksInspector(.graph, deviceDefaults: workspace.deviceDefaults)
                })
            }
        }
        if workspace.preferences.isEnabled(.map) {
            commands.append(PaletteCommand(id: "map-open", command: .openMap, systemImage: "map") {
                workspace.isMapPresented = true
            })
            if workspace.markdownSession != nil {
                commands.append(PaletteCommand(id: "map-local", command: .openLocalMap, systemImage: "mappin.and.ellipse") {
                    window.showLinksInspector(.map, deviceDefaults: workspace.deviceDefaults)
                })
            }
        }
        if workspace.preferences.isEnabled(.bookmarks) {
            commands.append(PaletteCommand(id: "bookmarks-show", command: .showBookmarks, systemImage: "bookmark") {
                workspace.deviceDefaults.set(SidebarPanel.bookmarks.rawValue, forKey: SidebarPanelSettingKey.panel)
                workspace.searchQuery = ""
                window.showSidebar()
            })
            if let path = workspace.selection {
                let isBookmarked = workspace.isBookmarked(path)
                commands.append(PaletteCommand(id: "bookmarks-file", command: .bookmarkCurrentFile, title: isBookmarked ? "Bookmarks: Remove bookmark" : "Bookmarks: Bookmark current file",
                                               systemImage: isBookmarked ? "bookmark.slash" : "bookmark") { Task { await workspace.toggleBookmark(path) } })
            }
            let query = workspace.searchQuery.trimmingCharacters(in: .whitespaces)
            if !query.isEmpty, workspace.bookmarks.searchBookmark(for: query) == nil {
                commands.append(PaletteCommand(id: "bookmarks-search", command: .bookmarkCurrentSearch, systemImage: "magnifyingglass") {
                    Task { await workspace.bookmarkSearch(query) }
                })
            }
        }
        if workspace.preferences.isEnabled(.dailyNotes) {
            commands += [
                PaletteCommand(id: "daily-today", command: .todaysDailyNote, systemImage: "calendar") { Task { await workspace.openDailyNote() } },
                PaletteCommand(id: "daily-previous", command: .previousDailyNote, systemImage: "chevron.backward.circle") {
                    Task { await workspace.openAdjacentDailyNote(forward: false) }
                },
                PaletteCommand(id: "daily-next", command: .nextDailyNote, systemImage: "chevron.forward.circle") {
                    Task { await workspace.openAdjacentDailyNote(forward: true) }
                },
            ]
        }
        if let path = workspace.selection {
            commands += [
                PaletteCommand(id: "rename", command: .renameFile, systemImage: "pencil") { workspace.fileSheet = .rename(path) },
                PaletteCommand(id: "move", command: .moveFile, systemImage: "folder") { workspace.fileSheet = .move(path) },
                PaletteCommand(id: "copy", command: .duplicateFile, systemImage: "plus.square.on.square") { Task { await workspace.duplicate(path) } },
                PaletteCommand(id: "delete", command: .deleteFile, systemImage: "trash") { Task { await workspace.requestDeletion(of: path) } },
                PaletteCommand(id: "reveal", command: .revealFile, systemImage: "scope") { workspace.revealCurrentFile() },
            ]
            if workspace.conflictedPaths.contains(path) {
                commands.append(PaletteCommand(id: "review-versions", command: .reviewOtherVersions, systemImage: "square.on.square") {
                    workspace.conflictVersionsRequest = ConflictVersionsRequest(path: path)
                })
            }
        }
        if let session = workspace.markdownSession {
            commands += noteCommands(session: session, workspace: workspace, window: window)
        }
        if workspace.preferences.isEnabled(.audioRecorder) {
            if workspace.recording.canStartRecording {
                commands.append(PaletteCommand(id: "record", command: .startRecording, systemImage: "mic") { Task { await workspace.startRecording() } })
                commands.append(PaletteCommand(id: "record-video", command: .startVideoRecording, systemImage: "video") { Task { await workspace.startRecording(.video) } })
            } else if workspace.recording.state.canStop {
                commands.append(PaletteCommand(id: "stop-recording", command: .stopRecording, systemImage: "stop.fill") { workspace.recording.stop() })
            }
        }
        commands += communityPluginCommands(for: workspace)
        let table = workspace.keyboardShortcuts.table(pluginCommands: workspace.communityPlugins.commands)
        return commands.map { command in command.showingShortcut(from: table) }
    }

    /// The commands of the vault's community plugins, named as Obsidian names them
    /// ("Plugin: Command"), with their ribbon buttons and open views. Editor commands are
    /// listed only while a note is open for editing, as in Obsidian.
    private static func communityPluginCommands(for workspace: WorkspaceModel) -> [PaletteCommand] {
        let host = workspace.communityPlugins
        guard host.isRuntimeRunning else { return [] }
        let isEditingNote = workspace.markdownSession.map { session in session.viewMode != .reading } ?? false
        var commands = host.commands.filter { command in !command.needsEditor || isEditingNote }.map { command in
            PaletteCommand(id: "community-plugin:" + command.id, shortcutCommandIdentifier: command.id, title: command.name, systemImage: "puzzlepiece.extension") {
                Task { await host.run(command) }
            }
        }
        commands += host.ribbonActions.map { ribbonAction in
            let pluginName = host.pluginName(of: ribbonAction.pluginIdentifier) ?? ribbonAction.pluginIdentifier
            return PaletteCommand(id: "community-plugin-ribbon:" + ribbonAction.id, title: pluginName + ": " + ribbonAction.title,
                                  systemImage: "puzzlepiece") { Task { await host.run(ribbonAction) } }
        }
        commands += host.pluginViews.map { pluginView in
            PaletteCommand(id: "community-plugin-view:" + pluginView.id, title: "Show " + pluginView.title, systemImage: "rectangle.on.rectangle") { Task { await host.show(pluginView) } }
        }
        return commands
    }

    /// Obsidian's tab and split commands.
    private static func tabCommands(for workspace: WorkspaceModel) -> [PaletteCommand] {
        let layout = workspace.layout
        let tab = layout.activeTab
        var commands = [
            PaletteCommand(id: "new-tab", command: .newTab, systemImage: "plus") { workspace.openNewTab() },
            PaletteCommand(id: "close-tab", command: .closeTab, systemImage: "xmark") { Task { await workspace.closeTab(tab.id) } },
            PaletteCommand(id: "pin-tab", command: .togglePin, title: tab.isPinned ? "Unpin current tab" : "Pin current tab", systemImage: tab.isPinned ? "pin.slash" : "pin") {
                workspace.togglePin(tab.id)
            },
        ]
        if layout.focusedGroup.tabs.count > 1 {
            commands += [
                PaletteCommand(id: "close-other-tabs", command: .closeOtherTabs, systemImage: "xmark.square") { Task { await workspace.closeOtherTabs(keeping: tab.id) } },
                PaletteCommand(id: "next-tab", command: .nextTab, systemImage: "arrow.right.square") { workspace.activateNeighborTab(forward: true) },
                PaletteCommand(id: "previous-tab", command: .previousTab, systemImage: "arrow.left.square") { workspace.activateNeighborTab(forward: false) },
            ]
        }
        if !layout.closedPaths.isEmpty {
            commands.append(PaletteCommand(id: "reopen-tab", command: .reopenClosedTab, systemImage: "arrow.uturn.backward") {
                Task { await workspace.reopenClosedTab() }
            })
        }
        if layout.isSplit {
            let focusedGroupID = layout.focusedGroupID
            commands += [
                PaletteCommand(id: "focus-other-side", command: .focusOtherSide, systemImage: "arrow.left.arrow.right") {
                    if let other = layout.otherGroup(than: focusedGroupID) { workspace.focusGroup(other.id) }
                },
                PaletteCommand(id: "close-side", command: .closeThisSide, systemImage: "xmark.rectangle") { Task { await workspace.closeGroup(focusedGroupID) } },
            ]
        } else {
            commands.append(PaletteCommand(id: "split-right", command: .splitRight, systemImage: "rectangle.split.2x1") { workspace.splitRight() })
        }
        if tab.path != nil || tab.coreView != nil || layout.focusedGroup.tabs.count > 1 || layout.isSplit {
            let isLeftSide = layout.groups.first?.id == layout.focusedGroupID
            commands.append(PaletteCommand(id: "move-tab", command: .moveTabToOtherSide, title: isLeftSide ? "Move current tab to the right" : "Move current tab to the left",
                                           systemImage: isLeftSide ? "rectangle.righthalf.inset.filled.arrow.right" : "rectangle.lefthalf.inset.filled.arrow.left") {
                workspace.moveTabToOtherGroup(tab.id)
            })
        }
        return commands
    }

    private static func noteCommands(session: MarkdownSession, workspace: WorkspaceModel, window: WindowActions) -> [PaletteCommand] {
        let editingMode = workspace.preferences.defaultEditingMode
        var commands = [
            PaletteCommand(id: "toggle-reading", command: .toggleReadingView, systemImage: "book") { session.toggleReadingView(editingMode: editingMode) },
            PaletteCommand(id: "toggle-source", command: .toggleSourceMode, systemImage: "chevron.left.forwardslash.chevron.right") {
                session.viewMode = session.viewMode == .source ? .livePreview : .source
            },
            PaletteCommand(id: "toggle-right-sidebar", command: .toggleRightSidebar, systemImage: "sidebar.right", run: window.toggleLinksInspector),
            PaletteCommand(id: "find-in-note", command: .findInNote, systemImage: "text.magnifyingglass") {
                session.requestFind(.find, editingMode: editingMode)
            },
            PaletteCommand(id: "replace-in-note", command: .findAndReplaceInNote, systemImage: "arrow.left.arrow.right") {
                session.requestFind(.findAndReplace, editingMode: editingMode)
            },
            PaletteCommand(id: "toggle-fold", command: .toggleFold, systemImage: "chevron.down") {
                session.toggleFold(atLine: session.selection.location)
            },
            PaletteCommand(id: "fold-all", command: .foldAll, systemImage: "rectangle.compress.vertical") { session.foldAll() },
            PaletteCommand(id: "unfold-all", command: .unfoldAll, systemImage: "rectangle.expand.vertical") { session.unfoldAll() },
        ]
        if workspace.preferences.isEnabled(.templates) {
            commands.append(PaletteCommand(id: "insert-template", command: .insertTemplate, systemImage: "doc.on.doc", run: window.showTemplatePicker))
        }
        guard session.viewMode != .reading else { return commands }
        let text = { session.text as NSString }
        commands += (1...6).map { level in
            PaletteCommand(id: "heading-\(level)", command: GraphiteCommand.heading(level), title: "Set as heading \(level)", systemImage: "number") {
                session.apply(MarkdownEditing.settingHeading(level: level, in: text(), selection: session.selection))
            }
        }
        commands += [
            PaletteCommand(id: "task", command: .insertTask, systemImage: "checklist") { session.insertBlock("- [ ] ") },
            PaletteCommand(id: "table", command: .insertTable, systemImage: "tablecells") { session.insertBlock("| Column | Column |\n| --- | --- |\n|  |  |") },
            PaletteCommand(id: "math", command: .insertMathBlock, systemImage: "function") { session.insertBlock("$$\n\n$$") },
            PaletteCommand(id: "callout", command: .insertCallout, systemImage: "text.bubble") { session.insertBlock("> [!note]\n> ") },
        ]
        let document = workspace.activeDocument
        if document.markdownSession === session {
            commands.append(PaletteCommand(id: "new-notebook-in-note", command: .insertNotebook, systemImage: "book.closed") {
                document.notebookInsertion = NotebookInsertionRequest(session: session)
            })
        }
        #if canImport(UIKit)
        if workspace.preferences.isEnabled(.drawings) {
            commands.append(PaletteCommand(id: "draw", command: .insertDrawing, systemImage: "pencil.tip.crop.circle.badge.plus") { workspace.beginNewDrawing(in: session) })
        }
        #endif
        return commands
    }
}

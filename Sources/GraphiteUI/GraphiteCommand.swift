import Foundation
import GraphiteCore

/// The groups of the Keyboard Shortcuts page; community plugins' commands are grouped by
/// plugin after these.
enum ShortcutCommandGroup: CaseIterable {
    case file, view, go, editor, canvas

    var title: String {
        switch self {
        case .file: "File"
        case .view: "View"
        case .go: "Go"
        case .editor: "Editor"
        case .canvas: "Canvas"
        }
    }
}

/// Where a command's shortcut is listened for.
enum ShortcutBinding {
    /// An item of the menu bar (`GraphiteCommands`).
    case menuBar
    /// A key command of the note's text view, while a note is edited.
    case editor(EditorCommand)
    /// A key command of the canvas being edited (`CanvasPane`).
    case canvas
    /// A command only the command palette lists: once it has a shortcut, the menu bar's
    /// View › Commands with Shortcuts holds it so the shortcut works.
    case commandsMenu
}

/// Every Graphite command a keyboard shortcut can run: the one list the menu bar, the editor's
/// key commands, the canvas, the command palette and Settings › Keyboard Shortcuts read their
/// shortcuts from. The raw value is the command's stable identifier, Obsidian's where Obsidian
/// has the same command, so a vault's `.obsidian/hotkeys.json` means the same in both apps;
/// Graphite's own commands start with `graphite:`.
enum GraphiteCommand: String, CaseIterable {
    // File
    case newNote = "file-explorer:new-file", newNotebook = "graphite:new-notebook", newBase = "bases:new-file", newCanvas = "canvas:new-file"
    case newFolder = "graphite:new-folder", newTab = "workspace:new-tab", quickSwitcher = "switcher:open"
    case closeTab = "workspace:close", reopenClosedTab = "workspace:undo-close-pane", save = "editor:save-file"
    case renameFile = "workspace:edit-file-title", moveFile = "file-explorer:move-file", duplicateFile = "file-explorer:duplicate-file"
    case deleteFile = "app:delete-file", revealFile = "file-explorer:reveal-active-file", collapseFolders = "graphite:collapse-all-folders"
    case copyURL = "workspace:copy-url", reviewOtherVersions = "graphite:review-other-versions"
    case exportToPDF = "workspace:export-pdf", printNote = "graphite:print-file"
    case browseSnapshots = "file-recovery:open", openLocalHistory = "graphite:open-local-history"
    case openVault = "app:open-vault", openSettings = "app:open-settings"
    case startRecording = "audio-recorder:start", startVideoRecording = "graphite:start-video-recording", stopRecording = "audio-recorder:stop"
    // View
    case toggleReadingView = "markdown:toggle-preview", toggleSourceMode = "editor:toggle-source"
    case toggleLeftSidebar = "app:toggle-left-sidebar", toggleRightSidebar = "app:toggle-right-sidebar"
    case openGraph = "graph:open", openLocalGraph = "graph:open-local", openMap = "graphite:open-map", openLocalMap = "graphite:open-local-map"
    case splitRight = "workspace:split-vertical", closeThisSide = "workspace:close-tab-group", commandPalette = "command-palette:open"
    case toggleFocusMode = "graphite:toggle-focus-mode"
    case increaseFontSize = "graphite:increase-font-size", decreaseFontSize = "graphite:decrease-font-size", resetFontSize = "graphite:reset-font-size"
    case showBookmarks = "bookmarks:open", bookmarkCurrentFile = "bookmarks:bookmark-current-view", bookmarkCurrentSearch = "bookmarks:bookmark-current-search"
    // Go
    case searchAllFiles = "global-search:open", goBack = "app:go-back", goForward = "app:go-forward"
    case nextTab = "workspace:next-tab", previousTab = "workspace:previous-tab"
    case goToTab1 = "workspace:goto-tab-1", goToTab2 = "workspace:goto-tab-2", goToTab3 = "workspace:goto-tab-3", goToTab4 = "workspace:goto-tab-4"
    case goToTab5 = "workspace:goto-tab-5", goToTab6 = "workspace:goto-tab-6", goToTab7 = "workspace:goto-tab-7", goToTab8 = "workspace:goto-tab-8"
    case goToLastTab = "workspace:goto-last-tab", closeOtherTabs = "workspace:close-others", togglePin = "workspace:toggle-pin"
    case moveTabToOtherSide = "graphite:move-tab-to-other-side", focusOtherSide = "graphite:focus-other-side"
    case toggleStackedTabs = "workspace:toggle-stacked-tabs", showTabOverview = "graphite:show-tab-overview"
    case todaysDailyNote = "daily-notes", previousDailyNote = "daily-notes:goto-prev", nextDailyNote = "daily-notes:goto-next"
    // Editor
    case toggleBold = "editor:toggle-bold", toggleItalics = "editor:toggle-italics", toggleStrikethrough = "editor:toggle-strikethrough"
    case toggleHighlight = "editor:toggle-highlight", toggleCode = "editor:toggle-code", toggleComment = "editor:toggle-comments"
    case insertLink = "editor:insert-link", toggleChecklist = "editor:toggle-checklist-status"
    case heading1 = "editor:set-heading-1", heading2 = "editor:set-heading-2", heading3 = "editor:set-heading-3"
    case heading4 = "editor:set-heading-4", heading5 = "editor:set-heading-5", heading6 = "editor:set-heading-6"
    case unindentList = "editor:unindent-list", swapLineUp = "editor:swap-line-up", swapLineDown = "editor:swap-line-down"
    case findInNote = "editor:open-search", findAndReplaceInNote = "editor:open-search-replace"
    case followLink = "editor:follow-link", openLinkInNewTab = "editor:open-link-in-new-leaf", openLinkOnOtherSide = "editor:open-link-in-new-split"
    case toggleFold = "editor:toggle-fold", foldAll = "editor:fold-all", unfoldAll = "editor:unfold-all"
    case insertTask = "graphite:insert-task", insertTable = "editor:insert-table", insertMathBlock = "editor:insert-mathblock"
    case insertCallout = "editor:insert-callout", insertTemplate = "insert-template", insertNotebook = "graphite:insert-notebook"
    case insertDrawing = "graphite:insert-drawing"
    // Canvas
    case canvasSelectAll = "graphite:canvas-select-all", canvasDeleteSelection = "graphite:canvas-delete-selection"
    case canvasDuplicateSelection = "graphite:canvas-duplicate-selection"

    var identifier: String { rawValue }

    var defaults: ShortcutCommandDefaults {
        ShortcutCommandDefaults(identifier: rawValue, defaultCombinations: descriptor.defaultCombinations)
    }

    var title: String { descriptor.title }
    var group: ShortcutCommandGroup { descriptor.group }
    var binding: ShortcutBinding { descriptor.binding }
    /// The core plugin the command belongs to; while it is off, the command is not offered.
    var corePlugin: CorePlugin? { descriptor.corePlugin }
    /// The titles of its menu item on the Mac, which shortcuts set in System Settings name.
    var macMenuTitles: [String] { descriptor.macMenuTitles }

    /// Whether the command exists on `platform`: Settings' ⌘, belongs to the Mac's app menu,
    /// and the Mac follows links with a click and has no Pencil drawings.
    func isAvailable(on platform: ShortcutPlatform) -> Bool {
        platform == .iPadOS || !Self.iPadOnlyCommands.contains(self)
    }

    private static let iPadOnlyCommands: Set<GraphiteCommand> = [.openSettings, .followLink, .openLinkInNewTab, .openLinkOnOtherSide, .insertDrawing]

    /// The commands a platform offers.
    static func available(on platform: ShortcutPlatform) -> [GraphiteCommand] {
        allCases.filter { command in command.isAvailable(on: platform) }
    }
}

/// What one command is, apart from its identifier.
struct GraphiteCommandDescriptor {
    let title: String
    let group: ShortcutCommandGroup
    var defaultCombinations: [KeyCombination] = []
    var binding: ShortcutBinding = .commandsMenu
    var corePlugin: CorePlugin? = nil
    var macMenuTitles: [String] = []
}

private func command(_ key: String, _ modifiers: KeyCombination.Modifiers = .command) -> [KeyCombination] {
    [KeyCombination(modifiers, .character(key))]
}

private func named(_ key: NamedKey, _ modifiers: KeyCombination.Modifiers) -> [KeyCombination] {
    [KeyCombination(modifiers, .named(key))]
}

extension GraphiteCommand {
    /// One exhaustive table. The defaults are Obsidian's Mac shortcuts where it has the command.
    var descriptor: GraphiteCommandDescriptor {
        typealias Descriptor = GraphiteCommandDescriptor
        switch self {
        case .newNote:
            return Descriptor(title: "Create new note", group: .file, defaultCombinations: command("N"), binding: .menuBar, macMenuTitles: ["New Note"])
        case .newNotebook: return Descriptor(title: "Create new notebook", group: .file, binding: .menuBar, macMenuTitles: ["New Notebook"])
        case .newBase: return Descriptor(title: "Bases: Create new base", group: .file, binding: .menuBar, corePlugin: .bases, macMenuTitles: ["New Base"])
        case .newCanvas:
            return Descriptor(title: "Canvas: Create new canvas", group: .file, binding: .menuBar, corePlugin: .canvas, macMenuTitles: ["New Canvas"])
        case .newFolder: return Descriptor(title: "Files: Create new folder", group: .file)
        case .newTab: return Descriptor(title: "New tab", group: .file, defaultCombinations: command("T"), binding: .menuBar, macMenuTitles: ["New Tab"])
        case .quickSwitcher:
            return Descriptor(title: "Quick switcher: Open quick switcher", group: .file, defaultCombinations: command("O"),
                              binding: .menuBar, macMenuTitles: ["Open Quick Switcher…"])
        case .closeTab:
            return Descriptor(title: "Close current tab", group: .file, defaultCombinations: command("W"), binding: .menuBar, macMenuTitles: ["Close Tab"])
        case .reopenClosedTab:
            return Descriptor(title: "Reopen closed tab", group: .file, defaultCombinations: command("T", [.command, .shift]),
                              binding: .menuBar, macMenuTitles: ["Reopen Closed Tab"])
        case .save: return Descriptor(title: "Save current file", group: .file, defaultCombinations: command("S"), binding: .menuBar, macMenuTitles: ["Save"])
        case .renameFile: return Descriptor(title: "Rename file", group: .file)
        case .moveFile: return Descriptor(title: "Move file to another folder", group: .file)
        case .duplicateFile: return Descriptor(title: "Make a copy of the current file", group: .file)
        case .deleteFile: return Descriptor(title: "Delete current file", group: .file)
        case .revealFile: return Descriptor(title: "Files: Reveal current file in navigation", group: .file)
        case .collapseFolders: return Descriptor(title: "Files: Collapse all folders", group: .file)
        case .copyURL: return Descriptor(title: "Copy Graphite URL", group: .file)
        case .exportToPDF: return Descriptor(title: "Export to PDF", group: .file, binding: .menuBar, macMenuTitles: ["Export as PDF…"])
        case .printNote:
            // ⌘P prints on the Mac, as in its other apps; the iPad keeps it for the command palette, as Obsidian does.
            return Descriptor(title: "Print current file", group: .file, defaultCombinations: ShortcutPlatform.current == .macOS ? command("P") : [],
                              binding: .menuBar, macMenuTitles: ["Print…"])
        case .reviewOtherVersions: return Descriptor(title: "Review other versions of the current file", group: .file)
        case .browseSnapshots: return Descriptor(title: "File recovery: Browse all snapshots", group: .file, corePlugin: .fileRecovery)
        case .openLocalHistory: return Descriptor(title: "File recovery: Open local history", group: .file, corePlugin: .fileRecovery)
        case .openVault: return Descriptor(title: "Open another vault", group: .file)
        case .openSettings: return Descriptor(title: "Open settings", group: .file, defaultCombinations: command(","), binding: .menuBar)
        case .startRecording: return Descriptor(title: "Audio recorder: Start recording", group: .file, corePlugin: .audioRecorder)
        case .startVideoRecording: return Descriptor(title: "Audio recorder: Start recording video", group: .file, corePlugin: .audioRecorder)
        case .stopRecording: return Descriptor(title: "Audio recorder: Stop recording", group: .file, corePlugin: .audioRecorder)
        case .toggleReadingView:
            return Descriptor(title: "Toggle reading view", group: .view, defaultCombinations: command("E"),
                              binding: .menuBar, macMenuTitles: ["Read Note", "Edit Note"])
        case .toggleSourceMode:
            return Descriptor(title: "Toggle Live Preview/Source mode", group: .view, binding: .menuBar, macMenuTitles: ["Use Live Preview", "Use Source Mode"])
        case .toggleLeftSidebar: return Descriptor(title: "Toggle left sidebar", group: .view, binding: .menuBar, macMenuTitles: ["Show or Hide Files"])
        case .toggleRightSidebar: return Descriptor(title: "Toggle right sidebar", group: .view, binding: .menuBar, macMenuTitles: ["Show or Hide Links"])
        case .openGraph:
            return Descriptor(title: "Graph view: Open graph view", group: .view, binding: .menuBar, corePlugin: .graph, macMenuTitles: ["Graph View"])
        case .openLocalGraph: return Descriptor(title: "Graph view: Open local graph", group: .view, corePlugin: .graph)
        case .openMap: return Descriptor(title: "Map view: Open map view", group: .view, binding: .menuBar, corePlugin: .map, macMenuTitles: ["Map View"])
        case .openLocalMap: return Descriptor(title: "Map view: Open local map", group: .view, corePlugin: .map)
        case .splitRight: return Descriptor(title: "Split right", group: .view, binding: .menuBar, macMenuTitles: ["Split Right"])
        case .closeThisSide: return Descriptor(title: "Close this side of the split", group: .view, binding: .menuBar, macMenuTitles: ["Close This Side"])
        case .commandPalette:
            return Descriptor(title: "Command palette: Open command palette", group: .view,
                              defaultCombinations: ShortcutPlatform.current == .macOS ? command("P", [.command, .shift]) : command("P"),
                              binding: .menuBar, macMenuTitles: ["Command Palette…"])
        case .toggleFocusMode: return Descriptor(title: "Workspace: Toggle focus mode", group: .view)
        case .increaseFontSize:
            return Descriptor(title: "Make text bigger", group: .view, defaultCombinations: command("+"),
                              binding: .menuBar, macMenuTitles: ["Make Text Bigger"])
        case .decreaseFontSize:
            return Descriptor(title: "Make text smaller", group: .view, defaultCombinations: command("-"),
                              binding: .menuBar, macMenuTitles: ["Make Text Smaller"])
        case .resetFontSize:
            return Descriptor(title: "Default text size", group: .view, defaultCombinations: command("0"),
                              binding: .menuBar, macMenuTitles: ["Default Text Size"])
        case .showBookmarks: return Descriptor(title: "Bookmarks: Show bookmarks", group: .view, corePlugin: .bookmarks)
        case .bookmarkCurrentFile: return Descriptor(title: "Bookmarks: Bookmark current file", group: .view, corePlugin: .bookmarks)
        case .bookmarkCurrentSearch: return Descriptor(title: "Bookmarks: Bookmark current search", group: .view, corePlugin: .bookmarks)
        case .searchAllFiles:
            return Descriptor(title: "Search: Search in all files", group: .go, defaultCombinations: command("F", [.command, .shift]),
                              binding: .menuBar, macMenuTitles: ["Search in All Files"])
        case .goBack: return Descriptor(title: "Navigate back", group: .go, defaultCombinations: command("["), binding: .menuBar, macMenuTitles: ["Back"])
        case .goForward:
            return Descriptor(title: "Navigate forward", group: .go, defaultCombinations: command("]"), binding: .menuBar, macMenuTitles: ["Forward"])
        case .nextTab:
            return Descriptor(title: "Go to next tab", group: .go, defaultCombinations: named(.tab, .control), binding: .menuBar, macMenuTitles: ["Next Tab"])
        case .previousTab:
            return Descriptor(title: "Go to previous tab", group: .go, defaultCombinations: named(.tab, [.control, .shift]),
                              binding: .menuBar, macMenuTitles: ["Previous Tab"])
        case .goToTab1, .goToTab2, .goToTab3, .goToTab4, .goToTab5, .goToTab6, .goToTab7, .goToTab8:
            let number = tabNumber ?? 1
            return Descriptor(title: "Go to tab #\(number)", group: .go, defaultCombinations: command(String(number)),
                              binding: .menuBar, macMenuTitles: ["Tab \(number)"])
        case .goToLastTab:
            return Descriptor(title: "Go to last tab", group: .go, defaultCombinations: command("9"), binding: .menuBar, macMenuTitles: ["Last Tab"])
        case .closeOtherTabs: return Descriptor(title: "Close all other tabs", group: .go)
        case .togglePin: return Descriptor(title: "Toggle pin", group: .go)
        case .moveTabToOtherSide: return Descriptor(title: "Move current tab to the other side", group: .go)
        case .toggleStackedTabs:
            return Descriptor(title: "Toggle stacked tabs", group: .go, binding: .menuBar, macMenuTitles: ["Stack Tabs", "Unstack Tabs"])
        // Safari's shortcut for its tab overview.
        case .showTabOverview:
            return Descriptor(title: "Show all tabs", group: .go, defaultCombinations: command("\\", [.command, .shift]), binding: .menuBar,
                              macMenuTitles: ["Show All Tabs"])
        case .focusOtherSide:
            return Descriptor(title: "Focus the other side of the split", group: .go, binding: .menuBar, macMenuTitles: ["Focus the Other Side"])
        case .todaysDailyNote:
            return Descriptor(title: "Daily notes: Open today's daily note", group: .go,
                              binding: .menuBar, corePlugin: .dailyNotes, macMenuTitles: ["Today's Daily Note"])
        case .previousDailyNote:
            return Descriptor(title: "Daily notes: Open previous daily note", group: .go,
                              binding: .menuBar, corePlugin: .dailyNotes, macMenuTitles: ["Previous Daily Note"])
        case .nextDailyNote:
            return Descriptor(title: "Daily notes: Open next daily note", group: .go,
                              binding: .menuBar, corePlugin: .dailyNotes, macMenuTitles: ["Next Daily Note"])
        case .toggleBold: return Descriptor(title: "Toggle bold", group: .editor, defaultCombinations: command("B"), binding: .editor(.bold))
        case .toggleItalics: return Descriptor(title: "Toggle italics", group: .editor, defaultCombinations: command("I"), binding: .editor(.italic))
        case .toggleStrikethrough:
            return Descriptor(title: "Toggle strikethrough", group: .editor, defaultCombinations: command("X", [.command, .shift]),
                              binding: .editor(.strikethrough))
        case .toggleHighlight:
            return Descriptor(title: "Toggle highlight", group: .editor, defaultCombinations: command("H", [.command, .shift]), binding: .editor(.highlight))
        // ⌃⌘C, beside the headings' ⌃⌘1 to ⌃⌘6: ⌘` cycles through an app's windows.
        case .toggleCode:
            return Descriptor(title: "Toggle code", group: .editor, defaultCombinations: command("C", [.command, .control]), binding: .editor(.code))
        case .toggleComment: return Descriptor(title: "Toggle comment", group: .editor, defaultCombinations: command("/"), binding: .editor(.comment))
        case .insertLink:
            return Descriptor(title: "Insert Markdown link", group: .editor, defaultCombinations: command("K"), binding: .editor(.insertMarkdownLink))
        case .toggleChecklist: return Descriptor(title: "Toggle checkbox status", group: .editor, defaultCombinations: command("L"), binding: .editor(.task))
        case .heading1, .heading2, .heading3, .heading4, .heading5, .heading6:
            let level = headingLevel ?? 1
            return Descriptor(title: "Set as heading \(level)", group: .editor, defaultCombinations: command(String(level), [.command, .control]),
                              binding: .editor(.heading(level)))
        case .unindentList: return Descriptor(title: "Unindent list", group: .editor, defaultCombinations: named(.tab, .shift), binding: .editor(.outdent))
        case .swapLineUp:
            return Descriptor(title: "Move line up", group: .editor, defaultCombinations: named(.arrowUp, [.command, .option]), binding: .editor(.moveLinesUp))
        case .swapLineDown:
            return Descriptor(title: "Move line down", group: .editor, defaultCombinations: named(.arrowDown, [.command, .option]),
                              binding: .editor(.moveLinesDown))
        case .findInNote: return Descriptor(title: "Search current file", group: .editor, defaultCombinations: command("F"), binding: .editor(.find))
        case .findAndReplaceInNote:
            return Descriptor(title: "Search & replace in current file", group: .editor, defaultCombinations: command("F", [.command, .option]),
                              binding: .editor(.findAndReplace))
        case .followLink:
            return Descriptor(title: "Follow link under cursor", group: .editor, defaultCombinations: named(.enter, .option),
                              binding: .editor(.followLink(.currentTab)))
        case .openLinkInNewTab:
            return Descriptor(title: "Open link under cursor in new tab", group: .editor, defaultCombinations: named(.enter, .command),
                              binding: .editor(.followLink(.newTab)))
        case .openLinkOnOtherSide:
            return Descriptor(title: "Open link under cursor to the right", group: .editor, defaultCombinations: named(.enter, [.command, .option]),
                              binding: .editor(.followLink(.otherGroup)))
        case .toggleFold: return Descriptor(title: "Toggle fold on the current line", group: .editor)
        case .foldAll: return Descriptor(title: "Fold all headings and lists", group: .editor)
        case .unfoldAll: return Descriptor(title: "Unfold all headings and lists", group: .editor)
        case .insertTask: return Descriptor(title: "Insert task", group: .editor)
        case .insertTable: return Descriptor(title: "Insert table", group: .editor)
        case .insertMathBlock: return Descriptor(title: "Insert math block", group: .editor)
        case .insertCallout: return Descriptor(title: "Insert callout", group: .editor)
        case .insertTemplate:
            return Descriptor(title: "Templates: Insert template", group: .editor,
                              binding: .menuBar, corePlugin: .templates, macMenuTitles: ["Insert Template…"])
        case .insertNotebook: return Descriptor(title: "Notebooks: Insert new notebook", group: .editor)
        case .insertDrawing: return Descriptor(title: "Pencil drawings: Insert drawing", group: .editor, corePlugin: .drawings)
        case .canvasSelectAll: return Descriptor(title: "Select all", group: .canvas, defaultCombinations: command("A"), binding: .canvas, corePlugin: .canvas)
        case .canvasDeleteSelection:
            return Descriptor(title: "Delete selection", group: .canvas, defaultCombinations: named(.backspace, []), binding: .canvas, corePlugin: .canvas)
        case .canvasDuplicateSelection:
            return Descriptor(title: "Duplicate selection", group: .canvas, defaultCombinations: command("D"), binding: .canvas, corePlugin: .canvas)
        }
    }

    /// For Go to Tab 1 to 8, the tab's number.
    var tabNumber: Int? {
        let tabCommands: [GraphiteCommand] = [.goToTab1, .goToTab2, .goToTab3, .goToTab4, .goToTab5, .goToTab6, .goToTab7, .goToTab8]
        return tabCommands.firstIndex(of: self).map { index in index + 1 }
    }

    /// For the heading commands, the heading's level.
    var headingLevel: Int? {
        let headingCommands: [GraphiteCommand] = [.heading1, .heading2, .heading3, .heading4, .heading5, .heading6]
        return headingCommands.firstIndex(of: self).map { index in index + 1 }
    }

    /// Go to Tab 1 to 8 by position.
    static func goToTab(_ number: Int) -> GraphiteCommand? {
        guard number >= 1 else { return nil }
        return [GraphiteCommand.goToTab1, .goToTab2, .goToTab3, .goToTab4, .goToTab5, .goToTab6, .goToTab7, .goToTab8].dropFirst(number - 1).first
    }

    /// The heading command of a level from 1 to 6.
    static func heading(_ level: Int) -> GraphiteCommand? {
        guard level >= 1 else { return nil }
        return [GraphiteCommand.heading1, .heading2, .heading3, .heading4, .heading5, .heading6].dropFirst(level - 1).first
    }
}

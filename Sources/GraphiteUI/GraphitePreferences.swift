import Foundation
import Observation
import SwiftUI
import GraphiteCore
import GraphiteIndex

/// Graphite features that can be switched off, like Obsidian's core plugins.
enum CorePlugin: String, CaseIterable, Identifiable, Codable {
    case backlinks, outgoingLinks, outline, properties, tags, wordCount
    case colors, drawings, audioRecorder, bases
    case templates, dailyNotes, footnotes, fileRecovery, bookmarks, graph

    var id: String { rawValue }

    var title: String {
        switch self {
        case .backlinks: "Backlinks"
        case .outgoingLinks: "Outgoing links"
        case .outline: "Outline"
        case .properties: "Properties view"
        case .tags: "Tags view"
        case .wordCount: "Word count"
        case .colors: "Colors"
        case .drawings: "Pencil drawings"
        case .audioRecorder: "Audio recorder"
        case .bases: "Bases"
        case .templates: "Templates"
        case .dailyNotes: "Daily notes"
        case .footnotes: "Footnotes view"
        case .fileRecovery: "File recovery"
        case .bookmarks: "Bookmarks"
        case .graph: "Graph view"
        }
    }

    var summary: String {
        switch self {
        case .backlinks: "Shows the notes that link to the current note."
        case .outgoingLinks: "Shows the links in the current note."
        case .outline: "Shows the headings of the current note, and jumps to them."
        case .properties: "Shows a note's frontmatter as editable properties, and every property in the vault in the left sidebar."
        case .tags: "Lists the tags of the current note, and every tag in the vault with its count in the left sidebar."
        case .wordCount: "Shows the word and character count of the current note."
        case .colors: "Colors text with ~={#hex}text=~, compatible with the Colors plugin for Obsidian."
        case .drawings: "Draw with Apple Pencil and embed the drawing in a note."
        case .audioRecorder: "Records lectures into ordinary audio files in the vault."
        case .bases: "Opens .base files and base code blocks as tables, cards, lists, and maps."
        case .templates: "Inserts notes from a templates folder, filling in the title, date, and time."
        case .dailyNotes: "Opens a note for today, created from a template, and the notes of other days."
        case .footnotes: "Lists the current note's footnotes in the right sidebar."
        case .fileRecovery: "Keeps copies of notes as they are edited, outside the vault, to recover earlier versions and deleted notes."
        case .bookmarks: "Keeps notes, headings, folders, and searches at hand in the left sidebar, shared with Obsidian."
        case .graph: "Draws the vault's notes and links, and each note's neighborhood in the right sidebar."
        }
    }

    var systemImage: String {
        switch self {
        case .backlinks: "arrow.uturn.left"
        case .outgoingLinks: "arrow.up.right"
        case .outline: "list.bullet.indent"
        case .properties: "list.bullet.rectangle"
        case .tags: "number"
        case .wordCount: "textformat.123"
        case .colors: "paintpalette"
        case .drawings: "pencil.tip.crop.circle"
        case .audioRecorder: "mic"
        case .bases: "tablecells"
        case .templates: "doc.on.doc"
        case .dailyNotes: "calendar"
        case .footnotes: "textformat.superscript"
        case .fileRecovery: "clock.arrow.circlepath"
        case .bookmarks: "bookmark"
        case .graph: "point.3.connected.trianglepath.dotted"
        }
    }
}

/// How a note opens and is edited, matching Obsidian's three views.
enum NoteViewMode: String, CaseIterable, Identifiable, Codable {
    case reading, livePreview, source
    var id: String { rawValue }
}

enum EditingMode: String, CaseIterable, Identifiable, Codable {
    case livePreview, source
    var id: String { rawValue }
    var title: String { self == .livePreview ? "Live Preview" : "Source mode" }
}

enum DefaultNoteView: String, CaseIterable, Identifiable, Codable {
    case editing, reading
    var id: String { rawValue }
    var title: String { self == .editing ? "Editing view" : "Reading view" }
}

enum AppearanceMode: String, CaseIterable, Identifiable, Codable {
    case system, light, dark
    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: "Adapt to system"
        case .light: "Light"
        case .dark: "Dark"
        }
    }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

/// A named color for menus. Notes only ever store the hex.
struct PaletteColor: Codable, Equatable, Identifiable {
    var id = UUID()
    var name: String
    var hex: String

    /// The defaults of the Colors plugin for Obsidian, so both apps offer the same colors.
    static let defaultPalette = [
        PaletteColor(name: "red", hex: "#e93147"), PaletteColor(name: "orange", hex: "#ec7500"),
        PaletteColor(name: "yellow", hex: "#e0ac00"), PaletteColor(name: "green", hex: "#08b94e"),
        PaletteColor(name: "cyan", hex: "#00bfbc"), PaletteColor(name: "blue", hex: "#086ddd"),
        PaletteColor(name: "purple", hex: "#7852ee"), PaletteColor(name: "pink", hex: "#d53984"),
    ]
}

/// Graphite's own preferences on this device. Settings Obsidian shares with the vault,
/// such as the attachment folder, live in `.obsidian/app.json` (`ObsidianSettings`).
@MainActor @Observable
final class GraphitePreferences {
    private enum Key {
        static let drawingFormat = "GraphiteDrawingFormat"
        static let drawingBackground = "GraphiteDrawingBackground"
        static let usesReadableLineLength = "GraphiteUsesReadableLineLength"
        static let disabledCorePlugins = "GraphiteDisabledCorePlugins"
        static let defaultNoteView = "GraphiteDefaultNoteView"
        static let defaultEditingMode = "GraphiteDefaultEditingMode"
        static let appearanceMode = "GraphiteAppearanceMode"
        static let textSize = "GraphiteTextSize"
        static let usesSpellChecking = "GraphiteUsesSpellChecking"
        static let colorPalette = "GraphiteColorPalette"
        static let embedsRecordingsInNote = "GraphiteEmbedsRecordingsInNote"
        static let accentHex = "GraphiteAccentColor"
        static let showsInlineTitle = "GraphiteShowsInlineTitle"
        static let showsFileExtensions = "GraphiteShowsFileExtensions"
        static let searchSortOrder = "GraphiteSearchSortOrder"
        static let recentCommandIdentifiers = "GraphiteRecentCommands"
        static let snapshotIntervalMinutes = "GraphiteSnapshotIntervalMinutes"
        static let snapshotHistoryDays = "GraphiteSnapshotHistoryDays"
    }
    static let textSizeRange: ClosedRange<Double> = 12...28
    private let defaults: UserDefaults

    var drawingFormat: DrawingFormat { didSet { defaults.set(drawingFormat.rawValue, forKey: Key.drawingFormat) } }
    var drawingBackground: DrawingBackground { didSet { defaults.set(drawingBackground.rawValue, forKey: Key.drawingBackground) } }
    /// Limits the editor to a comfortable column width, like Obsidian's option.
    var usesReadableLineLength: Bool { didSet { defaults.set(usesReadableLineLength, forKey: Key.usesReadableLineLength) } }
    var disabledCorePlugins: Set<CorePlugin> {
        didSet { defaults.set(disabledCorePlugins.map(\.rawValue).sorted(), forKey: Key.disabledCorePlugins) }
    }
    var defaultNoteView: DefaultNoteView { didSet { defaults.set(defaultNoteView.rawValue, forKey: Key.defaultNoteView) } }
    var defaultEditingMode: EditingMode { didSet { defaults.set(defaultEditingMode.rawValue, forKey: Key.defaultEditingMode) } }
    var appearanceMode: AppearanceMode { didSet { defaults.set(appearanceMode.rawValue, forKey: Key.appearanceMode) } }
    /// Body text size in points for editing and reading.
    var textSize: Double { didSet { defaults.set(textSize, forKey: Key.textSize) } }
    var usesSpellChecking: Bool { didSet { defaults.set(usesSpellChecking, forKey: Key.usesSpellChecking) } }
    var colorPalette: [PaletteColor] {
        didSet { defaults.set(try? JSONEncoder().encode(colorPalette), forKey: Key.colorPalette) }
    }
    /// Whether a finished recording is embedded at the cursor of the note it started in.
    var embedsRecordingsInNote: Bool { didSet { defaults.set(embedsRecordingsInNote, forKey: Key.embedsRecordingsInNote) } }
    /// The accent for links, checkboxes, selection and controls, like Obsidian's accent color.
    var accentHex: String { didSet { defaults.set(accentHex, forKey: Key.accentHex) } }
    /// Shows the note's name as a large title above its content, like Obsidian's inline title.
    var showsInlineTitle: Bool { didSet { defaults.set(showsInlineTitle, forKey: Key.showsInlineTitle) } }
    /// Shows every file with its extension (`Lecture.md`) in lists and the title bar.
    var showsFileExtensions: Bool { didSet { defaults.set(showsFileExtensions, forKey: Key.showsFileExtensions) } }
    /// Commands used lately, listed first in the command palette.
    var recentCommandIdentifiers: [String] { didSet { defaults.set(recentCommandIdentifiers, forKey: Key.recentCommandIdentifiers) } }
    /// The order of search results, as in Obsidian's search.
    var searchSortOrder: SearchSortOrder { didSet { defaults.set(searchSortOrder.rawValue, forKey: Key.searchSortOrder) } }
    var accentColor: Color { Color(graphiteHex: accentHex) ?? Color(graphiteHex: GraphiteTheme.defaultAccentHex) ?? .blue }
    /// File recovery's "Snapshot interval": at most one copy of a note per this many minutes.
    var snapshotIntervalMinutes: Int { didSet { defaults.set(snapshotIntervalMinutes, forKey: Key.snapshotIntervalMinutes) } }
    /// File recovery's "History length": copies older than this many days are removed.
    var snapshotHistoryDays: Int { didSet { defaults.set(snapshotHistoryDays, forKey: Key.snapshotHistoryDays) } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        drawingFormat = defaults.string(forKey: Key.drawingFormat).flatMap(DrawingFormat.init(rawValue:)) ?? .png
        drawingBackground = defaults.string(forKey: Key.drawingBackground).flatMap(DrawingBackground.init(rawValue:)) ?? .white
        usesReadableLineLength = defaults.object(forKey: Key.usesReadableLineLength) as? Bool ?? true
        disabledCorePlugins = Set((defaults.stringArray(forKey: Key.disabledCorePlugins) ?? []).compactMap(CorePlugin.init(rawValue:)))
        defaultNoteView = defaults.string(forKey: Key.defaultNoteView).flatMap(DefaultNoteView.init(rawValue:)) ?? .editing
        defaultEditingMode = defaults.string(forKey: Key.defaultEditingMode).flatMap(EditingMode.init(rawValue:)) ?? .livePreview
        appearanceMode = defaults.string(forKey: Key.appearanceMode).flatMap(AppearanceMode.init(rawValue:)) ?? .system
        let storedTextSize = defaults.double(forKey: Key.textSize)
        textSize = Self.textSizeRange.contains(storedTextSize) ? storedTextSize : 17
        usesSpellChecking = defaults.object(forKey: Key.usesSpellChecking) as? Bool ?? true
        colorPalette = defaults.data(forKey: Key.colorPalette).flatMap { storedPalette in try? JSONDecoder().decode([PaletteColor].self, from: storedPalette) } ?? PaletteColor.defaultPalette
        embedsRecordingsInNote = defaults.object(forKey: Key.embedsRecordingsInNote) as? Bool ?? true
        accentHex = defaults.string(forKey: Key.accentHex).flatMap(TextColorMarkup.canonicalHex) ?? GraphiteTheme.defaultAccentHex
        showsInlineTitle = defaults.object(forKey: Key.showsInlineTitle) as? Bool ?? true
        showsFileExtensions = defaults.object(forKey: Key.showsFileExtensions) as? Bool ?? true
        searchSortOrder = defaults.string(forKey: Key.searchSortOrder).flatMap(SearchSortOrder.init(rawValue:)) ?? .fileNameAscending
        recentCommandIdentifiers = defaults.stringArray(forKey: Key.recentCommandIdentifiers) ?? []
        // Obsidian's defaults: a snapshot at most every 5 minutes, kept for 7 days.
        let storedInterval = defaults.integer(forKey: Key.snapshotIntervalMinutes)
        snapshotIntervalMinutes = (1...60).contains(storedInterval) ? storedInterval : 5
        let storedHistory = defaults.integer(forKey: Key.snapshotHistoryDays)
        snapshotHistoryDays = (1...365).contains(storedHistory) ? storedHistory : 7
    }

    func isEnabled(_ plugin: CorePlugin) -> Bool { !disabledCorePlugins.contains(plugin) }

    /// A file's name as lists and the title bar show it: with its extension, or, when
    /// extensions are hidden, without `.md` (other files keep theirs, as in Obsidian).
    func displayName(for path: VaultPath) -> String {
        showsFileExtensions || DocumentKind(path: path) != .markdown ? path.name : path.stem
    }

    func setEnabled(_ plugin: CorePlugin, _ isEnabled: Bool) {
        if isEnabled { disabledCorePlugins.remove(plugin) } else { disabledCorePlugins.insert(plugin) }
    }

    /// The view a note opens in, from "Default view for new notes" and the editing mode.
    var initialNoteViewMode: NoteViewMode {
        defaultNoteView == .reading ? .reading : (defaultEditingMode == .livePreview ? .livePreview : .source)
    }
}

extension DrawingFormat {
    var title: String {
        switch self {
        case .png: "PNG image"
        case .pdf: "PDF (vector)"
        case .svg: "SVG (vector)"
        }
    }

    var summary: String {
        switch self {
        case .png: "Keeps the exact look of every brush. Best for sketches and shading."
        case .pdf: "Sharp at any zoom and prints cleanly. Brush texture is simplified."
        case .svg: "Sharp at any zoom and small for line drawings. Brush texture is simplified."
        }
    }
}

extension DrawingBackground {
    var title: String {
        switch self {
        case .white: "White"
        case .transparent: "Transparent"
        }
    }
}

extension LinkFormat {
    var title: String {
        switch self {
        case .shortest: "Shortest path when possible"
        case .relative: "Relative path to file"
        case .absolute: "Absolute path in vault"
        }
    }
}

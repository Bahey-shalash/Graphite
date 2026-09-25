import SwiftUI
import GraphiteCore
import GraphiteIndex

/// A row in the quick switcher or the command palette.
struct PaletteItem: Identifiable {
    let id: String
    let title: String
    /// Characters of `title` that matched the query, as UTF-16 offsets.
    var titleHighlights: [Range<Int>] = []
    var subtitle: String?
    let systemImage: String
    /// A keyboard shortcut to show, such as "⌘O".
    var shortcut: String?
    /// Return does not choose this item; it must be tapped (or reached with the arrow keys).
    var requiresExplicitChoice = false
    /// Opens a file in a new tab (⌘Return) or on the other side of the split (⌥⌘Return).
    var openElsewhere: ((TabPlacement) -> Void)?
    let run: () -> Void
}

/// Obsidian's quick switcher and command palette: a field, then results to pick with a
/// tap, or with the arrow keys and Return on a keyboard.
struct QuickPalette: View {
    let prompt: String
    @Binding var query: String
    let items: [PaletteItem]
    let emptyMessage: String
    /// True while the items are still for an earlier query; Return then waits for them.
    var isUpdating = false
    let close: () -> Void
    @State private var selectedIndex = 0
    @State private var isSubmitPending = false
    /// Set when the arrow keys moved the selection, so Return chooses exactly that item.
    @State private var hasMovedSelection = false
    @State private var resultsHeight: CGFloat = 0
    @FocusState private var isFieldFocused: Bool
    private static let maximumResultsHeight: CGFloat = 420
    #if canImport(UIKit)
    private static let secondaryColor = Color(uiColor: .secondaryLabel)
    #else
    private static let secondaryColor = Color(nsColor: .secondaryLabelColor)
    #endif
    @Environment(\.accent) private var accent

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(prompt, text: $query)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($isFieldFocused)
                    .autocorrectionDisabled()
                    #if canImport(UIKit)
                    .textInputAutocapitalization(.never)
                    #endif
                    .submitLabel(.go)
                    .onSubmit { runSelected() }
                    .onKeyPress(.return, phases: .down) { press in
                        guard press.modifiers.contains(.command) else { return .ignored }
                        runSelected(placement: press.modifiers.contains(.option) ? .otherGroup : .newTab)
                        return .handled
                    }
                    .onKeyPress(.downArrow) { moveSelection(by: 1); return .handled }
                    .onKeyPress(.upArrow) { moveSelection(by: -1); return .handled }
                    .onKeyPress(.escape) { close(); return .handled }
            }
            .padding(.horizontal, 18).padding(.vertical, 14)
            Divider()
            if items.isEmpty {
                Text(emptyMessage).foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(24)
            } else {
                ScrollViewReader { scrollProxy in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(Array(items.enumerated()), id: \.element.id) { itemIndex, item in
                                row(item, isSelected: itemIndex == selectedIndex)
                                    .id(item.id)
                                    .onTapGesture { Self.perform(item.run, closing: close) }
                                    .contextMenu {
                                        if let openElsewhere = item.openElsewhere {
                                            Button("Open in New Tab", systemImage: "plus.rectangle.on.rectangle") { Self.perform({ openElsewhere(.newTab) }, closing: close) }
                                            Button("Open on the Other Side", systemImage: "rectangle.split.2x1") { Self.perform({ openElsewhere(.otherGroup) }, closing: close) }
                                        }
                                    }
                            }
                        }
                        .padding(6)
                        .onGeometryChange(for: CGFloat.self) { geometry in geometry.size.height } action: { height in resultsHeight = height }
                    }
                    .onChange(of: selectedIndex) { _, newIndex in
                        guard items.indices.contains(newIndex) else { return }
                        scrollProxy.scrollTo(items[newIndex].id)
                    }
                }
                // As tall as the results, up to a limit, instead of filling the screen.
                .frame(height: min(max(resultsHeight, 52), Self.maximumResultsHeight))
                if items.contains(where: { item in item.openElsewhere != nil }) {
                    Divider()
                    // The text variation selector keeps ↩ from being drawn as an emoji.
                    Text("⌘↩\u{FE0E} new tab    ⌥⌘↩\u{FE0E} other side    long press for more")
                        .font(.caption)
                        .foregroundStyle(Self.secondaryColor)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 18).padding(.vertical, 8)
                }
            }
        }
        .frame(maxWidth: 620)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.separator))
        .shadow(color: .black.opacity(0.25), radius: 30, y: 12)
        .onAppear { isFieldFocused = true }
        .onChange(of: query) { selectedIndex = 0; hasMovedSelection = false }
        .onChange(of: isUpdating) { _, isStillUpdating in
            if !isStillUpdating && isSubmitPending { isSubmitPending = false; runSelected() }
        }
        .onChange(of: items.count) { _, count in selectedIndex = min(selectedIndex, max(count - 1, 0)) }
    }

    private func row(_ item: PaletteItem, isSelected: Bool) -> some View {
        HStack(spacing: 12) {
            // Label colors, not hierarchical styles: on the translucent panel those were
            // drawn with the material's vibrancy and nearly disappeared.
            Image(systemName: item.systemImage).foregroundStyle(Self.secondaryColor).frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(highlighted(item)).lineLimit(1).foregroundStyle(Color.primary)
                if let subtitle = item.subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(Self.secondaryColor).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if let shortcut = item.shortcut {
                Text(shortcut).font(.caption.monospaced()).foregroundStyle(Self.secondaryColor)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isSelected ? accent.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    /// The title with its matched characters in the accent color. The ranges come from
    /// whole characters, so no piece splits a character.
    private func highlighted(_ item: PaletteItem) -> AttributedString {
        let codeUnits = Array(item.title.utf16)
        var text = AttributedString()
        var position = 0
        for range in item.titleHighlights.sorted(by: { leftRange, rightRange in leftRange.lowerBound < rightRange.lowerBound })
        where range.lowerBound >= position && range.upperBound <= codeUnits.count {
            text += AttributedString(String(decoding: codeUnits[position..<range.lowerBound], as: UTF16.self))
            var match = AttributedString(String(decoding: codeUnits[range], as: UTF16.self))
            match.foregroundColor = accent
            match.font = .body.bold()
            text += match
            position = range.upperBound
        }
        text += AttributedString(String(decoding: codeUnits[position...], as: UTF16.self))
        return text
    }

    private func moveSelection(by offset: Int) {
        guard !items.isEmpty else { return }
        selectedIndex = (selectedIndex + offset + items.count) % items.count
        hasMovedSelection = true
    }

    /// Runs the selected item, or opens its file elsewhere for ⌘Return and ⌥⌘Return.
    private func runSelected(placement: TabPlacement? = nil) {
        // Return pressed right after typing picks from the results for what was typed.
        if isUpdating { isSubmitPending = placement == nil; return }
        guard items.indices.contains(selectedIndex) else { return }
        let item = items[selectedIndex]
        if item.requiresExplicitChoice && !hasMovedSelection { return }
        if let placement {
            guard let openElsewhere = item.openElsewhere else { return }
            Self.perform({ openElsewhere(placement) }, closing: close)
        } else {
            Self.perform(item.run, closing: close)
        }
    }

    /// Closes the palette, then runs the chosen action. An action that opens another
    /// palette, such as "Open quick switcher", would otherwise be undone by the close.
    static func perform(_ action: () -> Void, closing close: () -> Void) {
        close()
        action()
    }
}

/// Dims the document behind a palette and closes it when tapped.
struct PaletteOverlay<Palette: View>: View {
    let close: () -> Void
    @ViewBuilder let palette: Palette

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.2).ignoresSafeArea().onTapGesture(perform: close)
            palette.padding(.horizontal, 16).padding(.top, 70)
        }
        .transition(.opacity)
    }
}

// MARK: Quick switcher

/// Opens any file by a few letters of its name, alias or path, or creates a note, as
/// Obsidian's quick switcher does. Empty, it lists recent files.
struct QuickSwitcher: View {
    @Bindable var workspace: WorkspaceModel
    let close: () -> Void
    @State private var query = ""
    @State private var matches: [QuickSwitcherMatch] = []
    /// The query `matches` were found for.
    @State private var matchedQuery = ""

    var body: some View {
        QuickPalette(prompt: "Find or create a note…", query: $query, items: items,
                     emptyMessage: query.isEmpty ? "Files you open appear here." : "No files match.",
                     isUpdating: matchedQuery != query, close: close)
            .task(id: query) {
                do { try await Task.sleep(for: .milliseconds(60)) } catch { return }
                let searchedQuery = query
                let foundMatches = try? await workspace.index?.quickSwitcherMatches(for: searchedQuery)
                // A lookup cancelled because the query changed found nothing; storing that
                // would flash "No files match." for the old query.
                guard !Task.isCancelled else { return }
                matches = foundMatches ?? []
                matchedQuery = searchedQuery
            }
    }

    private var items: [PaletteItem] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespaces)
        if trimmedQuery.isEmpty {
            return workspace.existingRecentFiles(limit: 20, excluding: Set([workspace.selection].compactMap { path in path })).map { path in
                fileItem(path, title: workspace.preferences.displayName(for: path), highlights: [], alias: nil)
            }
        }
        // Recent files rank a little higher, as Obsidian ranks them.
        let recentPaths = Set(workspace.recentFiles.paths.prefix(10))
        var ranked = Self.uniqueMatches(matches).sorted { leftMatch, rightMatch in
            let leftScore = leftMatch.score + (recentPaths.contains(leftMatch.path) ? 1.5 : 0)
            let rightScore = rightMatch.score + (recentPaths.contains(rightMatch.path) ? 1.5 : 0)
            return leftScore > rightScore
        }.map { match in
            fileItem(match.path, title: Self.title(of: match, foundFor: matchedQuery), highlights: match.matchedRanges, alias: match.alias)
        }
        let isExistingNote = matches.contains { match in match.alias == nil && VaultIndex.switcherName(match.path).caseInsensitiveCompare(trimmedQuery) == .orderedSame }
        if !isExistingNote, FileNameRules.problem(with: trimmedQuery, isNote: true) == nil {
            // Until the index has seen every file, a note may exist without being found:
            // Return then does not create a second one.
            let isIndexComplete = workspace.hasCompletedIndexScan
            var create = PaletteItem(id: "create", title: "Create “\(trimmedQuery)”",
                                     subtitle: isIndexComplete ? "New note in \(folderDescription)" : "Graphite is still reading the vault; this note may already exist",
                                     systemImage: "plus") { [workspace] in
                Task { await workspace.createNote(named: trimmedQuery) }
            }
            create.requiresExplicitChoice = !isIndexComplete
            ranked.append(create)
        }
        return ranked
    }

    /// The text a match is listed under. It follows the query the match was found for, not
    /// the one being typed, since the match's highlighted ranges are offsets into that text.
    static func title(of match: QuickSwitcherMatch, foundFor matchedQuery: String) -> String {
        if let alias = match.alias { return alias }
        return matchedQuery.contains("/") ? match.path.rawValue : VaultIndex.switcherName(match.path)
    }

    /// The matches without repeats, since each row's identifier must be unique. A note can
    /// list the same alias twice in its properties.
    static func uniqueMatches(_ matches: [QuickSwitcherMatch]) -> [QuickSwitcherMatch] {
        var seenIdentifiers: Set<String> = []
        return matches.filter { match in seenIdentifiers.insert(match.id).inserted }
    }

    private var folderDescription: String {
        let directory = workspace.newFileDirectory(nil)
        return directory.rawValue.isEmpty ? workspace.title : directory.rawValue
    }

    private func fileItem(_ path: VaultPath, title: String, highlights: [Range<Int>], alias: String?) -> PaletteItem {
        let folder = path.parent.rawValue
        let subtitle = alias != nil ? workspace.preferences.displayName(for: path) + (folder.isEmpty ? "" : " — " + folder) : (folder.isEmpty ? nil : folder)
        var item = PaletteItem(id: path.rawValue + "|" + (alias ?? ""), title: title, titleHighlights: highlights, subtitle: subtitle,
                               systemImage: alias != nil ? "arrow.turn.down.right" : DocumentKind(path: path).systemImage) { [workspace] in
            Task { await workspace.open(path) }
        }
        item.openElsewhere = { [workspace] placement in Task { await workspace.open(path, placement: placement) } }
        return item
    }
}

extension DocumentKind {
    var systemImage: String {
        switch self {
        case .markdown: "doc.text"
        case .pdf: "doc.richtext"
        case .image: "photo"
        case .media: "play.rectangle"
        case .base: "tablecells"
        case .other: "doc"
        }
    }
}

// MARK: Command palette

/// An action the command palette offers, like Obsidian's commands.
struct PaletteCommand: Identifiable {
    let id: String
    let title: String
    let systemImage: String
    var shortcut: String?
    let run: () -> Void
}

/// Obsidian's command palette: every command, found by a few letters of its name.
/// Empty, it lists recently used commands first.
struct CommandPalette: View {
    let commands: [PaletteCommand]
    @Binding var recentCommandIdentifiers: [String]
    let close: () -> Void
    @State private var query = ""

    var body: some View {
        QuickPalette(prompt: "Type a command…", query: $query, items: items, emptyMessage: "No commands match.", close: close)
    }

    private var items: [PaletteItem] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespaces)
        let ordered: [(PaletteCommand, FuzzyMatcher.Match?)]
        if trimmedQuery.isEmpty {
            let recent = recentCommandIdentifiers.compactMap { identifier in commands.first { command in command.id == identifier } }
            let others = commands.filter { command in !recentCommandIdentifiers.contains(command.id) }
            ordered = (recent + others).map { command in (command, nil) }
        } else {
            ordered = commands.compactMap { command in FuzzyMatcher.match(trimmedQuery, in: command.title).map { match in (command, match) } }
                .sorted { leftEntry, rightEntry in (leftEntry.1?.score ?? 0) > (rightEntry.1?.score ?? 0) }
        }
        return ordered.map { command, match in
            PaletteItem(id: command.id, title: command.title, titleHighlights: match?.matchedRanges ?? [], systemImage: command.systemImage, shortcut: command.shortcut) {
                recentCommandIdentifiers.removeAll { identifier in identifier == command.id }
                recentCommandIdentifiers.insert(command.id, at: 0)
                if recentCommandIdentifiers.count > 8 { recentCommandIdentifiers.removeLast(recentCommandIdentifiers.count - 8) }
                command.run()
            }
        }
    }
}

// MARK: Templates

/// Obsidian's "Insert template": the notes of the Templates folder, found by name, inserted
/// at the cursor of the note being edited.
struct TemplatePicker: View {
    @Bindable var workspace: WorkspaceModel
    let close: () -> Void
    @State private var query = ""
    @State private var templates: [VaultPath] = []
    @State private var hasLoaded = false

    var body: some View {
        QuickPalette(prompt: "Find a template…", query: $query, items: items, emptyMessage: emptyMessage,
                     isUpdating: !hasLoaded, close: close)
            .task {
                let workspace = workspace
                templates = workspace.templateFiles()
                hasLoaded = true
            }
    }

    private var emptyMessage: String {
        if !hasLoaded { return "Reading the Templates folder…" }
        if workspace.templateSettings.folderPath == nil { return "Choose a Templates folder in Settings › Templates." }
        return templates.isEmpty ? "The Templates folder “\(workspace.templateSettings.folder)” has no notes." : "No templates match."
    }

    private var items: [PaletteItem] {
        let folder = workspace.templateSettings.folder
        let trimmedQuery = query.trimmingCharacters(in: .whitespaces)
        let matched: [(VaultPath, [Range<Int>])] = templates.compactMap { path in
            let name = Self.name(of: path, in: folder)
            if trimmedQuery.isEmpty { return (path, []) }
            return FuzzyMatcher.match(trimmedQuery, in: name).map { match in (path, match.matchedRanges) }
        }
        return matched.map { path, highlights in
            PaletteItem(id: path.rawValue, title: Self.name(of: path, in: folder), titleHighlights: highlights, systemImage: "doc.on.doc") { [workspace] in
                guard let session = workspace.markdownSession else { return }
                Task { await workspace.insertTemplate(path, into: session) }
            }
        }
    }

    /// The template's path inside the Templates folder, without `.md`, as Obsidian lists it.
    private static func name(of path: VaultPath, in folder: String) -> String {
        let relative = folder.isEmpty ? path.rawValue : String(path.rawValue.dropFirst(folder.count + 1))
        return (relative as NSString).deletingPathExtension
    }
}

/// Opens the template list for the note being edited. It always opens the same window's
/// list, so any two values are equal and views that read it do not update needlessly.
struct TemplatePickerAction: Equatable {
    let show: () -> Void
    static func == (leftAction: TemplatePickerAction, rightAction: TemplatePickerAction) -> Bool { true }
}

extension EnvironmentValues {
    /// Nil where Templates is off.
    @Entry var showTemplatePicker: TemplatePickerAction? = nil
}

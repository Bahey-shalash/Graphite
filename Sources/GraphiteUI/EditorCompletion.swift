import SwiftUI
import GraphiteCore
import GraphiteIndex

/// One suggestion while typing a link or a tag.
struct CompletionItem: Identifiable {
    let id: String
    let title: String
    /// The characters of `title` the typed query matched, as UTF-16 offsets.
    var titleHighlights: [Range<Int>] = []
    var subtitle: String?
    let systemImage: String
    /// The edits to make in the note, last location first; may write another file first,
    /// as when a block gets a new `^id`. They are built for the context at the moment the
    /// item is chosen, which can be newer than the one it was found for, since typing goes
    /// on while suggestions load. Empty when the item no longer fits what is typed, or when
    /// the note changed while the edits were prepared.
    let makeEdits: @MainActor (CompletionContext) async throws -> [MarkdownTextEdit]
}

/// The suggestions shown at the cursor, as Obsidian shows them while typing `[[` or `#`.
@MainActor @Observable
final class CompletionModel {
    private(set) var context: CompletionContext?
    /// Where the cursor is, in the editor's own coordinates.
    private(set) var caretRect: CGRect = .zero
    /// The latest suggestions found. Until the ones for a newer context arrive, the older
    /// list stays on screen rather than flickering away at every letter typed.
    private(set) var items: [CompletionItem] = []
    var selectedIndex = 0
    /// Set by the editor: applies edits to the text view so they can be undone.
    @ObservationIgnored var performEdits: (([MarkdownTextEdit]) -> Void)?
    /// Set by the pane: finds the suggestions for a context.
    @ObservationIgnored var provider: ((CompletionContext) async -> [CompletionItem])?
    /// Set by the pane: tells the person why a chosen suggestion could not be inserted.
    @ObservationIgnored var reportError: ((Error) -> Void)?
    @ObservationIgnored private var fetchTask: Task<Void, Never>?
    /// A context the person closed with Escape; it stays closed until the text changes.
    @ObservationIgnored private var dismissedContext: CompletionContext?

    var isVisible: Bool { context != nil && !items.isEmpty }

    func update(context newContext: CompletionContext?, caretRect newCaretRect: CGRect) {
        caretRect = newCaretRect
        guard newContext != context else { return }
        context = newContext == dismissedContext ? nil : newContext
        if newContext != dismissedContext { dismissedContext = nil }
        selectedIndex = 0
        fetchTask?.cancel()
        guard let currentContext = context, let provider else { items = []; return }
        fetchTask = Task { [weak self] in
            // A short pause, so fast typing does not query the index for every letter.
            do { try await Task.sleep(for: .milliseconds(40)) } catch { return }
            let foundItems = await provider(currentContext)
            guard !Task.isCancelled, let self, self.context == currentContext else { return }
            self.items = foundItems
            self.selectedIndex = min(self.selectedIndex, max(foundItems.count - 1, 0))
        }
    }

    func moveSelection(by offset: Int) {
        guard !items.isEmpty else { return }
        selectedIndex = (selectedIndex + offset + items.count) % items.count
    }

    func dismiss() {
        dismissedContext = context
        context = nil
        items = []
        fetchTask?.cancel()
    }

    /// Chooses a suggestion: its edits go to the editor, and the list closes. The edits
    /// are made for what is typed now, even when the list shown was found for an earlier
    /// query, so a fast Return never replaces an outdated range.
    func accept(_ index: Int? = nil) {
        let chosenIndex = index ?? selectedIndex
        guard let currentContext = context, items.indices.contains(chosenIndex) else { return }
        let item = items[chosenIndex]
        context = nil
        items = []
        fetchTask?.cancel()
        Task { [weak self] in
            do {
                let edits = try await item.makeEdits(currentContext)
                guard !edits.isEmpty else { return }
                self?.performEdits?(edits)
            } catch {
                self?.reportError?(error)
            }
        }
    }

    /// Suggestions from the vault for `session`'s note. Both are held weakly: the session
    /// owns this model, and a strong reference back would keep every note ever edited, with
    /// its whole text, in memory.
    func suggest(from workspace: WorkspaceModel, for session: MarkdownSession) {
        provider = { [weak workspace, weak session] context in
            guard let workspace, let session else { return [] }
            return await CompletionProvider(workspace: workspace, session: session).items(for: context)
        }
        reportError = { [weak workspace] error in workspace?.errorMessage = error.localizedDescription }
    }
}

/// Builds suggestions from the vault for the note being edited. The items' edits hold
/// the workspace and session weakly, for the same reason as `CompletionModel.suggest`.
@MainActor
struct CompletionProvider {
    let workspace: WorkspaceModel
    let session: MarkdownSession
    /// Suggestions listed at most.
    static let maximumItemCount = 40

    func items(for context: CompletionContext) async -> [CompletionItem] {
        switch context {
        case .tag(let query, let replacementRange):
            return await tagItems(query: query, replacementRange: replacementRange)
        case .link(let query):
            if let blockQuery = query.blockQuery { return await blockItems(query: query, blockQuery: blockQuery) }
            if let headingQuery = query.headingQuery { return await headingItems(query: query, headingQuery: headingQuery) }
            return await fileItems(query: query)
        }
    }

    // MARK: Links

    /// What a chosen link suggestion points to, in both of Obsidian's link styles.
    struct LinkChoice: Equatable {
        /// The Wikilink target, such as `Note#Heading`.
        let wikilinkTarget: String
        /// The Markdown link's file path with its extension; empty for a heading or block
        /// of the note being edited, which the fragment alone reaches.
        let markdownPath: String
        /// The heading, or `^` and the block's identifier, after `#`.
        let fragment: String?
        /// The Markdown link's text when there is no alias.
        let label: String
        var alias: String?
    }

    /// Replaces the typed query with the chosen target and closes the link; with Markdown
    /// links chosen in the vault's settings, the whole `[[…` becomes `[Name](path)`.
    nonisolated static func linkEdit(query: LinkQuery, choice: LinkChoice, usesWikilinks: Bool) -> MarkdownTextEdit {
        // The replacement covers a closed link's `|alias`, so an alias already written is
        // kept when the chosen suggestion has none of its own.
        let alias = choice.alias ?? query.writtenAlias
        guard usesWikilinks else {
            let openingLength = query.isEmbed ? 3 : 2
            let start = query.replacementRange.location - openingLength
            let fragment = choice.fragment.map { fragment in "#" + fragment } ?? ""
            let unreserved = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~/")
            let encodedPath = (choice.markdownPath.addingPercentEncoding(withAllowedCharacters: unreserved) ?? choice.markdownPath)
                + (fragment.addingPercentEncoding(withAllowedCharacters: unreserved.union(CharacterSet(charactersIn: "#^"))) ?? fragment)
            let link = (query.isEmbed ? "!" : "") + "[" + (alias ?? choice.label) + "](" + encodedPath + ")"
            let range = NSRange(location: start, length: NSMaxRange(query.replacementRange) - start)
            return MarkdownTextEdit(range: range, replacement: link, selectionAfter: NSRange(location: start + link.utf16.count, length: 0))
        }
        let replacement = choice.wikilinkTarget + (alias.map { alias in "|" + alias } ?? "") + "]]"
        return MarkdownTextEdit(range: query.replacementRange, replacement: replacement,
                                selectionAfter: NSRange(location: query.replacementRange.location + replacement.utf16.count, length: 0))
    }

    /// A heading or block (`^id`) of the note a `Note#…` query names, or of the note being
    /// edited when no name is typed. The typed name is taken whole: a dot in it, as in
    /// `Meeting 3.4`, is not an extension.
    nonisolated static func fragmentChoice(notePart: String, fragment: String) -> LinkChoice {
        let hasMarkdownExtension = notePart.lowercased().hasSuffix(".md")
        let noteName = (notePart as NSString).lastPathComponent
        return LinkChoice(wikilinkTarget: notePart + "#" + fragment,
                          markdownPath: notePart.isEmpty || hasMarkdownExtension ? notePart : notePart + ".md",
                          fragment: fragment,
                          label: (hasMarkdownExtension ? (noteName as NSString).deletingPathExtension : noteName) + "#" + fragment)
    }

    // MARK: Files

    private func fileItems(query: LinkQuery) async -> [CompletionItem] {
        guard let index = workspace.index else { return [] }
        let notePart = query.notePart
        // A query with a folder is matched against the whole path, so its matched
        // characters are not those of the file name shown as the title.
        let highlightsTitle = !notePart.contains("/")
        var entries: [(path: VaultPath, alias: String?, highlights: [Range<Int>])] = []
        if notePart.trimmingCharacters(in: .whitespaces).isEmpty {
            entries = workspace.recentFiles.paths.filter { path in path != session.path }.prefix(Self.maximumItemCount).map { path in (path, nil, []) }
        } else if let matches = try? await index.quickSwitcherMatches(for: notePart, limit: Self.maximumItemCount) {
            entries = matches.map { match in (match.path, match.alias, highlightsTitle ? match.matchedRanges : []) }
        }
        return entries.map { entry in
            let path = entry.path, alias = entry.alias
            let folder = path.parent.rawValue
            return CompletionItem(id: path.rawValue + "|" + (alias ?? ""), title: alias ?? VaultIndex.switcherName(path), titleHighlights: entry.highlights,
                                  subtitle: alias != nil ? VaultIndex.switcherName(path) + (folder.isEmpty ? "" : " — " + folder) : (folder.isEmpty ? nil : folder),
                                  systemImage: alias != nil ? "arrow.turn.down.right" : DocumentKind(path: path).systemImage) { [weak workspace, weak session] context in
                guard case .link(let currentQuery) = context, currentQuery.headingQuery == nil, currentQuery.blockQuery == nil,
                      let workspace, let session else { return [] }
                let textBeforeLookup = session.text
                let isNameUnique = await Self.isNameUnique(path, in: workspace)
                // Text typed while the index answered moves the range to replace.
                guard session.text == textBeforeLookup else { return [] }
                let target = LinkCompletion.linkTarget(for: path, from: session.path, settings: workspace.vaultSettings, isNameUnique: isNameUnique)
                let choice = LinkChoice(wikilinkTarget: target, markdownPath: DocumentKind(path: path) == .markdown ? target + ".md" : target,
                                        fragment: nil, label: path.stem, alias: alias)
                return [Self.linkEdit(query: currentQuery, choice: choice, usesWikilinks: workspace.vaultSettings.usesWikilinks)]
            }
        }
    }

    /// Whether a bare name links to `path` without ambiguity. Before the first index scan
    /// finishes, or when the index cannot answer, another file of that name may exist
    /// unseen, so the link keeps its folder, as `WorkspaceModel` does for embeds.
    private static func isNameUnique(_ path: VaultPath, in workspace: WorkspaceModel) async -> Bool {
        guard workspace.hasCompletedIndexScan, let index = workspace.index,
              let fileCount = try? await index.fileCount(named: path.name) else { return false }
        return fileCount <= 1
    }

    // MARK: Headings and blocks

    /// The note a `Note#…` query names, and its text; the current note when no name is typed.
    private func targetNote(for query: LinkQuery) async -> (path: VaultPath, text: String)? {
        let notePart = query.notePart
        if notePart.isEmpty { return (session.path, session.text) }
        guard let path = await workspace.resolveLink(notePart, from: session.path), DocumentKind(path: path) == .markdown else { return nil }
        if path == session.path { return (path, session.text) }
        guard let snapshot = try? await workspace.store?.read(path, maximumBytes: MarkdownSession.maximumEditableBytes),
              let decoded = NoteTextEncoding.decode(snapshot.data) else { return nil }
        return (path, decoded.text)
    }

    private func headingItems(query: LinkQuery, headingQuery: String) async -> [CompletionItem] {
        guard let (_, text) = await targetNote(for: query) else { return [] }
        let headings = await Task.detached(priority: .userInitiated) { Self.headings(inNoteText: text) }.value
        let ranked: [((level: Int, text: String, anchor: String), FuzzyMatcher.Match?)] = headingQuery.isEmpty
            ? headings.map { heading in (heading, nil) }
            : headings.compactMap { heading in FuzzyMatcher.match(headingQuery, in: heading.text).map { match in (heading, match) } }
                .sorted { leftEntry, rightEntry in (leftEntry.1?.score ?? 0) > (rightEntry.1?.score ?? 0) }
        return ranked.prefix(Self.maximumItemCount).enumerated().map { position, entry in
            let (heading, match) = entry
            let choice = Self.fragmentChoice(notePart: query.notePart, fragment: heading.text)
            return CompletionItem(id: "heading-\(position)-\(heading.text)", title: heading.text, titleHighlights: match?.matchedRanges ?? [],
                                  subtitle: "Heading \(heading.level)", systemImage: "number") { [weak workspace] context in
                guard case .link(let currentQuery) = context, currentQuery.headingQuery != nil, currentQuery.notePart == query.notePart,
                      let workspace else { return [] }
                return [Self.linkEdit(query: currentQuery, choice: choice, usesWikilinks: workspace.vaultSettings.usesWikilinks)]
            }
        }
    }

    /// The headings of a note's body, after its frontmatter. Reading the outline takes a
    /// Markdown parse of the whole note, so callers run it off the main actor; only the
    /// frontmatter is cut, without the full semantic parse.
    nonisolated static func headings(inNoteText text: String) -> [(level: Int, text: String, anchor: String)] {
        let source = text as NSString
        return NotePreviewDocument.outline(of: source.substring(from: FrontmatterLocator.length(in: source)))
    }

    private func blockItems(query: LinkQuery, blockQuery: String) async -> [CompletionItem] {
        guard let (notePath, text) = await targetNote(for: query) else { return [] }
        // Finding the blocks reads the whole note, so it stays off the main actor while typing.
        let blocks = await Task.detached(priority: .userInitiated) { NoteBlocks.blocks(in: text) }.value
        let filtered = blockQuery.isEmpty ? blocks : blocks.filter { block in
            block.text.localizedCaseInsensitiveContains(blockQuery) || block.identifier?.localizedCaseInsensitiveContains(blockQuery) == true
        }
        let existingIdentifiers = Set(blocks.compactMap(\.identifier))
        return filtered.prefix(Self.maximumItemCount).enumerated().map { position, block in
            let preview = block.text.split(whereSeparator: \.isNewline).first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? ""
            return CompletionItem(id: "block-\(position)-\(block.range.location)", title: String(preview.prefix(90)),
                                  subtitle: block.identifier.map { identifier in "^" + identifier }, systemImage: "text.alignleft") { [weak workspace, weak session] context in
                guard case .link(let currentQuery) = context, currentQuery.blockQuery != nil, currentQuery.notePart == query.notePart,
                      let workspace, let session else { return [] }
                let usesWikilinks = workspace.vaultSettings.usesWikilinks
                func link(to identifier: String) -> MarkdownTextEdit {
                    Self.linkEdit(query: currentQuery, choice: Self.fragmentChoice(notePart: query.notePart, fragment: "^" + identifier), usesWikilinks: usesWikilinks)
                }
                if let identifier = block.identifier { return [link(to: identifier)] }
                if notePath == session.path {
                    // Typing the query since the blocks were listed moved them; the `^id`
                    // goes into the block where it is now.
                    let currentText = session.text
                    let currentBlocks = currentText == text ? blocks : NoteBlocks.blocks(in: currentText)
                    guard let currentBlock = Self.block(matching: block, in: currentBlocks) else {
                        throw GraphiteError.unavailable("This paragraph changed while its link was being made. Choose it again.")
                    }
                    let identifier = NoteBlocks.newIdentifier(avoiding: Set(currentBlocks.compactMap(\.identifier)))
                    return [NoteBlocks.addingIdentifier(identifier, to: currentBlock, in: currentText), link(to: identifier)]
                }
                let identifier = NoteBlocks.newIdentifier(avoiding: existingIdentifiers)
                let identifierEdit = NoteBlocks.addingIdentifier(identifier, to: block, in: text)
                let textBeforeWrite = session.text
                // Another note gets its `^id` through a revision-checked write.
                try await workspace.addBlockIdentifier(identifierEdit, to: notePath, expectingText: text)
                // Text typed during the write moves the range to replace.
                guard session.text == textBeforeWrite else { return [] }
                return [link(to: identifier)]
            }
        }
    }

    /// The block with `block`'s kind and text nearest its old place: typing elsewhere in
    /// the note moves blocks without changing them.
    private static func block(matching block: NoteBlock, in blocks: [NoteBlock]) -> NoteBlock? {
        blocks.filter { candidate in candidate.kind == block.kind && candidate.text == block.text }
            .min { leftCandidate, rightCandidate in
                abs(leftCandidate.range.location - block.range.location) < abs(rightCandidate.range.location - block.range.location)
            }
    }

    // MARK: Tags

    private func tagItems(query: String, replacementRange: NSRange) async -> [CompletionItem] {
        guard let tags = try? await workspace.index?.tags(matching: query, limit: Self.maximumItemCount) else { return [] }
        return tags.filter { tagCount in tagCount.tag.caseInsensitiveCompare(query) != .orderedSame }.map { tagCount in
            CompletionItem(id: "tag-" + tagCount.tag, title: "#" + tagCount.tag,
                           titleHighlights: FuzzyMatcher.match(query, in: "#" + tagCount.tag)?.matchedRanges ?? [],
                           subtitle: tagCount.fileCount == 1 ? "1 note" : "\(tagCount.fileCount) notes", systemImage: "number") { context in
                guard case .tag(_, let currentReplacementRange) = context else { return [] }
                let replacement = tagCount.tag + " "
                return [MarkdownTextEdit(range: currentReplacementRange, replacement: replacement,
                                         selectionAfter: NSRange(location: currentReplacementRange.location + replacement.utf16.count, length: 0))]
            }
        }
    }
}

extension WorkspaceModel {
    /// Writes a new `^id` into another note, only if it is unchanged since it was read.
    func addBlockIdentifier(_ edit: MarkdownTextEdit, to path: VaultPath, expectingText text: String) async throws {
        guard let store else { throw GraphiteError.unavailable("Open a vault first.") }
        let snapshot = try await store.read(path, maximumBytes: MarkdownSession.maximumEditableBytes)
        guard let decoded = NoteTextEncoding.decode(snapshot.data), decoded.text == text else { throw GraphiteError.conflict }
        let updated = (text as NSString).replacingCharacters(in: edit.range, with: edit.replacement)
        _ = try await store.save(NoteTextEncoding.encode(updated, hasByteOrderMark: decoded.hasByteOrderMark), at: path, expecting: .revision(snapshot.revision))
        refreshIndex(for: [path])
    }
}

/// The list of suggestions under the cursor.
struct CompletionPopup: View {
    @Bindable var model: CompletionModel
    @Environment(\.accent) private var accent
    static let width: CGFloat = 360
    static let maximumHeight: CGFloat = 280
    #if canImport(UIKit)
    private static let secondaryColor = Color(uiColor: .secondaryLabel)
    #else
    private static let secondaryColor = Color.secondary
    #endif

    var body: some View {
        ScrollViewReader { scrollProxy in
            ScrollView {
                LazyVStack(spacing: 1) {
                    ForEach(Array(model.items.enumerated()), id: \.element.id) { itemIndex, item in
                        row(item, isSelected: itemIndex == model.selectedIndex)
                            .id(item.id)
                            .onTapGesture { model.accept(itemIndex) }
                    }
                }
                .padding(4)
            }
            .onChange(of: model.selectedIndex) { _, newIndex in
                guard model.items.indices.contains(newIndex) else { return }
                scrollProxy.scrollTo(model.items[newIndex].id)
            }
        }
        .frame(width: Self.width, height: min(Self.maximumHeight, CGFloat(model.items.count) * 48 + 8))
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.separator))
        .shadow(color: .black.opacity(0.2), radius: 16, y: 6)
    }

    private func row(_ item: CompletionItem, isSelected: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: item.systemImage).foregroundStyle(Self.secondaryColor).frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(Self.highlightedTitle(item.title, highlights: item.titleHighlights, accent: accent)).lineLimit(1).foregroundStyle(Color.primary)
                if let subtitle = item.subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(Self.secondaryColor).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .frame(maxWidth: .infinity, minHeight: 46, alignment: .leading)
        .background(isSelected ? accent.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    /// The title with the characters the query matched in the accent color, as the quick
    /// switcher shows them. Ranges that do not fit the title are left out.
    static func highlightedTitle(_ title: String, highlights: [Range<Int>], accent: Color) -> AttributedString {
        let codeUnits = Array(title.utf16)
        var highlightedText = AttributedString()
        var position = 0
        for range in highlights.sorted(by: { leftRange, rightRange in leftRange.lowerBound < rightRange.lowerBound })
        where range.lowerBound >= position && range.upperBound <= codeUnits.count {
            highlightedText += AttributedString(String(decoding: codeUnits[position..<range.lowerBound], as: UTF16.self))
            var match = AttributedString(String(decoding: codeUnits[range], as: UTF16.self))
            match.foregroundColor = accent
            match.font = .body.bold()
            highlightedText += match
            position = range.upperBound
        }
        highlightedText += AttributedString(String(decoding: codeUnits[position...], as: UTF16.self))
        return highlightedText
    }
}

import Foundation
import GraphiteCore
import GraphiteIndex

/// One note that mentions another, with the lines where it does.
struct MentionGroup: Identifiable, Equatable {
    let path: VaultPath
    let matches: [SearchMatch]
    var id: VaultPath { path }
}

/// Obsidian's Backlinks panel: linked mentions with their lines, and unlinked mentions,
/// which can be turned into links.
extension WorkspaceModel {
    /// At most this many notes are read for either list, so a much-linked note stays quick.
    private static var maximumMentioningNotes: Int { 200 }

    /// The note's name and aliases, the words that can name it.
    func mentionNames(of note: VaultPath, text: String) -> [String] {
        let aliases = (try? MarkdownSemantics.parse(text).aliases) ?? []
        return [note.stem] + aliases.filter { alias in !alias.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    /// The notes that link to `note`, each with the lines of its links to it.
    func linkedMentions(of note: VaultPath, names: [String]) async -> [MentionGroup] {
        guard let index else { return [] }
        let sources = ((try? await index.backlinks(to: note)) ?? []).filter { source in source != note }.prefix(Self.maximumMentioningNotes)
        var groups: [MentionGroup] = []
        for source in sources {
            guard let text = await currentText(of: source) else { continue }
            var matches: [SearchMatch] = []
            for link in (try? Mentions.linkCandidates(in: text, names: names)) ?? [] {
                guard await resolveLink(link.target, from: source, isWiki: link.isWiki) == note else { continue }
                matches.append(SearchExcerpts.excerpt(around: link.range, in: text as NSString))
            }
            // A note whose links the index knows but the text no longer has (an unsaved
            // edit) is still listed, by name, until the index catches up.
            groups.append(MentionGroup(path: source, matches: matches))
        }
        return groups
    }

    /// Notes that write the note's name or an alias without linking it.
    func unlinkedMentions(of note: VaultPath, names: [String]) async -> [MentionGroup] {
        guard let index else { return [] }
        let query = names.map { name in "content:\"" + name.replacingOccurrences(of: "\"", with: " ") + "\"" }.joined(separator: " OR ")
        guard let page = try? await index.search(query, limit: Self.maximumMentioningNotes) else { return [] }
        var groups: [MentionGroup] = []
        for result in page.results where result.path != note && DocumentKind(path: result.path) == .markdown {
            guard let text = await currentText(of: result.path) else { continue }
            let mentions = Mentions.unlinkedMentions(of: names, in: text)
            guard !mentions.isEmpty else { continue }
            groups.append(MentionGroup(path: result.path, matches: mentions.map { range in SearchExcerpts.excerpt(around: range, in: text as NSString) }))
        }
        return groups
    }

    /// Turns an unlinked mention into a link to `note`, as Obsidian's "Link" button does.
    /// The note it is in changes through its editor when open, so the change can be undone;
    /// otherwise the file is rewritten only if it is still as it was read.
    func linkMention(_ match: SearchMatch, in source: VaultPath, to note: VaultPath) async {
        guard let store else { return }
        let settings = vaultSettings
        let fileCount = (try? await index?.fileCount(named: note.name)) ?? 0
        let linkTarget = LinkCompletion.linkTarget(for: note, from: source, settings: settings, isNameUnique: fileCount <= 1)
        let unreserved = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~/")
        let destination = (linkTarget + ".md").addingPercentEncoding(withAllowedCharacters: unreserved) ?? linkTarget + ".md"
        let range = NSRange(location: match.location, length: match.length)
        do {
            if let session = openMarkdownSession(at: source) {
                guard Self.mentionIsStill(at: range, in: session.text, matching: match) else { throw Self.mentionChanged }
                session.apply(Mentions.linkingEdit(mention: range, in: session.text, linkTarget: linkTarget, usesWikilinks: settings.usesWikilinks, markdownDestination: destination))
                return
            }
            let snapshot = try await store.read(source, maximumBytes: MarkdownSession.maximumEditableBytes)
            guard let text = String(data: snapshot.data, encoding: .utf8), Self.mentionIsStill(at: range, in: text, matching: match) else { throw Self.mentionChanged }
            let edit = Mentions.linkingEdit(mention: range, in: text, linkTarget: linkTarget, usesWikilinks: settings.usesWikilinks, markdownDestination: destination)
            let updated = (text as NSString).replacingCharacters(in: edit.range, with: edit.replacement)
            _ = try await store.save(Data(updated.utf8), at: source, expecting: .revision(snapshot.revision))
            refreshIndex(for: [source])
        } catch { errorMessage = error.localizedDescription }
    }

    private static var mentionChanged: GraphiteError {
        GraphiteError.unavailable("The note changed since the mentions were listed. Look again and try once more.")
    }

    /// Whether the words at `range` are still those the mention was found for.
    private static func mentionIsStill(at range: NSRange, in text: String, matching match: SearchMatch) -> Bool {
        let source = text as NSString
        guard NSMaxRange(range) <= source.length, let highlighted = match.highlightedRanges.first else { return false }
        let excerptWords = (match.excerpt as NSString).substring(with: NSRange(location: highlighted.lowerBound, length: highlighted.count))
        return source.substring(with: range) == excerptWords
    }

    /// A note's text: as open in a tab, with unsaved changes, else as saved.
    private func currentText(of path: VaultPath) async -> String? {
        if let session = openMarkdownSession(at: path) { return session.text }
        guard let store, let snapshot = try? await store.read(path, maximumBytes: MarkdownSession.maximumEditableBytes) else { return nil }
        return String(data: snapshot.data, encoding: .utf8)
    }
}

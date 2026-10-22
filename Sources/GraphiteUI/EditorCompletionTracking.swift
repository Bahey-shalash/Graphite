import Foundation
import GraphiteCore

/// What an editor remembers about the suggestions at its cursor, the same on the iPad and
/// the Mac: the text revision the open suggestions were found at, the change community
/// plugins last heard of, and the revisions of accepted suggestions whose edits are still
/// being made. Those edits arrive after asynchronous work and are moved past typing that
/// happened meanwhile.
struct EditorCompletionTracking {
    /// The text and cursor community plugins last heard of.
    private struct PluginEditorState: Equatable {
        let textRevision: Int
        let cursor: Int
    }

    private var openSuggestionsRevision: Int?
    private var lastPluginEditorState: PluginEditorState?
    /// The revision plugins answered with suggestions for.
    private var pluginSuggestionRevision: Int?
    private var acceptedSuggestionRevisions: [Int] = []
    /// Only a few are kept: the edits use the latest.
    private static let maximumAcceptedSuggestionRevisions = 8

    /// Suggestions that closed since the last update without Escape were accepted; their
    /// edits are on the way and belong to the revision the suggestions were found at.
    mutating func recordAcceptedSuggestion(isListOpen: Bool) {
        guard !isListOpen, let openSuggestionsRevision else { return }
        acceptedSuggestionRevisions.append(openSuggestionsRevision)
        if acceptedSuggestionRevisions.count > Self.maximumAcceptedSuggestionRevisions { acceptedSuggestionRevisions.removeFirst() }
        self.openSuggestionsRevision = nil
    }

    /// What to suggest at `cursor`: a link or tag Graphite completes, else what community
    /// plugins suggest. Plugins hear each change and cursor move once; asking again for the
    /// same, as scrolling does, keeps their last answer.
    mutating func context(in source: NSString, cursor: Int, textRevision: Int, pluginEditorDidChange: (() -> Int?)?) -> CompletionContext? {
        if let context = LinkCompletion.context(in: source, cursor: cursor) { return context }
        guard let pluginEditorDidChange else { return nil }
        let state = PluginEditorState(textRevision: textRevision, cursor: cursor)
        if state != lastPluginEditorState {
            lastPluginEditorState = state
            pluginSuggestionRevision = pluginEditorDidChange()
        }
        return pluginSuggestionRevision.map { revision in CompletionContext.pluginSuggestion(revision: revision) }
    }

    /// Records the revision the suggestions now open were found at, or that none are open.
    mutating func listDidUpdate(isOpen: Bool, at textRevision: Int) {
        openSuggestionsRevision = isOpen ? textRevision : nil
    }

    /// Forgets the open suggestions without accepting them, as Escape closes them.
    mutating func forgetOpenSuggestions() {
        openSuggestionsRevision = nil
    }

    /// An accepted suggestion's edits, moved past what was typed since its suggestions were
    /// found; the edits themselves when nothing was. Nil when that typing changed the text
    /// they replace: a link without its `^id`, or a query replaced in the middle of new
    /// text, would corrupt the note.
    mutating func editsMovedPastTyping(_ edits: [MarkdownTextEdit], history: CharacterEditHistory) -> [MarkdownTextEdit]? {
        // The edits belong to the suggestion accepted last: suggestions are accepted one at a
        // time, and one whose edits could not be found leaves an older revision behind,
        // which would move these edits by typing they already account for.
        let baseRevision = acceptedSuggestionRevisions.last
        acceptedSuggestionRevisions.removeAll()
        guard let baseRevision else { return edits }
        var movedEdits: [MarkdownTextEdit] = []
        for edit in edits {
            guard let movedRange = history.replacedRange(edit.range, computedAt: baseRevision) else { return nil }
            let shift = movedRange.location - edit.range.location
            movedEdits.append(MarkdownTextEdit(range: movedRange, replacement: edit.replacement, selectionAfter: edit.selectionAfter.shifted(by: shift)))
        }
        return movedEdits
    }

    /// Why an accepted suggestion's edits were not made.
    static let noteChangedMessage = "The note changed before the suggestion could be inserted. Choose it again."
}

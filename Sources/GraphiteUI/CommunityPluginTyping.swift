import Foundation
import GraphiteCore

/// Suggestions a plugin found at the cursor (`EditorSuggest`), as Graphite's list shows them.
struct CommunityPluginSuggestion: Sendable {
    struct Item: Sendable {
        let position: Int
        let title: String
        let subtitle: String?
    }

    /// Names the suggestions in the runtime, which keeps them until one is chosen.
    let requestIdentifier: String
    let pluginIdentifier: String?
    let items: [Item]
}

/// Typing in a note, for plugins: each change and cursor move of the focused note is sent to
/// the runtime as Obsidian's editor reports it (`editor-change`), and the plugins' typing
/// suggestions at the cursor come back for Graphite's suggestion list. A chosen suggestion
/// is inserted by its plugin through the editor, as one undoable edit.
extension CommunityPluginHost {
    /// Notes longer than this, in UTF-16 code units, are not sent at every change: plugins
    /// get no typing events or suggestions there.
    static let maximumTypingNoteLength = 512 * 1024
    /// How long a plugin may take to answer one change before its suggestions are skipped.
    static let typingTimeout: Duration = .seconds(4)

    /// Sends the focused note as it is now. Returns the change's revision when plugins
    /// suggest as the person types, nil otherwise.
    func editorDidChange(in session: MarkdownSession) -> Int? {
        guard isRuntimeRunning, hasEditorSuggestions || hasEditorChangeListeners, let workspace, workspace.markdownSession === session,
              (session.text as NSString).length <= Self.maximumTypingNoteLength else { return nil }
        lastTypingRevision += 1
        let revision = lastTypingRevision
        let wantsSuggestions = hasEditorSuggestions
        let message: [String: Any] = [
            "operation": "editor.update", "activeDocument": activeDocumentDescription(includingEditor: true),
            "wantsSuggestions": wantsSuggestions, "requestIdentifier": String(revision),
        ]
        let previousAnswer = typingRequest?.answer
        let answer = Task { [weak self] () -> CommunityPluginSuggestion? in
            // In order: a plugin such as Natural Language Dates remembers where its `@` was.
            _ = await previousAnswer?.value
            guard let self, let reply = try? await self.send(message, timeout: Self.typingTimeout),
                  let suggestion = reply["suggestion"] as? [String: Any], let requestIdentifier = suggestion["requestIdentifier"] as? String else { return nil }
            let items = (suggestion["items"] as? [[String: Any]] ?? []).compactMap { item -> CommunityPluginSuggestion.Item? in
                guard let position = item["position"] as? Int, let title = item["title"] as? String else { return nil }
                return CommunityPluginSuggestion.Item(position: position, title: title, subtitle: item["subtitle"] as? String)
            }
            return CommunityPluginSuggestion(requestIdentifier: requestIdentifier, pluginIdentifier: suggestion["pluginIdentifier"] as? String, items: items)
        }
        typingRequest = (revision, answer)
        return wantsSuggestions ? revision : nil
    }

    /// The suggestions plugins answered for a change, as items of Graphite's list; none
    /// once a newer change was sent.
    func suggestionItems(forRevision revision: Int) async -> [CompletionItem] {
        guard let typingRequest, typingRequest.revision == revision, let suggestion = await typingRequest.answer.value else { return [] }
        let pluginName = suggestion.pluginIdentifier.flatMap(pluginName(of:))
        return suggestion.items.map { item in
            CompletionItem(id: suggestion.requestIdentifier + "-" + String(item.position), title: item.title, subtitle: item.subtitle ?? pluginName,
                           systemImage: "puzzlepiece.extension") { [weak self] _ in
                // The plugin makes the edit itself, through the note's editor.
                self?.chooseSuggestion(item, of: suggestion)
                return []
            }
        }
    }

    /// The suggestions were closed without a choice (Escape), so the plugin's suggest closes.
    func closeSuggestions() {
        guard isRuntimeRunning, hasEditorSuggestions else { return }
        Task { _ = try? await send(["operation": "editor.closeSuggestions"], timeout: .seconds(5)) }
    }

    private func chooseSuggestion(_ item: CommunityPluginSuggestion.Item, of suggestion: CommunityPluginSuggestion) {
        Task {
            guard let answer = try? await send(["operation": "editor.chooseSuggestion", "requestIdentifier": suggestion.requestIdentifier, "position": item.position],
                                               timeout: .seconds(5)) else { return }
            if answer["outcome"] as? String == "failed" {
                showNotice("“\(item.title)” could not be inserted: \(answer["message"] as? String ?? "")", pluginIdentifier: suggestion.pluginIdentifier)
            }
        }
    }
}

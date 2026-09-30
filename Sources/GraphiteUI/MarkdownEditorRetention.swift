import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// A note's native editor (its text view and the controller that styles it), which can
/// outlive the SwiftUI view that showed it. The text view owns its undo history, so the
/// history returns with it.
@MainActor
protocol RetainableMarkdownEditor: AnyObject {
    /// The note the editor shows.
    var editedSession: MarkdownSession { get }
    /// The UTF-16 length of the editor's text, which the retention budget counts.
    var retainedTextLength: Int { get }
    /// Tears the editor down for good. Its undo history is lost; the session keeps the
    /// text, cursor, and scroll position.
    func discardRetainedEditor()
}

/// Keeps the native editors of the notes most recently hidden, so switching tabs, moving a
/// tab to the other side, or reading a note and returning to Write keeps undo and redo.
///
/// Memory stays bounded: at most `maximumHiddenEditorCount` hidden editors holding at most
/// `maximumHiddenTextLength` UTF-16 units together, and none after a memory warning. An
/// editor let go of this way loses its undo history, as every hidden editor did before.
/// Editors on screen are tracked but never counted or discarded here.
@MainActor
final class MarkdownEditorRetention {
    struct Limits: Equatable {
        var maximumHiddenEditorCount: Int
        var maximumHiddenTextLength: Int
    }

    /// Three hidden notes cover switching between a few tabs and both sides of a split.
    static let standardLimits = Limits(maximumHiddenEditorCount: 3, maximumHiddenTextLength: 2_000_000)

    private struct HiddenEditor {
        /// The tab the editor belongs to. The editor is stale once the tab is closed or
        /// shows another file.
        weak var owner: TabDocument?
        let editor: any RetainableMarkdownEditor
    }

    let limits: Limits
    /// Least recently hidden first.
    private var hiddenEditors: [HiddenEditor] = []
    /// Editors on screen, by the identity of their session, so a view that shows the same
    /// note again (a tab moved to the other side) takes the editor over before the old
    /// view is dismantled.
    private var attachedEditors: [ObjectIdentifier: WeakEditor] = [:]
    #if canImport(UIKit)
    private var memoryWarningObserver: NSObjectProtocol?
    #endif

    private final class WeakEditor {
        weak var editor: (any RetainableMarkdownEditor)?
        init(_ editor: any RetainableMarkdownEditor) { self.editor = editor }
    }

    init(limits: Limits = MarkdownEditorRetention.standardLimits) {
        self.limits = limits
        #if canImport(UIKit)
        memoryWarningObserver = NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification,
                                                                       object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.discardHiddenEditors() }
        }
        #endif
    }

    isolated deinit {
        #if canImport(UIKit)
        if let memoryWarningObserver { NotificationCenter.default.removeObserver(memoryWarningObserver) }
        #endif
    }

    var hiddenEditorCount: Int { hiddenEditors.count }

    /// Whether an editor for this note is kept off screen.
    func hasHiddenEditor(for session: MarkdownSession) -> Bool {
        hiddenEditors.contains { hidden in hidden.editor.editedSession === session }
    }

    /// The editor to show `session` with: the one on screen for it, which moves to the new
    /// view, or the one kept since it was hidden. Nil when neither exists, or when the tab
    /// no longer shows that note.
    func takeEditor(for session: MarkdownSession, owner: TabDocument) -> (any RetainableMarkdownEditor)? {
        discardStaleEditors()
        guard owner.markdownSession === session else { return nil }
        if let attached = attachedEditors[ObjectIdentifier(session)]?.editor { return attached }
        guard let position = hiddenEditors.lastIndex(where: { hidden in hidden.editor.editedSession === session }) else { return nil }
        return hiddenEditors.remove(at: position).editor
    }

    /// Records that an editor is on screen.
    func editorDidAttach(_ editor: any RetainableMarkdownEditor) {
        attachedEditors[ObjectIdentifier(editor.editedSession)] = WeakEditor(editor)
        // A second editor of one note can exist only when a view was created before the
        // old one was dismantled and could not take it over; the older one goes.
        discardHiddenEditors { hidden in hidden.editor.editedSession === editor.editedSession && hidden.editor !== editor }
    }

    /// Keeps an editor whose view left the screen, discarding the least recently hidden
    /// ones beyond the limits. Returns false, and keeps nothing, when the editor cannot be
    /// kept (its tab closed, or its note alone is over the budget); the caller then tears
    /// it down.
    @discardableResult
    func keepHiddenEditor(_ editor: any RetainableMarkdownEditor, owner: TabDocument?) -> Bool {
        let sessionIdentifier = ObjectIdentifier(editor.editedSession)
        if attachedEditors[sessionIdentifier]?.editor === editor { attachedEditors[sessionIdentifier] = nil }
        guard let owner, owner.markdownSession === editor.editedSession,
              limits.maximumHiddenEditorCount > 0, editor.retainedTextLength <= limits.maximumHiddenTextLength else { return false }
        discardHiddenEditors { hidden in hidden.editor.editedSession === editor.editedSession }
        hiddenEditors.append(HiddenEditor(owner: owner, editor: editor))
        discardStaleEditors()
        while hiddenEditors.count > limits.maximumHiddenEditorCount || hiddenTextLength > limits.maximumHiddenTextLength {
            hiddenEditors.removeFirst().editor.discardRetainedEditor()
        }
        return true
    }

    /// Lets go of every hidden editor whose tab closed or shows another file.
    func discardStaleEditors() {
        discardHiddenEditors { hidden in hidden.owner?.markdownSession !== hidden.editor.editedSession }
        attachedEditors = attachedEditors.filter { _, attached in attached.editor != nil }
    }

    /// Lets go of every hidden editor, as on a memory warning or when another vault opens.
    func discardHiddenEditors() {
        discardHiddenEditors { _ in true }
    }

    private var hiddenTextLength: Int {
        hiddenEditors.reduce(0) { total, hidden in total + hidden.editor.retainedTextLength }
    }

    private func discardHiddenEditors(where shouldDiscard: (HiddenEditor) -> Bool) {
        let discarded = hiddenEditors.filter(shouldDiscard)
        guard !discarded.isEmpty else { return }
        hiddenEditors.removeAll(where: shouldDiscard)
        for hidden in discarded { hidden.editor.discardRetainedEditor() }
    }
}

/// The containers of the SwiftUI views that show one note's editor, oldest first. SwiftUI
/// makes a note's new view before it dismantles the old one, and can dismantle a view it
/// has only just made, so which view stays is known only as the others are dismantled.
struct EditorContainersInUse<Container: AnyObject> {
    private struct Reference {
        weak var container: Container?
    }

    private var references: [Reference] = []

    /// The container of the newest view that has not been dismantled.
    var newest: Container? {
        references.reversed().lazy.compactMap(\.container).first
    }

    func contains(where isMatch: (Container) -> Bool) -> Bool {
        references.contains { reference in reference.container.map(isMatch) ?? false }
    }

    mutating func add(_ container: Container) {
        remove(container)
        references.append(Reference(container: container))
    }

    /// Forgets a dismantled view's container, and any that were released without being
    /// dismantled.
    mutating func remove(_ container: Container) {
        references.removeAll { reference in reference.container == nil || reference.container === container }
    }
}

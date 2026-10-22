import Foundation
import GraphiteCore

/// What a note's pane holds for the note it shows: its open pickers and confirmation, the
/// reading start and section Read Aloud was asked for, and the drawing or image at the
/// cursor. The pane stays when its tab shows another note, and then replaces this whole value,
/// so nothing of one note carries over to the next.
struct MarkdownPaneNoteState {
    var showsAttachmentPicker = false
    var showsPhotoPicker = false
    var showsCamera = false
    var showsDocumentScanner = false
    var showsLinkPicker = false
    var showsReloadConfirmation = false
    var readingStartOffset: Int?
    var showsReadingSections = false
    var pendingReadingSection: (section: ReadAloudSection, source: String)?
    /// An editable drawing embedded where the cursor is, if any.
    var drawingAtCursor: VaultPath?
    /// An image embedded where the cursor is that can be drawn on, if any.
    var imageAtCursor: VaultPath?
}

extension MarkdownPaneNoteState {
    /// Whether the pane's note is shown in the reading view while Read Aloud is on, keyed by
    /// the note, so the pane points Read Aloud at the reading view again when it shows another note.
    struct ReadingWithNavigatorKey: Equatable {
        let note: ObjectIdentifier
        let isReadingWithNavigator: Bool
    }
}

import SwiftUI
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

#if canImport(UIKit)
typealias PlatformCellField = TableCellTextView
#else
typealias PlatformCellField = TableCellMacTextField
#endif

/// A key a table cell's editor gives the table: Return, Tab and the others move between cells.
enum TableCellKey {
    case returnKey, tab, backtab, escape, upArrow, downArrow
}

/// The text field of a Live Preview table's cell editor: a native text view, so the table
/// decides what Return, Tab, Shift-Tab, Escape and the arrow keys do. SwiftUI's text field
/// treated a hardware Return as submitting and gave up the keyboard on the iPad, so text typed
/// right after Return was lost. Shift-Return (Option-Return on the Mac too) puts a line break
/// in the cell. Smart dashes and quotes are off, as in the note's editor: a cell's `--` and
/// quotes are Markdown.
struct TableCellTextField {
    /// The cell editor that has the keyboard, in any table.
    @MainActor private static weak var focusedField: PlatformCellField?

    /// Takes the keyboard from another table's cell editor at once, as a tap opens this one:
    /// keys typed before this table's field takes the keyboard went into that cell's text.
    @MainActor static func endEditingInOtherTables() {
        guard let focusedField else { return }
        #if canImport(UIKit)
        focusedField.resignFirstResponder()
        #else
        if let window = focusedField.window, focusedField.currentEditor() != nil { window.makeFirstResponder(nil) }
        #endif
    }

    @Binding var text: String
    let font: PlatformFont
    /// Takes the keyboard each time this changes.
    let focusRequest: Int
    /// Whether the table took the key; one it did not take is typed as usual.
    let handleKey: (TableCellKey) -> Bool
    let focusDidChange: (_ isFocused: Bool) -> Void
}

#if canImport(UIKit)
extension TableCellTextField: UIViewRepresentable {
    final class Coordinator: NSObject, UITextViewDelegate {
        var field: TableCellTextField
        var appliedFocusRequest = 0

        init(field: TableCellTextField) {
            self.field = field
        }

        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText replacement: String) -> Bool {
            guard replacement == "\n", let cellTextView = textView as? TableCellTextView, !cellTextView.isInsertingLineBreak else { return true }
            return !cellTextView.perform(.returnKey)
        }

        func textViewDidChange(_ textView: UITextView) {
            // Text an input method is still composing is not the cell's yet.
            guard textView.markedTextRange == nil, field.text != textView.text else { return }
            field.text = textView.text
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            TableCellTextField.focusedField = textView as? TableCellTextView
            field.focusDidChange(true)
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            if TableCellTextField.focusedField === textView { TableCellTextField.focusedField = nil }
            field.focusDidChange(false)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(field: self) }

    func makeUIView(context: Context) -> TableCellTextView {
        let textView = TableCellTextView()
        textView.isScrollEnabled = false
        textView.backgroundColor = .clear
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.smartDashesType = .no
        textView.smartQuotesType = .no
        textView.delegate = context.coordinator
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return textView
    }

    func updateUIView(_ textView: TableCellTextView, context: Context) {
        context.coordinator.field = self
        textView.handleKey = handleKey
        textView.currentText = { [text = _text] in text.wrappedValue }
        if textView.font != font { textView.font = font }
        if textView.text != text, textView.markedTextRange == nil {
            textView.showCellText(text)
        }
        guard context.coordinator.appliedFocusRequest != focusRequest else { return }
        context.coordinator.appliedFocusRequest = focusRequest
        // Not during the view update, which a change of first responder would re-enter.
        DispatchQueue.main.async { [weak textView] in
            guard let textView, !textView.isFirstResponder else { return }
            textView.becomeFirstResponder()
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView textView: TableCellTextView, context: Context) -> CGSize? {
        let width = proposal.width ?? textView.bounds.width
        let fittingSize = textView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: ceil(fittingSize.height))
    }
}

/// The cell editor's text view, with the keys the table moves by.
final class TableCellTextView: UITextView {
    var handleKey: ((TableCellKey) -> Bool)?
    /// The draft as the table has it now, read at once after a key moved the editor.
    var currentText: (() -> String)?
    /// Undo within the cell being edited: the note's own history holds each written cell, and
    /// typing undone after a move to another cell must not apply to that cell's text.
    private let cellUndoManager = UndoManager()

    override var undoManager: UndoManager? { cellUndoManager }

    /// Shows another cell's text with the cursor at its end, and forgets the typing undo of
    /// the cell before.
    func showCellText(_ cellText: String) {
        cellUndoManager.removeAllActions()
        text = cellText
        selectedRange = NSRange(location: (cellText as NSString).length, length: 0)
    }
    /// While Shift-Return inserts its line break, which Return's check lets through.
    private(set) var isInsertingLineBreak = false

    override var keyCommands: [UIKeyCommand]? {
        let commands = [
            UIKeyCommand(input: "\t", modifierFlags: [], action: #selector(tabKey)),
            UIKeyCommand(input: "\t", modifierFlags: .shift, action: #selector(backtabKey)),
            UIKeyCommand(input: UIKeyCommand.inputEscape, modifierFlags: [], action: #selector(escapeKey)),
            UIKeyCommand(input: UIKeyCommand.inputUpArrow, modifierFlags: [], action: #selector(upArrowKey)),
            UIKeyCommand(input: UIKeyCommand.inputDownArrow, modifierFlags: [], action: #selector(downArrowKey)),
            UIKeyCommand(input: "\r", modifierFlags: .shift, action: #selector(lineBreakKey)),
        ]
        for command in commands { command.wantsPriorityOverSystemBehavior = true }
        return commands
    }

    /// Gives the key to the table and, when it moved the editor, shows the new cell's text
    /// at once: keys typed before SwiftUI's next update would otherwise go into the old cell's
    /// text and be written into the new cell.
    func perform(_ key: TableCellKey) -> Bool {
        guard handleKey?(key) == true else { return false }
        if let newText = currentText?(), newText != text { showCellText(newText) }
        return true
    }

    @objc private func tabKey() { _ = perform(.tab) }
    @objc private func backtabKey() { _ = perform(.backtab) }
    @objc private func escapeKey() { _ = perform(.escape) }

    /// The arrows leave the cell only while it is one line; within a cell of several lines
    /// they move the cursor.
    @objc private func upArrowKey() {
        if !perform(.upArrow) { moveCursorByLine(upward: true) }
    }

    @objc private func downArrowKey() {
        if !perform(.downArrow) { moveCursorByLine(upward: false) }
    }

    private func moveCursorByLine(upward: Bool) {
        guard let selected = selectedTextRange,
              let position = position(from: upward ? selected.start : selected.end, in: upward ? .up : .down, offset: 1) else { return }
        selectedTextRange = textRange(from: position, to: position)
    }

    @objc private func lineBreakKey() {
        isInsertingLineBreak = true
        insertText("\n")
        isInsertingLineBreak = false
    }
}
#else
extension TableCellTextField: NSViewRepresentable {
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var field: TableCellTextField
        var appliedFocusRequest = 0

        init(field: TableCellTextField) {
            self.field = field
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            let key: TableCellKey
            switch commandSelector {
            case #selector(NSResponder.insertNewline(_:)): key = .returnKey
            case #selector(NSResponder.insertTab(_:)): key = .tab
            case #selector(NSResponder.insertBacktab(_:)): key = .backtab
            case #selector(NSResponder.cancelOperation(_:)): key = .escape
            case #selector(NSResponder.moveUp(_:)): key = .upArrow
            case #selector(NSResponder.moveDown(_:)): key = .downArrow
            case #selector(NSResponder.insertLineBreak(_:)), #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)):
                textView.insertNewlineIgnoringFieldEditor(nil)
                return true
            default: return false
            }
            guard field.handleKey(key) else { return false }
            // The new cell's text at once, so keys typed before SwiftUI's next update go into it.
            if textView.string != field.text {
                (control as? TableCellMacTextField)?.cellUndoManager.removeAllActions()
                textView.string = field.text
                textView.selectedRange = NSRange(location: (field.text as NSString).length, length: 0)
            }
            return true
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let textField = notification.object as? NSTextField else { return }
            // Text an input method is still composing is not the cell's yet.
            if (textField.currentEditor() as? NSTextView)?.hasMarkedText() == true { return }
            guard field.text != textField.stringValue else { return }
            field.text = textField.stringValue
        }

        func controlTextDidBeginEditing(_ notification: Notification) {
            (notification.userInfo?["NSFieldEditor"] as? NSTextView)?.turnOffSubstitutionsForMarkdown()
            TableCellTextField.focusedField = notification.object as? TableCellMacTextField
            field.focusDidChange(true)
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            if TableCellTextField.focusedField === notification.object as AnyObject { TableCellTextField.focusedField = nil }
            field.focusDidChange(false)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(field: self) }

    func makeNSView(context: Context) -> TableCellMacTextField {
        let textField = TableCellMacTextField(string: text)
        textField.isBordered = false
        textField.drawsBackground = false
        textField.focusRingType = .none
        textField.usesSingleLineMode = false
        textField.lineBreakMode = .byWordWrapping
        textField.maximumNumberOfLines = 0
        textField.cell?.wraps = true
        textField.cell?.isScrollable = false
        textField.delegate = context.coordinator
        textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return textField
    }

    func updateNSView(_ textField: TableCellMacTextField, context: Context) {
        context.coordinator.field = self
        if textField.font != font { textField.font = font }
        if textField.stringValue != text, (textField.currentEditor() as? NSTextView)?.hasMarkedText() != true {
            textField.cellUndoManager.removeAllActions()
            textField.stringValue = text
            textField.currentEditor()?.selectedRange = NSRange(location: (text as NSString).length, length: 0)
        }
        guard context.coordinator.appliedFocusRequest != focusRequest else { return }
        context.coordinator.appliedFocusRequest = focusRequest
        DispatchQueue.main.async { [weak textField] in
            guard let textField, let window = textField.window, textField.currentEditor() == nil else { return }
            window.makeFirstResponder(textField)
            // AppKit reports the beginning of editing only at the first change.
            if textField.currentEditor() != nil { TableCellTextField.focusedField = textField }
            // The field editor is shared by the window's fields; a cell's `--` stays as typed.
            (textField.currentEditor() as? NSTextView)?.turnOffSubstitutionsForMarkdown()
            textField.currentEditor()?.selectedRange = NSRange(location: (textField.stringValue as NSString).length, length: 0)
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView textField: TableCellMacTextField, context: Context) -> CGSize? {
        let width = proposal.width ?? textField.bounds.width
        textField.preferredMaxLayoutWidth = width
        let height = textField.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: width, height: .greatestFiniteMagnitude)).height ?? textField.intrinsicContentSize.height
        return CGSize(width: width, height: ceil(height))
    }
}

/// The cell editor's field on the Mac, with an undo history of its own: the window's field
/// editor would apply typing undone after a move to another cell to that cell's text.
final class TableCellMacTextField: NSTextField {
    let cellUndoManager = UndoManager()

    /// Asked by the field editor, whose delegate the field is while it edits.
    @objc(undoManagerForTextView:)
    func undoManager(for textView: NSTextView) -> UndoManager? { cellUndoManager }
}

private extension NSTextView {
    func turnOffSubstitutionsForMarkdown() {
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticTextReplacementEnabled = false
    }
}
#endif

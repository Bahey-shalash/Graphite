import Foundation
import GraphiteCore
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// What the note editor's context menu (the Mac's right-click menu, the iPad's edit menu)
/// asks of the pane that shows the note. Every edit goes through the pane's session, as the
/// toolbar's Format menu does, so undo and the selection afterwards behave the same.
struct EditorContextMenuActions {
    /// Runs a toolbar command on the note.
    let run: (EditorCommand) -> Void
    /// The note's text and selection as they are when asked: when a menu opens, and again when
    /// an item is chosen.
    let noteState: () -> (text: NSString, selection: NSRange)
    /// Applies an edit computed on `noteState`, so it can be undone.
    let apply: (MarkdownTextEdit) -> Void
    /// Inserts a block on lines of its own, after the selection, which stays in the note.
    let insertBlock: (String) -> Void
    /// The vault's palette; nil while the Colors feature is off, which has no Color menu.
    let colors: [PaletteColor]?
    /// Wraps the selection in Obsidian's Colors syntax `~={hex}text=~`; the placeholder
    /// stands in for the text when nothing is selected.
    let insertColor: (_ hexColor: String, _ placeholder: String) -> Void
    /// Opens the picker for a link to a note.
    let linkToNote: () -> Void
    /// Opens the template picker; nil while templates are unavailable.
    let template: (() -> Void)?
}

/// One entry of the editor's context menu, described apart from the platform's menu classes
/// so the Mac and the iPad show the same items.
struct EditorContextMenuEntry {
    enum Content {
        case action(isEnabled: Bool, perform: () -> Void)
        case submenu([EditorContextMenuEntry])
        /// Entries set apart from their neighbors by a separator (a Mac menu) or an inline
        /// section (an iPad menu).
        case group([EditorContextMenuEntry])
    }

    let title: String
    let systemImage: String?
    let content: Content

    static func action(_ title: String, _ systemImage: String? = nil, isEnabled: Bool = true, perform: @escaping () -> Void) -> EditorContextMenuEntry {
        EditorContextMenuEntry(title: title, systemImage: systemImage, content: .action(isEnabled: isEnabled, perform: perform))
    }

    static func submenu(_ title: String, _ systemImage: String, _ entries: [EditorContextMenuEntry]) -> EditorContextMenuEntry {
        EditorContextMenuEntry(title: title, systemImage: systemImage, content: .submenu(entries))
    }

    static func group(_ entries: [EditorContextMenuEntry]) -> EditorContextMenuEntry {
        EditorContextMenuEntry(title: "", systemImage: nil, content: .group(entries))
    }
}

/// The items of Obsidian's editor context menu that Graphite offers, in Obsidian's order:
/// links, then the Color, Format, Paragraph and Insert submenus. Titles and symbols are the
/// toolbar's. The entries are built when a menu opens, never while typing.
///
/// Left out, because Graphite has no working command for them: Search for the selection and
/// Format › Clear Formatting. Color › Custom… is left out too: the Mac's color panel reports
/// every change while a color is dragged and never that the person has chosen, so it would
/// rewrite the note at each change; the menus keep to the same items on both platforms.
enum EditorContextMenuContent {
    /// The blocks the toolbar's Format menu and this menu insert.
    static let tableBlock = "| Column | Column |\n| --- | --- |\n|  |  |"
    static let mathBlock = "$$\n\n$$"
    static let calloutBlock = "> [!note]\n> "
    static let codeBlock = "```\n\n```"
    static let horizontalRule = "---"

    static func entries(actions: EditorContextMenuActions, editorActions: EditorActions) -> [EditorContextMenuEntry] {
        var submenus: [EditorContextMenuEntry] = []
        if let colors = actions.colors { submenus.append(colorMenu(colors: colors, actions: actions)) }
        submenus.append(formatMenu(actions: actions))
        submenus.append(paragraphMenu(actions: actions))
        submenus.append(insertMenu(actions: actions, editorActions: editorActions))
        return [
            .group([
                .action("Add Link", "link") { actions.run(.insertWikilink) },
                .action("Add External Link", "link.badge.plus") { actions.run(.insertMarkdownLink) },
            ]),
            .group(submenus),
        ]
    }

    private static func colorMenu(colors: [PaletteColor], actions: EditorContextMenuActions) -> EditorContextMenuEntry {
        let paletteHexByName = Dictionary(colors.map { color in (color.name, color.hex) }, uniquingKeysWith: { firstHex, _ in firstHex })
        let noteState = actions.noteState()
        let canRemoveColor = TextColorMarkup.removingColor(in: noteState.text, selection: noteState.selection, paletteHexByName: paletteHexByName) != nil
        let colorEntries: [EditorContextMenuEntry] = colors.map { color in
            .action(color.name) { actions.insertColor(color.hex, color.name) }
        }
        let removeEntry = EditorContextMenuEntry.action("Remove", "xmark.circle", isEnabled: canRemoveColor) {
            applying(actions) { text, selection in
                TextColorMarkup.removingColor(in: text, selection: selection, paletteHexByName: paletteHexByName)
            }
        }
        return .submenu("Color", "paintpalette", [.group(colorEntries), .group([removeEntry])])
    }

    private static func formatMenu(actions: EditorContextMenuActions) -> EditorContextMenuEntry {
        .submenu("Format", "textformat", [
            .action("Bold", "bold") { actions.run(.bold) },
            .action("Italic", "italic") { actions.run(.italic) },
            .action("Strikethrough", "strikethrough") { actions.run(.strikethrough) },
            .action("Highlight", "highlighter") { actions.run(.highlight) },
            .action("Code", "chevron.left.forwardslash.chevron.right") { actions.run(.code) },
            .action("Inline Math", "function") { actions.run(.math) },
            .action("Comment", "eye.slash") { actions.run(.comment) },
        ])
    }

    private static func paragraphMenu(actions: EditorContextMenuActions) -> EditorContextMenuEntry {
        var headingEntries: [EditorContextMenuEntry] = (1...6).map { level in
            .action("Heading \(level)") { actions.run(.heading(level)) }
        }
        headingEntries.append(.action("Body", "text.alignleft") { applying(actions, ParagraphEditing.removingHeadingMarks) })
        return .submenu("Paragraph", "paragraph", [
            .group([
                .action("Bulleted List", "list.bullet") { actions.run(.bulletList) },
                .action("Numbered List", "list.number") { actions.run(.numberedList) },
                .action("Task", "checklist") { actions.run(.task) },
            ]),
            .group(headingEntries),
            .group([
                .action("Quote", "text.quote") { applying(actions, ParagraphEditing.togglingQuote) },
            ]),
        ])
    }

    private static func insertMenu(actions: EditorContextMenuActions, editorActions: EditorActions) -> EditorContextMenuEntry {
        let blockEntries: [EditorContextMenuEntry] = [
            .action("Table", "tablecells") { actions.insertBlock(tableBlock) },
            .action("Callout", "text.bubble") { actions.insertBlock(calloutBlock) },
            .action("Code Block", "curlybraces") { actions.insertBlock(codeBlock) },
            .action("Math Block", "function") { actions.insertBlock(mathBlock) },
            .action("Horizontal Rule", "minus") { actions.insertBlock(horizontalRule) },
            .action("Tag", "number") { actions.run(.insertTag) },
        ]
        var attachmentEntries: [EditorContextMenuEntry] = [
            .action("Link to Note…", "link") { actions.linkToNote() },
        ]
        if let choosePhoto = editorActions.choosePhoto { attachmentEntries.append(.action("Photo Library…", "photo.on.rectangle") { choosePhoto() }) }
        if let takePhoto = editorActions.takePhoto { attachmentEntries.append(.action("Take Photo…", "camera") { takePhoto() }) }
        if let scanDocument = editorActions.scanDocument { attachmentEntries.append(.action("Scan Document…", "doc.viewfinder") { scanDocument() }) }
        if let attach = editorActions.attach { attachmentEntries.append(.action("Attachment…", "doc.badge.plus") { attach() }) }
        if let draw = editorActions.draw { attachmentEntries.append(.action("Draw", "pencil.tip.crop.circle.badge.plus") { draw() }) }
        if let template = actions.template { attachmentEntries.append(.action("Template…", "doc.on.doc") { template() }) }
        return .submenu("Insert", "paperclip", [.group(blockEntries), .group(attachmentEntries)])
    }

    /// Computes an edit on the note as it is when the item is chosen, and applies it.
    private static func applying(_ actions: EditorContextMenuActions, _ makeEdit: (_ text: NSString, _ selection: NSRange) -> MarkdownTextEdit?) {
        let noteState = actions.noteState()
        guard let edit = makeEdit(noteState.text, noteState.selection) else { return }
        actions.apply(edit)
    }
}

/// Paragraph changes `MarkdownEditing` has no command for. Like its commands, each returns
/// one edit that changes only the selected lines and keeps the selection on the same text.
enum ParagraphEditing {
    /// One replacement inside a line, in UTF-16 offsets of the line without its line ending.
    private struct LineChange {
        let range: NSRange
        let replacement: String
    }

    private static let headingMarksPattern = ParagraphEditingPattern.headingMarksPattern.compiled()
    private static let quoteMarkPattern = ParagraphEditingPattern.quoteMarkPattern.compiled()

    /// Makes the selected heading lines plain paragraphs (Obsidian's Body); other lines stay
    /// as they are. Nil when no selected line is a heading.
    static func removingHeadingMarks(in text: NSString, selection: NSRange) -> MarkdownTextEdit? {
        rewritingLines(in: text, selection: selection) { line, _ in
            markRemoval(of: headingMarksPattern, in: line)
        }
    }

    /// Puts the selected lines in a quote, or takes them out when every one already is in one.
    /// A blank line between selected paragraphs stays blank, so each paragraph is its own quote.
    static func togglingQuote(in text: NSString, selection: NSRange) -> MarkdownTextEdit? {
        let selectedLines = lines(in: lineRange(covering: selection, in: text), of: text)
        let nonBlankLines = selectedLines.filter { line in !isBlank(line.content) }
        let removes = !nonBlankLines.isEmpty && nonBlankLines.allSatisfy { line in markRemoval(of: quoteMarkPattern, in: line.content) != nil }
        return rewritingLines(in: text, selection: selection) { line, lineCount in
            // A lone empty line becomes an empty quote, which the cursor can then type into.
            if isBlank(line), lineCount > 1 { return nil }
            if removes { return markRemoval(of: quoteMarkPattern, in: line) }
            return LineChange(range: NSRange(location: 0, length: 0), replacement: "> ")
        }
    }

    /// The change that removes a line's leading marks, keeping the indentation before them.
    private static func markRemoval(of pattern: NSRegularExpression, in line: String) -> LineChange? {
        guard let match = pattern.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)) else { return nil }
        let indentationLength = match.range(at: 1).length
        return LineChange(range: NSRange(location: indentationLength, length: match.range.length - indentationLength), replacement: "")
    }

    private static func isBlank(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Applies `change` to each selected line; nil leaves a line as it is. The closure also
    /// gets how many lines are selected. Nil when no line changes.
    private static func rewritingLines(in text: NSString, selection: NSRange, change: (_ line: String, _ lineCount: Int) -> LineChange?) -> MarkdownTextEdit? {
        let linesRange = lineRange(covering: selection, in: text)
        let selectedLines = lines(in: linesRange, of: text)
        var changes: [LineChange] = []
        for line in selectedLines {
            guard let lineChange = change(line.content, selectedLines.count) else { continue }
            changes.append(LineChange(range: NSRange(location: line.location - linesRange.location + lineChange.range.location, length: lineChange.range.length),
                                      replacement: lineChange.replacement))
        }
        guard !changes.isEmpty else { return nil }
        let rewrittenLines = NSMutableString(string: text.substring(with: linesRange))
        for lineChange in changes.reversed() {
            rewrittenLines.replaceCharacters(in: lineChange.range, with: lineChange.replacement)
        }
        /// Where a position of the text lands after the changes; inside removed marks it lands
        /// after what replaced them, and an insertion at it pushes it along.
        func positionAfterChanges(_ position: Int) -> Int {
            var shift = 0
            for lineChange in changes {
                let changeEnd = linesRange.location + NSMaxRange(lineChange.range)
                let changeStart = linesRange.location + lineChange.range.location
                if position >= changeEnd {
                    shift += lineChange.replacement.utf16.count - lineChange.range.length
                } else if position > changeStart {
                    return changeStart + shift + lineChange.replacement.utf16.count
                } else {
                    break
                }
            }
            return position + shift
        }
        let clampedStart = min(max(selection.location, linesRange.location), NSMaxRange(linesRange))
        let clampedEnd = min(max(NSMaxRange(selection), clampedStart), NSMaxRange(linesRange))
        let selectionStart = positionAfterChanges(clampedStart)
        let selectionEnd = positionAfterChanges(clampedEnd)
        return MarkdownTextEdit(range: linesRange, replacement: rewrittenLines as String,
                                selectionAfter: NSRange(location: selectionStart, length: selection.length == 0 ? 0 : max(0, selectionEnd - selectionStart)))
    }

    /// The whole lines the selection touches; a selection that ends just after a line break
    /// does not include the next line.
    private static func lineRange(covering selection: NSRange, in text: NSString) -> NSRange {
        let location = min(max(selection.location, 0), text.length)
        var end = min(max(NSMaxRange(selection), location), text.length)
        if end > location, isLineBreak(text.character(at: end - 1)) { end -= 1 }
        return text.lineRange(for: NSRange(location: location, length: end - location))
    }

    /// The lines of a range of whole lines, each with where it starts; an empty range, such as
    /// the end of a note that ends with a line break, is one empty line.
    private static func lines(in linesRange: NSRange, of text: NSString) -> [(location: Int, content: String)] {
        var selectedLines: [(location: Int, content: String)] = []
        var lineStart = linesRange.location
        while lineStart < NSMaxRange(linesRange) {
            var lineEnd = 0
            var contentsEnd = 0
            text.getLineStart(nil, end: &lineEnd, contentsEnd: &contentsEnd, for: NSRange(location: lineStart, length: 0))
            selectedLines.append((lineStart, text.substring(with: NSRange(location: lineStart, length: contentsEnd - lineStart))))
            lineStart = lineEnd
        }
        if selectedLines.isEmpty { selectedLines.append((linesRange.location, "")) }
        return selectedLines
    }

    /// The UTF-16 units that end a line for NSString.
    private static func isLineBreak(_ unit: unichar) -> Bool {
        unit == 10 || unit == 13 || unit == 0x85 || unit == 0x2028 || unit == 0x2029
    }
}

#if canImport(UIKit)
extension EditorContextMenuContent {
    /// The entries as the edit menu shows them: submenus open a second level, and groups
    /// are sections.
    @MainActor
    static func menuElements(actions: EditorContextMenuActions, editorActions: EditorActions) -> [UIMenuElement] {
        entries(actions: actions, editorActions: editorActions).map { entry in entry.menuElement() }
    }
}

private extension EditorContextMenuEntry {
    @MainActor
    func menuElement() -> UIMenuElement {
        let image = systemImage.flatMap { name in UIImage(systemName: name) }
        switch content {
        case .action(let isEnabled, let perform):
            return UIAction(title: title, image: image, attributes: isEnabled ? [] : .disabled) { _ in perform() }
        case .submenu(let entries):
            return UIMenu(title: title, image: image, children: entries.map { entry in entry.menuElement() })
        case .group(let entries):
            return UIMenu(title: "", options: .displayInline, children: entries.map { entry in entry.menuElement() })
        }
    }
}
#elseif canImport(AppKit)
/// A menu item that runs a closure. A menu item holds its target weakly, so it is its own.
private final class EditorContextMenuActionItem: NSMenuItem, NSMenuItemValidation {
    private let perform: () -> Void
    /// Kept apart from `isEnabled`: a menu that enables its items automatically asks the
    /// target, and would otherwise enable every item.
    private let isActionEnabled: Bool

    init(title: String, isEnabled: Bool, perform: @escaping () -> Void) {
        self.perform = perform
        isActionEnabled = isEnabled
        super.init(title: title, action: #selector(EditorContextMenuActionItem.performAction), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) {
        perform = {}
        isActionEnabled = false
        super.init(coder: coder)
    }

    @objc private func performAction() { perform() }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool { isActionEnabled }
}

extension NSMenu {
    /// Puts Graphite's items first in the editor's context menu, with a separator before the
    /// system's items as in Obsidian, and takes out the system's Font submenu: it changes the
    /// font of text that is plain Markdown, which does nothing useful.
    func insertEditorContextMenuEntries(_ entries: [EditorContextMenuEntry]) {
        removeFontSubmenu()
        let editorItems = Self.menuItems(for: entries)
        guard !editorItems.isEmpty else { return }
        for (position, item) in editorItems.enumerated() { insertItem(item, at: position) }
        insertItem(.separator(), at: editorItems.count)
    }

    /// The Font submenu is the one with the font panel (or boldface or underline) in it, found
    /// by its actions because its title is translated. Left alone when not found.
    private func removeFontSubmenu() {
        let fontActions = ["orderFrontFontPanel:", "toggleBoldface:", "underline:"].map { name in NSSelectorFromString(name) }
        for item in items {
            guard let submenu = item.submenu,
                  submenu.items.contains(where: { subitem in subitem.action.map { action in fontActions.contains(action) } ?? false }) else { continue }
            removeItem(item)
        }
    }

    private static func menuItems(for entries: [EditorContextMenuEntry]) -> [NSMenuItem] {
        var items: [NSMenuItem] = []
        for entry in entries {
            if case .group(let groupEntries) = entry.content {
                let groupItems = menuItems(for: groupEntries)
                guard !groupItems.isEmpty else { continue }
                if !items.isEmpty { items.append(.separator()) }
                items.append(contentsOf: groupItems)
                continue
            }
            items.append(menuItem(for: entry))
        }
        return items
    }

    private static func menuItem(for entry: EditorContextMenuEntry) -> NSMenuItem {
        let item: NSMenuItem
        switch entry.content {
        case .action(let isEnabled, let perform):
            item = EditorContextMenuActionItem(title: entry.title, isEnabled: isEnabled, perform: perform)
        case .submenu(let entries):
            item = NSMenuItem(title: entry.title, action: nil, keyEquivalent: "")
            let submenu = NSMenu(title: entry.title)
            for childItem in menuItems(for: entries) { submenu.addItem(childItem) }
            item.submenu = submenu
        case .group:
            // Groups are flattened by `menuItems(for:)`; one never reaches here.
            item = NSMenuItem()
        }
        if let systemImage = entry.systemImage { item.image = NSImage(systemSymbolName: systemImage, accessibilityDescription: entry.title) }
        return item
    }
}
#endif

/// The constant patterns of `ParagraphEditing`; `StaticPatternTests` compiles every case.
enum ParagraphEditingPattern: String, StaticPatternSet {
    case headingMarksPattern = #"^( {0,3})#{1,6}(?:[ \t]+|$)"#
    case quoteMarkPattern = "^( {0,3})> ?"
}

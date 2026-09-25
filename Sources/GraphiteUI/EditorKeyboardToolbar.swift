import SwiftUI
import GraphiteCore

/// Commands the editor's toolbar, menus, and keyboard shortcuts run on the note.
enum EditorCommand {
    case undo, redo
    case heading(Int)
    /// Wraps the selection or word in the markers, or removes them.
    case wrap(opening: String, closing: String)
    case bulletList, numberedList, task
    case indent, outdent
    case moveLinesUp, moveLinesDown
    case insertWikilink, insertTag, insertMarkdownLink
    case attach, draw
    case find, findAndReplace
    case dismissKeyboard
    /// Follows the link at the cursor: here, in a new tab, or on the other side.
    case followLink(TabPlacement)

    static let bold = EditorCommand.wrap(opening: "**", closing: "**")
    static let italic = EditorCommand.wrap(opening: "*", closing: "*")
    static let strikethrough = EditorCommand.wrap(opening: "~~", closing: "~~")
    static let highlight = EditorCommand.wrap(opening: "==", closing: "==")
    static let code = EditorCommand.wrap(opening: "`", closing: "`")
    static let math = EditorCommand.wrap(opening: "$", closing: "$")
    /// Obsidian's comment, hidden in reading view.
    static let comment = EditorCommand.wrap(opening: "%%", closing: "%%")
}

/// Actions only the surrounding pane can take for the editor.
struct EditorActions {
    var attach: (() -> Void)?
    var choosePhoto: (() -> Void)?
    /// Nil where the device has no camera.
    var takePhoto: (() -> Void)?
    var draw: (() -> Void)?
    /// Saves pasted or dropped data as an attachment and embeds it at the range.
    var insertAttachment: ((_ data: Data, _ stem: String, _ fileExtension: String, _ range: NSRange) -> Void)?
    /// Inserts a link to a vault file dragged from the sidebar.
    var insertLinkToVaultFile: ((VaultPath, NSRange) -> Void)?
    /// Called when the note starts taking typing, so its side of the split is focused.
    var beginEditing: (() -> Void)?
    /// Follows a link in a new tab (⌘-tap) or on the other side of the split (⌥⌘-tap).
    var followLinkElsewhere: ((_ target: String, _ isWiki: Bool, _ placement: TabPlacement) -> Void)?
}

extension MarkdownEditing {
    /// The edit a text command makes, or nil for commands that do not change text by themselves.
    /// A menu command uses the cursor the note last had, which can lie past the end after
    /// the text shrank with no editor on screen (a property removed in reading view), so it
    /// is kept inside the text first. `tabSize` is how many spaces one level is when the vault
    /// indents with tabs, for lines indented with spaces.
    static func edit(for command: EditorCommand, in text: NSString, selection unclampedSelection: NSRange, indentUnit: String, tabSize: Int = 4) -> MarkdownTextEdit? {
        let location = min(max(unclampedSelection.location, 0), text.length)
        let selection = NSRange(location: location, length: min(max(unclampedSelection.length, 0), text.length - location))
        switch command {
        case .heading(let level): return settingHeading(level: level, in: text, selection: selection)
        case .wrap(let opening, let closing): return togglingWrap(opening, closingMarker: closing, in: text, selection: selection)
        case .bulletList: return togglingList(numbered: false, in: text, selection: selection)
        case .numberedList: return togglingList(numbered: true, in: text, selection: selection)
        case .task: return togglingTask(in: text, selection: selection)
        case .indent: return indenting(in: text, selection: selection, indentUnit: indentUnit)
        case .outdent: return outdenting(in: text, selection: selection, indentUnit: indentUnit, tabSize: tabSize)
        case .moveLinesUp: return movingLines(up: true, in: text, selection: selection)
        case .moveLinesDown: return movingLines(up: false, in: text, selection: selection)
        case .insertWikilink:
            // Typed `[[`, so link suggestions open for the text that follows.
            let selected = text.substring(with: selection)
            return MarkdownTextEdit(range: selection, replacement: "[[" + selected + "]]",
                                    selectionAfter: NSRange(location: selection.location + 2 + selected.utf16.count, length: 0))
        case .insertTag:
            // The whole character before the cursor decides: an emoji is two UTF-16 units,
            // and `🙂#tag` is not a tag. Selected words become the tag's name.
            let previousCharacter = selection.location > 0 ? text.substring(with: text.rangeOfComposedCharacterSequence(at: selection.location - 1)) : ""
            let needsSpace = previousCharacter.unicodeScalars.first.map { scalar in !CharacterSet.whitespacesAndNewlines.contains(scalar) } ?? false
            let insertion = (needsSpace ? " " : "") + "#" + text.substring(with: selection)
            return MarkdownTextEdit(range: selection, replacement: insertion, selectionAfter: NSRange(location: selection.location + insertion.utf16.count, length: 0))
        case .insertMarkdownLink:
            let selected = text.substring(with: selection)
            let link = "[" + selected + "]()"
            // The cursor goes where the next thing to type is: the label, or the address.
            let cursor = selected.isEmpty ? selection.location + 1 : selection.location + link.utf16.count - 1
            return MarkdownTextEdit(range: selection, replacement: link, selectionAfter: NSRange(location: cursor, length: 0))
        case .undo, .redo, .attach, .draw, .find, .findAndReplace, .dismissKeyboard, .followLink:
            return nil
        }
    }
}

#if canImport(UIKit)
import UIKit

/// The row of buttons above the keyboard, like Obsidian mobile's editing toolbar. It
/// scrolls sideways when it is wider than the screen.
final class EditorKeyboardToolbar: UIInputView {
    private let run: (EditorCommand) -> Void
    private let scrollView = UIScrollView()
    private let stackView = UIStackView()
    static let height: CGFloat = 48
    /// Which of the pane's actions the buttons were built for.
    private var builtActions: AvailableActions

    /// The pane's optional actions that add buttons; a change rebuilds the row, so no
    /// button stays for a feature that was turned off.
    private struct AvailableActions: Equatable {
        let canAttach: Bool
        let canChoosePhoto: Bool
        let canTakePhoto: Bool
        let canDraw: Bool

        init(_ actions: EditorActions) {
            canAttach = actions.attach != nil
            canChoosePhoto = actions.choosePhoto != nil
            canTakePhoto = actions.takePhoto != nil
            canDraw = actions.draw != nil
        }
    }

    init(actions: EditorActions, run: @escaping (EditorCommand) -> Void) {
        self.run = run
        builtActions = AvailableActions(actions)
        super.init(frame: CGRect(x: 0, y: 0, width: 0, height: Self.height), inputViewStyle: .keyboard)
        allowsSelfSizing = true
        autoresizingMask = .flexibleWidth
        // The keyboard style draws no background of its own here, so the sidebar would
        // show through; a bar material sits behind the buttons.
        let background = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterial))
        background.translatesAutoresizingMaskIntoConstraints = false
        addSubview(background)
        let topSeparator = UIView()
        topSeparator.backgroundColor = .separator
        topSeparator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(topSeparator)
        NSLayoutConstraint.activate([
            background.leadingAnchor.constraint(equalTo: leadingAnchor), background.trailingAnchor.constraint(equalTo: trailingAnchor),
            background.topAnchor.constraint(equalTo: topAnchor), background.bottomAnchor.constraint(equalTo: bottomAnchor),
            topSeparator.leadingAnchor.constraint(equalTo: leadingAnchor), topSeparator.trailingAnchor.constraint(equalTo: trailingAnchor),
            topSeparator.topAnchor.constraint(equalTo: topAnchor), topSeparator.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale),
        ])
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .horizontal
        stackView.spacing = 2
        stackView.alignment = .center
        stackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)
        scrollView.addSubview(stackView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            stackView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 8),
            stackView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -8),
            stackView.centerYAnchor.constraint(equalTo: scrollView.frameLayoutGuide.centerYAnchor),
            heightAnchor.constraint(equalToConstant: Self.height),
        ])
        buildButtons(actions: actions)
    }

    required init?(coder: NSCoder) { nil }

    override var intrinsicContentSize: CGSize { CGSize(width: UIView.noIntrinsicMetric, height: Self.height) }

    /// Shows the buttons the pane's current actions allow, as when Drawings is turned off
    /// or on in Settings while the note stays open.
    func update(actions: EditorActions) {
        let availableActions = AvailableActions(actions)
        guard availableActions != builtActions else { return }
        builtActions = availableActions
        for arrangedView in stackView.arrangedSubviews {
            stackView.removeArrangedSubview(arrangedView)
            arrangedView.removeFromSuperview()
        }
        buildButtons(actions: actions)
    }

    private func buildButtons(actions: EditorActions) {
        add("Undo", "arrow.uturn.backward", .undo)
        add("Redo", "arrow.uturn.forward", .redo)
        addSeparator()
        addHeadingMenu()
        add("Bold", "bold", .bold)
        add("Italic", "italic", .italic)
        add("Strikethrough", "strikethrough", .strikethrough)
        add("Highlight", "highlighter", .highlight)
        add("Code", "chevron.left.forwardslash.chevron.right", .code)
        add("Inline math", "function", .math)
        addSeparator()
        add("Link to note", "link", .insertWikilink)
        add("Tag", "number", .insertTag)
        addSeparator()
        add("Bulleted list", "list.bullet", .bulletList)
        add("Numbered list", "list.number", .numberedList)
        add("Task", "checklist", .task)
        add("Outdent", "decrease.indent", .outdent)
        add("Indent", "increase.indent", .indent)
        add("Move line up", "arrow.up", .moveLinesUp)
        add("Move line down", "arrow.down", .moveLinesDown)
        if actions.attach != nil || actions.draw != nil { addSeparator() }
        if actions.attach != nil { addAttachMenu(actions: actions) }
        if actions.draw != nil { add("Draw", "pencil.tip.crop.circle.badge.plus", .draw) }
        addSeparator()
        add("Find in note", "magnifyingglass", .find)
        add("Hide keyboard", "keyboard.chevron.compact.down", .dismissKeyboard)
    }

    private func makeButton(_ title: String, _ systemImage: String) -> UIButton {
        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(systemName: systemImage, withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .regular))
        configuration.baseForegroundColor = .label
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 10, bottom: 8, trailing: 10)
        let button = UIButton(configuration: configuration)
        button.accessibilityLabel = title
        button.toolTip = title
        button.widthAnchor.constraint(greaterThanOrEqualToConstant: 42).isActive = true
        return button
    }

    private func add(_ title: String, _ systemImage: String, _ command: EditorCommand) {
        let button = makeButton(title, systemImage)
        button.addAction(UIAction { [weak self] _ in self?.run(command) }, for: .touchUpInside)
        stackView.addArrangedSubview(button)
    }

    /// Files, Photos, and the camera, as Obsidian mobile's attach button offers them.
    private func addAttachMenu(actions: EditorActions) {
        let button = makeButton("Attach", "paperclip")
        var items: [UIMenuElement] = []
        if let takePhoto = actions.takePhoto { items.append(UIAction(title: "Take Photo", image: UIImage(systemName: "camera")) { _ in takePhoto() }) }
        if let choosePhoto = actions.choosePhoto { items.append(UIAction(title: "Photo Library", image: UIImage(systemName: "photo.on.rectangle")) { _ in choosePhoto() }) }
        if let attach = actions.attach { items.append(UIAction(title: "Choose File", image: UIImage(systemName: "folder")) { _ in attach() }) }
        button.menu = UIMenu(title: "Attach", children: items)
        button.showsMenuAsPrimaryAction = true
        stackView.addArrangedSubview(button)
    }

    private func addHeadingMenu() {
        let button = makeButton("Heading", "textformat.size")
        button.menu = UIMenu(title: "Heading", children: (1...6).map { level in
            UIAction(title: "Heading \(level)") { [weak self] _ in self?.run(.heading(level)) }
        })
        button.showsMenuAsPrimaryAction = true
        stackView.addArrangedSubview(button)
    }

    private func addSeparator() {
        let separator = UIView()
        separator.backgroundColor = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([separator.widthAnchor.constraint(equalToConstant: 1), separator.heightAnchor.constraint(equalToConstant: 22)])
        stackView.addArrangedSubview(separator)
        stackView.setCustomSpacing(8, after: stackView.arrangedSubviews[max(stackView.arrangedSubviews.count - 2, 0)])
        stackView.setCustomSpacing(8, after: separator)
    }
}
#endif

#if canImport(UIKit)
/// The system camera, for a photo of the board or a page, saved as a JPEG attachment.
struct CameraCapture: UIViewControllerRepresentable {
    let capture: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    /// "Photo 2026-09-23 22.18.05", like Graphite's drawing names.
    static func photoStem(at date: Date = .now) -> String {
        "Photo" + AttachmentResolver().drawingFileStem(createdAt: date).dropFirst("Drawing".count)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ picker: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraCapture
        init(parent: CameraCapture) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { parent.capture(image) }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
#endif

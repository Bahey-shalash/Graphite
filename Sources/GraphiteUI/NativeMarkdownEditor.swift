import SwiftUI
import UniformTypeIdentifiers
import GraphiteCore

#if canImport(UIKit)
import UIKit

/// The target of an undo action the iPad's editor registers itself; see `replaceCharacters`.
final class UndoActionToken {}

/// A TextKit 2 text view that keeps a readable column centered on wide screens and
/// hosts Live Preview's rendered blocks.
final class MarkdownTextView: UITextView {
    var readAloudRange: NSRange? { didSet { if readAloudRange != oldValue { setNeedsLayout() } } }
    var followsReading = false {
        didSet {
            guard followsReading != oldValue else { return }
            // Following again (after Back to Reading) reveals the current word at once.
            lastHighlightLayout = nil
            setNeedsLayout()
        }
    }
    private(set) var readAloudHighlights: [UIView] = []
    /// Tells the floating player where the highlight is on screen, so it can move aside.
    var reportReadingHighlightFrame: ((CGRect?, CGRect?) -> Void)?
    static let readableColumnWidth: CGFloat = 740
    static let minimumHorizontalInset: CGFloat = 28
    var usesReadableLineLength = true { didSet { setNeedsLayout() } }
    /// The readable column's width: Graphite's, or the vault theme's line width.
    var readableColumnWidth: CGFloat = MarkdownTextView.readableColumnWidth { didSet { if readableColumnWidth != oldValue { setNeedsLayout() } } }
    /// The note's name above the text, drawn by a label the text is inset below.
    var inlineTitle: (text: String, font: UIFont, color: UIColor)? {
        didSet {
            guard inlineTitle?.text != oldValue?.text || inlineTitle?.font != oldValue?.font || inlineTitle?.color != oldValue?.color else { return }
            updateInlineTitleLabel()
        }
    }
    private var inlineTitleLabel: UILabel?
    private static let topInset: CGFloat = 32
    private static let inlineTitleSpacing: CGFloat = 20
    var didLayout: ((MarkdownTextView) -> Void)?
    var didMoveIntoWindow: ((MarkdownTextView) -> Void)?
    /// When a touch last reached the view. SwiftUI's focus system also hands focus to text
    /// views on its own (for example when a search field ends editing), which would raise
    /// the keyboard and scroll to the cursor; the note starts editing only when touched
    /// or when Graphite asks.
    private var lastTouchUptime: TimeInterval = -.infinity
    private var isEditingRequested = false
    /// True while the note's view goes away and the text view gives up the keyboard. Ending
    /// editing in an embedded PDF hands focus on to the text view around it, and a note
    /// touched a moment before took it: it began editing and made its own tab active again,
    /// right after an embed's "Open in PDF View" had shown the PDF's tab.
    var refusesFocus = false

    /// A text view on TextKit 2, the system's default for a text view made in code. Not
    /// `UITextView(usingTextLayoutManager:)`: that factory makes the view through an
    /// initializer Swift does not see, which left the properties above without their
    /// initial values, all zero, and crashed the first layout once one was an array.
    init() {
        super.init(frame: .zero, textContainer: nil)
    }

    required init?(coder: NSCoder) { nil }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hitView = super.hitTest(point, with: event)
        // Only a touch on the text itself lets the note start editing. A touch on a rendered
        // block (the properties, a callout) belongs to the block; counting it let SwiftUI's
        // focus system hand the note the keyboard a moment later, its cursor in the YAML.
        if let hitView, event?.type == .touches, !isOverlay(hitView) { lastTouchUptime = ProcessInfo.processInfo.systemUptime }
        return hitView
    }

    /// Over a rendered block or a fold button, only scrolling and zooming are the text
    /// view's: its taps, loupe, selection and drag would take the touch from the block's
    /// own controls. A folded callout's title did not open, and a drag starting on the
    /// properties could end as a tap at the note's start.
    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer !== panGestureRecognizer, !(gestureRecognizer is UIPinchGestureRecognizer),
           let touchedView = super.hitTest(gestureRecognizer.location(in: self), with: nil), isOverlay(touchedView) {
            return false
        }
        return super.gestureRecognizerShouldBegin(gestureRecognizer)
    }

    /// Whether `view` is in a rendered block's view or is a fold button, placed over the text,
    /// rather than one of the views UIKit draws the text with.
    private func isOverlay(_ view: UIView) -> Bool {
        var placedView = view
        while let superview = placedView.superview, superview !== self { placedView = superview }
        guard placedView.superview === self else { return false }
        if placedView is UIControl { return true }
        // A hosting controller's view: SwiftUI puts responders of its own between the view
        // and its controller, and the chain reaches a view again after the controller.
        var responder = placedView.next
        while let currentResponder = responder, !(currentResponder is UIView) {
            if currentResponder is UIViewController { return true }
            responder = currentResponder.next
        }
        return false
    }

    override var canBecomeFirstResponder: Bool {
        let wasRecentlyTouched = ProcessInfo.processInfo.systemUptime - lastTouchUptime < 1
        return super.canBecomeFirstResponder && (isFirstResponder || (!refusesFocus && (isEditingRequested || wasRecentlyTouched)))
    }

    /// Starts editing on Graphite's behalf, for example to show a rendered block's source.
    func beginEditing() {
        isEditingRequested = true
        becomeFirstResponder()
        isEditingRequested = false
    }

    private struct InlineTitleMeasure: Equatable {
        let text: NSAttributedString
        let width: CGFloat
    }
    private var measuredInlineTitle: (key: InlineTitleMeasure, height: CGFloat)?

    override func layoutSubviews() {
        super.layoutSubviews()
        let horizontalInset = usesReadableLineLength
            ? max(Self.minimumHorizontalInset, (bounds.width - readableColumnWidth) / 2)
            : Self.minimumHorizontalInset
        var topInset = Self.topInset
        if let inlineTitleLabel {
            let titleWidth = max(bounds.width - 2 * horizontalInset - 2 * textContainer.lineFragmentPadding, 1)
            // Measured again only when the title, its font or the width changes, not on every
            // frame of a scroll.
            let titleKey = InlineTitleMeasure(text: inlineTitleLabel.attributedText ?? NSAttributedString(string: inlineTitleLabel.text ?? ""), width: titleWidth)
            let titleHeight: CGFloat
            if let measuredInlineTitle, measuredInlineTitle.key == titleKey {
                titleHeight = measuredInlineTitle.height
            } else {
                titleHeight = ceil(inlineTitleLabel.sizeThatFits(CGSize(width: titleWidth, height: .greatestFiniteMagnitude)).height)
                measuredInlineTitle = (titleKey, titleHeight)
            }
            inlineTitleLabel.frame = CGRect(x: horizontalInset + textContainer.lineFragmentPadding, y: Self.topInset, width: titleWidth, height: titleHeight)
            topInset += titleHeight + Self.inlineTitleSpacing
        }
        let insets = UIEdgeInsets(top: topInset, left: horizontalInset, bottom: 160, right: horizontalInset)
        // Setting equal insets would still invalidate the layout.
        if textContainerInset != insets { textContainerInset = insets }
        didLayout?(self)
        // UIKit lays a scroll view out on every frame of a scroll. The highlight is measured
        // again only when the word, the width or the text's height changed, so scrolling by
        // hand never pays for it, and never scrolls back to it.
        let highlightLayout = ReadAloudHighlightLayout(range: readAloudRange, width: bounds.width, contentHeight: contentSize.height)
        if highlightLayout != lastHighlightLayout {
            let wordChanged = highlightLayout.range != lastHighlightLayout?.range
            lastHighlightLayout = highlightLayout
            updateReadAloudHighlights(revealsWord: wordChanged)
        } else if let window, let first = readAloudHighlights.first {
            // Scrolling moves the highlight on screen; the player is told where it now is.
            let union = readAloudHighlights.dropFirst().reduce(first.frame) { $0.union($1.frame) }
            reportReadingHighlightFrame?(convert(union, to: nil), window.bounds)
        }
    }

    private struct ReadAloudHighlightLayout: Equatable {
        let range: NSRange?
        let width: CGFloat
        let contentHeight: CGFloat
    }
    private var lastHighlightLayout: ReadAloudHighlightLayout?

    private func updateReadAloudHighlights(revealsWord: Bool) {
        guard let range = readAloudRange, range.location >= 0, range.length > 0,
              range.location <= textStorage.length, range.length <= textStorage.length - range.location,
              let start = position(from: beginningOfDocument, offset: range.location),
              let end = position(from: start, offset: range.length), let textRange = textRange(from: start, to: end) else {
            readAloudHighlights.forEach { highlight in highlight.removeFromSuperview() }
            readAloudHighlights.removeAll(keepingCapacity: true)
            reportReadingHighlightFrame?(nil, nil)
            return
        }
        let frames = selectionRects(for: textRange).map(\.rect).filter { frame in frame.width > 0 && frame.height > 0 }
        defer {
            if let window, let first = frames.first {
                reportReadingHighlightFrame?(convert(frames.dropFirst().reduce(first) { $0.union($1) }, to: nil), window.bounds)
            }
        }
        let isScrolledByHand = isTracking || isDragging || isDecelerating
        let comfortableArea = bounds.inset(by: UIEdgeInsets(top: adjustedContentInset.top + 40, left: 0, bottom: adjustedContentInset.bottom + 120, right: 0))
        if revealsWord, followsReading, !isScrolledByHand, window != nil, let frame = frames.first, !comfortableArea.contains(frame) {
            // The word comes back a third of the way down, not at the very edge, so the
            // lines that follow are already in view.
            let visibleHeight = bounds.height - adjustedContentInset.top - adjustedContentInset.bottom
            let maximumOffset = max(-adjustedContentInset.top, contentSize.height + adjustedContentInset.bottom - bounds.height)
            let destination = frame.minY - adjustedContentInset.top - visibleHeight / 3
            setContentOffset(CGPoint(x: contentOffset.x, y: min(max(-adjustedContentInset.top, destination), maximumOffset)), animated: false)
        }
        guard readAloudHighlights.map(\.frame) != frames else { return }
        readAloudHighlights.forEach { highlight in highlight.removeFromSuperview() }
        readAloudHighlights.removeAll(keepingCapacity: true)
        for frame in frames {
            let highlight = UIView(frame: frame)
            highlight.backgroundColor = ReadAloudHighlightStyle.fill
            highlight.layer.cornerRadius = 3
            highlight.isUserInteractionEnabled = false
            highlight.isAccessibilityElement = false
            addSubview(highlight)
            readAloudHighlights.append(highlight)
        }
    }

    override func willMove(toWindow newWindow: UIWindow?) {
        // The find session's highlights ask this view for previews as they lay out; once it
        // is off screen (another tab, reading view, a closed tab), UIKit raises instead.
        // Dismissing the find bar leaves the session alive; only turning the interaction
        // off ends it.
        if newWindow == nil {
            if findInteraction?.isFindNavigatorVisible == true { findInteraction?.dismissFindNavigator() }
            isFindInteractionEnabled = false
        }
        super.willMove(toWindow: newWindow)
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else { return }
        isFindInteractionEnabled = true
        didMoveIntoWindow?(self)
        // A jump asked for while the view was off-window runs from the next layout pass.
        setNeedsLayout()
    }

    private func updateInlineTitleLabel() {
        guard let inlineTitle else {
            inlineTitleLabel?.removeFromSuperview()
            inlineTitleLabel = nil
            setNeedsLayout()
            return
        }
        let label = inlineTitleLabel ?? UILabel()
        label.text = inlineTitle.text
        label.font = inlineTitle.font
        label.textColor = inlineTitle.color
        label.numberOfLines = 0
        label.accessibilityTraits = .header
        if label.superview == nil { addSubview(label) }
        inlineTitleLabel = label
        setNeedsLayout()
    }

    /// The width available to a rendered block inside the text column.
    var contentColumnWidth: CGFloat {
        bounds.width - textContainerInset.left - textContainerInset.right - 2 * textContainer.lineFragmentPadding
    }

    /// The left edge of the pane inside its margins, where a base starts.
    var paneContentMinX: CGFloat { Self.minimumHorizontalInset + textContainer.lineFragmentPadding }
    /// The pane's width inside its margins, which a base takes.
    var paneContentWidth: CGFloat { max(0, bounds.width - 2 * paneContentMinX) }

    // MARK: Keyboard

    /// Runs an editing command; set by the editor's coordinator.
    var runCommand: ((EditorCommand) -> Void)?
    /// The suggestions at the cursor, which take the arrow keys, Return, and Escape while open.
    weak var completion: CompletionModel?
    /// Closes the suggestions on Escape; set by the coordinator, which tracks what they were found for.
    var dismissCompletion: (() -> Void)?

    /// Whether the cursor is on a link, so Return with ⌥ or ⌘ follows it; set by the coordinator.
    var isCursorOnLink: (() -> Bool)?

    /// The vault's editing shortcuts (`VaultKeyboardShortcuts`); set by the editor.
    var keyCommandTable = EditorKeyCommandTable.defaults

    /// The system's own ⌘B and ⌘I: they arrive through `toggleBoldface` and `toggleItalics`,
    /// which also serve the edit menu's format items, so they get no key command of their own.
    private static let systemFormatShortcuts: [GraphiteCommand: KeyCombination] = [
        .toggleBold: KeyCombination(.command, .character("B")), .toggleItalics: KeyCombination(.command, .character("I")),
    ]

    /// The vault's editing shortcuts as key commands. The commands on a link exist only while
    /// the cursor is on one, so Return keeps its usual meaning elsewhere.
    private var editorKeyCommands: [UIKeyCommand] {
        let isOnLink = isCursorOnLink?() == true
        return keyCommandTable.entries.compactMap { entry in
            guard !entry.command.followsLink || isOnLink, Self.systemFormatShortcuts[entry.command] != entry.combination,
                  let input = entry.combination.keyCommandInput else { return nil }
            let keyCommand = UIKeyCommand(title: entry.command.title, action: #selector(runKeyCommand(_:)), input: input,
                                          modifierFlags: entry.combination.keyModifierFlags, propertyList: entry.command.identifier)
            keyCommand.wantsPriorityOverSystemBehavior = true
            return keyCommand
        }
    }

    override var keyCommands: [UIKeyCommand]? {
        var keyCommands = (super.keyCommands ?? []) + editorKeyCommands
        if completion?.isVisible == true {
            for (input, name) in [(UIKeyCommand.inputUpArrow, "up"), (UIKeyCommand.inputDownArrow, "down"), (UIKeyCommand.inputEscape, "escape")] {
                let keyCommand = UIKeyCommand(title: "", action: #selector(runCompletionKey(_:)), input: input, modifierFlags: [], propertyList: name)
                keyCommand.wantsPriorityOverSystemBehavior = true
                keyCommands.append(keyCommand)
            }
        }
        return keyCommands
    }

    @objc private func runCompletionKey(_ keyCommand: UIKeyCommand) {
        switch keyCommand.propertyList as? String {
        case "up": completion?.moveSelection(by: -1)
        case "down": completion?.moveSelection(by: 1)
        default:
            if let dismissCompletion { dismissCompletion() } else { completion?.dismiss() }
        }
    }

    @objc private func runKeyCommand(_ keyCommand: UIKeyCommand) {
        guard let identifier = keyCommand.propertyList as? String, let editorCommand = GraphiteCommand(rawValue: identifier)?.editorCommand else { return }
        runCommand?(editorCommand)
    }

    // MARK: Paste and drop

    /// Saves pasted or dropped files and images, and links dropped vault files; set by the
    /// coordinator. Each request carries the text revision it was made at, because the
    /// content loads and saves asynchronously while the note may change.
    var insertAttachment: ((_ data: Data, _ stem: String, _ fileExtension: String, _ request: InsertionRequest) -> Void)?
    var insertLinkToVaultFile: ((VaultPath, InsertionRequest) -> Void)?
    /// The note's current text revision; set by the coordinator.
    var textRevision: (() -> Int)?
    /// Tells the person that a pasted or dropped item could not be read; set by the coordinator.
    var reportUnreadableItem: (() -> Void)?
    var convertsPastedHTML = true
    /// Community plugins that listen for pastes and drops (`editor-paste`, `editor-drop`); nil
    /// while none does. Each answers whether a plugin took the paste or drop over.
    var offerPasteToPlugins: ((_ text: String?, _ html: String?) async -> Bool)?
    var offerDropToPlugins: ((_ files: [(name: String, type: String)], _ text: String?) async -> Bool)?

    /// Image types saved as they are; others are converted to PNG. HEIC is converted to
    /// JPEG because Obsidian does not show HEIC images.
    private static let keptImageTypes: [(UTType, String)] = [(.png, "png"), (.jpeg, "jpg"), (.gif, "gif"), (.webP, "webp")]

    private func insertionRequest(at range: NSRange) -> InsertionRequest {
        InsertionRequest(range: range, revision: textRevision?() ?? 0)
    }

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if action == #selector(toggleUnderline(_:)) { return false }
        // ⌘B and ⌘I stay the system's while the vault gives them to bold and italics.
        for (command, selector) in [(GraphiteCommand.toggleBold, #selector(toggleBoldface(_:))), (.toggleItalics, #selector(toggleItalics(_:)))]
        where action == selector {
            guard let combination = Self.systemFormatShortcuts[command], keyCommandTable.isBound(command, to: combination) else { return false }
        }
        if action == #selector(paste(_:)) && UIPasteboard.general.hasImages && insertAttachment != nil { return true }
        return super.canPerformAction(action, withSender: sender)
    }

    override func paste(_ sender: Any?) {
        let pasteboard = UIPasteboard.general
        // An image copied on its own (a screenshot, an image from Safari or Photos). Safari
        // copies an image with its address, so a URL alongside does not make it text. The
        // item providers load it asynchronously: another app may only have promised the data.
        if pasteboard.hasImages, !pasteboard.hasStrings || pasteboard.hasURLs, let insertAttachment {
            // Read during the paste action itself: iOS allows reading the pasteboard only then.
            switch Self.pastedImage(from: pasteboard) {
            case .encoded(let data, let fileExtension):
                insertAttachment(data, WorkspaceModel.pastedImageStem(), fileExtension, insertionRequest(at: selectedRange))
            case .unencoded(let image):
                insertEncodedAttachment(of: image, stem: WorkspaceModel.pastedImageStem(), request: insertionRequest(at: selectedRange))
            case nil:
                paste(itemProviders: pasteboard.itemProviders)
            }
            return
        }
        // A web address pasted over selected text links the text to it, as in Obsidian.
        if selectedRange.length > 0, let pastedText = pasteboard.string,
           let edit = MarkdownEditing.linkingSelection(to: pastedText, in: (text ?? "") as NSString, selection: selectedRange),
           let start = position(from: beginningOfDocument, offset: edit.range.location), let end = position(from: start, offset: edit.range.length),
           let replacedRange = textRange(from: start, to: end) {
            replace(replacedRange, withText: edit.replacement)
            return
        }
        // Text plugins may take over (Link or Card makes a card of an address). The pasteboard is
        // read now, while iOS allows it; Graphite pastes what it read if no plugin takes it.
        if let offerPasteToPlugins, pasteboard.hasStrings {
            let text = pasteboard.string
            let htmlData = convertsPastedHTML ? pasteboard.data(forPasteboardType: UTType.html.identifier) : nil
            let html = htmlData.flatMap { data in String(data: data, encoding: .utf8) }
            let pastedRange = selectedRange
            let textWhenPasted = self.text ?? ""
            Task { [weak self] in
                let isTakenOver = await offerPasteToPlugins(text, html)
                guard let self, !isTakenOver else { return }
                if let htmlData, htmlData.count <= HTMLToMarkdown.maximumConvertedLength {
                    self.insertConvertedHTML(htmlData, plainText: text, at: pastedRange)
                } else if let text, !text.isEmpty {
                    // Where the paste was asked for, unless the note changed meanwhile; then
                    // at the cursor. It went in at the cursor, wherever it had moved.
                    if self.text == textWhenPasted, NSMaxRange(pastedRange) <= (textWhenPasted as NSString).length { self.selectedRange = pastedRange }
                    self.insertText(text)
                }
            }
            return
        }
        // A web page or rich text becomes Markdown, as with Obsidian's "Auto convert HTML".
        if convertsPastedHTML, let htmlData = pasteboard.data(forPasteboardType: UTType.html.identifier),
           htmlData.count <= HTMLToMarkdown.maximumConvertedLength {
            insertConvertedHTML(htmlData, plainText: pasteboard.string, at: selectedRange)
            return
        }
        super.paste(sender)
    }

    /// Converts pasted HTML off the main thread, since a large page takes long to convert.
    /// The pasteboard is read before, as iOS allows reading it only during the paste. The
    /// Markdown goes where the paste was asked for while the note is unchanged; after an
    /// edit that place may no longer exist, so the plain text goes at the cursor instead.
    private func insertConvertedHTML(_ htmlData: Data, plainText: String?, at pastedRange: NSRange) {
        let revisionAtPaste = textRevision?() ?? 0
        Task { [weak self] in
            let markdown = await Task.detached(priority: .userInitiated) { () -> String? in
                guard let html = String(data: htmlData, encoding: .utf8) ?? String(data: htmlData, encoding: .utf16) else { return nil }
                let markdown = HTMLToMarkdown.markdown(from: html)
                return markdown.isEmpty ? nil : markdown
            }.value
            guard let self else { return }
            let isTextUnchanged = (self.textRevision?() ?? 0) == revisionAtPaste
            guard let pastedText = isTextUnchanged ? (markdown ?? plainText) : plainText, !pastedText.isEmpty else { return }
            if isTextUnchanged, NSMaxRange(pastedRange) <= self.textStorage.length { self.selectedRange = pastedRange }
            self.insertText(pastedText)
        }
    }

    /// Encodes an image as PNG off the main thread, then saves it as an attachment.
    private func insertEncodedAttachment(of image: UIImage, stem: String, request: InsertionRequest) {
        Task { [weak self] in
            let pngData = await Task.detached(priority: .userInitiated) { image.pngData() }.value
            guard let self else { return }
            guard let pngData else {
                self.reportUnreadableItem?()
                return
            }
            self.insertAttachment?(pngData, stem, "png", request)
        }
    }

    /// A pasted image as bytes in a format kept as it is, or as an image still to be encoded.
    private enum PastedImage {
        case encoded(Data, fileExtension: String)
        case unencoded(UIImage)
    }

    private static func pastedImage(from pasteboard: UIPasteboard) -> PastedImage? {
        for (type, fileExtension) in keptImageTypes {
            if let data = pasteboard.data(forPasteboardType: type.identifier) { return .encoded(data, fileExtension: fileExtension) }
        }
        return pasteboard.image.map(PastedImage.unencoded)
    }

    /// Drops of files, images, and sidebar items arrive here (see `pasteConfiguration`).
    /// Every item asks for the place the drop landed; the coordinator moves each one past
    /// the note's changes, including the items inserted before it.
    override func paste(itemProviders: [NSItemProvider]) {
        // Plugins that listen for drops hear of the files first, by name and type.
        if let offerDropToPlugins {
            let files = itemProviders.map { provider in
                (name: provider.suggestedName ?? "", type: provider.registeredTypeIdentifiers.first.flatMap { identifier in UTType(identifier)?.preferredMIMEType } ?? "")
            }
            let request = insertionRequest(at: selectedRange)
            Task { [weak self] in
                guard !(await offerDropToPlugins(files, nil)), let self else { return }
                self.insertDroppedItems(itemProviders, dropRequest: request)
            }
            return
        }
        insertDroppedItems(itemProviders, dropRequest: insertionRequest(at: selectedRange))
    }

    private func insertDroppedItems(_ itemProviders: [NSItemProvider], dropRequest: InsertionRequest) {
        for provider in itemProviders {
            if provider.hasItemConformingToTypeIdentifier(UTType.graphiteVaultItem.identifier) {
                _ = provider.loadTransferable(type: VaultItemTransfer.self) { [weak self] result in
                    guard case .success(let item) = result, let path = try? VaultPath(item.path) else {
                        Task { @MainActor in self?.reportUnreadableItem?() }
                        return
                    }
                    Task { @MainActor in self?.insertLinkToVaultFile?(path, dropRequest) }
                }
                continue
            }
            guard insertAttachment != nil else { continue }
            let suggestedStem = provider.suggestedName.map { name in (name as NSString).deletingPathExtension }
            if let (type, fileExtension) = Self.keptImageTypes.first(where: { type, _ in provider.hasItemConformingToTypeIdentifier(type.identifier) }) {
                provider.loadDataRepresentation(forTypeIdentifier: type.identifier) { [weak self] data, _ in
                    guard let data else {
                        Task { @MainActor in self?.reportUnreadableItem?() }
                        return
                    }
                    Task { @MainActor in self?.insertAttachment?(data, suggestedStem ?? WorkspaceModel.pastedImageStem(), fileExtension, dropRequest) }
                }
            } else if provider.canLoadObject(ofClass: UIImage.self) {
                _ = provider.loadObject(ofClass: UIImage.self) { [weak self] object, _ in
                    guard let image = object as? UIImage, let data = image.jpegData(compressionQuality: 0.9) else {
                        Task { @MainActor in self?.reportUnreadableItem?() }
                        return
                    }
                    Task { @MainActor in self?.insertAttachment?(data, suggestedStem ?? WorkspaceModel.pastedImageStem(), "jpg", dropRequest) }
                }
            } else if let typeIdentifier = provider.registeredTypeIdentifiers.first(where: { identifier in UTType(identifier)?.conforms(to: .data) == true }) {
                // Any other file, such as a PDF or a recording, keeps its own format.
                provider.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { [weak self] location, _ in
                    guard let location, let data = try? Data(contentsOf: location, options: .mappedIfSafe) else {
                        Task { @MainActor in self?.reportUnreadableItem?() }
                        return
                    }
                    let fileExtension = location.pathExtension.isEmpty ? (UTType(typeIdentifier)?.preferredFilenameExtension ?? "bin") : location.pathExtension
                    let stem = suggestedStem ?? location.deletingPathExtension().lastPathComponent
                    Task { @MainActor in self?.insertAttachment?(data, stem, fileExtension, dropRequest) }
                }
            }
        }
    }

    override func toggleBoldface(_ sender: Any?) { runCommand?(.bold) }
    override func toggleItalics(_ sender: Any?) { runCommand?(.italic) }
}

/// Hosts a note's text view for one SwiftUI view. The text view can outlive it: a hidden
/// note's text view is kept by `MarkdownEditorRetention` and shown again in a new container.
final class MarkdownEditorContainerView: UIView {
    private(set) weak var hostedTextView: MarkdownTextView?
    /// The latest update of this container's SwiftUI view, made while an earlier view of
    /// the note still showed the text view. It runs when the text view arrives here.
    var updateWhenTextViewArrives: ((MarkdownTextView) -> Void)?

    func host(_ textView: MarkdownTextView) {
        textView.removeFromSuperview()
        textView.frame = bounds
        textView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(textView)
        hostedTextView = textView
        let waitingUpdate = updateWhenTextViewArrives
        updateWhenTextViewArrives = nil
        waitingUpdate?(textView)
    }

    /// The text view, while this container shows it rather than another view of the note.
    var textViewShownHere: MarkdownTextView? {
        guard let hostedTextView, hostedTextView.superview === self else { return nil }
        return hostedTextView
    }
}

struct NativeMarkdownEditor: UIViewRepresentable {
    @Bindable var session: MarkdownSession
    let configuration: EditorConfiguration
    var environment: LivePreviewEnvironment?
    let headingScrollRequest: HeadingScrollRequest?
    var actions = EditorActions()
    let follow: (String, Bool) -> Void
    /// Keeps this editor, with its undo history, after it leaves the screen; see
    /// `MarkdownEditorRetention`. Without it the editor is torn down when hidden.
    var retention: MarkdownEditorRetention?
    /// The tab the note is open in, which decides whether a kept editor is still wanted.
    var retentionOwner: TabDocument?
    var readAloudRange: NSRange?
    var followsReading = false
    var suspendReadingFollow: (() -> Void)?
    var readAloudHooks: ReadAloudEditorHooks?
    /// The Color, Format, Paragraph and Insert submenus of the edit menu; see `EditorContextMenuContent`.
    var contextMenu: EditorContextMenuActions?
    /// The vault's editing shortcuts.
    var keyCommandTable: EditorKeyCommandTable

    init(session: MarkdownSession, configuration: EditorConfiguration, environment: LivePreviewEnvironment? = nil,
         headingScrollRequest: HeadingScrollRequest?, actions: EditorActions = EditorActions(),
         retention: MarkdownEditorRetention? = nil, retentionOwner: TabDocument? = nil, readAloudRange: NSRange? = nil,
         followsReading: Bool = false, suspendReadingFollow: (() -> Void)? = nil, readAloudHooks: ReadAloudEditorHooks? = nil,
         contextMenu: EditorContextMenuActions? = nil, keyCommandTable: EditorKeyCommandTable = .defaults, follow: @escaping (String, Bool) -> Void) {
        self.contextMenu = contextMenu
        self.keyCommandTable = keyCommandTable
        self.session = session
        self.configuration = configuration
        self.environment = environment
        self.headingScrollRequest = headingScrollRequest
        self.actions = actions
        self.retention = retention
        self.retentionOwner = retentionOwner
        self.readAloudRange = readAloudRange
        self.followsReading = followsReading
        self.suspendReadingFollow = suspendReadingFollow
        self.readAloudHooks = readAloudHooks
        self.follow = follow
    }

    func makeCoordinator() -> Coordinator {
        if let retention, let retentionOwner, let keptEditor = retention.takeEditor(for: session, owner: retentionOwner) as? Coordinator {
            return keptEditor
        }
        return Coordinator(session: session, configuration: configuration)
    }

    func makeUIView(context: Context) -> MarkdownEditorContainerView {
        let container = MarkdownEditorContainerView()
        let coordinator = context.coordinator
        coordinator.retention = retention
        coordinator.retentionOwner = retentionOwner
        if coordinator.textView == nil {
            let textView = makeTextView(coordinator: coordinator)
            coordinator.textView = textView
            container.host(textView)
        }
        coordinator.viewWasMade(with: container)
        retention?.editorDidAttach(coordinator)
        return container
    }

    private func makeTextView(coordinator: Coordinator) -> MarkdownTextView {
        let textView = MarkdownTextView()
        coordinator.environment = environment
        coordinator.follow = follow
        textView.textLayoutManager?.delegate = coordinator
        textView.backgroundColor = .clear
        textView.alwaysBounceVertical = true
        textView.keyboardDismissMode = .interactive
        textView.smartQuotesType = .no
        textView.smartDashesType = .no
        textView.spellCheckingType = configuration.usesSpellChecking ? .yes : .no
        textView.accessibilityLabel = "Markdown note"
        // The system's find and replace bar, opened with ⌘F or the toolbar.
        textView.isFindInteractionEnabled = true
        textView.addInteraction(UIPencilInteraction(delegate: coordinator))
        coordinator.actions = actions
        textView.runCommand = { [weak coordinator, weak textView] command in
            guard let coordinator, let textView else { return }
            coordinator.run(command, in: textView)
        }
        coordinator.updateKeyboardToolbar(of: textView)
        textView.completion = session.completion
        textView.dismissCompletion = { [weak coordinator] in coordinator?.dismissCompletion() }
        textView.isCursorOnLink = { [weak coordinator, weak textView] in
            guard let coordinator, let textView else { return false }
            return coordinator.link(atCharacter: textView.selectedRange.location, in: textView, skipsShownMarkup: false) != nil
        }
        textView.textRevision = { [weak coordinator] in coordinator?.textRevision ?? 0 }
        textView.reportUnreadableItem = { [weak coordinator] in coordinator?.session.errorMessage = NativeMarkdownEditor.unreadableItemMessage }
        coordinator.updateInsertionHandlers(of: textView)
        textView.convertsPastedHTML = configuration.editingBehavior.convertsPastedHTML
        // Files, images, and items from the sidebar can be dropped into the note.
        textView.pasteConfiguration = UIPasteConfiguration(acceptableTypeIdentifiers: [
            UTType.graphiteVaultItem.identifier, UTType.image.identifier, UTType.pdf.identifier, UTType.audio.identifier, UTType.movie.identifier,
        ])
        session.completion.performEdits = { [weak coordinator, weak textView] edits in
            guard let coordinator, let textView else { return }
            coordinator.performCompletionEdits(edits, in: textView)
        }
        textView.usesReadableLineLength = configuration.usesReadableLineLength
        // The theme's line width, plus the text container's padding on each side.
        textView.readableColumnWidth = configuration.theme?.readableColumnWidth(forTextSize: configuration.textSize).map { width in width + 10 } ?? MarkdownTextView.readableColumnWidth
        // The theme's inline title (Phase 3), else the text font at 1.75 times, semibold.
        textView.inlineTitle = configuration.inlineTitle.map { title in
            (title, InlineTitleStyle.font(textSize: configuration.textSize, typography: configuration.typography, theme: configuration.theme),
             configuration.theme?.inlineTitleColor ?? .label)
        }
        // The text and the saved cursor go in before the delegate: setting the text places
        // the cursor at its end, which the delegate would otherwise record as the note's.
        textView.text = session.text
        coordinator.lastSynchronizedText = session.text
        let textLength = (session.text as NSString).length
        let cursorLocation = min(session.selection.location, textLength)
        textView.selectedRange = NSRange(location: cursorLocation, length: min(session.selection.length, textLength - cursorLocation))
        textView.delegate = coordinator
        coordinator.observeCharacterEdits(in: textView)
        coordinator.observeMemoryWarnings()
        session.undoAvailability.follow(textView.undoManager)
        textView.didLayout = { [weak coordinator] layoutView in
            coordinator?.returnToScrollLocationIfWidthChangedWhileHidden(in: layoutView)
            coordinator?.schedulePendingJumpIfReady(in: layoutView)
            coordinator?.positionWidgets(in: layoutView)
            coordinator?.positionFoldButtons(in: layoutView)
            coordinator?.layOutViewportAgainIfShort(in: layoutView)
            coordinator?.placeWidgetsAfterWidthChange(in: layoutView)
        }
        textView.didMoveIntoWindow = { [weak coordinator] windowedView in
            coordinator?.startEditingIfRequested(in: windowedView)
            coordinator?.presentFindIfRequested(in: windowedView)
            coordinator?.goToReadingPlaceIfSwitched(in: windowedView)
        }
        if let savedScrollLocation = session.savedScrollLocation { coordinator.pendingJump = .topOfCharacter(savedScrollLocation) }
        session.isEditorAttached = true
        coordinator.reportPlace(of: textView)
        coordinator.installLinkTapRecognizer(on: textView)
        coordinator.installQuickFontSizePinch(on: textView)
        coordinator.rebuildBlocks(in: textView)
        coordinator.restyleEverything(in: textView)
        // Rendered blocks and drawn replacements take their colors from the appearance.
        textView.registerForTraitChanges([UITraitUserInterfaceStyle.self]) { [weak coordinator] (changedView: MarkdownTextView, _: UITraitCollection) in
            coordinator?.restyleEverything(in: changedView)
            coordinator?.refreshWidgets(in: changedView)
        }
        return textView
    }

    func updateUIView(_ container: MarkdownEditorContainerView, context: Context) {
        let coordinator = context.coordinator
        guard let textView = container.textViewShownHere else {
            // An earlier view of this note still shows the text view; this view's state
            // reaches the editor when the text view moves here.
            container.updateWhenTextViewArrives = { [self] arrivedTextView in update(arrivedTextView, coordinator: coordinator) }
            return
        }
        update(textView, coordinator: coordinator)
    }

    private func update(_ textView: MarkdownTextView, coordinator: Coordinator) {
        coordinator.session = session
        textView.readAloudRange = readAloudRange
        textView.keyCommandTable = keyCommandTable
        textView.followsReading = followsReading
        coordinator.suspendReadingFollow = suspendReadingFollow
        coordinator.installReadAloudHooks(readAloudHooks, in: textView)
        coordinator.contextMenu = contextMenu
        let previousBlockPolicy = coordinator.renderedBlockPolicy
        coordinator.environment = environment
        coordinator.follow = follow
        coordinator.actions = actions
        coordinator.updateInsertionHandlers(of: textView)
        coordinator.updateKeyboardToolbar(of: textView)
        coordinator.quickFontSizePinch?.adjustment = actions.quickFontSize
        textView.convertsPastedHTML = configuration.editingBehavior.convertsPastedHTML
        textView.usesReadableLineLength = configuration.usesReadableLineLength
        // The theme's line width, plus the text container's padding on each side.
        textView.readableColumnWidth = configuration.theme?.readableColumnWidth(forTextSize: configuration.textSize).map { width in width + 10 } ?? MarkdownTextView.readableColumnWidth
        // The theme's inline title (Phase 3), else the text font at 1.75 times, semibold.
        textView.inlineTitle = configuration.inlineTitle.map { title in
            (title, InlineTitleStyle.font(textSize: configuration.textSize, typography: configuration.typography, theme: configuration.theme),
             configuration.theme?.inlineTitleColor ?? .label)
        }
        textView.spellCheckingType = configuration.usesSpellChecking ? .yes : .no
        // Turning the Properties view on or off changes which blocks are rendered, as the
        // configuration can.
        if coordinator.configuration != configuration || coordinator.renderedBlockPolicy != previousBlockPolicy {
            coordinator.configuration = configuration
            coordinator.rebuildBlocks(in: textView, forcesBlockScan: true)
            coordinator.restyleEverything(in: textView)
        }
        // Rendered blocks already on screen show the new settings, index state, files and
        // accent in place, keeping their own state (such as a base's chosen view). A changed
        // file reaches them too: each looks its files up again and keeps showing what it
        // shows until then. Rebuilding them blanked every drawing in the note for a few
        // frames after each save, since the system reports the note's own save as a change.
        coordinator.refreshWidgets(for: LivePreviewWidgetSignature(environment: environment, accentHex: configuration.accentHex, notePath: session.path.rawValue),
                                   in: textView)
        let hasAppliedInsertion = coordinator.applyPendingInsertions(to: textView)
        if !hasAppliedInsertion, session.text != coordinator.lastSynchronizedText, textView.markedTextRange == nil {
            // The file changed on disk, or properties were edited from a rendered view.
            coordinator.replaceText(with: session.text, in: textView)
        }
        if session.foldedKeys != coordinator.appliedFoldedKeys { coordinator.applyFolds(in: textView) }
        coordinator.startEditingIfRequested(in: textView)
        coordinator.presentFindIfRequested(in: textView)
        if let headingScrollRequest, headingScrollRequest.token != session.handledHeadingScrollToken {
            session.handledHeadingScrollToken = headingScrollRequest.token
            // A jump replaces the return to where the note was left.
            if let textRange = headingScrollRequest.textRange {
                coordinator.pendingJump = .textRange(textRange)
            } else {
                coordinator.pendingJump = .heading(anchor: headingScrollRequest.anchor, occurrence: headingScrollRequest.occurrence)
            }
        }
        coordinator.performPendingJumpIfReady(in: textView)
    }

    static func dismantleUIView(_ container: MarkdownEditorContainerView, coordinator: Coordinator) {
        coordinator.viewWasDismantled(with: container)
    }

    @MainActor
    final class Coordinator: NSObject, UITextViewDelegate, UIGestureRecognizerDelegate, NSTextLayoutManagerDelegate, RetainableMarkdownEditor,
                             UIPencilInteractionDelegate {
        var session: MarkdownSession
        /// The text view this coordinator styles and edits through. It lives as long as the
        /// coordinator, which a hidden note's retention can keep beyond its SwiftUI view.
        var textView: MarkdownTextView?
        weak var retention: MarkdownEditorRetention?
        weak var retentionOwner: TabDocument?
        /// The containers of the SwiftUI views that show this note.
        private var containersInUse = EditorContainersInUse<MarkdownEditorContainerView>()
        /// Set while a dismantled view lets go of the text view; see `viewWasDismantled`.
        private var isLettingGoOfTextView = false
        /// The text view's width when it left the screen; a new width reflows the note,
        /// so it returns to its top line rather than to the old pixel offset.
        private var widthWhenHidden: CGFloat?
        /// The text's styling, markup revealed at the selection, and rendered blocks, shared
        /// with the Mac's editor. Views kept off screen are dropped on a memory warning.
        let styling: MarkdownEditorStyling
        var configuration: EditorConfiguration {
            get { styling.configuration }
            set { styling.configuration = newValue }
        }
        var environment: LivePreviewEnvironment? {
            get { styling.environment }
            set { styling.environment = newValue }
        }
        var follow: (String, Bool) -> Void = { _, _ in }
        var appliedInsertionIdentifier: UUID?
        /// Where the view should go once it is in a window and has a width: laying out a
        /// view that has neither measures the note at the wrong width, and the system's find
        /// highlight asserts off-window.
        enum Jump: Equatable {
            /// `occurrence` picks one of several headings that read the same, from zero.
            case heading(anchor: String, occurrence: Int = 0)
            case textRange(NSRange)
            /// Back where the note was left, as when switching tabs.
            case topOfCharacter(Int)
        }
        var pendingJump: Jump?
        private var isPendingJumpScheduled = false
        /// Headings and list items that fold, found with the blocks, and the folds last applied.
        private var foldableRegions: [FoldableRegion] = [] {
            didSet { foldableRegionsRevision += 1 }
        }
        /// Changes with `foldableRegions`, for what is worked out from them on every frame.
        private var foldableRegionsRevision = 0
        /// The text `foldableRegions` were found in or moved to.
        private var foldableRegionsSource: NSString?
        var appliedFoldedKeys: Set<String> = []
        private var foldButtons: [String: (chevron: UIButton, ellipsis: UIButton)] = [:]
        /// Where the cursor was, to tell which way it moved into a folded section.
        private var lastSelectionLocation = 0
        /// Notes longer than this do not fold, to keep typing fast.
        private static let maximumFoldingLength = 2_000_000
        /// The folded regions, and the headers that show a fold button, worked out again only
        /// when the regions or the folds change: they were worked out several times on every
        /// frame of a scroll, each a pass over every foldable region.
        private var foldedRegions: [FoldableRegion] { foldLayout.folded }
        private var foldLayout: (folded: [FoldableRegion], regionsByStart: [Int: FoldableRegion]) {
            if let foldLayoutCache, foldLayoutCache.revision == foldableRegionsRevision, foldLayoutCache.foldedKeys == session.foldedKeys {
                return (foldLayoutCache.folded, foldLayoutCache.regionsByStart)
            }
            let folded = NoteFolding.foldedRegions(in: foldableRegions, foldedKeys: session.foldedKeys)
            var regionsByStart: [Int: FoldableRegion] = [:]
            for region in foldableRegions where NoteFolding.regions(hiding: region.headerRange.location, in: folded).isEmpty {
                if regionsByStart[region.headerRange.location] == nil { regionsByStart[region.headerRange.location] = region }
            }
            foldLayoutCache = (foldableRegionsRevision, session.foldedKeys, folded, regionsByStart)
            return (folded, regionsByStart)
        }
        private var foldLayoutCache: (revision: Int, foldedKeys: Set<String>, folded: [FoldableRegion], regionsByStart: [Int: FoldableRegion])?
        /// The text's length, the edit's location, and the folds before the edit under way,
        /// to carry folds across it.
        private var lengthBeforeEdit = 0
        private var editLocationBeforeEdit = 0
        private var foldedRegionsBeforeEdit: [FoldableRegion] = []
        /// Set while a second viewport layout is waiting, so layout passes do not ask for more.
        private var isViewportRelayoutPending = false
        var actions = EditorActions()
        /// The quick font size pinch on the text view, which follows `actions.quickFontSize`.
        var quickFontSizePinch: QuickFontSizePinchRecognizer?
        var suspendReadingFollow: (() -> Void)?
        /// Which optional keyboard toolbar buttons exist; the toolbar is rebuilt when this changes.
        private var keyboardToolbarButtons: KeyboardToolbarButtons?
        /// Set while Graphite changes the text itself, so its own change is not rewritten again.
        private var isPerformingEdit = false
        /// Set while an insertion moves the cursor, changes the text, and moves the cursor
        /// again: the insertion restyles the whole note and updates the suggestions once, for
        /// the final cursor, instead of for each step.
        private var isApplyingInsertion = false
        /// The text last given to or taken from the session. Comparing the session's text with
        /// it is instant while nothing else changed the session's text, because both share
        /// one storage; comparing with the text view's text reads the whole note each update.
        var lastSynchronizedText = ""
        /// The text, its rendered blocks, and the edits styling has not caught up with. Every
        /// character edit reaches it from the text storage before UIKit reports the new
        /// selection, so nothing styles the new text with ranges found in the old one.
        private var textState: LivePreviewTextState { styling.textState }
        /// The markup the styling shows as written; see `RevealedMarkup`.
        private var revealedMarkup: RevealedMarkup? { styling.revealedMarkup }
        /// Whether the text view has keyboard focus; markup is revealed only then.
        private var isEditing = false {
            didSet { styling.revealsMarkupAtSelection = isEditing }
        }
        private var blockEntries: [LivePreviewBlockEntry] { textState.blockEntries }
        private var renderedBlocks: LivePreviewRenderedBlocks { styling.renderedBlocks }
        private var memoryWarningObserver: NSObjectProtocol?
        /// Consecutive layout passes that placed, moved, or could not place a rendered block.
        private var unsettledPlacementPasses = 0
        /// Later tries for a rendered block still missing after the passes above, which can
        /// happen when TextKit lays out the viewport only after the view settles.
        private var delayedPlacementTries = 0
        /// Set while blocks are placed again on a viewport laid out for them in the same pass.
        private var isPlacingOnViewportLaidOutNow = false
        /// The text column's and the pane's widths when rendered blocks were last placed, and
        /// the placement waiting for a new width to settle. A wider pane leaves the readable
        /// column as it is, but widens the bases.
        private var placedColumnWidth: CGFloat = 0
        private var placedPaneWidth: CGFloat = 0
        private var placementAfterWidthChange: DispatchWorkItem?
        /// A heading the view keeps at its top while rendered blocks above it settle their
        /// heights, until they have or until the person scrolls or starts editing.
        private var pinnedHeading: HeadingJumpPin?
        /// Pastes and drops whose content is still loading or saving.
        private var pendingInsertionRequests = PendingInsertionRequests()
        /// The text revision the open suggestions were found at, and the revisions of accepted
        /// suggestions whose edits are still being made. Their edits arrive after
        /// asynchronous work and are moved past typing that happened meanwhile.
        private var completionContextRevision: Int?
        /// The text and cursor community plugins last heard of, and the revision they answered
        /// with suggestions for.
        private struct PluginEditorState: Equatable {
            let textRevision: Int
            let cursor: Int
        }
        private var lastPluginEditorState: PluginEditorState?
        private var pluginSuggestionRevision: Int?
        private var acceptedCompletionRevisions: [Int] = []
        /// Only a few are kept: the edits use the latest.
        private static let maximumAcceptedCompletionRevisions = 8
        /// Block views kept off screen, by their estimated memory. At 24 MB the iPad kept about a
        /// third of a 40-section note's 120 block views and built 84 again scrolling back up
        /// (23 to 24 frames of 97 over 16 ms); at 64 MB it builds about 28 (9 to 10 over 16 ms)
        /// for about 40 MB more at the peak (simulator, 2026-10-22). The iPhone has less memory.
        /// A memory warning empties the pool either way.
        private static var detachedViewsBudgetMegabytes: Int { UIDevice.current.userInterfaceIdiom == .pad ? 64 : 32 }

        init(session: MarkdownSession, configuration: EditorConfiguration) {
            self.session = session
            // The properties show their YAML while the cursor is in it, as any block's source.
            styling = MarkdownEditorStyling(configuration: configuration, propertiesSource: .whileTheCursorIsInIt,
                                            detachedViewsBudgetMegabytes: Self.detachedViewsBudgetMegabytes)
            super.init()
            styling.revealsMarkupAtSelection = false
            styling.foldedRegions = { [weak self] in self?.foldedRegions ?? [] }
            // The text view's next layout pass places the rendered blocks and fold buttons.
            styling.didRestyle = { restyledTextView in (restyledTextView as? UIView)?.setNeedsLayout() }
        }

        // MARK: Lifetime

        var editedSession: MarkdownSession { session }
        var retainedTextLength: Int { textView?.textStorage.length ?? 0 }

        /// Takes in the container of a new SwiftUI view of the note. A hidden note's text
        /// view is shown in it at once. A text view that an earlier view still shows stays
        /// there until that view is dismantled: SwiftUI makes the new view in the middle
        /// of its update, where taking the keyboard from the text view made SwiftUI update
        /// again from inside that update, and it can dismantle the new view before the
        /// earlier one. So does a view made while a dismantled one lets go of the text view.
        func viewWasMade(with container: MarkdownEditorContainerView) {
            let isShownInEarlierView = containersInUse.contains { earlierContainer in earlierContainer.textViewShownHere != nil }
            containersInUse.add(container)
            guard let textView, !isShownInEarlierView, !isLettingGoOfTextView, container.textViewShownHere == nil else { return }
            // The same text view, cursor, layout, and undo history as when it was hidden.
            container.host(textView)
            resume(textView)
        }

        /// Lets go of the container of a dismantled SwiftUI view. The text view it showed
        /// moves to the newest view of the note that is left (the split opening or
        /// closing, a tab moved to the other side); with none left, the editor leaves
        /// the screen.
        ///
        /// The keyboard goes first, from the text view or from a view inside it, such as an
        /// embedded PDF or a rendered block's field. Giving it up can lay the window out at
        /// once, and SwiftUI then makes the note's next view in the middle of this
        /// dismantling; that view gets the text view once this one has let it go. Moving it
        /// there while UIKit was still removing it left SwiftUI updating without end (an
        /// iPad, 2026-10-10).
        func viewWasDismantled(with container: MarkdownEditorContainerView) {
            containersInUse.remove(container)
            guard let textView = container.textViewShownHere else { return }
            // The keyboard given up here, by the text view or a view inside it, does not
            // come back to the note.
            textView.refusesFocus = true
            defer { textView.refusesFocus = false }
            isLettingGoOfTextView = true
            textView.endEditing(true)
            if let remainingContainer = containersInUse.newest {
                remainingContainer.host(textView)
                placeWidgetsAgain(in: textView)
                isLettingGoOfTextView = false
                return
            }
            suspend(textView)
            isLettingGoOfTextView = false
            if let containerMadeMeanwhile = containersInUse.newest {
                containerMadeMeanwhile.host(textView)
                resume(textView)
                return
            }
            if retention?.keepHiddenEditor(self, owner: retentionOwner) != true { discardRetainedEditor() }
        }

        /// Takes the editor off screen without ending it: the text view keeps its text,
        /// selection, and undo history. Rendered blocks are released and rebuilt when it
        /// returns, and insertions requested meanwhile go into the session's text, which
        /// the editor adopts as an undoable edit when it is shown again.
        func suspend(_ textView: MarkdownTextView) {
            // Ends editing first, so leaving editing does not place rendered blocks again.
            textView.endEditing(true)
            session.applyPendingInsertionsBeforeSaving = nil
            session.isEditorAttached = false
            stopObservingCharacterEdits()
            stopObservingMemoryWarnings()
            textView.findInteraction?.dismissFindNavigator()
            recordScrollLocation(of: textView)
            session.recordEditorPlace = nil
            widthWhenHidden = textView.bounds.width
            removeAllWidgets()
            textView.removeFromSuperview()
            session.undoAvailability.follow(nil)
        }

        /// Shows a suspended editor again, in a new container.
        func resume(_ textView: MarkdownTextView) {
            observeCharacterEdits(in: textView)
            observeMemoryWarnings()
            session.completion.performEdits = { [weak self, weak textView] edits in
                guard let self, let textView else { return }
                self.performCompletionEdits(edits, in: textView)
            }
            session.isEditorAttached = true
            session.undoAvailability.follow(textView.undoManager)
            reportPlace(of: textView)
            placeWidgetsAgain(in: textView)
        }

        /// Lets the session ask where the editor is, as Graphite leaves the screen, while the
        /// editor shows the note. A pending jump has not landed yet, and is the place.
        func reportPlace(of textView: MarkdownTextView) {
            session.recordEditorPlace = { [weak self, weak textView] in
                guard let self, let textView, textView.window != nil, self.pendingJump == nil else { return }
                self.recordScrollLocation(of: textView)
            }
        }

        /// Ends the editor for good; its undo history goes with the text view.
        func discardRetainedEditor() {
            guard let textView else { return }
            textView.didLayout = nil
            textView.removeFromSuperview()
            self.textView = nil
        }

        /// A kept text view shown at another width (the other side of a split, a rotation
        /// while hidden) returns to the line that was at its top.
        func returnToScrollLocationIfWidthChangedWhileHidden(in textView: MarkdownTextView) {
            guard let widthWhenHidden, textView.window != nil, textView.bounds.width > 0 else { return }
            self.widthWhenHidden = nil
            guard abs(textView.bounds.width - widthWhenHidden) > 0.5, pendingJump == nil,
                  let savedScrollLocation = session.savedScrollLocation else { return }
            pendingJump = .topOfCharacter(savedScrollLocation)
        }

        // MARK: Apple Pencil

        func pencilInteraction(_ interaction: UIPencilInteraction, didReceiveTap tap: UIPencilInteraction.Tap) {
            guard let textView else { return }
            handlePencilDoubleTap(hoverLocation: tap.hoverPose?.location, in: textView)
        }

        /// Starts a drawing, at the hovering Pencil's place in the text when it hovers, else
        /// at the cursor. The iPadOS setting to ignore double-tap is honored.
        func handlePencilDoubleTap(hoverLocation: CGPoint?, in textView: MarkdownTextView,
                                   preferredTapAction: UIPencilPreferredAction = UIPencilInteraction.preferredTapAction) {
            guard preferredTapAction != .ignore else { return }
            startDrawingAtPencil(hoverLocation: hoverLocation, in: textView)
        }

        func pencilInteraction(_ interaction: UIPencilInteraction, didReceiveSqueeze squeeze: UIPencilInteraction.Squeeze) {
            guard squeeze.phase == .ended, let textView else { return }
            handlePencilSqueeze(hoverLocation: squeeze.hoverPose?.location, in: textView)
        }

        /// A squeeze of Apple Pencil Pro starts a drawing as a double-tap does, when iPadOS
        /// leaves the squeeze to the app to show its tools; a note's tools are its drawing.
        func handlePencilSqueeze(hoverLocation: CGPoint?, in textView: MarkdownTextView,
                                 preferredSqueezeAction: UIPencilPreferredAction = UIPencilInteraction.preferredSqueezeAction) {
            guard preferredSqueezeAction == .showContextualPalette else { return }
            startDrawingAtPencil(hoverLocation: hoverLocation, in: textView)
        }

        private func startDrawingAtPencil(hoverLocation: CGPoint?, in textView: MarkdownTextView) {
            // Apple Pencil's double-tap and squeeze reach every Pencil interaction in the
            // window, so one made in the drawing editor reaches the note under it too;
            // answering it would replace the open drawing, unsaved strokes and all.
            guard let drawOnPencilDoubleTap = actions.drawOnPencilDoubleTap, textView.window != nil,
                  !textView.isCoveredByPresentedScreen else { return }
            if let hoverLocation, let position = textView.closestPosition(to: hoverLocation) {
                let offset = textView.offset(from: textView.beginningOfDocument, to: position)
                textView.selectedRange = NSRange(location: offset, length: 0)
                session.selection = textView.selectedRange
            }
            drawOnPencilDoubleTap()
        }

        private var isLivePreview: Bool { styling.rendersBlocks }
        /// What decides which blocks are rendered besides the configuration: plugins that
        /// register a code block language later have their blocks found again.
        var renderedBlockPolicy: [String] { styling.renderedBlockPolicy }
        var textRevision: Int { textState.history.revision }

        // MARK: Character edits

        /// Follows every change to the text view's characters. The text storage reports a
        /// change before UIKit's selection callback runs against the new text, and on paths
        /// that never call `shouldChangeTextIn`: `insertText`, `replace(_:withText:)`,
        /// Backspace, undo and redo, find and replace, and setting the text.
        func observeCharacterEdits(in textView: UITextView) {
            session.applyPendingInsertionsBeforeSaving = { [weak self, weak textView] in
                guard let self, let textView else { return }
                _ = self.applyPendingInsertions(to: textView)
            }
            // UIKit reports `textViewDidChange` after its own edits and Graphite settles its
            // own; this catches a path that does neither, once UIKit's edit is done.
            styling.observeCharacterEdits(in: textView) { [weak self, weak textView] in
                guard let self, let textView else { return }
                self.textViewDidChange(textView)
            }
        }

        func stopObservingCharacterEdits() {
            styling.stopObservingCharacterEdits()
        }

        func observeMemoryWarnings() {
            memoryWarningObserver = NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification,
                                                                           object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.renderedBlocks.dropDetachedViews() }
            }
        }

        func stopObservingMemoryWarnings() {
            if let memoryWarningObserver { NotificationCenter.default.removeObserver(memoryWarningObserver) }
            memoryWarningObserver = nil
        }

        /// The text as an immutable snapshot: reading `UITextView.text` copies the whole note.
        private func currentSource(of textView: UITextView) -> NSString {
            styling.currentSource(of: textView)
        }

        /// Whether blocks, folds, and the revealed markup describe the text on screen, so
        /// they can be styled or acted on.
        private func canStyle(_ textView: UITextView) -> Bool {
            styling.canStyle(textView)
        }

        // MARK: Styling

        func rebuildBlocks(in textView: UITextView, forcesBlockScan: Bool = false) {
            let edit = textState.editSinceBlockScan
            styling.updateTextState(of: textView, forcesBlockScan: forcesBlockScan)
            // The snapshot the blocks were found in, which the next edit names as the text
            // before it: the folds move with that edit only if they were found in the same one.
            let source = textState.source
            // Folding reads every line; typing in plain text only moves the regions, which keeps
            // a keystroke in a long note within a frame.
            if source.length > Self.maximumFoldingLength {
                foldableRegions = []
            } else if let edit, edit.sourceBeforeEdit === foldableRegionsSource,
                      let movedRegions = NoteFolding.regions(foldableRegions, across: edit.edit.replacedRange, replacementLength: edit.edit.editedRange.length,
                                                             before: edit.sourceBeforeEdit, after: source) {
                foldableRegions = movedRegions
            } else {
                foldableRegions = NoteFolding.regions(in: source as String)
            }
            foldableRegionsSource = source
            styling.revealMarkupAtSelection(of: textView)
        }

        func restyleEverything(in textView: UITextView) {
            appliedFoldedKeys = session.foldedKeys
            // The pending edit is styled with the rest, so its blocks and folds must describe the text.
            if textState.cachesDescribeOldText { rebuildBlocks(in: textView) }
            styling.restyleEverything(in: textView)
        }

        private func restyle(_ range: NSRange, in textView: UITextView) {
            styling.restyle(range, in: textView)
        }

        /// Brings blocks and styling up to date after character edits. The blocks follow the
        /// text even while an IME composes, so they never describe older text; styling waits
        /// for the composition to end, because it would disturb the marked text.
        private func settleTextChange(in textView: UITextView) {
            if textState.cachesDescribeOldText { rebuildBlocks(in: textView) }
            guard textView.markedTextRange == nil else { return }
            // A fold that moved to an edited line, or whose hidden text changed, restyles the
            // whole note rather than leaving the old section's lines hidden.
            if carryFoldsAcrossEdit(in: textView) {
                restyleEverything(in: textView)
                styling.restyleBlocksAwaitingRestyle(in: textView)
                return
            }
            styling.restyleUnstyledEdit(in: textView)
        }

        /// The blocks whose source is concealed under their views, in note order: every block
        /// the cursor is not in, all of them while the note is only read, and none that a
        /// folded section hides.
        private func concealedEntries(in textView: UITextView) -> [LivePreviewBlockEntry] {
            styling.concealedEntries(in: textView)
        }

        // MARK: Editing

        /// Puts the cursor in a note just created, as Obsidian does, once the editor is on screen.
        func startEditingIfRequested(in textView: MarkdownTextView) {
            guard session.startsEditingWhenShown, textView.window != nil else { return }
            // After the update: becoming first responder during one would re-enter SwiftUI.
            DispatchQueue.main.async { [weak self, weak textView] in
                guard let self, let textView, textView.window != nil, self.session.startsEditingWhenShown else { return }
                self.session.startsEditingWhenShown = false
                textView.beginEditing()
            }
        }

        /// After the note switched from reading, shows the line that was at the top of the
        /// reading view: a kept editor would otherwise return to where it was itself.
        func goToReadingPlaceIfSwitched(in textView: MarkdownTextView) {
            guard textView.window != nil, let location = session.takeEditingStartLocation() else { return }
            // The note's start is the top of the view, with the inline title above the text.
            guard location > 0 else {
                pendingJump = nil
                textView.setContentOffset(CGPoint(x: textView.contentOffset.x, y: -textView.adjustedContentInset.top), animated: false)
                return
            }
            pendingJump = .topOfCharacter(location)
            performPendingJumpIfReady(in: textView)
        }

        /// Opens the find bar the command palette asked for, once the editor is on screen.
        func presentFindIfRequested(in textView: MarkdownTextView) {
            guard session.findRequest != nil, textView.window != nil else { return }
            DispatchQueue.main.async { [weak self, weak textView] in
                guard let self, let textView, textView.window != nil, let request = self.session.findRequest else { return }
                self.session.findRequest = nil
                textView.findInteraction?.presentFindNavigator(showingReplace: request == .findAndReplace)
            }
        }

        /// Applies every insertion waiting in the session, in order, and tells whether there
        /// was any. Several can be queued between updates, such as images dropped together;
        /// each apply removes its insertion from the queue.
        func applyPendingInsertions(to textView: UITextView) -> Bool {
            var hasAppliedInsertion = false
            while let insertion = session.pendingInsertion, insertion.id != appliedInsertionIdentifier {
                apply(insertion, to: textView)
                hasAppliedInsertion = true
            }
            return hasAppliedInsertion
        }

        func apply(_ insertion: EditorInsertion, to textView: UITextView) {
            appliedInsertionIdentifier = insertion.id
            // Restyling the whole note re-estimates TextKit's layout, which would otherwise
            // leave the view somewhere else in the note; the edit happens where the person is.
            let contentOffset = textView.contentOffset
            defer {
                textView.layoutIfNeeded()
                textView.setContentOffset(contentOffset, animated: false)
                keepSelectionVisible(in: textView)
            }
            let source = currentSource(of: textView)
            var insertionText = insertion.text
            var insertionRange = insertion.range
            var selectionAfter = insertion.selectionAfter
            // A paste or drop prepared its block for the place it asked for.
            let pendingRequest = insertion.selectionAfter == nil ? pendingInsertionRequests.take(preparedFor: insertion.range, in: textState.history) : nil
            if let movedRange = pendingRequest?.currentTarget(in: textState.history), movedRange != insertion.range {
                // The note changed while a paste or drop was loading and saving: the block
                // goes where the person put it, with the line breaks that place needs.
                (insertionText, insertionRange) = MovedBlockInsertion.insertion(of: insertion.text, movedTo: movedRange, in: source)
                selectionAfter = nil
            }
            let safeLocation = min(insertionRange.location, source.length)
            isApplyingInsertion = true
            textView.selectedRange = NSRange(location: safeLocation, length: min(insertionRange.length, source.length - safeLocation))
            // insertText keeps the insertion on the native undo stack.
            isPerformingEdit = true
            textView.insertText(insertionText)
            isPerformingEdit = false
            // insertText leaves the cursor after the inserted text.
            if let pendingRequest {
                pendingInsertionRequests.placeRemainingItems(of: pendingRequest, after: textView.selectedRange.location, at: textRevision)
            }
            if let selectionAfter, NSMaxRange(selectionAfter) <= textView.textStorage.length {
                textView.selectedRange = selectionAfter
            }
            isApplyingInsertion = false
            if textState.cachesDescribeOldText { rebuildBlocks(in: textView) }
            restyleEverything(in: textView)
            publish(textView)
            updateCompletion(in: textView)
            // Consumed synchronously: a recreated editor must never apply it a second time.
            session.markInsertionApplied(insertion)
        }

        /// Hands pastes and drops to the pane's actions, remembering where each asked to go.
        func updateInsertionHandlers(of textView: MarkdownTextView) {
            textView.insertAttachment = actions.insertAttachment == nil ? nil : { [weak self] data, stem, fileExtension, request in
                guard let self, let insertAttachment = self.actions.insertAttachment else { return }
                self.pendingInsertionRequests.remember(request)
                insertAttachment(data, stem, fileExtension, request.range)
            }
            textView.offerPasteToPlugins = actions.pluginPaste
            textView.offerDropToPlugins = actions.pluginDrop
            textView.insertLinkToVaultFile = actions.insertLinkToVaultFile == nil ? nil : { [weak self] path, request in
                guard let self, let insertLinkToVaultFile = self.actions.insertLinkToVaultFile else { return }
                self.pendingInsertionRequests.remember(request)
                insertLinkToVaultFile(path, request.range)
            }
        }

        /// The keyboard toolbar's optional buttons.
        struct KeyboardToolbarButtons: Equatable {
            let attach, choosePhoto, takePhoto, scanDocument, draw: Bool
        }

        /// Builds the keyboard toolbar again when its optional buttons change, such as when
        /// Drawings is turned on or off while the note is open. Its buttons call the pane's
        /// current actions, not the ones from when the toolbar was built.
        func updateKeyboardToolbar(of textView: MarkdownTextView) {
            let buttons = KeyboardToolbarButtons(attach: actions.attach != nil, choosePhoto: actions.choosePhoto != nil,
                                                 takePhoto: actions.takePhoto != nil, scanDocument: actions.scanDocument != nil,
                                                 draw: actions.draw != nil)
            guard buttons != keyboardToolbarButtons else { return }
            keyboardToolbarButtons = buttons
            var toolbarActions = EditorActions()
            if buttons.attach { toolbarActions.attach = { [weak self] in self?.actions.attach?() } }
            if buttons.choosePhoto { toolbarActions.choosePhoto = { [weak self] in self?.actions.choosePhoto?() } }
            if buttons.takePhoto { toolbarActions.takePhoto = { [weak self] in self?.actions.takePhoto?() } }
            if buttons.scanDocument { toolbarActions.scanDocument = { [weak self] in self?.actions.scanDocument?() } }
            if buttons.draw { toolbarActions.draw = { [weak self] in self?.actions.draw?() } }
            textView.inputAccessoryView = EditorKeyboardToolbar(actions: toolbarActions) { [weak self, weak textView] command in
                guard let self, let textView else { return }
                self.run(command, in: textView)
            }
            if textView.isFirstResponder { textView.reloadInputViews() }
        }

        /// Replaces characters as one change that can be undone. Through the text view while
        /// it has the keyboard; otherwise in its text storage, with the undo registered here:
        /// `replace(_:withText:)` on a text view without the keyboard ran the system's smart
        /// dashes over the whole note though they are off for it (iOS 27), so writing one cell
        /// of a table turned every `---` of its delimiter row, and of the frontmatter, into `—`.
        func replaceCharacters(in range: NSRange, with replacement: String, in textView: UITextView) {
            guard NSMaxRange(range) <= textView.textStorage.length else { return }
            if textView.isFirstResponder,
               let start = textView.position(from: textView.beginningOfDocument, offset: range.location),
               let end = textView.position(from: start, offset: range.length),
               let textRange = textView.textRange(from: start, to: end) {
                textView.replace(textRange, withText: replacement)
                return
            }
            let replacedText = (textView.textStorage.string as NSString).substring(with: range)
            let restoredRange = NSRange(location: range.location, length: (replacement as NSString).length)
            // The undo manager does not keep its target alive, and can outlive this editor; the
            // handler keeps its own token, and does nothing once the editor is gone.
            let undoToken = UndoActionToken()
            textView.undoManager?.registerUndo(withTarget: undoToken) { [weak self, weak textView, undoToken] _ in
                withExtendedLifetime(undoToken) {}
                guard let self, let textView else { return }
                // Undoing registers the redo in turn.
                self.isPerformingEdit = true
                self.replaceCharacters(in: restoredRange, with: replacedText, in: textView)
                self.isPerformingEdit = false
                self.textViewDidChange(textView)
            }
            let attributes = textView.textStorage.length > 0
                ? textView.textStorage.attributes(at: min(range.location, textView.textStorage.length - 1), effectiveRange: nil)
                : textView.typingAttributes
            textView.textStorage.replaceCharacters(in: range, with: NSAttributedString(string: replacement, attributes: attributes))
        }

        /// Puts a new text in place by replacing only what differs, through the text view,
        /// so the change joins the undo history instead of clearing it, and the cursor
        /// stays on the same character.
        func replaceText(with newText: String, in textView: UITextView) {
            let oldSource = NSString(string: textView.textStorage.string)
            let newSource = newText as NSString
            guard let (replacedRange, replacementRange) = TextDifference.changedRanges(from: oldSource, to: newSource) else {
                lastSynchronizedText = newText
                return
            }
            let edit = CharacterEdit(editedRange: replacementRange, changeInLength: newSource.length - oldSource.length)
            let selection = TextRangeMapping.insertionTarget(textView.selectedRange, through: edit)
            // Text another app changed, adopted as Graphite comes back to the screen, must not
            // move the note under the reader, as an insertion does not (`apply(_:to:)`).
            let contentOffset = textView.contentOffset
            isPerformingEdit = true
            replaceCharacters(in: replacedRange, with: newSource.substring(with: replacementRange), in: textView)
            isPerformingEdit = false
            if NSMaxRange(selection) <= textView.textStorage.length { textView.selectedRange = selection }
            if let textLayoutManager = textView.textLayoutManager {
                textView.layoutIfNeeded()
                let maximumOffset = maximumContentOffset(of: textView, layoutManager: textLayoutManager)
                textView.setContentOffset(CGPoint(x: contentOffset.x, y: min(max(contentOffset.y, -textView.adjustedContentInset.top), maximumOffset)), animated: false)
            }
            if textState.cachesDescribeOldText || session.text != textView.text { textViewDidChange(textView) }
        }

        /// Obsidian's typing helpers: lists that continue on Return, Tab to indent list
        /// items, bracket pairs, and Backspace removing an empty pair.
        private func smartEdit(replacing range: NSRange, with replacement: String, in textView: UITextView) -> MarkdownTextEdit? {
            let behavior = configuration.editingBehavior
            let text = currentSource(of: textView)
            let selection = textView.selectedRange
            switch replacement {
            case "\n":
                return behavior.continuesLists ? MarkdownEditing.continuingList(in: text, selection: range, indentUnit: behavior.indentUnit, tabSize: behavior.tabSize) : nil
            case "\t":
                let line = text.substring(with: text.lineRange(for: NSRange(location: range.location, length: 0)))
                guard behavior.continuesLists, MarkdownListSyntax.listLine(line.trimmingCharacters(in: .newlines))?.isListItem == true || selection.length > 0 else { return nil }
                return MarkdownEditing.indenting(in: text, selection: selection, indentUnit: behavior.indentUnit)
            case "":
                guard range.length == 1, selection.length == 0, NSMaxRange(range) == selection.location, behavior.pairsBrackets else { return nil }
                return MarkdownEditing.deletingPair(in: text, selection: selection)
            default:
                return MarkdownEditing.pairing(typed: replacement, in: text, selection: range, pairsBrackets: behavior.pairsBrackets, pairsMarkdown: behavior.pairsMarkdown)
            }
        }

        /// Makes an edit through the text view, so it joins the undo history.
        func perform(_ edit: MarkdownTextEdit, in textView: UITextView) {
            let length = textView.textStorage.length
            guard NSMaxRange(edit.range) <= length else { return }
            if edit.range.length > 0 || !edit.replacement.isEmpty {
                isPerformingEdit = true
                replaceCharacters(in: edit.range, with: edit.replacement, in: textView)
                isPerformingEdit = false
            }
            if NSMaxRange(edit.selectionAfter) <= textView.textStorage.length { textView.selectedRange = edit.selectionAfter }
            if textState.cachesDescribeOldText || session.text != textView.text { textViewDidChange(textView) }
            keepSelectionVisible(in: textView)
            textView.setNeedsLayout()
        }

        /// Several edits made at once, such as a link and the `^id` it points to. Each is
        /// written against the original text; the last one's selection is kept.
        func perform(_ edits: [MarkdownTextEdit], in textView: UITextView) {
            guard let primary = edits.last else { return }
            var selectionShift = 0
            for edit in edits.sorted(by: { leftEdit, rightEdit in leftEdit.range.location > rightEdit.range.location }) {
                perform(MarkdownTextEdit(range: edit.range, replacement: edit.replacement, selectionAfter: edit.selectionAfter), in: textView)
                if edit != primary, edit.range.location < primary.range.location { selectionShift += edit.replacement.utf16.count - edit.range.length }
            }
            let selection = NSRange(location: primary.selectionAfter.location + selectionShift, length: primary.selectionAfter.length)
            if NSMaxRange(selection) <= textView.textStorage.length { textView.selectedRange = selection }
        }

        /// An accepted suggestion's edits, which arrive after finding what to insert (and,
        /// for a block link, writing its `^id`). They were made for the text the suggestions
        /// were found in, so they move past what was typed meanwhile. When that typing
        /// changed the text they replace, none are made: a link without its `^id`, or a
        /// query replaced in the middle of new text, would corrupt the note.
        func performCompletionEdits(_ edits: [MarkdownTextEdit], in textView: UITextView) {
            recordAcceptedCompletion()
            // The edits belong to the suggestion accepted last: suggestions are accepted one
            // at a time, and one whose edits could not be found leaves an older revision
            // behind, which would move these edits by typing they already account for.
            let baseRevision = acceptedCompletionRevisions.last
            acceptedCompletionRevisions.removeAll()
            guard let baseRevision else {
                perform(edits, in: textView)
                return
            }
            var movedEdits: [MarkdownTextEdit] = []
            for edit in edits {
                guard let movedRange = textState.history.replacedRange(edit.range, computedAt: baseRevision) else {
                    session.errorMessage = "The note changed before the suggestion could be inserted. Choose it again."
                    return
                }
                let shift = movedRange.location - edit.range.location
                movedEdits.append(MarkdownTextEdit(range: movedRange, replacement: edit.replacement, selectionAfter: edit.selectionAfter.shifted(by: shift)))
            }
            perform(movedEdits, in: textView)
        }

        /// Closes the suggestions on Escape. They were not accepted, so no edits follow.
        func dismissCompletion() {
            completionContextRevision = nil
            session.completion.dismiss()
        }

        /// Suggestions that closed since the last update without Escape were accepted; their
        /// edits are on the way and belong to the revision the suggestions were found at.
        private func recordAcceptedCompletion() {
            guard session.completion.context == nil, let completionContextRevision else { return }
            acceptedCompletionRevisions.append(completionContextRevision)
            if acceptedCompletionRevisions.count > Self.maximumAcceptedCompletionRevisions { acceptedCompletionRevisions.removeFirst() }
            self.completionContextRevision = nil
        }

        /// Shows or hides suggestions for what is typed at the cursor.
        func updateCompletion(in textView: UITextView) {
            recordAcceptedCompletion()
            defer { completionContextRevision = session.completion.context == nil ? nil : textRevision }
            guard textView.isFirstResponder, textView.markedTextRange == nil, textView.selectedRange.length == 0 else {
                session.completion.update(context: nil, caretRect: .zero)
                return
            }
            var context = LinkCompletion.context(in: currentSource(of: textView), cursor: textView.selectedRange.location)
            if context == nil, let pluginEditorDidChange = actions.pluginEditorDidChange {
                // Plugins hear each change and cursor move once; scrolling asks again for the same.
                let key = PluginEditorState(textRevision: textRevision, cursor: textView.selectedRange.location)
                if key != lastPluginEditorState {
                    lastPluginEditorState = key
                    pluginSuggestionRevision = pluginEditorDidChange()
                }
                context = pluginSuggestionRevision.map { revision in CompletionContext.pluginSuggestion(revision: revision) }
            }
            var caretRect = CGRect.zero
            if context != nil, let end = textView.selectedTextRange?.end {
                caretRect = textView.caretRect(for: end).offsetBy(dx: -textView.contentOffset.x, dy: -textView.contentOffset.y)
            }
            session.completion.update(context: context, caretRect: caretRect)
        }

        /// Runs a toolbar, menu, or shortcut command.
        func run(_ command: EditorCommand, in textView: UITextView) {
            switch command {
            case .undo: textView.undoManager?.undo()
            case .redo: textView.undoManager?.redo()
            case .attach: actions.attach?()
            case .draw: actions.draw?()
            case .find: textView.findInteraction?.presentFindNavigator(showingReplace: false)
            case .findAndReplace: textView.findInteraction?.presentFindNavigator(showingReplace: true)
            case .followLink(let placement):
                switch link(atCharacter: textView.selectedRange.location, in: textView, skipsShownMarkup: false) {
                case .note(let target, let isWiki)?:
                    if placement == .currentTab { follow(target, isWiki) } else { actions.followLinkElsewhere?(target, isWiki, placement) }
                case .web(let location)?: UIApplication.shared.open(location)
                case nil: break
                }
            case .dismissKeyboard: textView.resignFirstResponder()
            default:
                guard let edit = MarkdownEditing.edit(for: command, in: currentSource(of: textView), selection: textView.selectedRange,
                                                      indentUnit: configuration.editingBehavior.indentUnit, tabSize: configuration.editingBehavior.tabSize) else { return }
                perform(edit, in: textView)
            }
        }

        /// Scrolls only when the cursor is outside the visible part of the note.
        private func keepSelectionVisible(in textView: UITextView) {
            guard let end = textView.selectedTextRange?.end else { return }
            let caret = textView.caretRect(for: end)
            guard !caret.isNull, !caret.isInfinite else { return }
            let visible = textView.bounds.inset(by: textView.adjustedContentInset)
            if !visible.contains(caret) { textView.scrollRectToVisible(caret.insetBy(dx: 0, dy: -40), animated: false) }
        }

        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText replacement: String) -> Bool {
            // Return at the end of a folded line starts a line after the folded section.
            if !isPerformingEdit, replacement == "\n", range.length == 0, textView.markedTextRange == nil,
               let region = foldedRegions.first(where: { region in region.hiddenRange.location == range.location }) {
                perform(NoteFolding.newLineAfterFoldedSection(region, in: textView.text), in: textView)
                return false
            }
            // An edit that reaches into a folded section unfolds it first, so nothing is
            // typed into, or deleted from, text that cannot be seen.
            if !isPerformingEdit {
                let folded = foldedRegions
                let touchesFold = folded.contains { region in
                    let hidden = NSRange(location: region.hiddenRange.location + 1, length: max(0, region.endLocation - region.hiddenRange.location - 1))
                    return NSIntersectionRange(hidden, range).length > 0 || (range.length == 0 && NSLocationInRange(range.location, hidden))
                }
                if touchesFold {
                    let hiding = folded.filter { region in NSIntersectionRange(NSRange(location: region.hiddenRange.location, length: region.endLocation - region.hiddenRange.location), range).length > 0 || NSLocationInRange(range.location, region.hiddenRange) }
                    session.foldedKeys.subtract(hiding.map(\.key))
                    applyFolds(in: textView)
                }
            }
            // Undo and redo also arrive here, restoring earlier text; they must apply exactly
            // as recorded, not as typing that continues a list or pairs a bracket.
            let isHistoryChange = textView.undoManager?.isUndoing == true || textView.undoManager?.isRedoing == true
            if !isPerformingEdit, !isHistoryChange, session.completion.isVisible, replacement == "\n" || replacement == "\t" {
                session.completion.accept()
                return false
            }
            if !isPerformingEdit, !isHistoryChange, textView.markedTextRange == nil, let smartEdit = smartEdit(replacing: range, with: replacement, in: textView) {
                perform(smartEdit, in: textView)
                return false
            }
            // The folds are carried from before a composition started: during one, the
            // foldable regions already follow the marked text.
            if textView.markedTextRange == nil {
                lengthBeforeEdit = textView.textStorage.length
                editLocationBeforeEdit = range.location
                foldedRegionsBeforeEdit = foldedRegions
            }
            return true
        }

        func textViewDidChange(_ textView: UITextView) {
            // The insertion settles its own change once it is complete.
            guard !isApplyingInsertion else { return }
            settleTextChange(in: textView)
            publish(textView)
            updateCompletion(in: textView)
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            // The cursor is kept in sight from now on, not a heading jumped to.
            pinnedHeading = nil
            actions.beginEditing?()
            isEditing = true
            session.isTyping = true
            // A tap that starts editing is turned into a cursor position after this call.
            // Revealing the markup at the old cursor now would invalidate the layout below
            // it, and the tap would land at the end of the note; the markup is revealed
            // once the cursor is in place.
            DispatchQueue.main.async { [weak self, weak textView] in
                guard let self, let textView, self.isEditing else { return }
                self.updateRevealedMarkup(in: textView)
                self.placeWidgetsAgain(in: textView)
            }
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            isEditing = false
            session.isTyping = false
            formatCodeBlockLeftBehind(in: textView, editingEnded: true)
            // A suggestion chosen as the keyboard closes still gets its edits.
            recordAcceptedCompletion()
            completionContextRevision = nil
            session.completion.update(context: nil, caretRect: .zero)
            updateRevealedMarkup(in: textView)
            // In a split, the other note can take the keyboard without this view being laid
            // out again, so its rendered blocks are placed here.
            placeWidgetsAgain(in: textView)
        }

        /// Places rendered blocks again with a fresh set of passes.
        private func placeWidgetsAgain(in textView: UITextView) {
            unsettledPlacementPasses = 0
            delayedPlacementTries = 0
            textView.setNeedsLayout()
        }

        /// A new width (the sidebar opening, a split, a rotation) reflows the text after TextKit
        /// laid out the viewport for the old one, so placing blocks on those fragments left a
        /// rendered block blank and fold chevrons out of place until the next scroll. Once the
        /// width stops changing, the viewport is laid out again and everything placed on it.
        func placeWidgetsAfterWidthChange(in textView: MarkdownTextView) {
            let width = textView.contentColumnWidth
            let paneWidth = textView.paneContentWidth
            guard abs(width - placedColumnWidth) > 0.5 || abs(paneWidth - placedPaneWidth) > 0.5 else { return }
            placedColumnWidth = width
            placedPaneWidth = paneWidth
            placementAfterWidthChange?.cancel()
            let placement = DispatchWorkItem { [weak self, weak textView] in
                guard let self, let textView, textView.window != nil else { return }
                textView.textLayoutManager?.textViewportLayoutController.layoutViewport()
                self.placeWidgetsAgain(in: textView)
            }
            placementAfterWidthChange = placement
            // After the sidebar's animation, which changes the width many times.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: placement)
        }

        /// The Color, Format, Paragraph and Insert submenus; set by the editor.
        var contextMenu: EditorContextMenuActions?

        /// The system's edit menu, with Graphite's submenus and community plugins' items for
        /// the cursor after it.
        func textView(_ textView: UITextView, editMenuForTextIn range: NSRange, suggestedActions: [UIMenuElement]) -> UIMenu? {
            var extraItems: [UIMenuElement] = []
            if let contextMenu { extraItems += EditorContextMenuContent.menuElements(actions: contextMenu, editorActions: actions) }
            if let readAloudHooks {
                extraItems.append(UIAction(title: "Read from Here", image: UIImage(systemName: "speaker.wave.2")) { _ in
                    readAloudHooks.readFromHere(range.location)
                })
            }
            if let pluginItems = actions.pluginEditMenuElement?() { extraItems.append(pluginItems) }
            guard !extraItems.isEmpty else { return nil }
            return UIMenu(children: suggestedActions + extraItems)
        }

        // MARK: Read Aloud

        var readAloudHooks: ReadAloudEditorHooks?
        private var readAloudTapRecognizer: UITapGestureRecognizer?
        private let readAloudTapDelegate = SimultaneousTapDelegate()

        /// While the note is read, a tap moves reading to the tapped paragraph (or marks a
        /// range end); the view also reports its first visible line and the highlight's place.
        func installReadAloudHooks(_ hooks: ReadAloudEditorHooks?, in textView: MarkdownTextView) {
            readAloudHooks = hooks
            textView.reportReadingHighlightFrame = hooks?.reportHighlightFrame
            if hooks != nil, readAloudTapRecognizer == nil {
                let recognizer = UITapGestureRecognizer(target: self, action: #selector(readAloudTap(_:)))
                recognizer.cancelsTouchesInView = false
                recognizer.delegate = readAloudTapDelegate
                textView.addGestureRecognizer(recognizer)
                readAloudTapRecognizer = recognizer
            }
            readAloudTapRecognizer?.isEnabled = hooks?.isReadingThisNote ?? false
            hooks?.registerVisibleLocation { [weak textView] in
                guard let textView else { return nil }
                let point = CGPoint(x: textView.textContainerInset.left + 8, y: textView.contentOffset.y + textView.adjustedContentInset.top + 12)
                guard let position = textView.closestPosition(to: point) else { return nil }
                return textView.offset(from: textView.beginningOfDocument, to: position)
            }
        }

        @objc private func readAloudTap(_ recognizer: UITapGestureRecognizer) {
            guard let textView = recognizer.view as? UITextView, let hooks = readAloudHooks, hooks.isReadingThisNote,
                  let position = textView.closestPosition(to: recognizer.location(in: textView)) else { return }
            hooks.tapped(textView.offset(from: textView.beginningOfDocument, to: position))
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            // Folds describe the text before an edit until it settles.
            if !textState.cachesDescribeOldText, let target = locationOutsideFolds(for: textView.selectedRange, in: textView) {
                textView.selectedRange = NSRange(location: target, length: 0)
                return
            }
            lastSelectionLocation = textView.selectedRange.location
            if textView.isFirstResponder { session.hasPlacedCursor = true }
            session.selection = textView.selectedRange
            guard !isApplyingInsertion else { return }
            updateRevealedMarkup(in: textView)
            formatCodeBlockLeftBehind(in: textView, editingEnded: false)
            // During an edit the selection is reported before the text; `textViewDidChange`
            // updates the suggestions right after, for the same selection.
            guard !textState.cachesDescribeOldText else { return }
            updateCompletion(in: textView)
        }

        /// Formats the code block the user edited once the selection leaves it or editing
        /// ends, on the next turn of the run loop rather than inside the text view's callback,
        /// through the text view so Undo puts the code back.
        private func formatCodeBlockLeftBehind(in textView: UITextView, editingEnded: Bool) {
            guard configuration.formatsCodeBlocks else { return }
            DispatchQueue.main.async { [weak self, weak textView] in
                guard let self, let textView, textView.markedTextRange == nil,
                      let edit = self.styling.codeFormattingEdit(afterSelectionChangeIn: textView, editingEnded: editingEnded) else { return }
                self.perform(edit, in: textView)
            }
        }

        /// Restyles the markup that starts or stops showing as the selection moves: the
        /// markers of the inline elements it reaches and leaves, the markers of the lines
        /// it moves between, and the rendered blocks the cursor enters or leaves.
        private func updateRevealedMarkup(in textView: UITextView) {
            guard isLivePreview, canStyle(textView) else { return }
            // An edit whose styling waited for an IME composition that ended without
            // `textViewDidChange` is styled now, revealed markup included.
            if textState.hasUnstyledEdit {
                settleTextChange(in: textView)
                return
            }
            styling.restyleRevealedMarkup(in: textView)
        }

        private func publish(_ textView: UITextView) {
            let text = currentSource(of: textView) as String
            session.text = text
            lastSynchronizedText = text
            session.selection = textView.selectedRange
            session.undoAvailability.refresh()
            // An edit moves the text again, so rendered blocks get a fresh set of placement
            // passes; a budget spent earlier would otherwise leave a block unplaced.
            unsettledPlacementPasses = 0
            delayedPlacementTries = 0
        }

        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
            guard let textView = scrollView as? UITextView else { return }
            placeWidgetsAgain(in: textView)
        }

        func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
            guard let textView = scrollView as? UITextView else { return }
            placeWidgetsAgain(in: textView)
        }

        // MARK: Rendered blocks

        /// Places rendered blocks over the space reserved for them. Only fragments TextKit
        /// has laid out for the viewport are used, because only their frames say where the
        /// text on screen is drawn. Forcing layout elsewhere would move the estimated
        /// positions of the visible text, and the views would drift from it. A fragment
        /// outside the viewport keeps an estimated frame, or one from before the blocks
        /// around it took their measured heights, so a view placed from it covers the text
        /// next to it, such as the heading a jump has just brought to the top.
        func positionWidgets(in textView: MarkdownTextView) {
            guard isLivePreview, let environment, let textLayoutManager = textView.textLayoutManager else {
                removeAllWidgets()
                return
            }
            // Mid-edit, the blocks describe the text before it; the views stay until it settles.
            guard !textState.cachesDescribeOldText else { return }
            let column = RenderedBlockColumn(minX: textView.textContainerInset.left + textView.textContainer.lineFragmentPadding,
                                             textContainerTop: textView.textContainerInset.top, width: textView.contentColumnWidth,
                                             paneMinX: textView.paneContentMinX, paneWidth: textView.paneContentWidth)
            // TextKit can have no viewport range until it lays out the viewport again, as after
            // a restyle; that layout places the views. Removing them meanwhile rebuilt them all,
            // each reported its height again and restyled, and the rebuilding could go on
            // without end.
            guard let placement = renderedBlocks.placeViews(of: concealedEntries(in: textView), in: textView, textLayoutManager: textLayoutManager,
                                                            column: column, configuration: configuration, makeRootView: { entry in
                widgetRootView(for: entry, environment: environment, textView: textView)
            }) else { return }
            // The cursor leaving a block restyles it, which replaces its fragment, and TextKit
            // lays the viewport out only after this pass. Waiting a turn of the run loop showed
            // a frame or two with the text below already moved down and the block's space
            // empty. The viewport is laid out now instead, and the blocks placed on it. Laying
            // it out can scroll the view, as when the block takes its height back below a
            // selection that UIKit keeps in sight, so it is laid out once more where it went.
            if !placement.keysAwaitingLayout.isEmpty, !isPlacingOnViewportLaidOutNow {
                isPlacingOnViewportLaidOutNow = true
                defer { isPlacingOnViewportLaidOutNow = false }
                for _ in 0..<2 {
                    let offsetBeforeLayout = textView.contentOffset
                    textLayoutManager.textViewportLayoutController.layoutViewport()
                    if textView.contentOffset == offsetBeforeLayout { break }
                }
                positionWidgets(in: textView)
                return
            }
            renderedBlocks.detachViews(except: placement.keysInUse, entries: blockEntries)
            // A height measured at a new width, or by another editor, is reserved in the text first.
            styling.restyleLater(placement.entriesToRestyle, in: textView)
            // After a jump (the keyboard closing, a scroll to a heading) or a restyle, TextKit
            // can finish laying out the viewport after this pass; try again once it has.
            // A placed view can change the height it reserves, and TextKit then moves the text
            // after this pass; one more pass on the next turn of the run loop follows it.
            if (placement.isMissingBlock || placement.didMoveView) && unsettledPlacementPasses < 6 {
                unsettledPlacementPasses += 1
                DispatchQueue.main.async { [weak textView] in textView?.setNeedsLayout() }
            } else if placement.isMissingBlock && delayedPlacementTries < 3 {
                // Still missing after the quick passes: try again once the view has settled,
                // rather than leaving a gap until the next scroll.
                delayedPlacementTries += 1
                unsettledPlacementPasses = 0
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak textView] in textView?.setNeedsLayout() }
            } else if !placement.isMissingBlock && !placement.didMoveView {
                unsettledPlacementPasses = 0
                delayedPlacementTries = 0
            }
            keepPinnedHeadingAtTop(in: textView)
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            guard let textView = scrollView as? MarkdownTextView else { return }
            // The blocks and fold buttons are placed by the layout pass UIKit runs on every
            // frame of a scroll (`didLayout`); placing them here as well did it twice a frame.
            if session.completion.context != nil { updateCompletion(in: textView) }
        }

        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
            pinnedHeading = nil
            suspendReadingFollow?()
        }

        /// Gives the rendered blocks on screen, and those kept off screen, the environment and
        /// appearance `signature` describes, in place; only the blocks that read the index
        /// when nothing else changed.
        func refreshWidgets(for signature: LivePreviewWidgetSignature, in textView: MarkdownTextView) {
            guard let environment else { return }
            _ = renderedBlocks.refreshViews(for: signature, entries: blockEntries) { entry in
                widgetRootView(for: entry, environment: environment, textView: textView)
            }
        }

        /// Gives every rendered block a new root view, as after a change of appearance.
        func refreshWidgets(in textView: MarkdownTextView) {
            guard let environment else { return }
            renderedBlocks.refreshViews(entries: blockEntries) { entry in widgetRootView(for: entry, environment: environment, textView: textView) }
        }

        /// The appearance is passed in: a hosted view does not inherit it from the text view.
        /// A tap on a block's view puts the cursor at the block's start, showing its source.
        private func widgetRootView(for entry: LivePreviewBlockEntry, environment: LivePreviewEnvironment, textView: MarkdownTextView) -> RenderedBlockRoot {
            let key = entry.key
            let isFrontmatter = entry.block.kind == .frontmatter
            return LivePreviewRenderedBlocks.rootView(for: entry, environment: environment, accentHex: configuration.accentHex,
                                                      colorScheme: textView.traitCollection.userInterfaceStyle == .dark ? .dark : .light, revealSource: { [weak self, weak textView] in
                guard let self, let textView, self.canStyle(textView),
                      let currentEntry = self.blockEntries.first(where: { candidate in candidate.key == key }) else { return }
                textView.beginEditing()
                textView.selectedRange = NSRange(location: currentEntry.range.location, length: 0)
                self.textViewDidChangeSelection(textView)
            }, reportHeight: { [weak self, weak textView] height in
                guard let self, let textView else { return }
                self.styling.reserveMeasuredHeight(height, forBlockWithKey: key, isFrontmatter: isFrontmatter, in: textView)
            }, sourceEditing: RenderedBlockSourceEditing(replaceSource: { [weak self, weak textView] editor, transform in
                guard let self, let textView else { return }
                self.replaceSource(ofBlockWithKey: key, editedBy: editor, using: transform, in: textView)
            }, setIsEditingInView: { [weak self] isEditing, editor in
                guard let self else { return }
                if !isEditing { return self.renderedBlocks.endEditingInView(owner: editor) }
                guard let entry = self.blockEntries.first(where: { candidate in candidate.key == key }) else { return }
                self.renderedBlocks.beginEditingInView(blockWithKey: key, at: entry.range.location, owner: editor)
            }))
        }

        /// Replaces a rendered block's source with what its view made of it, as a table's cell
        /// editor does, through the text view so it can be undone. Mid-edit or during an input
        /// method's composition, the change waits a turn.
        func replaceSource(ofBlockWithKey key: LivePreviewBlockKey, editedBy editor: ObjectIdentifier, using transform: @escaping (String) -> String?,
                           in textView: UITextView, attemptsLeft: Int = 3) {
            guard canStyle(textView), textView.markedTextRange == nil else {
                guard attemptsLeft > 0 else { return }
                DispatchQueue.main.async { [weak self, weak textView] in
                    guard let self, let textView else { return }
                    self.replaceSource(ofBlockWithKey: key, editedBy: editor, using: transform, in: textView, attemptsLeft: attemptsLeft - 1)
                }
                return
            }
            let source = currentSource(of: textView)
            guard let blockRange = renderedBlocks.rangeOfBlock(withKey: key, editedBy: editor, in: blockEntries, source: source),
                  let replacement = transform(source.substring(with: blockRange)) else { return }
            replaceText(with: source.replacingCharacters(in: blockRange, with: replacement), in: textView)
        }

        /// When rendered blocks settle their heights after TextKit laid out the viewport, the
        /// text below them moves down and the laid-out part can end above the bottom of the
        /// view. After a jump, UIKit lays the viewport out for the new offset only after this
        /// pass, which found the lines laid out for the old one: they start below the top of
        /// the view, and the blocks above them (a base just under the heading jumped to) were
        /// never placed. Lines in such a gap have no rendered blocks or fold chevrons until
        /// the next scroll, so the viewport is laid out once more then.
        func layOutViewportAgainIfShort(in textView: MarkdownTextView) {
            guard !isViewportRelayoutPending, let textLayoutManager = textView.textLayoutManager,
                  let viewportRange = textLayoutManager.textViewportLayoutController.viewportRange else { return }
            var laidOutTop = CGFloat.greatestFiniteMagnitude
            var laidOutBottom: CGFloat = 0
            textLayoutManager.enumerateTextLayoutFragments(from: viewportRange.location, options: []) { fragment in
                laidOutTop = min(laidOutTop, fragment.layoutFragmentFrame.minY)
                laidOutBottom = max(laidOutBottom, fragment.layoutFragmentFrame.maxY)
                return fragment.rangeInElement.location.compare(viewportRange.endLocation) == .orderedAscending
            }
            let visibleTop = textView.contentOffset.y - textView.textContainerInset.top
            let documentRange = textLayoutManager.documentRange
            guard laidOutBottom > 0,
                  ViewportLayoutCoverage.leavesVisibleTextUncovered(
                      laidOutTop: laidOutTop, laidOutBottom: laidOutBottom, visibleTop: visibleTop, visibleBottom: visibleTop + textView.bounds.height,
                      startsAtDocumentStart: viewportRange.location.compare(documentRange.location) != .orderedDescending,
                      endsAtDocumentEnd: viewportRange.endLocation.compare(documentRange.endLocation) != .orderedAscending) else { return }
            isViewportRelayoutPending = true
            DispatchQueue.main.async { [weak self, weak textView] in
                guard let self, let textView else { return }
                textView.textLayoutManager?.textViewportLayoutController.layoutViewport()
                self.placeWidgetsAgain(in: textView)
                // Another shortfall is allowed only after a moment, so a note whose end is
                // above the bottom of the view cannot loop.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.isViewportRelayoutPending = false }
            }
        }

        // MARK: Folding

        /// Applies the session's folds: restyles, and moves the cursor out of what is hidden.
        func applyFolds(in textView: UITextView) {
            restyleEverything(in: textView)
            if let target = locationOutsideFolds(for: textView.selectedRange, in: textView) {
                textView.selectedRange = NSRange(location: target, length: 0)
            }
            placeWidgetsAgain(in: textView)
            if let markdownTextView = textView as? MarkdownTextView { positionFoldButtons(in: markdownTextView) }
        }

        func toggleFold(_ key: String, in textView: UITextView) {
            if session.foldedKeys.contains(key) { session.foldedKeys.remove(key) } else { session.foldedKeys.insert(key) }
            applyFolds(in: textView)
        }

        /// A folded heading or list item whose line was edited has a new key; the fold moves to
        /// it, as the fold belongs to the line. Returns whether the folds changed, so the note is
        /// restyled rather than left with the old section's hidden lines.
        private func carryFoldsAcrossEdit(in textView: UITextView) -> Bool {
            let previouslyFolded = foldedRegionsBeforeEdit
            foldedRegionsBeforeEdit = []
            guard !previouslyFolded.isEmpty else { return false }
            let lengthChange = textView.textStorage.length - lengthBeforeEdit
            let editLocation = editLocationBeforeEdit
            // Every fold follows its header to where the edit moved it, whatever key the header
            // has now: keys count headings of the same text, so a new "## Notes" typed above a
            // folded one took its key, and the fold jumped to the other heading.
            var keys = session.foldedKeys.subtracting(previouslyFolded.map(\.key))
            for region in previouslyFolded {
                let headerStart = region.headerRange.location + (editLocation < region.headerRange.location ? lengthChange : 0)
                if let moved = foldableRegions.first(where: { candidate in candidate.headerRange.location == headerStart }) {
                    keys.insert(moved.key)
                } else if foldableRegions.contains(where: { candidate in candidate.key == region.key }) {
                    keys.insert(region.key)
                }
            }
            var changed = keys != session.foldedKeys
            // A section that still folds but whose hidden text moved or changed needs restyling too.
            let stillFolded = NoteFolding.foldedRegions(in: foldableRegions, foldedKeys: keys)
            if stillFolded.map(\.hiddenRange) != previouslyFolded.map({ region in
                NSRange(location: region.hiddenRange.location + (editLocation < region.hiddenRange.location ? lengthChange : 0), length: region.hiddenRange.length)
            }) { changed = true }
            if keys != session.foldedKeys { session.foldedKeys = keys }
            return changed
        }

        /// Unfolds the sections that hide `location`, before a jump shows it.
        private func unfoldSections(hiding location: Int, in textView: UITextView) {
            let hiding = NoteFolding.regions(hiding: location, in: foldedRegions)
            guard !hiding.isEmpty else { return }
            session.foldedKeys.subtract(hiding.map(\.key))
            applyFolds(in: textView)
        }

        /// Where a cursor that landed in a folded section goes instead: past the section when
        /// it moved down into it, else to the end of the section's header line.
        private func locationOutsideFolds(for selection: NSRange, in textView: UITextView) -> Int? {
            guard selection.length == 0 else { return nil }
            let location = selection.location
            let textLength = textView.textStorage.length
            for region in foldedRegions {
                let hasVisibleEnd = region.endLocation > NSMaxRange(region.hiddenRange)
                let isHidden = location > region.hiddenRange.location && (location < region.endLocation || (!hasVisibleEnd && location == region.endLocation))
                guard isHidden else { continue }
                // A tap lands in the hidden text's collapsed lines, which sit at the end of the
                // header line; the arrow keys move from the header past the section.
                let movedDownByOneLine = lastSelectionLocation == region.hiddenRange.location
                return movedDownByOneLine && hasVisibleEnd && region.endLocation <= textLength ? region.endLocation : region.hiddenRange.location
            }
            return nil
        }

        /// Places a chevron beside each heading and list item that folds, and "…" after a
        /// folded one, for the lines TextKit has laid out on screen.
        func positionFoldButtons(in textView: MarkdownTextView) {
            // Mid-edit, the regions describe the text before it; the buttons stay until it settles.
            guard !textState.cachesDescribeOldText else { return }
            guard !foldableRegions.isEmpty, let textLayoutManager = textView.textLayoutManager,
                  let contentStorage = textLayoutManager.textContentManager as? NSTextContentStorage,
                  let viewportRange = textLayoutManager.textViewportLayoutController.viewportRange else {
                removeFoldButtons()
                return
            }
            let regionsByStart = foldLayout.regionsByStart
            let source = currentSource(of: textView)
            let documentStart = contentStorage.documentRange.location
            var keysInUse = Set<String>()
            textLayoutManager.enumerateTextLayoutFragments(from: viewportRange.location, options: []) { fragment in
                let fragmentStart = contentStorage.offset(from: documentStart, to: fragment.rangeInElement.location)
                if let region = regionsByStart[fragmentStart], NSMaxRange(region.headerRange) <= source.length,
                   let firstLine = fragment.textLineFragments.first, let lastLine = fragment.textLineFragments.last {
                    keysInUse.insert(region.key)
                    let isFolded = session.foldedKeys.contains(region.key)
                    let buttons = foldButtons[region.key] ?? makeFoldButtons(for: region.key, in: textView)
                    foldButtons[region.key] = buttons
                    let header = source.substring(with: region.headerRange)
                    let indentLength = (header.prefix { character in character == " " || character == "\t" } as Substring).utf16.count
                    let fragmentOrigin = CGPoint(x: textView.textContainerInset.left + fragment.layoutFragmentFrame.minX,
                                                 y: textView.textContainerInset.top + fragment.layoutFragmentFrame.minY)
                    let textStartX = firstLine.locationForCharacter(at: min(indentLength, max(0, firstLine.characterRange.length - 1))).x
                    // Apple's smallest comfortable touch target; the chevron is drawn at 11 points inside it.
                    let size: CGFloat = 28
                    let firstLineBounds = firstLine.typographicBounds
                    buttons.chevron.frame = CGRect(x: max(2, fragmentOrigin.x + textStartX - size - 4),
                                                   y: fragmentOrigin.y + firstLineBounds.minY + (firstLineBounds.height - size) / 2, width: size, height: size)
                    // Set when the fold or the header changes, not on every frame of a scroll.
                    let chevronImage = isFolded ? Self.foldedChevron : Self.unfoldedChevron
                    if buttons.chevron.image(for: .normal) !== chevronImage {
                        buttons.chevron.setImage(chevronImage, for: .normal)
                        buttons.chevron.alpha = isFolded ? 1 : 0.4
                    }
                    let headerText = header.trimmingCharacters(in: .whitespaces).drop { character in character == "#" }
                        .trimmingCharacters(in: .whitespaces)
                    let label = isFolded ? "Unfold \(headerText)" : "Fold \(headerText)"
                    if buttons.chevron.accessibilityLabel != label { buttons.chevron.accessibilityLabel = label }
                    buttons.ellipsis.isHidden = !isFolded
                    if isFolded {
                        let lastLineBounds = lastLine.typographicBounds
                        buttons.ellipsis.frame = CGRect(x: fragmentOrigin.x + lastLineBounds.maxX + 6,
                                                        y: fragmentOrigin.y + lastLineBounds.minY + (lastLineBounds.height - size) / 2, width: 34, height: size)
                    }
                }
                return fragment.rangeInElement.location.compare(viewportRange.endLocation) == .orderedAscending
            }
            for (key, buttons) in foldButtons where !keysInUse.contains(key) {
                buttons.chevron.removeFromSuperview()
                buttons.ellipsis.removeFromSuperview()
                foldButtons[key] = nil
            }
        }

        private static let foldedChevron = UIImage(systemName: "chevron.right", withConfiguration: UIImage.SymbolConfiguration(pointSize: 11, weight: .semibold))
        private static let unfoldedChevron = UIImage(systemName: "chevron.down", withConfiguration: UIImage.SymbolConfiguration(pointSize: 11, weight: .semibold))

        private func makeFoldButtons(for key: String, in textView: UITextView) -> (chevron: UIButton, ellipsis: UIButton) {
            let toggle = UIAction { [weak self, weak textView] _ in
                guard let self, let textView else { return }
                self.toggleFold(key, in: textView)
            }
            let chevron = UIButton(type: .system, primaryAction: toggle)
            chevron.tintColor = .secondaryLabel
            let ellipsis = UIButton(type: .system, primaryAction: toggle)
            ellipsis.setTitle("…", for: .normal)
            ellipsis.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
            ellipsis.tintColor = .secondaryLabel
            ellipsis.backgroundColor = UIColor.tertiarySystemFill
            ellipsis.layer.cornerRadius = 6
            ellipsis.accessibilityLabel = "Unfold"
            textView.addSubview(chevron)
            textView.addSubview(ellipsis)
            return (chevron, ellipsis)
        }

        private func removeFoldButtons() {
            for buttons in foldButtons.values {
                buttons.chevron.removeFromSuperview()
                buttons.ellipsis.removeFromSuperview()
            }
            foldButtons.removeAll()
        }

        func removeAllWidgets() {
            renderedBlocks.removeAllViews()
        }

        // MARK: Drawn replacements

        nonisolated func textLayoutManager(_ textLayoutManager: NSTextLayoutManager, textLayoutFragmentFor location: NSTextLocation,
                                           in textElement: NSTextElement) -> NSTextLayoutFragment {
            ConcealedReplacementLayoutFragment(textElement: textElement, range: textElement.elementRange)
        }

        // MARK: Links, tasks, and headings

        /// Pinching the note changes the vault's font size while quick adjustment is on.
        func installQuickFontSizePinch(on textView: UITextView) {
            let recognizer = QuickFontSizePinchRecognizer()
            recognizer.adjustment = actions.quickFontSize
            textView.addGestureRecognizer(recognizer)
            quickFontSizePinch = recognizer
        }

        func installLinkTapRecognizer(on textView: UITextView) {
            let recognizer = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
            recognizer.delegate = self
            textView.addGestureRecognizer(recognizer)
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let textView = gestureRecognizer.view as? UITextView else { return false }
            let point = gestureRecognizer.location(in: textView)
            return taskCheckboxRange(at: point, in: textView) != nil || link(at: point, in: textView) != nil
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { false }

        @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard let textView = recognizer.view as? UITextView else { return }
            let point = recognizer.location(in: textView)
            if let checkboxRange = taskCheckboxRange(at: point, in: textView) {
                toggleTask(checkboxRange, in: textView)
            } else if let link = link(at: point, in: textView) {
                switch link {
                case .note(let target, let isWiki):
                    // ⌘ opens the link in a new tab, ⌥⌘ beside the note and ⇧⌥⌘ in a new window, as in Obsidian.
                    let modifierFlags = recognizer.modifierFlags
                    if modifierFlags.contains(.command), let followLinkElsewhere = actions.followLinkElsewhere {
                        followLinkElsewhere(target, isWiki, TabPlacement.forLink(command: true, option: modifierFlags.contains(.alternate),
                                                                                 shift: modifierFlags.contains(.shift)))
                    } else {
                        follow(target, isWiki)
                    }
                case .web(let location):
                    UIApplication.shared.open(location)
                }
            }
        }

        /// The `[ ]` or `[x]` under the finger on a line whose checkbox is drawn.
        private func taskCheckboxRange(at point: CGPoint, in textView: UITextView) -> NSRange? {
            guard isLivePreview, canStyle(textView), let position = textView.closestPosition(to: point) else { return nil }
            let characterIndex = textView.offset(from: textView.beginningOfDocument, to: position)
            let source = currentSource(of: textView)
            guard characterIndex <= source.length else { return nil }
            // The selection's lines show `[ ]` as written, and a tap there places the cursor.
            let lineRange = source.lineRange(for: NSRange(location: characterIndex, length: 0))
            if let revealedMarkup, revealedMarkup.showsLineMarker(at: lineRange.location) { return nil }
            return LivePreviewTapTargets.taskCheckboxRange(at: characterIndex, in: source)
        }

        /// Checks or unchecks a task through the text view, so the change can be undone.
        private func toggleTask(_ checkboxRange: NSRange, in textView: UITextView) {
            let source = currentSource(of: textView)
            let stateRange = NSRange(location: checkboxRange.location + 1, length: 1)
            guard NSMaxRange(stateRange) <= source.length else { return }
            let isChecked = source.substring(with: stateRange) != " "
            let selectedRange = textView.selectedRange
            isPerformingEdit = true
            replaceCharacters(in: stateRange, with: isChecked ? " " : "x", in: textView)
            isPerformingEdit = false
            textView.selectedRange = selectedRange
            if textState.cachesDescribeOldText || session.text != textView.text { textViewDidChange(textView) }
        }

        /// A link under the finger whose markup is concealed, as in Obsidian's Live
        /// Preview, where a tap on a link follows it instead of placing the cursor.
        private func link(at point: CGPoint, in textView: UITextView) -> LinkInText? {
            guard isLivePreview, let position = textView.closestPosition(to: point) else { return nil }
            return link(atCharacter: textView.offset(from: textView.beginningOfDocument, to: position), in: textView, skipsShownMarkup: true)
        }

        /// The link around a character. Taps skip a link whose markup is showing, which is
        /// being edited; the keyboard's link commands do not. A link written in code or
        /// math is text.
        func link(atCharacter characterIndex: Int, in textView: UITextView, skipsShownMarkup: Bool) -> LinkInText? {
            let source = currentSource(of: textView)
            guard characterIndex <= source.length, source.length > 0 else { return nil }
            if skipsShownMarkup {
                guard characterIndex < source.length else { return nil }
                if let revealedMarkup, canStyle(textView),
                   LivePreviewTapTargets.isInsideLinkShowingItsMarkup(characterIndex, in: source, revealedMarkup: revealedMarkup) { return nil }
            }
            let lineRange = source.lineRange(for: NSRange(location: characterIndex, length: 0))
            guard let link = LinkLocator.link(in: source.substring(with: lineRange), at: characterIndex - lineRange.location, includesEnd: !skipsShownMarkup),
                  !LivePreviewTapTargets.isInsideCode(characterIndex, in: source) else { return nil }
            return link
        }

        // MARK: Jumps

        /// Runs the pending jump from the next turn of the run loop once a layout pass finds
        /// the view in a window with a width. Layout passes do not scroll from inside themselves.
        func schedulePendingJumpIfReady(in textView: MarkdownTextView) {
            guard pendingJump != nil, !isPendingJumpScheduled, textView.window != nil, textView.bounds.width > 0 else { return }
            isPendingJumpScheduled = true
            DispatchQueue.main.async { [weak self, weak textView] in
                guard let self else { return }
                self.isPendingJumpScheduled = false
                guard let textView else { return }
                self.performPendingJumpIfReady(in: textView)
            }
        }

        /// Makes the pending jump when the view is in a window and has a width; otherwise it
        /// waits for a layout pass that finds both.
        func performPendingJumpIfReady(in textView: UITextView) {
            guard let jump = pendingJump, textView.window != nil, textView.bounds.width > 0 else { return }
            pendingJump = nil
            switch jump {
            case .heading(let anchor, let occurrence): scroll(to: anchor, occurrence: occurrence, in: textView)
            case .textRange(let range): reveal(range, in: textView)
            case .topOfCharacter(let characterLocation): scrollToTop(of: min(characterLocation, textView.textStorage.length), in: textView)
            }
        }

        /// Brings a heading to the top of the view, as Obsidian's outline does. The cursor
        /// moves there only while editing, so a jump never raises the keyboard.
        /// - Parameter occurrence: Which of the headings with this anchor, from zero, for
        ///   notes where several headings read the same.
        func scroll(to anchor: String, occurrence: Int = 0, in textView: UITextView) {
            guard let lineLocation = HeadingLocator.lineLocation(ofHeadingWithAnchor: anchor, occurrence: occurrence, in: currentSource(of: textView)) else { return }
            unfoldSections(hiding: lineLocation, in: textView)
            if textView.isFirstResponder { textView.selectedRange = NSRange(location: lineLocation, length: 0) }
            scrollToTop(of: lineLocation, in: textView)
        }

        /// Shows a range, such as a search match or a linked block, near the top and marks it
        /// briefly. The mark is drawn by Graphite: the system's find highlight asserts when
        /// the text view is not yet in a window, as happens right after a note opens.
        func reveal(_ range: NSRange, in textView: UITextView) {
            let source = currentSource(of: textView)
            guard NSMaxRange(range) <= source.length else { return }
            unfoldSections(hiding: range.location, in: textView)
            scrollToTop(of: source.lineRange(for: NSRange(location: range.location, length: 0)).location, in: textView)
            if textView.isFirstResponder { textView.selectedRange = NSRange(location: range.location, length: 0) }
            Task { @MainActor [weak self, weak textView] in
                // After the jump settles, so the mark lands on the text's final position.
                try? await Task.sleep(for: .milliseconds(250))
                guard let self, let textView, textView.window != nil, NSMaxRange(range) <= textView.textStorage.length else { return }
                self.flashHighlight(range, in: textView)
            }
        }

        private func flashHighlight(_ range: NSRange, in textView: UITextView) {
            guard let start = textView.position(from: textView.beginningOfDocument, offset: range.location),
                  let end = textView.position(from: start, offset: range.length),
                  let textRange = textView.textRange(from: start, to: end) else { return }
            let accent = UIColor.graphiteAccent(hex: configuration.accentHex) ?? .tintColor
            let rects = textView.selectionRects(for: textRange).map(\.rect).filter { rect in rect.width > 1 && rect.height > 1 }
            let marks = rects.map { rect -> UIView in
                let mark = UIView(frame: rect.insetBy(dx: -2, dy: -1))
                mark.backgroundColor = accent.withAlphaComponent(0.28)
                mark.layer.cornerRadius = 4
                mark.isUserInteractionEnabled = false
                textView.addSubview(mark)
                return mark
            }
            UIView.animate(withDuration: 0.6, delay: 1.8, options: [.allowUserInteraction]) {
                marks.forEach { mark in mark.alpha = 0 }
            } completion: { _ in
                marks.forEach { mark in mark.removeFromSuperview() }
            }
        }

        /// Corrects the offset while the blocks above a heading that was jumped to take their
        /// measured heights, as long as `HeadingJumpPin` holds: while a block above has not
        /// reported its height (a base loading its rows), and for a moment after the heading
        /// last moved or such a block reported. A heading near the end of the note stops where the note ends, as the
        /// jump itself does.
        private func keepPinnedHeadingAtTop(in textView: UITextView) {
            guard var pinnedHeading else { return }
            let uptime = ProcessInfo.processInfo.systemUptime
            let isBlockAboveAwaitingHeight = renderedBlocks.hasPlacedBlockAwaitingHeight(before: pinnedHeading.location, in: blockEntries)
            let holds = pinnedHeading.holds(atUptime: uptime, isBlockAboveAwaitingHeight: isBlockAboveAwaitingHeight)
            self.pinnedHeading = holds ? pinnedHeading : nil
            guard holds else { return }
            guard let textLayoutManager = textView.textLayoutManager,
                  let contentStorage = textLayoutManager.textContentManager as? NSTextContentStorage,
                  let location = contentStorage.location(contentStorage.documentRange.location, offsetBy: pinnedHeading.location),
                  var fragment = textLayoutManager.textLayoutFragment(for: location) else { return }
            // A heading's fragment that a restyle replaced has no frame until TextKit lays it
            // out again, which it does only within the viewport. A block above that grew can
            // leave the heading above the viewport, where no later pass would, so the text up
            // to and including the heading is laid out here, as the jump does.
            if fragment.state != .layoutAvailable {
                guard let throughHeading = NSTextRange(location: contentStorage.documentRange.location, end: fragment.rangeInElement.endLocation) else { return }
                textLayoutManager.ensureLayout(for: throughHeading)
                guard let laidOutFragment = textLayoutManager.textLayoutFragment(for: location), laidOutFragment.state == .layoutAvailable else { return }
                fragment = laidOutFragment
            }
            let targetOffset = fragment.layoutFragmentFrame.minY + textView.textContainerInset.top - 12
            let clampedOffset = min(max(-textView.adjustedContentInset.top, targetOffset), maximumContentOffset(of: textView, layoutManager: textLayoutManager))
            if abs(textView.contentOffset.y - clampedOffset) > 1 {
                textView.setContentOffset(CGPoint(x: textView.contentOffset.x, y: clampedOffset), animated: false)
                self.pinnedHeading?.recordMove(atUptime: uptime)
            }
        }

        /// The largest vertical offset that still ends at the note's end. The content size
        /// can lag behind a layout just forced, so the layout's own height bounds it too.
        private func maximumContentOffset(of textView: UITextView, layoutManager textLayoutManager: NSTextLayoutManager) -> CGFloat {
            let contentHeight = max(textView.contentSize.height,
                                    textLayoutManager.usageBoundsForTextContainer.maxY + textView.textContainerInset.top + textView.textContainerInset.bottom)
            return max(-textView.adjustedContentInset.top, contentHeight - textView.bounds.height + textView.adjustedContentInset.bottom)
        }

        /// Remembers the character at the top of the view in the session.
        func recordScrollLocation(of textView: UITextView) {
            guard textView.contentOffset.y > -textView.adjustedContentInset.top + 1 else {
                session.savedScrollLocation = nil
                return
            }
            guard let textLayoutManager = textView.textLayoutManager,
                  let fragment = textLayoutManager.textLayoutFragment(for: CGPoint(x: 0, y: textView.contentOffset.y + 12 - textView.textContainerInset.top)) else { return }
            let contentManager = textLayoutManager.textContentManager
            session.savedScrollLocation = contentManager.map { manager in manager.offset(from: manager.documentRange.location, to: fragment.rangeInElement.location) }
        }

        func scrollToTop(of characterLocation: Int, in textView: UITextView) {
            pinnedHeading = HeadingJumpPin(location: characterLocation, pinnedAtUptime: ProcessInfo.processInfo.systemUptime)
            guard let textLayoutManager = textView.textLayoutManager,
                  let contentStorage = textLayoutManager.textContentManager as? NSTextContentStorage,
                  let location = contentStorage.location(contentStorage.documentRange.location, offsetBy: characterLocation),
                  let precedingRange = NSTextRange(location: contentStorage.documentRange.location, end: location) else { return }
            // Positions before the heading must be real, not estimated, for the jump to land.
            textLayoutManager.ensureLayout(for: precedingRange)
            guard let fragment = textLayoutManager.textLayoutFragment(for: location) else { return }
            let targetOffset = fragment.layoutFragmentFrame.minY + textView.textContainerInset.top - 12
            let maximumOffset = maximumContentOffset(of: textView, layoutManager: textLayoutManager)
            textView.setContentOffset(CGPoint(x: textView.contentOffset.x, y: min(max(-textView.adjustedContentInset.top, targetOffset), maximumOffset)), animated: false)
            textView.setNeedsLayout()
        }
    }
}
#else
import AppKit

/// The Mac's Markdown text view. Pasted and dropped files and images become attachments,
/// items dragged from the sidebar become links, and a click on a link whose markup is
/// concealed follows it, as on the iPad.
final class MarkdownMacTextView: NSTextView {
    /// The inherited convenience factory currently creates TextKit 1. Source
    /// highlights and native geometry require an explicitly owned TextKit 2 view.
    static func makeScrollableTextView() -> NSScrollView {
        let textView = MarkdownMacTextView(usingTextLayoutManager: true)
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        textView.minSize = .zero
        textView.maxSize = CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = .width
        // The find bar of "Search current file" shows above the note, inside the scroll view.
        textView.usesFindBar = true
        textView.textContainer?.containerSize = CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        scrollView.documentView = textView
        return scrollView
    }

    var readAloudRange: NSRange? { didSet { if readAloudRange != oldValue { needsDisplay = true } } }
    var suspendReadingFollow: (() -> Void)?

    func followReadingRange() {
        guard window != nil, let range = readAloudRange, range.location >= 0, range.length > 0,
              let textStorage, range.location <= textStorage.length, range.length <= textStorage.length - range.location else { return }
        scrollRangeToVisible(range)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let range = readAloudRange, range.location >= 0, range.length > 0,
              let textStorage, range.location <= textStorage.length, range.length <= textStorage.length - range.location,
              let textLayoutManager, let contentManager = textLayoutManager.textContentManager,
              let start = contentManager.location(contentManager.documentRange.location, offsetBy: range.location),
              let end = contentManager.location(start, offsetBy: range.length), let textRange = NSTextRange(location: start, end: end) else { return }
        ReadAloudHighlightStyle.fill.setFill()
        textLayoutManager.enumerateTextSegments(in: textRange, type: .standard, options: []) { _, frame, _, _ in
            let positionedFrame = frame.offsetBy(dx: self.textContainerOrigin.x, dy: self.textContainerOrigin.y)
            if positionedFrame.intersects(dirtyRect) { NSBezierPath(roundedRect: positionedFrame, xRadius: 3, yRadius: 3).fill() }
            return true
        }
    }
    /// Saves pasted or dropped files and images, and links vault items; set by the coordinator.
    var insertAttachment: ((_ data: Data, _ stem: String, _ fileExtension: String, _ range: NSRange) -> Void)?
    var insertLinkToVaultFile: ((VaultPath, NSRange) -> Void)?
    /// Tells the person that a pasted or dropped file could not be read; set by the coordinator.
    var reportUnreadableItem: (() -> Void)?
    /// Follows the link a click lands on and says whether there was one; set by the coordinator.
    var followLinkOnClick: ((_ characterIndex: Int, _ modifierFlags: NSEvent.ModifierFlags) -> Bool)?
    /// Checks or unchecks the drawn task box a click lands on and says whether there was
    /// one; set by the coordinator.
    var toggleTaskOnClick: ((_ characterIndex: Int) -> Bool)?
    /// Called when the view takes keyboard focus; set by the coordinator.
    var didBecomeFirstResponder: (() -> Void)?
    /// Called when the view gives up keyboard focus, as when the file list takes it; set by
    /// the coordinator.
    var didResignFirstResponder: (() -> Void)?
    /// Control-scrolling or pinching the trackpad changes the vault's font size; nil when
    /// quick adjustment is off. Set by the coordinator.
    var quickFontSize: QuickFontSizeAdjustment?
    private var quickFontSizeInput = QuickFontSizeMacInput()

    /// The vault's editing shortcuts; set by the editor.
    var keyCommandTable = EditorKeyCommandTable.defaults
    /// The editor's coordinator, which runs the editing command a shortcut names.
    weak var keyCommandOwner: NativeMarkdownEditor.Coordinator?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if window?.firstResponder === self, runKeyCommand(for: event) { return true }
        return super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if runKeyCommand(for: event) { return }
        super.keyDown(with: event)
    }

    /// Runs the editing command the vault gives the key press; false when it gives none, or
    /// while text is being composed.
    private func runKeyCommand(for event: NSEvent) -> Bool {
        guard !hasMarkedText(), let keyCommandOwner, let combination = KeyCombination(event: event),
              let editorCommand = keyCommandTable.command(matching: combination)?.editorCommand else { return false }
        return keyCommandOwner.runKeyCommand(editorCommand, in: self)
    }

    override func scrollWheel(with event: NSEvent) {
        // Control-scrolling changes the font size and does not scroll, so reading keeps following.
        if quickFontSizeInput.handleScroll(event, adjustment: quickFontSize) { return }
        suspendReadingFollow?()
        super.scrollWheel(with: event)
    }

    override func magnify(with event: NSEvent) {
        if quickFontSizeInput.handleMagnify(event, adjustment: quickFontSize) { return }
        super.magnify(with: event)
    }
    /// Called when the view enters a window or first gets a width, the two things a jump
    /// needs to measure the note; set by the coordinator.
    var didBecomeMeasurable: ((MarkdownMacTextView) -> Void)?
    /// Called when the text column moves or changes width, which the views placed over the
    /// text follow; set by the coordinator.
    var didMoveTextColumn: (() -> Void)?
    /// Called once TextKit has laid out the viewport, as the view scrolls or its text
    /// changes, where the rendered blocks are placed; set by the coordinator.
    var didLayOutViewport: (() -> Void)?

    override func textViewportLayoutControllerDidLayout(_ textViewportLayoutController: NSTextViewportLayoutController) {
        super.textViewportLayoutControllerDidLayout(textViewportLayoutController)
        didLayOutViewport?()
    }

    private var canInsertAttachments: Bool { insertAttachment != nil || insertLinkToVaultFile != nil }

    override func becomeFirstResponder() -> Bool {
        let didBecome = super.becomeFirstResponder()
        if didBecome { didBecomeFirstResponder?() }
        return didBecome
    }

    override func resignFirstResponder() -> Bool {
        let didResign = super.resignFirstResponder()
        if didResign { didResignFirstResponder?() }
        return didResign
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { didBecomeMeasurable?(self) }
    }

    override func setFrameSize(_ newSize: NSSize) {
        let previousWidth = frame.width
        super.setFrameSize(newSize)
        updateReadableInset()
        // The view grows taller with its text; only a new width moves the column.
        if newSize.width != previousWidth { didMoveTextColumn?() }
        if previousWidth <= 0, newSize.width > 0 { didBecomeMeasurable?(self) }
    }

    /// The readable column's width (Graphite's, or the vault theme's line width), or nil to
    /// use the whole width; as the iPad editor, the text is centered in it.
    var readableColumnWidth: CGFloat? { didSet { if readableColumnWidth != oldValue { updateReadableInset() } } }
    static let minimumHorizontalInset: CGFloat = 32
    /// The iPad editor's column, so a note wraps alike on both.
    static let graphiteReadableColumnWidth: CGFloat = 740

    /// The left edge of the pane inside its margins, where a base starts.
    var paneContentMinX: CGFloat { Self.minimumHorizontalInset + (textContainer?.lineFragmentPadding ?? 0) }
    /// The pane's width inside its margins, which a base takes.
    var paneContentWidth: CGFloat { max(0, frame.width - 2 * paneContentMinX) }

    private func updateReadableInset() {
        let horizontalInset = readableColumnWidth.map { width in max(Self.minimumHorizontalInset, (frame.width - width) / 2) } ?? Self.minimumHorizontalInset
        guard abs(textContainerInset.width - horizontalInset) > 0.5 else { return }
        textContainerInset = CGSize(width: horizontalInset, height: textContainerInset.height)
        didMoveTextColumn?()
    }

    override func mouseDown(with event: NSEvent) {
        // Control-click opens the context menu, with the plugins' items.
        if event.modifierFlags.contains(.control), pluginContextMenuItems != nil {
            rightMouseDown(with: event)
            return
        }
        let characterIndex = characterIndexForInsertion(at: convert(event.locationInWindow, from: nil))
        if event.clickCount == 1, toggleTaskOnClick?(characterIndex) == true { return }
        if event.clickCount == 1, followLinkOnClick?(characterIndex, event.modifierFlags) == true { return }
        super.mouseDown(with: event)
    }

    // MARK: Plugins' menu items and paste

    /// Asks community plugins for their items in the context menu at the cursor; set by the
    /// coordinator while plugins add some.
    var pluginContextMenuItems: (() async -> [NSMenuItem])?
    /// The plugins' items for the menu being opened; empty otherwise.
    var pendingPluginMenuItems: [NSMenuItem] = []
    /// Offers a paste to community plugins that listen; true when one took it over.
    var offerPasteToPlugins: ((_ text: String?, _ html: String?) async -> Bool)?

    /// The Color, Format, Paragraph and Insert submenus, built when the menu opens; set by the
    /// pane's update, nil outside Source and Live Preview editing.
    var contextMenuEntries: (() -> [EditorContextMenuEntry])?

    override func rightMouseDown(with event: NSEvent) {
        // As in Obsidian, the menu is for where it was opened: a click outside the selection
        // moves the cursor there first, so a menu item acts on the word clicked.
        if pluginContextMenuItems != nil || contextMenuEntries != nil {
            let characterIndex = characterIndexForInsertion(at: convert(event.locationInWindow, from: nil))
            if !NSLocationInRange(characterIndex, selectedRange()) || selectedRange().length == 0 {
                setSelectedRange(NSRange(location: characterIndex, length: 0))
            }
        }
        guard let pluginContextMenuItems else {
            super.rightMouseDown(with: event)
            return
        }
        Task { @MainActor [weak self] in
            let items = await pluginContextMenuItems()
            guard let self, self.window != nil else { return }
            self.pendingPluginMenuItems = items
            self.openContextMenu(for: event)
            self.pendingPluginMenuItems = []
        }
    }

    private func openContextMenu(for event: NSEvent) {
        super.rightMouseDown(with: event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        var menu = super.menu(for: event)
        if let contextMenuEntries {
            let editorMenu = menu ?? NSMenu()
            editorMenu.insertEditorContextMenuEntries(contextMenuEntries())
            menu = editorMenu
        }
        guard !pendingPluginMenuItems.isEmpty else { return menu }
        let pluginsMenu = menu ?? NSMenu()
        pluginsMenu.addItem(.separator())
        for item in pendingPluginMenuItems { pluginsMenu.addItem(item) }
        return pluginsMenu
    }

    override func paste(_ sender: Any?) {
        if canInsertAttachments, insertAttachments(from: .general, at: selectedRange()) { return }
        // Text plugins may take over (Link or Card makes a card of an address); the text is
        // pasted as usual when none does.
        let pasteboard = NSPasteboard.general
        // A web address pasted over selected text links the text to it, as in Obsidian.
        if selectedRange().length > 0, let pastedText = pasteboard.string(forType: .string),
           let edit = MarkdownEditing.linkingSelection(to: pastedText, in: string as NSString, selection: selectedRange()) {
            if shouldChangeText(in: edit.range, replacementString: edit.replacement) {
                replaceCharacters(in: edit.range, with: edit.replacement)
                didChangeText()
                setSelectedRange(edit.selectionAfter)
            }
            return
        }
        if let offerPasteToPlugins, let text = pasteboard.string(forType: .string) {
            let html = pasteboard.string(forType: .html)
            let pastedRange = selectedRange()
            let textWhenPasted = string
            Task { @MainActor [weak self] in
                let isTakenOver = await offerPasteToPlugins(text, html)
                guard let self, !isTakenOver else { return }
                // The range was the selection's before the plugins answered: a note changed
                // meanwhile takes the text at its selection now. A note made shorter raised
                // an exception, and a longer one received the text at the wrong place.
                let pastedRange = self.string == textWhenPasted ? pastedRange : self.selectedRange()
                if self.shouldChangeText(in: pastedRange, replacementString: text) {
                    self.replaceCharacters(in: pastedRange, with: text)
                    self.didChangeText()
                    self.setSelectedRange(NSRange(location: pastedRange.location + (text as NSString).length, length: 0))
                }
            }
            return
        }
        super.paste(sender)
    }

    override var acceptableDragTypes: [NSPasteboard.PasteboardType] {
        super.acceptableDragTypes + MacPastedAttachment.pasteboardTypes
    }

    override func draggingEntered(_ draggingInfo: NSDraggingInfo) -> NSDragOperation {
        let operation = super.draggingEntered(draggingInfo)
        return canInsertAttachments && MacPastedAttachment.isOffered(on: draggingInfo.draggingPasteboard) ? .copy : operation
    }

    override func draggingUpdated(_ draggingInfo: NSDraggingInfo) -> NSDragOperation {
        let operation = super.draggingUpdated(draggingInfo)
        return canInsertAttachments && MacPastedAttachment.isOffered(on: draggingInfo.draggingPasteboard) ? .copy : operation
    }

    override func performDragOperation(_ draggingInfo: NSDraggingInfo) -> Bool {
        let dropLocation = characterIndexForInsertion(at: convert(draggingInfo.draggingLocation, from: nil))
        if canInsertAttachments, insertAttachments(from: draggingInfo.draggingPasteboard, at: NSRange(location: dropLocation, length: 0)) { return true }
        return super.performDragOperation(draggingInfo)
    }

    /// Inserts what the pasteboard carries besides text; false when it carries only text.
    private func insertAttachments(from pasteboard: NSPasteboard, at range: NSRange) -> Bool {
        let attachments = MacPastedAttachment.attachments(on: pasteboard)
        guard !attachments.isEmpty else { return false }
        for attachment in attachments {
            switch attachment {
            case .vaultItem(let path): insertLinkToVaultFile?(path, range)
            case .file(let data, let stem, let fileExtension): insertAttachment?(data, stem, fileExtension, range)
            case .unreadableFile: reportUnreadableItem?()
            }
        }
        return true
    }
}

/// What a paste or drop on the Mac adds to a note besides text.
enum MacPastedAttachment: Equatable {
    /// A file or folder dragged from Graphite's sidebar, linked where it is.
    case vaultItem(VaultPath)
    /// A file or image saved as an attachment and embedded.
    case file(data: Data, stem: String, fileExtension: String)
    /// A file whose content could not be read.
    case unreadableFile(name: String)

    static let vaultItemType = NSPasteboard.PasteboardType(UTType.graphiteVaultItem.identifier)
    /// Image types saved as they are; any other image is converted to PNG.
    private static let keptImageTypes: [(type: NSPasteboard.PasteboardType, fileExtension: String)] = [
        (.png, "png"), (NSPasteboard.PasteboardType(UTType.jpeg.identifier), "jpg"),
        (NSPasteboard.PasteboardType(UTType.gif.identifier), "gif"), (NSPasteboard.PasteboardType(UTType.webP.identifier), "webp"),
    ]
    static var pasteboardTypes: [NSPasteboard.PasteboardType] { [vaultItemType, .fileURL, .tiff] + keptImageTypes.map(\.type) }

    /// Whether the pasteboard carries something that becomes an attachment or a link.
    static func isOffered(on pasteboard: NSPasteboard) -> Bool {
        pasteboard.availableType(from: [vaultItemType]) != nil
            || pasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
            || pasteboard.availableType(from: [.tiff] + keptImageTypes.map(\.type)) != nil
    }

    /// Vault items first, then files, then an image copied on its own. An image that comes
    /// with text, such as one copied from a web page with its caption, is pasted as text;
    /// one that comes with its address is an image.
    @MainActor
    static func attachments(on pasteboard: NSPasteboard, now: Date = .now) -> [MacPastedAttachment] {
        let vaultItems: [MacPastedAttachment] = (pasteboard.pasteboardItems ?? []).compactMap { pasteboardItem in
            guard let data = pasteboardItem.data(forType: vaultItemType),
                  let item = try? JSONDecoder().decode(VaultItemTransfer.self, from: data),
                  let path = try? VaultPath(item.path) else { return nil }
            return .vaultItem(path)
        }
        if !vaultItems.isEmpty { return vaultItems }
        let fileURLs = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        if !fileURLs.isEmpty {
            return fileURLs.map { fileURL in
                guard let data = try? Data(contentsOf: fileURL, options: .mappedIfSafe) else { return .unreadableFile(name: fileURL.lastPathComponent) }
                let fileExtension = fileURL.pathExtension.isEmpty ? "bin" : fileURL.pathExtension
                return .file(data: data, stem: fileURL.deletingPathExtension().lastPathComponent, fileExtension: fileExtension)
            }
        }
        let hasText = pasteboard.availableType(from: [.string]) != nil
        let hasAddress = pasteboard.availableType(from: [.URL]) != nil
        guard !hasText || hasAddress, let (data, fileExtension) = imageData(on: pasteboard) else { return [] }
        return [.file(data: data, stem: WorkspaceModel.pastedImageStem(at: now), fileExtension: fileExtension)]
    }

    private static func imageData(on pasteboard: NSPasteboard) -> (Data, String)? {
        for (type, fileExtension) in keptImageTypes {
            if let data = pasteboard.data(forType: type) { return (data, fileExtension) }
        }
        guard let tiffData = pasteboard.data(forType: .tiff),
              let pngData = NSBitmapImageRep(data: tiffData)?.representation(using: .png, properties: [:]) else { return nil }
        return (pngData, "png")
    }
}

/// Hosts a note's scroll view and text view for one SwiftUI view; see the iPad container.
final class MarkdownEditorContainerView: NSView {
    private(set) weak var hostedScrollView: NSScrollView?
    /// The latest update of this container's SwiftUI view, made while an earlier view of
    /// the note still showed the editor. It runs when the editor arrives here.
    var updateWhenScrollViewArrives: ((NSScrollView) -> Void)?

    func host(_ scrollView: NSScrollView) {
        scrollView.removeFromSuperview()
        scrollView.frame = bounds
        scrollView.autoresizingMask = [.width, .height]
        addSubview(scrollView)
        hostedScrollView = scrollView
        let waitingUpdate = updateWhenScrollViewArrives
        updateWhenScrollViewArrives = nil
        waitingUpdate?(scrollView)
    }

    /// The scroll view, while this container shows it rather than another view of the note.
    var scrollViewShownHere: NSScrollView? {
        guard let hostedScrollView, hostedScrollView.superview === self else { return nil }
        return hostedScrollView
    }
}

struct NativeMarkdownEditor: NSViewRepresentable {
    @Bindable var session: MarkdownSession
    let configuration: EditorConfiguration
    let headingScrollRequest: HeadingScrollRequest?
    let actions: EditorActions
    let follow: (String, Bool) -> Void
    /// Keeps this editor, with its undo history, after it leaves the screen; see
    /// `MarkdownEditorRetention`.
    var retention: MarkdownEditorRetention?
    var retentionOwner: TabDocument?
    var readAloudRange: NSRange?
    var followsReading = false
    var suspendReadingFollow: (() -> Void)?
    /// What Live Preview's rendered blocks read.
    let environment: LivePreviewEnvironment?
    /// The Color, Format, Paragraph and Insert submenus of the context menu; see `EditorContextMenuContent`.
    var contextMenu: EditorContextMenuActions?
    /// The vault's editing shortcuts.
    var keyCommandTable: EditorKeyCommandTable

    /// The Mac has no keyboard toolbar: of `actions`, it uses pasting, dropping, following
    /// links elsewhere, and focusing the note's side.
    init(session: MarkdownSession, configuration: EditorConfiguration, environment: LivePreviewEnvironment? = nil,
         headingScrollRequest: HeadingScrollRequest?, actions: EditorActions = EditorActions(),
         retention: MarkdownEditorRetention? = nil, retentionOwner: TabDocument? = nil, readAloudRange: NSRange? = nil,
         followsReading: Bool = false, suspendReadingFollow: (() -> Void)? = nil,
         readAloudHooks: ReadAloudEditorHooks? = nil, contextMenu: EditorContextMenuActions? = nil,
         keyCommandTable: EditorKeyCommandTable = .defaults, follow: @escaping (String, Bool) -> Void) {
        self.contextMenu = contextMenu
        self.keyCommandTable = keyCommandTable
        self.session = session
        self.configuration = configuration
        self.headingScrollRequest = headingScrollRequest
        self.actions = actions
        self.retention = retention
        self.retentionOwner = retentionOwner
        self.readAloudRange = readAloudRange
        self.followsReading = followsReading
        self.suspendReadingFollow = suspendReadingFollow
        self.environment = environment
        self.follow = follow
    }

    func makeCoordinator() -> Coordinator {
        if let retention, let retentionOwner, let keptEditor = retention.takeEditor(for: session, owner: retentionOwner) as? Coordinator {
            return keptEditor
        }
        return Coordinator(session: session, configuration: configuration)
    }

    func makeNSView(context: Context) -> MarkdownEditorContainerView {
        let container = MarkdownEditorContainerView()
        let coordinator = context.coordinator
        coordinator.retention = retention
        coordinator.retentionOwner = retentionOwner
        if coordinator.scrollView == nil {
            let scrollView = makeScrollView(coordinator: coordinator)
            coordinator.scrollView = scrollView
            container.host(scrollView)
        }
        coordinator.viewWasMade(with: container)
        retention?.editorDidAttach(coordinator)
        return container
    }

    private func makeScrollView(coordinator: Coordinator) -> NSScrollView {
        let scrollView = MarkdownMacTextView.makeScrollableTextView()
        guard let textView = scrollView.documentView as? MarkdownMacTextView else { return scrollView }
        coordinator.actions = actions
        coordinator.follow = follow
        coordinator.environment = environment
        textView.isRichText = false
        textView.quickFontSize = actions.quickFontSize
        textView.readableColumnWidth = configuration.usesReadableLineLength
            ? (configuration.theme?.readableColumnWidth(forTextSize: configuration.textSize).map { width in width + 10 } ?? MarkdownMacTextView.graphiteReadableColumnWidth) : nil
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isContinuousSpellCheckingEnabled = configuration.usesSpellChecking
        textView.allowsUndo = true
        textView.textContainerInset = CGSize(width: 32, height: 32)
        textView.setAccessibilityLabel("Markdown note")
        // The text and the saved cursor go in before the delegate, which would otherwise
        // record the cursor that setting the text leaves at its end.
        textView.string = session.text
        coordinator.lastSynchronizedText = session.text
        let textLength = (session.text as NSString).length
        let cursorLocation = min(session.selection.location, textLength)
        textView.setSelectedRange(NSRange(location: cursorLocation, length: min(session.selection.length, textLength - cursorLocation)))
        textView.delegate = coordinator
        coordinator.connect(textView)
        textView.updateDragTypeRegistration()
        if let savedScrollLocation = session.savedScrollLocation { coordinator.pendingJump = .topOfCharacter(savedScrollLocation) }
        session.isEditorAttached = true
        coordinator.reportPlace(of: textView)
        session.undoAvailability.follow(coordinator.noteUndoManager)
        coordinator.restyleEverything(in: textView)
        coordinator.keepSelectionOutOfConcealedProperties(in: textView)
        return scrollView
    }

    func updateNSView(_ container: MarkdownEditorContainerView, context: Context) {
        let coordinator = context.coordinator
        guard let scrollView = container.scrollViewShownHere else {
            // An earlier view of this note still shows the editor; this view's state
            // reaches it when the editor moves here.
            container.updateWhenScrollViewArrives = { [self] arrivedScrollView in update(arrivedScrollView, coordinator: coordinator) }
            return
        }
        update(scrollView, coordinator: coordinator)
    }

    private func update(_ scrollView: NSScrollView, coordinator: Coordinator) {
        coordinator.session = session
        coordinator.actions = actions
        coordinator.follow = follow
        guard let textView = scrollView.documentView as? NSTextView else { return }
        (textView as? MarkdownMacTextView)?.readAloudRange = readAloudRange
        (textView as? MarkdownMacTextView)?.keyCommandTable = keyCommandTable
        (textView as? MarkdownMacTextView)?.keyCommandOwner = coordinator
        (textView as? MarkdownMacTextView)?.quickFontSize = actions.quickFontSize
        (textView as? MarkdownMacTextView)?.readableColumnWidth = configuration.usesReadableLineLength
            ? (configuration.theme?.readableColumnWidth(forTextSize: configuration.textSize).map { width in width + 10 } ?? MarkdownMacTextView.graphiteReadableColumnWidth) : nil
        (textView as? MarkdownMacTextView)?.suspendReadingFollow = suspendReadingFollow
        // Plugins that start, or start listening, after the editor was made reach it here.
        (textView as? MarkdownMacTextView)?.pluginContextMenuItems = coordinator.actions.pluginContextMenuItems == nil ? nil : { [weak coordinator] in
            await coordinator?.actions.pluginContextMenuItems?() ?? []
        }
        (textView as? MarkdownMacTextView)?.offerPasteToPlugins = coordinator.actions.pluginPaste
        let editorActions = actions
        (textView as? MarkdownMacTextView)?.contextMenuEntries = contextMenu.map { menuActions in
            { EditorContextMenuContent.entries(actions: menuActions, editorActions: editorActions) }
        }
        let previousBlockPolicy = coordinator.renderedBlockPolicy
        let hasNewConfiguration = coordinator.configuration != configuration
        coordinator.configuration = configuration
        coordinator.environment = environment
        // Turning the Properties view on or off, or a plugin starting to draw code blocks,
        // changes which blocks are rendered, as the configuration can.
        if hasNewConfiguration || coordinator.renderedBlockPolicy != previousBlockPolicy {
            coordinator.restyleEverything(in: textView, forcesBlockScan: coordinator.renderedBlockPolicy != previousBlockPolicy)
            coordinator.keepSelectionOutOfConcealedProperties(in: textView)
        }
        coordinator.refreshBlockViews(in: textView)
        let hasAppliedInsertion = coordinator.applyPendingInsertions(to: textView)
        if !hasAppliedInsertion, !textView.hasMarkedText(), session.text != coordinator.lastSynchronizedText {
            // The file changed on disk, or properties were edited from a panel.
            coordinator.replaceText(with: session.text, in: textView)
        }
        if let headingScrollRequest, headingScrollRequest.token != session.handledHeadingScrollToken {
            session.handledHeadingScrollToken = headingScrollRequest.token
            // A jump replaces the return to where the note was left.
            if let textRange = headingScrollRequest.textRange {
                coordinator.pendingJump = .textRange(textRange)
            } else {
                coordinator.pendingJump = .heading(anchor: headingScrollRequest.anchor, occurrence: headingScrollRequest.occurrence)
            }
        }
        coordinator.serveSessionRequests(in: textView)
        coordinator.performPendingJumpIfReady(in: textView)
        if followsReading { (textView as? MarkdownMacTextView)?.followReadingRange() }
    }

    static func dismantleNSView(_ container: MarkdownEditorContainerView, coordinator: Coordinator) {
        coordinator.viewWasDismantled(with: container)
    }

    /// On the Mac, Live Preview conceals markup away from the selection and draws its blocks
    /// as views over their concealed source, as on the iPad.
    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate, NSTextLayoutManagerDelegate, RetainableMarkdownEditor {
        var session: MarkdownSession
        /// The text's styling, markup revealed at the selection, and rendered blocks, shared
        /// with the iPad's editor; the Mac has the memory to keep more views off screen.
        let styling: MarkdownEditorStyling
        var configuration: EditorConfiguration {
            get { styling.configuration }
            set { styling.configuration = newValue }
        }
        /// What Live Preview's rendered blocks read; nil in Source mode.
        var environment: LivePreviewEnvironment? {
            get { styling.environment }
            set { styling.environment = newValue }
        }
        /// The editor's views, which live as long as it: a hidden note's retention can keep
        /// them beyond their SwiftUI view.
        var scrollView: NSScrollView?
        weak var retention: MarkdownEditorRetention?
        weak var retentionOwner: TabDocument?
        /// The containers of the SwiftUI views that show this note.
        private var containersInUse = EditorContainersInUse<MarkdownEditorContainerView>()
        /// The note's own history. AppKit text views otherwise record in the window's,
        /// which every note in the window shares.
        let noteUndoManager = UndoManager()
        var actions = EditorActions()
        var follow: (String, Bool) -> Void = { _, _ in }
        var appliedInsertionIdentifier: UUID?
        /// Where the view goes once it is in a window and has a width, where the note can
        /// be measured.
        enum Jump: Equatable {
            /// `occurrence` picks one of several headings that read the same, from zero.
            case heading(anchor: String, occurrence: Int = 0)
            case textRange(NSRange)
            /// Back where the note was left.
            case topOfCharacter(Int)
        }
        var pendingJump: Jump?
        private var textState: LivePreviewTextState { styling.textState }
        /// The markup the styling shows as written in Live Preview; see `RevealedMarkup`.
        var revealedMarkup: RevealedMarkup? { styling.revealedMarkup }
        private var renderedBlocks: LivePreviewRenderedBlocks { styling.renderedBlocks }
        /// The text last given to or taken from the session; see the iPad coordinator.
        var lastSynchronizedText = ""
        /// Pastes and drops whose content is still loading or saving.
        private var pendingInsertionRequests = PendingInsertionRequests()
        private var isPlacementScheduled = false
        /// Set by "Edit Source": the YAML shows, and the cursor can be in it, until the
        /// cursor leaves it.
        private(set) var showsPropertiesSource: Bool {
            get { styling.propertiesSource == .afterEditSource(isShown: true) }
            set { styling.propertiesSource = .afterEditSource(isShown: newValue) }
        }
        /// Set while Graphite changes the text itself, which may change the YAML.
        private var isApplyingOwnEdit = false

        init(session: MarkdownSession, configuration: EditorConfiguration) {
            self.session = session
            // The properties show their YAML after "Edit Source", as Obsidian keeps them above the note.
            styling = MarkdownEditorStyling(configuration: configuration, propertiesSource: .afterEditSource(isShown: false), detachedViewsBudgetMegabytes: 64)
            super.init()
            // Until the note has keyboard focus; see `followKeyboardFocus`.
            styling.revealsMarkupAtSelection = false
            styling.didRestyle = { [weak self] restyledTextView in
                guard let self, let textView = restyledTextView as? NSTextView else { return }
                self.schedulePlacement(in: textView)
            }
        }

        /// Whether Live Preview draws its blocks as views.
        var rendersBlocks: Bool { styling.rendersBlocks }
        /// Whether the frontmatter is rendered as properties, as Obsidian's Live Preview shows
        /// them; without the Properties view it stays styled source.
        var rendersProperties: Bool { styling.rendersProperties }
        /// What decides which blocks are rendered; a change finds the blocks again.
        var renderedBlockPolicy: [String] { styling.renderedBlockPolicy }

        func undoManager(for view: NSTextView) -> UndoManager? { noteUndoManager }

        // MARK: Lifetime

        var editedSession: MarkdownSession { session }
        var retainedTextLength: Int { (scrollView?.documentView as? NSTextView)?.textStorage?.length ?? 0 }

        /// Takes in the container of a new SwiftUI view of the note; see the iPad editor's
        /// `viewWasMade`. An editor an earlier view still shows stays there until that
        /// view is dismantled.
        func viewWasMade(with container: MarkdownEditorContainerView) {
            let isShownInEarlierView = containersInUse.contains { earlierContainer in earlierContainer.scrollViewShownHere != nil }
            containersInUse.add(container)
            guard let scrollView, !isShownInEarlierView, container.scrollViewShownHere == nil else { return }
            container.host(scrollView)
            resume(scrollView)
        }

        /// Lets go of the container of a dismantled SwiftUI view. The editor it showed
        /// moves to the newest view of the note that is left; with none left, it leaves
        /// the screen.
        func viewWasDismantled(with container: MarkdownEditorContainerView) {
            containersInUse.remove(container)
            guard let scrollView = container.scrollViewShownHere else { return }
            if let remainingContainer = containersInUse.newest {
                remainingContainer.host(scrollView)
                return
            }
            suspend(scrollView)
            if retention?.keepHiddenEditor(self, owner: retentionOwner) != true { discardRetainedEditor() }
        }

        /// Takes the editor off screen without ending it; see the iPad editor's `suspend`.
        func suspend(_ scrollView: NSScrollView) {
            session.applyPendingInsertionsBeforeSaving = nil
            session.isEditorAttached = false
            stopObservingCharacterEdits()
            if let textView = scrollView.documentView as? NSTextView {
                if textView.window?.firstResponder === textView { textView.window?.makeFirstResponder(nil) }
                recordScrollLocation(of: textView)
            }
            session.recordEditorPlace = nil
            scrollView.removeFromSuperview()
            session.undoAvailability.follow(nil)
        }

        func resume(_ scrollView: NSScrollView) {
            if let textView = scrollView.documentView as? NSTextView {
                observeCharacterEdits(in: textView)
                reportPlace(of: textView)
            }
            session.isEditorAttached = true
            session.undoAvailability.follow(noteUndoManager)
        }

        func discardRetainedEditor() {
            // Blocks' views are taken out of the text view first: one still in it when the
            // text view goes stays registered with AppKit's notification center, and keeps
            // its environment, the note's session and the workspace's closures with it.
            styling.renderedBlocks.removeAllViews()
            scrollView?.removeFromSuperview()
            scrollView = nil
        }

        /// Connects the view's paste, drop, click, and focus handling, and follows its edits.
        func connect(_ textView: MarkdownMacTextView) {
            // Each request remembers the text revision it was made at: the content saves
            // asynchronously while the note may change, and the items of one paste or drop
            // all ask for the same place.
            textView.insertAttachment = { [weak self] data, stem, fileExtension, range in
                guard let self, let insertAttachment = self.actions.insertAttachment else { return }
                self.pendingInsertionRequests.remember(InsertionRequest(range: range, revision: self.textState.history.revision))
                insertAttachment(data, stem, fileExtension, range)
            }
            textView.insertLinkToVaultFile = { [weak self] path, range in
                guard let self, let insertLinkToVaultFile = self.actions.insertLinkToVaultFile else { return }
                self.pendingInsertionRequests.remember(InsertionRequest(range: range, revision: self.textState.history.revision))
                insertLinkToVaultFile(path, range)
            }
            textView.reportUnreadableItem = { [weak self] in self?.session.errorMessage = NativeMarkdownEditor.unreadableItemMessage }
            textView.followLinkOnClick = { [weak self, weak textView] characterIndex, modifierFlags in
                guard let self, let textView else { return false }
                return self.followLink(atCharacter: characterIndex, modifierFlags: modifierFlags, in: textView)
            }
            // Markup and a block's source show at the cursor only while the note has keyboard
            // focus, as on the iPad: a note opened from the file list, its cursor at the start,
            // showed the callout or table there as source until a click in the note.
            textView.didBecomeFirstResponder = { [weak self, weak textView] in
                guard let self, let textView else { return }
                self.actions.beginEditing?()
                self.followKeyboardFocus(true, in: textView)
            }
            textView.didResignFirstResponder = { [weak self, weak textView] in
                guard let self, let textView else { return }
                self.followKeyboardFocus(false, in: textView)
            }
            textView.toggleTaskOnClick = { [weak self, weak textView] characterIndex in
                guard let self, let textView else { return false }
                return self.toggleTask(atCharacter: characterIndex, in: textView)
            }
            // Bullets, task boxes, quote bars and inline math are drawn over their hidden
            // markup, as on the iPad.
            textView.textLayoutManager?.delegate = self
            textView.didMoveTextColumn = { [weak self, weak textView] in
                guard let self, let textView else { return }
                self.schedulePlacement(in: textView)
            }
            textView.didLayOutViewport = { [weak self, weak textView] in
                guard let self, let textView else { return }
                self.placeBlockViews(in: textView)
            }
            textView.didBecomeMeasurable = { [weak self] measurableView in
                // Not from inside the window change or layout itself.
                DispatchQueue.main.async { [weak self, weak measurableView] in
                    guard let self, let measurableView else { return }
                    self.performPendingJumpIfReady(in: measurableView)
                    self.startEditingIfRequested(in: measurableView)
                }
            }
            observeCharacterEdits(in: textView)
        }

        // MARK: Character edits

        /// Follows every change to the characters, whichever path made it; AppKit reports
        /// `textDidChange` after its own edits, and a change it does not report is settled
        /// once it is done.
        func observeCharacterEdits(in textView: NSTextView) {
            session.applyPendingInsertionsBeforeSaving = { [weak self, weak textView] in
                guard let self, let textView else { return }
                _ = self.applyPendingInsertions(to: textView)
            }
            styling.observeCharacterEdits(in: textView) { [weak self, weak textView] in
                guard let self, let textView else { return }
                self.settleTextChange(in: textView)
                self.publish(textView)
            }
        }

        func stopObservingCharacterEdits() {
            styling.stopObservingCharacterEdits()
        }

        private func currentSource(of textView: NSTextView) -> NSString {
            styling.currentSource(of: textView)
        }

        // MARK: Styling

        /// Finds the blocks again and styles the whole note.
        /// - Parameter forcesBlockScan: Finds the blocks again, after a change in which are rendered.
        func restyleEverything(in textView: NSTextView, forcesBlockScan: Bool = false) {
            styling.updateTextState(of: textView, forcesBlockScan: forcesBlockScan)
            styling.restyleEverything(in: textView)
        }

        private func restyle(_ range: NSRange, in textView: NSTextView) {
            styling.restyle(range, in: textView)
        }

        /// Restyles what the edits since the last styling changed, once no text is marked:
        /// styling would disturb an input method's composition.
        private func settleTextChange(in textView: NSTextView) {
            guard !textView.hasMarkedText(), textState.cachesDescribeOldText || textState.hasUnstyledEdit else { return }
            styling.updateTextState(of: textView)
            styling.restyleUnstyledEdit(in: textView)
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            settleTextChange(in: textView)
            publish(textView)
            // Plugins hear the note change as in Obsidian's editor (`editor-change`). The
            // Mac shows no suggestions list, so suggestions plugins answer go unused.
            _ = actions.pluginEditorDidChange?()
        }

        /// Shows the markup at the cursor once the note has keyboard focus, and hides it, the
        /// blocks drawn again, once it has not.
        private func followKeyboardFocus(_ hasKeyboardFocus: Bool, in textView: NSTextView) {
            guard styling.revealsMarkupAtSelection != hasKeyboardFocus else { return }
            styling.revealsMarkupAtSelection = hasKeyboardFocus
            styling.restyleRevealedMarkup(in: textView)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            session.selection = textView.selectedRange()
            concealPropertiesSourceIfLeft(in: textView)
            styling.restyleRevealedMarkup(in: textView)
            formatCodeBlockLeftBehind(in: textView, editingEnded: false)
        }

        func textDidEndEditing(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            formatCodeBlockLeftBehind(in: textView, editingEnded: true)
        }

        /// Formats the code block the user edited once the selection leaves it or editing
        /// ends, on the next turn of the run loop, through the text view so Undo puts the
        /// code back.
        private func formatCodeBlockLeftBehind(in textView: NSTextView, editingEnded: Bool) {
            guard configuration.formatsCodeBlocks else { return }
            DispatchQueue.main.async { [weak self, weak textView] in
                guard let self, let textView, !textView.hasMarkedText(), let textStorage = textView.textStorage,
                      let edit = self.styling.codeFormattingEdit(afterSelectionChangeIn: textView, editingEnded: editingEnded),
                      NSMaxRange(edit.range) <= textStorage.length else { return }
                textView.breakUndoCoalescing()
                self.isApplyingOwnEdit = true
                defer { self.isApplyingOwnEdit = false }
                guard textView.shouldChangeText(in: edit.range, replacementString: edit.replacement) else { return }
                textStorage.replaceCharacters(in: edit.range, with: edit.replacement)
                textView.didChangeText()
                if NSMaxRange(edit.selectionAfter) <= textStorage.length { textView.setSelectedRange(edit.selectionAfter) }
            }
        }

        func textView(_ textView: NSTextView, willChangeSelectionFromCharacterRange oldSelectedCharRange: NSRange,
                      toCharacterRange newSelectedCharRange: NSRange) -> NSRange {
            guard let entry = concealedPropertiesEntry(in: textView) else { return newSelectedCharRange }
            return Self.selection(newSelectedCharRange, keptBelowConcealedPropertiesEndingAt: NSMaxRange(entry.range))
        }

        /// The spelling checker marks nothing in a block's concealed source: its marks were
        /// drawn at the hidden lines' height, a red speck above the block's view.
        func textView(_ textView: NSTextView, shouldSetSpellingState value: Int, range affectedCharRange: NSRange) -> Int {
            guard value != 0, concealedEntries(in: textView).contains(where: { entry in NSIntersectionRange(entry.range, affectedCharRange).length > 0 }) else { return value }
            return 0
        }

        /// An edit that starts in the concealed YAML and reaches its end, as a backspace at
        /// the start of the note's text does, would join the properties' closing line to the
        /// text and turn the properties into text; it is refused. Replacing the whole YAML,
        /// as after Select All, and edits inside it, as find and replace makes, are allowed.
        func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
            guard !isApplyingOwnEdit, !noteUndoManager.isUndoing, !noteUndoManager.isRedoing,
                  let entry = concealedPropertiesEntry(in: textView) else { return true }
            return !Self.cutsIntoConcealedProperties(affectedCharRange, propertiesEnd: NSMaxRange(entry.range))
        }

        /// Applies every insertion waiting in the session, in order, and tells whether there
        /// was any. Several can be queued between updates, such as images dropped together;
        /// each apply removes its insertion from the queue.
        func applyPendingInsertions(to textView: NSTextView) -> Bool {
            var hasAppliedInsertion = false
            while let insertion = session.pendingInsertion, insertion.id != appliedInsertionIdentifier {
                apply(insertion, to: textView)
                hasAppliedInsertion = true
            }
            return hasAppliedInsertion
        }

        /// Makes an insertion through the text view, so it can be undone. A pasted or dropped
        /// block goes where its request points now, past the note's changes since.
        func apply(_ insertion: EditorInsertion, to textView: NSTextView) {
            appliedInsertionIdentifier = insertion.id
            isApplyingOwnEdit = true
            defer { isApplyingOwnEdit = false }
            let source = currentSource(of: textView)
            var insertionText = insertion.text
            var insertionRange = insertion.range
            var selectionAfter = insertion.selectionAfter
            let pendingRequest = insertion.selectionAfter == nil ? pendingInsertionRequests.take(preparedFor: insertion.range, in: textState.history) : nil
            if let movedRange = pendingRequest?.currentTarget(in: textState.history), movedRange != insertion.range {
                (insertionText, insertionRange) = MovedBlockInsertion.insertion(of: insertion.text, movedTo: movedRange, in: source)
                selectionAfter = nil
            }
            let safeLocation = min(insertionRange.location, source.length)
            textView.insertText(insertionText, replacementRange: NSRange(location: safeLocation, length: min(insertionRange.length, source.length - safeLocation)))
            // With a replacement range, AppKit need not move the cursor after the new text.
            if let pendingRequest {
                let insertedEnd = safeLocation + (insertionText as NSString).length
                pendingInsertionRequests.placeRemainingItems(of: pendingRequest, after: insertedEnd, at: textState.history.revision)
            }
            if let selectionAfter, NSMaxRange(selectionAfter) <= (textView.textStorage?.length ?? 0) {
                textView.setSelectedRange(selectionAfter)
            }
            restyleEverything(in: textView)
            publish(textView)
            session.markInsertionApplied(insertion)
        }

        private func publish(_ textView: NSTextView) {
            let text = currentSource(of: textView) as String
            session.text = text
            lastSynchronizedText = text
            session.selection = textView.selectedRange()
        }

        /// Puts a new text in place by replacing only what differs, as an undoable edit:
        /// setting the whole text would leave the undo history pointing at older text.
        func replaceText(with newText: String, in textView: NSTextView) {
            guard let textStorage = textView.textStorage else { return }
            let oldSource = NSString(string: textStorage.string)
            let newSource = newText as NSString
            guard let (replacedRange, replacementRange) = TextDifference.changedRanges(from: oldSource, to: newSource) else {
                lastSynchronizedText = newText
                return
            }
            let replacement = newSource.substring(with: replacementRange)
            let edit = CharacterEdit(editedRange: replacementRange, changeInLength: newSource.length - oldSource.length)
            let selection = TextRangeMapping.insertionTarget(textView.selectedRange(), through: edit)
            isApplyingOwnEdit = true
            defer { isApplyingOwnEdit = false }
            guard textView.shouldChangeText(in: replacedRange, replacementString: replacement) else {
                textView.string = newText
                restyleEverything(in: textView)
                return
            }
            textStorage.replaceCharacters(in: replacedRange, with: replacement)
            textView.didChangeText()
            if NSMaxRange(selection) <= textStorage.length { textView.setSelectedRange(selection) }
        }

        // MARK: Rendered blocks

        /// The frontmatter, while the properties are rendered and it describes the text on screen.
        private var propertiesEntry: LivePreviewBlockEntry? {
            guard rendersProperties, !textState.cachesDescribeOldText else { return nil }
            return textState.blockEntries.first { entry in entry.block.kind == .frontmatter && entry.range.location == 0 }
        }

        /// The frontmatter while its YAML is concealed under the properties view.
        private func concealedPropertiesEntry(in textView: NSTextView) -> LivePreviewBlockEntry? {
            guard !showsPropertiesSource, let entry = propertiesEntry, NSMaxRange(entry.range) <= (textView.textStorage?.length ?? 0) else { return nil }
            return entry
        }

        /// The blocks whose source is concealed under their views, in note order: the
        /// properties unless "Edit Source" shows their YAML, as Obsidian keeps them above the
        /// note, and every other block while the selection is outside it, as on the iPad.
        private func concealedEntries(in textView: NSTextView) -> [LivePreviewBlockEntry] {
            styling.concealedEntries(in: textView)
        }

        /// A selection that starts in the concealed YAML starts after it instead, so the
        /// cursor never lands in text that is not drawn. A selection of the whole YAML, as
        /// Select All makes, is kept.
        static func selection(_ selection: NSRange, keptBelowConcealedPropertiesEndingAt propertiesEnd: Int) -> NSRange {
            guard selection.location < propertiesEnd else { return selection }
            if selection.location == 0, selection.length > 0, NSMaxRange(selection) >= propertiesEnd { return selection }
            return NSRange(location: propertiesEnd, length: max(NSMaxRange(selection), propertiesEnd) - propertiesEnd)
        }

        static func cutsIntoConcealedProperties(_ range: NSRange, propertiesEnd: Int) -> Bool {
            range.location > 0 && range.location < propertiesEnd && NSMaxRange(range) >= propertiesEnd
        }

        /// Moves the selection out of the concealed YAML, as when a note opens with the cursor
        /// at its start; AppKit asks the delegate only about selections made after it is set.
        func keepSelectionOutOfConcealedProperties(in textView: NSTextView) {
            guard let entry = concealedPropertiesEntry(in: textView) else { return }
            let selection = textView.selectedRange()
            let keptSelection = Self.selection(selection, keptBelowConcealedPropertiesEndingAt: NSMaxRange(entry.range))
            if keptSelection != selection { textView.setSelectedRange(keptSelection) }
        }

        /// Conceals the YAML "Edit Source" showed once the cursor leaves it. While it is
        /// being edited into something that is not frontmatter, it stays shown.
        private func concealPropertiesSourceIfLeft(in textView: NSTextView) {
            guard showsPropertiesSource, !textView.hasMarkedText(), !textState.hasUnstyledEdit, let entry = propertiesEntry,
                  !LivePreviewBlockActivity.isActive(blockRange: entry.range, selection: textView.selectedRange(), in: currentSource(of: textView)) else { return }
            showsPropertiesSource = false
            restyle(entry.range, in: textView)
        }

        /// Shows the YAML in place of the properties view, with the cursor on its first
        /// property: the view's "Edit Source".
        func showPropertiesSource(in textView: NSTextView) {
            guard !textView.hasMarkedText(), !textState.hasUnstyledEdit, let entry = concealedPropertiesEntry(in: textView) else { return }
            showsPropertiesSource = true
            restyle(entry.range, in: textView)
            let source = currentSource(of: textView)
            let firstPropertyLocation = min(NSMaxRange(source.lineRange(for: NSRange(location: 0, length: 0))), NSMaxRange(entry.range))
            textView.window?.makeFirstResponder(textView)
            textView.setSelectedRange(NSRange(location: firstPropertyLocation, length: 0))
            textView.scrollRangeToVisible(NSRange(location: 0, length: 0))
        }

        /// Shows a block's source with the cursor at its start, after a click on its view;
        /// the cursor in the block keeps its source shown until it leaves.
        func revealSource(ofBlockWithKey key: LivePreviewBlockKey, in textView: NSTextView) {
            guard !textView.hasMarkedText(), !textState.cachesDescribeOldText,
                  let entry = textState.blockEntries.first(where: { candidate in candidate.key == key }) else { return }
            if entry.block.kind == .frontmatter { return showPropertiesSource(in: textView) }
            textView.window?.makeFirstResponder(textView)
            textView.setSelectedRange(NSRange(location: entry.range.location, length: 0))
        }

        /// Gives the blocks' views the current environment and appearance in place, keeping
        /// their own state; only those that read the index when nothing else changed.
        func refreshBlockViews(in textView: NSTextView) {
            guard let environment else { return }
            let signature = LivePreviewWidgetSignature(environment: environment, accentHex: configuration.accentHex, notePath: session.path.rawValue)
            let didRefresh = renderedBlocks.refreshViews(for: signature, entries: textState.blockEntries) { entry in
                blockRootView(for: entry, environment: environment, textView: textView)
            }
            if didRefresh { placeBlockViews(in: textView) }
        }

        /// Places the views of the concealed blocks TextKit has laid out and takes off screen
        /// those of blocks that are not: TextKit lays out the viewport, so a long note's
        /// blocks below it cost nothing until they scroll into view, and says when it has.
        func placeBlockViews(in textView: NSTextView) {
            guard let environment, rendersBlocks, let textContainer = textView.textContainer, let textLayoutManager = textView.textLayoutManager,
                  textView.renderedBlockColumnWidth > 0 else {
                renderedBlocks.removeAllViews()
                return
            }
            // Mid-edit, the blocks describe the text before it; the views stay until it settles.
            guard !textState.cachesDescribeOldText, !textView.hasMarkedText() else { return }
            let columnMinX = textView.textContainerOrigin.x + textContainer.lineFragmentPadding
            let paneMinX = (textView as? MarkdownMacTextView)?.paneContentMinX ?? columnMinX
            let column = RenderedBlockColumn(minX: columnMinX, textContainerTop: textView.textContainerOrigin.y, width: textView.renderedBlockColumnWidth,
                                             paneMinX: paneMinX, paneWidth: textView.renderedBlockPaneWidth)
            // A paragraph a restyle changed waits for TextKit's next layout of the viewport,
            // which places it then.
            guard let placement = renderedBlocks.placeViews(of: concealedEntries(in: textView), in: textView, textLayoutManager: textLayoutManager,
                                                            column: column, configuration: configuration, makeRootView: { entry in
                blockRootView(for: entry, environment: environment, textView: textView)
            }) else { return }
            renderedBlocks.detachViews(except: placement.keysInUse, entries: textState.blockEntries)
            // A height measured at a new width, or by another editor, is reserved in the text first.
            styling.restyleLater(placement.entriesToRestyle, in: textView)
        }

        func removeAllBlockViews() {
            renderedBlocks.removeAllViews()
        }

        /// Places the blocks after a change, on the next turn of the run loop; TextKit's
        /// own layout of the viewport places them too (`MarkdownMacTextView.didLayOutViewport`).
        private func schedulePlacement(in textView: NSTextView) {
            // A block whose source now shows loses its view at once, before its text is drawn.
            if !textState.cachesDescribeOldText {
                renderedBlocks.detachViews(except: Set(concealedEntries(in: textView).map(\.key)), entries: textState.blockEntries)
            }
            guard !isPlacementScheduled else { return }
            isPlacementScheduled = true
            DispatchQueue.main.async { [weak self, weak textView] in
                guard let self else { return }
                self.isPlacementScheduled = false
                guard let textView else { return }
                self.placeBlockViews(in: textView)
            }
        }

        /// The hosted view takes the appearance from the text view it is in. A click on a
        /// block's view shows its source; on the properties, "Edit Source" does.
        private func blockRootView(for entry: LivePreviewBlockEntry, environment: LivePreviewEnvironment, textView: NSTextView) -> RenderedBlockRoot {
            let key = entry.key
            let isFrontmatter = entry.block.kind == .frontmatter
            return LivePreviewRenderedBlocks.rootView(for: entry, environment: environment, accentHex: configuration.accentHex, colorScheme: nil, revealSource: { [weak self, weak textView] in
                // Not from inside the view's own action, which the view's removal would end.
                DispatchQueue.main.async { [weak self, weak textView] in
                    guard let self, let textView else { return }
                    if isFrontmatter { self.showPropertiesSource(in: textView) } else { self.revealSource(ofBlockWithKey: key, in: textView) }
                }
            }, reportHeight: { [weak self, weak textView] height in
                guard let self, let textView else { return }
                self.styling.reserveMeasuredHeight(height, forBlockWithKey: key, isFrontmatter: isFrontmatter, in: textView)
            }, sourceEditing: RenderedBlockSourceEditing(replaceSource: { [weak self, weak textView] editor, transform in
                guard let self, let textView else { return }
                self.replaceSource(ofBlockWithKey: key, editedBy: editor, using: transform, in: textView)
            }, setIsEditingInView: { [weak self] isEditing, editor in
                guard let self else { return }
                if !isEditing { return self.renderedBlocks.endEditingInView(owner: editor) }
                guard let entry = self.textState.blockEntries.first(where: { candidate in candidate.key == key }) else { return }
                self.renderedBlocks.beginEditingInView(blockWithKey: key, at: entry.range.location, owner: editor)
            }))
        }

        /// Replaces a rendered block's source with what its view made of it, as a table's cell
        /// editor does, through the text view so it can be undone. Mid-edit or during an input
        /// method's composition, the change waits a turn.
        func replaceSource(ofBlockWithKey key: LivePreviewBlockKey, editedBy editor: ObjectIdentifier, using transform: @escaping (String) -> String?,
                           in textView: NSTextView, attemptsLeft: Int = 3) {
            guard !textView.hasMarkedText(), !textState.cachesDescribeOldText else {
                guard attemptsLeft > 0 else { return }
                DispatchQueue.main.async { [weak self, weak textView] in
                    guard let self, let textView else { return }
                    self.replaceSource(ofBlockWithKey: key, editedBy: editor, using: transform, in: textView, attemptsLeft: attemptsLeft - 1)
                }
                return
            }
            let source = currentSource(of: textView)
            guard let blockRange = renderedBlocks.rangeOfBlock(withKey: key, editedBy: editor, in: textState.blockEntries, source: source),
                  let replacement = transform(source.substring(with: blockRange)) else { return }
            replaceText(with: source.replacingCharacters(in: blockRange, with: replacement), in: textView)
        }

        // MARK: Drawn replacements and tasks

        nonisolated func textLayoutManager(_ textLayoutManager: NSTextLayoutManager, textLayoutFragmentFor location: NSTextLocation,
                                           in textElement: NSTextElement) -> NSTextLayoutFragment {
            ConcealedReplacementLayoutFragment(textElement: textElement, range: textElement.elementRange)
        }

        /// Checks or unchecks the drawn task box at a clicked character, through the text view
        /// so it can be undone. On the selection's lines the box shows as `[ ]`, and a click
        /// there places the cursor.
        func toggleTask(atCharacter characterIndex: Int, in textView: NSTextView) -> Bool {
            guard configuration.mode == .livePreview, !textState.cachesDescribeOldText, !textView.hasMarkedText(),
                  let textStorage = textView.textStorage else { return false }
            let source = currentSource(of: textView)
            guard characterIndex <= source.length else { return false }
            let lineRange = source.lineRange(for: NSRange(location: characterIndex, length: 0))
            if let revealedMarkup, revealedMarkup.showsLineMarker(at: lineRange.location) { return false }
            guard let checkboxRange = LivePreviewTapTargets.taskCheckboxRange(at: characterIndex, in: source) else { return false }
            let stateRange = NSRange(location: checkboxRange.location + 1, length: 1)
            guard NSMaxRange(stateRange) <= source.length else { return false }
            let newState = source.substring(with: stateRange) == " " ? "x" : " "
            let selection = textView.selectedRange()
            guard textView.shouldChangeText(in: stateRange, replacementString: newState) else { return true }
            textStorage.replaceCharacters(in: stateRange, with: newState)
            textView.didChangeText()
            if NSMaxRange(selection) <= textStorage.length { textView.setSelectedRange(selection) }
            return true
        }

        // MARK: Links

        /// Follows the link at a clicked character, as a tap does on the iPad: ⌘ opens it
        /// in a new tab and ⌥⌘ beside the note.
        /// Runs an editing shortcut as an edit Undo takes back; false for a command the Mac's
        /// editor does not run from the keyboard.
        func runKeyCommand(_ command: EditorCommand, in textView: NSTextView) -> Bool {
            switch command {
            case .find, .findAndReplace:
                let finderAction: NSTextFinder.Action = if case .find = command { .showFindInterface } else { .showReplaceInterface }
                let sender = NSMenuItem()
                sender.tag = finderAction.rawValue
                textView.performTextFinderAction(sender)
                return true
            case .undo, .redo, .attach, .draw, .dismissKeyboard, .followLink:
                return false
            case .heading, .wrap, .bulletList, .numberedList, .task, .indent, .outdent, .moveLinesUp, .moveLinesDown,
                 .insertWikilink, .insertTag, .insertMarkdownLink:
                guard let textStorage = textView.textStorage,
                      let edit = MarkdownEditing.edit(for: command, in: currentSource(of: textView), selection: textView.selectedRange(),
                                                      indentUnit: configuration.editingBehavior.indentUnit, tabSize: configuration.editingBehavior.tabSize),
                      NSMaxRange(edit.range) <= textStorage.length else { return false }
                textView.breakUndoCoalescing()
                guard textView.shouldChangeText(in: edit.range, replacementString: edit.replacement) else { return true }
                textStorage.replaceCharacters(in: edit.range, with: edit.replacement)
                textView.didChangeText()
                if NSMaxRange(edit.selectionAfter) <= textStorage.length { textView.setSelectedRange(edit.selectionAfter) }
                return true
            }
        }

        func followLink(atCharacter characterIndex: Int, modifierFlags: NSEvent.ModifierFlags, in textView: NSTextView) -> Bool {
            guard let link = link(atCharacter: characterIndex, in: textView) else { return false }
            switch link {
            case .note(let target, let isWiki):
                if modifierFlags.contains(.command), let followLinkElsewhere = actions.followLinkElsewhere {
                    followLinkElsewhere(target, isWiki, TabPlacement.forLink(command: true, option: modifierFlags.contains(.option),
                                                                             shift: modifierFlags.contains(.shift)))
                } else {
                    follow(target, isWiki)
                }
            case .web(let location):
                NSWorkspace.shared.open(location)
            }
            return true
        }

        /// The link at a character in Live Preview, while its markup is concealed. A link
        /// that shows its markup is being edited, so a click there places the cursor; a
        /// link written in code or math is text.
        func link(atCharacter characterIndex: Int, in textView: NSTextView) -> LinkInText? {
            guard configuration.mode == .livePreview, !textState.cachesDescribeOldText else { return nil }
            let source = currentSource(of: textView)
            guard characterIndex < source.length else { return nil }
            if let revealedMarkup, LivePreviewTapTargets.isInsideLinkShowingItsMarkup(characterIndex, in: source, revealedMarkup: revealedMarkup) { return nil }
            let lineRange = source.lineRange(for: NSRange(location: characterIndex, length: 0))
            guard let link = LinkLocator.link(in: source.substring(with: lineRange), at: characterIndex - lineRange.location, includesEnd: false),
                  !LivePreviewTapTargets.isInsideCode(characterIndex, in: source) else { return nil }
            return link
        }

        // MARK: Session requests

        /// Answers what the session asks of the editor on screen, as the iPad editor does.
        func serveSessionRequests(in textView: NSTextView) {
            goToReadingPlaceIfSwitched(in: textView)
            presentFindIfRequested(in: textView)
            startEditingIfRequested(in: textView)
        }

        /// Puts the cursor in a note just created, as Obsidian does, once the editor is in a window.
        private func startEditingIfRequested(in textView: NSTextView) {
            guard session.startsEditingWhenShown, textView.window != nil else { return }
            // After the update: becoming first responder during one would re-enter SwiftUI.
            DispatchQueue.main.async { [weak self, weak textView] in
                guard let self, let textView, let window = textView.window, self.session.startsEditingWhenShown else { return }
                self.session.startsEditingWhenShown = false
                window.makeFirstResponder(textView)
            }
        }

        /// After the note switched from reading, shows the line that was at the top of the
        /// reading view: a kept editor would otherwise stay where it was itself.
        private func goToReadingPlaceIfSwitched(in textView: NSTextView) {
            guard textView.window != nil, let location = session.takeEditingStartLocation() else { return }
            // The note's start is the top of the view.
            guard location > 0 else {
                pendingJump = nil
                textView.scroll(NSPoint(x: 0, y: 0))
                return
            }
            pendingJump = .topOfCharacter(location)
            performPendingJumpIfReady(in: textView)
        }

        /// Opens the find bar the command palette asked for, once the editor is on screen.
        private func presentFindIfRequested(in textView: NSTextView) {
            guard session.findRequest != nil, textView.window != nil else { return }
            // After the update: showing the bar during one would re-enter SwiftUI.
            DispatchQueue.main.async { [weak self, weak textView] in
                guard let self, let textView, let window = textView.window, let request = self.session.findRequest else { return }
                self.session.findRequest = nil
                window.makeFirstResponder(textView)
                let action: NSTextFinder.Action = request == .findAndReplace ? .showReplaceInterface : .showFindInterface
                let sender = NSMenuItem()
                sender.tag = action.rawValue
                textView.performTextFinderAction(sender)
            }
        }

        // MARK: Jumps

        /// Makes the pending jump once the view is in a window and has a width.
        func performPendingJumpIfReady(in textView: NSTextView) {
            guard let jump = pendingJump, textView.window != nil, textView.bounds.width > 0 else { return }
            pendingJump = nil
            let textLength = textView.textStorage?.length ?? 0
            switch jump {
            case .heading(let anchor, let occurrence):
                guard let lineLocation = HeadingLocator.lineLocation(ofHeadingWithAnchor: anchor, occurrence: occurrence, in: currentSource(of: textView)) else { return }
                textView.setSelectedRange(NSRange(location: lineLocation, length: 0))
                scrollToTop(of: lineLocation, in: textView)
            case .textRange(let range):
                guard NSMaxRange(range) <= textLength else { return }
                // Selecting the match marks it, as a search does on the Mac.
                textView.setSelectedRange(range)
                scrollToTop(of: (currentSource(of: textView)).lineRange(for: NSRange(location: range.location, length: 0)).location, in: textView)
            case .topOfCharacter(let characterLocation):
                scrollToTop(of: min(characterLocation, textLength), in: textView)
            }
        }

        /// Brings a character's line to the top of the view, or as near as the note's end allows.
        func scrollToTop(of characterLocation: Int, in textView: NSTextView) {
            guard let textLayoutManager = textView.textLayoutManager, let contentManager = textLayoutManager.textContentManager,
                  let location = contentManager.location(contentManager.documentRange.location, offsetBy: characterLocation),
                  let precedingRange = NSTextRange(location: contentManager.documentRange.location, end: location) else { return }
            // Positions before the line must be real, not estimated, for the jump to land. The
            // view's height follows the layout only when the viewport is laid out, and a
            // scroll past its current height would stop short.
            textLayoutManager.ensureLayout(for: precedingRange)
            textLayoutManager.textViewportLayoutController.layoutViewport()
            guard let fragment = textLayoutManager.textLayoutFragment(for: location) else { return }
            textView.scroll(NSPoint(x: 0, y: max(0, fragment.layoutFragmentFrame.minY + textView.textContainerOrigin.y - 12)))
        }

        /// Lets the session ask where the editor is, as a tab closes or Graphite leaves the
        /// screen, while the editor shows the note. A pending jump has not landed yet, and is
        /// the place.
        func reportPlace(of textView: NSTextView) {
            session.recordEditorPlace = { [weak self, weak textView] in
                guard let self, let textView, textView.window != nil, self.pendingJump == nil else { return }
                self.recordScrollLocation(of: textView)
            }
        }

        /// How far, in points, the clip view's alignment to device pixels can move a scroll position.
        private static let scrollAlignmentAllowance: CGFloat = 1

        /// Remembers the character at the top of the view in the session.
        func recordScrollLocation(of textView: NSTextView) {
            let visibleTop = textView.visibleRect.minY
            guard visibleTop > 1 else {
                session.savedScrollLocation = nil
                return
            }
            // `scrollToTop` puts a line 12 points below the top, but the clip view then aligns its
            // origin to whole device pixels: up to a point earlier on a display of one pixel to the
            // point, which would put the probe in the line above. The allowance keeps it in the line.
            let probeY = visibleTop + 12 + Self.scrollAlignmentAllowance - textView.textContainerOrigin.y
            guard let textLayoutManager = textView.textLayoutManager, let contentManager = textLayoutManager.textContentManager,
                  let fragment = textLayoutManager.textLayoutFragment(for: CGPoint(x: 0, y: probeY)) else { return }
            session.savedScrollLocation = contentManager.offset(from: contentManager.documentRange.location, to: fragment.rangeInElement.location)
        }
    }
}
#endif

extension NativeMarkdownEditor {
    /// Shown when a pasted or dropped item's content cannot be read, so nothing is added.
    static let unreadableItemMessage = "An item could not be read, so it was not added to the note."
}

import SwiftUI
import UniformTypeIdentifiers
import GraphiteCore

#if canImport(UIKit)
import UIKit

/// A TextKit 2 text view that keeps a readable column centered on wide screens and
/// hosts Live Preview's rendered blocks.
final class MarkdownTextView: UITextView {
    static let readableColumnWidth: CGFloat = 740
    static let minimumHorizontalInset: CGFloat = 28
    var usesReadableLineLength = true { didSet { setNeedsLayout() } }
    /// The note's name above the text, drawn by a label the text is inset below.
    var inlineTitle: (text: String, fontSize: CGFloat)? {
        didSet {
            guard inlineTitle?.text != oldValue?.text || inlineTitle?.fontSize != oldValue?.fontSize else { return }
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

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hitView = super.hitTest(point, with: event)
        if hitView != nil, event?.type == .touches { lastTouchUptime = ProcessInfo.processInfo.systemUptime }
        return hitView
    }

    override var canBecomeFirstResponder: Bool {
        let wasRecentlyTouched = ProcessInfo.processInfo.systemUptime - lastTouchUptime < 1
        return super.canBecomeFirstResponder && (isFirstResponder || isEditingRequested || wasRecentlyTouched)
    }

    /// Starts editing on Graphite's behalf, for example to show a rendered block's source.
    func beginEditing() {
        isEditingRequested = true
        becomeFirstResponder()
        isEditingRequested = false
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let horizontalInset = usesReadableLineLength
            ? max(Self.minimumHorizontalInset, (bounds.width - Self.readableColumnWidth) / 2)
            : Self.minimumHorizontalInset
        var topInset = Self.topInset
        if let inlineTitleLabel {
            let titleWidth = max(bounds.width - 2 * horizontalInset - 2 * textContainer.lineFragmentPadding, 1)
            let titleHeight = ceil(inlineTitleLabel.sizeThatFits(CGSize(width: titleWidth, height: .greatestFiniteMagnitude)).height)
            inlineTitleLabel.frame = CGRect(x: horizontalInset + textContainer.lineFragmentPadding, y: Self.topInset, width: titleWidth, height: titleHeight)
            topInset += titleHeight + Self.inlineTitleSpacing
        }
        let insets = UIEdgeInsets(top: topInset, left: horizontalInset, bottom: 160, right: horizontalInset)
        // Setting equal insets would still invalidate the layout.
        if textContainerInset != insets { textContainerInset = insets }
        didLayout?(self)
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
        label.font = .systemFont(ofSize: inlineTitle.fontSize, weight: .bold)
        label.textColor = .label
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

    // MARK: Keyboard

    /// Runs an editing command; set by the editor's coordinator.
    var runCommand: ((EditorCommand) -> Void)?
    /// The suggestions at the cursor, which take the arrow keys, Return, and Escape while open.
    weak var completion: CompletionModel?
    /// Closes the suggestions on Escape; set by the coordinator, which tracks what they were found for.
    var dismissCompletion: (() -> Void)?

    /// Whether the cursor is on a link, so Return with ⌥ or ⌘ follows it; set by the coordinator.
    var isCursorOnLink: (() -> Bool)?

    /// Obsidian's editing shortcuts. ⌘B and ⌘I arrive through `toggleBoldface` and
    /// `toggleItalics`, which also serve the edit menu's format items.
    private var editorShortcuts: [(title: String, input: String, modifiers: UIKeyModifierFlags, command: EditorCommand)] {
        var shortcuts: [(title: String, input: String, modifiers: UIKeyModifierFlags, command: EditorCommand)] = [
            ("Outdent", "\t", .shift, .outdent),
            ("Toggle Checkbox", "l", .command, .task),
            ("Insert Link", "k", .command, .insertMarkdownLink),
            ("Highlight", "h", [.command, .shift], .highlight),
            ("Strikethrough", "x", [.command, .shift], .strikethrough),
            ("Code", "`", .command, .code),
            ("Comment", "/", .command, .comment),
            ("Find and Replace", "f", [.command, .alternate], .findAndReplace),
            ("Move Line Up", UIKeyCommand.inputUpArrow, [.command, .alternate], .moveLinesUp),
            ("Move Line Down", UIKeyCommand.inputDownArrow, [.command, .alternate], .moveLinesDown),
        ]
        shortcuts += (1...6).map { level in ("Heading \(level)", String(level), [.command, .control], .heading(level)) }
        // Only on a link, so these keys keep their usual meaning elsewhere.
        if isCursorOnLink?() == true {
            shortcuts += [
                ("Follow Link", "\r", .alternate, .followLink(.currentTab)),
                ("Open Link in New Tab", "\r", .command, .followLink(.newTab)),
                ("Open Link on the Other Side", "\r", [.command, .alternate], .followLink(.otherGroup)),
            ]
        }
        return shortcuts
    }

    override var keyCommands: [UIKeyCommand]? {
        var keyCommands = (super.keyCommands ?? []) + editorShortcuts.map { shortcut in
            let keyCommand = UIKeyCommand(title: shortcut.title, action: #selector(runKeyCommand(_:)), input: shortcut.input,
                                          modifierFlags: shortcut.modifiers, propertyList: shortcut.title)
            keyCommand.wantsPriorityOverSystemBehavior = true
            return keyCommand
        }
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
        guard let title = keyCommand.propertyList as? String,
              let shortcut = editorShortcuts.first(where: { shortcut in shortcut.title == title }) else { return }
        runCommand?(shortcut.command)
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

    /// Image types saved as they are; others are converted to PNG. HEIC is converted to
    /// JPEG because Obsidian does not show HEIC images.
    private static let keptImageTypes: [(UTType, String)] = [(.png, "png"), (.jpeg, "jpg"), (.gif, "gif"), (.webP, "webp")]

    private func insertionRequest(at range: NSRange) -> InsertionRequest {
        InsertionRequest(range: range, revision: textRevision?() ?? 0)
    }

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if action == #selector(toggleUnderline(_:)) { return false }
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
        let dropRequest = insertionRequest(at: selectedRange)
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

struct NativeMarkdownEditor: UIViewRepresentable {
    @Bindable var session: MarkdownSession
    let configuration: EditorConfiguration
    var environment: LivePreviewEnvironment?
    let headingScrollRequest: HeadingScrollRequest?
    var actions = EditorActions()
    let follow: (String, Bool) -> Void

    init(session: MarkdownSession, configuration: EditorConfiguration, environment: LivePreviewEnvironment? = nil,
         headingScrollRequest: HeadingScrollRequest?, actions: EditorActions = EditorActions(), follow: @escaping (String, Bool) -> Void) {
        self.session = session
        self.configuration = configuration
        self.environment = environment
        self.headingScrollRequest = headingScrollRequest
        self.actions = actions
        self.follow = follow
    }

    func makeCoordinator() -> Coordinator { Coordinator(session: session, configuration: configuration) }

    func makeUIView(context: Context) -> MarkdownTextView {
        let textView = MarkdownTextView(usingTextLayoutManager: true)
        let coordinator = context.coordinator
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
            return coordinator.link(atCharacter: textView.selectedRange.location, in: textView, skipsRevealedLines: false) != nil
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
        textView.inlineTitle = configuration.inlineTitle.map { title in (title, CGFloat(configuration.textSize * InlineTitleStyle.fontScale)) }
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
        textView.didLayout = { [weak coordinator] layoutView in
            coordinator?.schedulePendingJumpIfReady(in: layoutView)
            coordinator?.positionWidgets(in: layoutView)
            coordinator?.positionFoldButtons(in: layoutView)
            coordinator?.layOutViewportAgainIfShort(in: layoutView)
            coordinator?.placeWidgetsAfterWidthChange(in: layoutView)
        }
        textView.didMoveIntoWindow = { [weak coordinator] windowedView in
            coordinator?.startEditingIfRequested(in: windowedView)
            coordinator?.presentFindIfRequested(in: windowedView)
        }
        if let savedScrollLocation = session.savedScrollLocation { coordinator.pendingJump = .topOfCharacter(savedScrollLocation) }
        session.isEditorAttached = true
        coordinator.installLinkTapRecognizer(on: textView)
        coordinator.rebuildBlocks(in: textView)
        coordinator.restyleEverything(in: textView)
        // Rendered blocks and drawn replacements take their colors from the appearance.
        textView.registerForTraitChanges([UITraitUserInterfaceStyle.self]) { [weak coordinator] (changedView: MarkdownTextView, _: UITraitCollection) in
            coordinator?.restyleEverything(in: changedView)
            coordinator?.refreshWidgets(in: changedView)
        }
        return textView
    }

    func updateUIView(_ textView: MarkdownTextView, context: Context) {
        let coordinator = context.coordinator
        coordinator.session = session
        // Rendered drawings must be rebuilt after a drawing file is rewritten.
        if coordinator.environment?.drawingVersion != environment?.drawingVersion { coordinator.removeAllWidgets() }
        let previousBlockPolicy = coordinator.renderedBlockPolicy
        coordinator.environment = environment
        coordinator.follow = follow
        coordinator.actions = actions
        coordinator.updateInsertionHandlers(of: textView)
        coordinator.updateKeyboardToolbar(of: textView)
        textView.convertsPastedHTML = configuration.editingBehavior.convertsPastedHTML
        textView.usesReadableLineLength = configuration.usesReadableLineLength
        textView.inlineTitle = configuration.inlineTitle.map { title in (title, CGFloat(configuration.textSize * InlineTitleStyle.fontScale)) }
        textView.spellCheckingType = configuration.usesSpellChecking ? .yes : .no
        // Turning the Properties view on or off changes which blocks are rendered, as the
        // configuration can.
        if coordinator.configuration != configuration || coordinator.renderedBlockPolicy != previousBlockPolicy {
            coordinator.configuration = configuration
            coordinator.rebuildBlocks(in: textView, forcesBlockScan: true)
            coordinator.restyleEverything(in: textView)
        }
        // Rendered blocks already on screen show the new settings, index state and
        // accent in place, keeping their own state (such as a base's chosen view).
        let widgetSignature = LivePreviewWidgetSignature(environment: environment, accentHex: configuration.accentHex, notePath: session.path.rawValue)
        if coordinator.widgetSignature != widgetSignature {
            let changesOnlyIndex = coordinator.widgetSignature?.appearance == widgetSignature.appearance
            coordinator.widgetSignature = widgetSignature
            coordinator.refreshWidgets(in: textView, onlyThoseReadingIndex: changesOnlyIndex)
        }
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

    static func dismantleUIView(_ textView: MarkdownTextView, coordinator: Coordinator) {
        coordinator.session.isEditorAttached = false
        coordinator.stopObservingCharacterEdits()
        coordinator.stopObservingMemoryWarnings()
        textView.findInteraction?.dismissFindNavigator()
        textView.didLayout = nil
        coordinator.recordScrollLocation(of: textView)
        coordinator.removeAllWidgets()
    }

    @MainActor
    final class Coordinator: NSObject, UITextViewDelegate, UIGestureRecognizerDelegate, NSTextLayoutManagerDelegate {
        var session: MarkdownSession
        var configuration: EditorConfiguration
        var environment: LivePreviewEnvironment?
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
        private var foldableRegions: [FoldableRegion] = []
        var appliedFoldedKeys: Set<String> = []
        private var foldButtons: [String: (chevron: UIButton, ellipsis: UIButton)] = [:]
        /// Where the cursor was, to tell which way it moved into a folded section.
        private var lastSelectionLocation = 0
        /// Notes longer than this do not fold, to keep typing fast.
        private static let maximumFoldingLength = 2_000_000
        private var foldedRegions: [FoldableRegion] { NoteFolding.foldedRegions(in: foldableRegions, foldedKeys: session.foldedKeys) }
        /// The text's length, the edit's location, and the folds before the edit under way,
        /// to carry folds across it.
        private var lengthBeforeEdit = 0
        private var editLocationBeforeEdit = 0
        private var foldedRegionsBeforeEdit: [FoldableRegion] = []
        /// Set while a second viewport layout is waiting, so layout passes do not ask for more.
        private var isViewportRelayoutPending = false
        var actions = EditorActions()
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
        private let textState = LivePreviewTextState()
        private var characterEditObserver: NSObjectProtocol?
        private var revealedRange: NSRange?
        /// Scanner state at line starts of this text view's storage, so restyling a line far
        /// down a long note does not rescan the note from its top. It drops what an edit
        /// invalidates by observing the storage itself.
        private let blockContextCheckpoints = MarkdownBlockContextCheckpoints()
        /// Whether the text view has keyboard focus; markup is revealed only then.
        private var isEditing = false
        private var blockEntries: [LivePreviewBlockEntry] { textState.blockEntries }
        /// Measured heights of rendered blocks, keyed by their content: the height each
        /// block's view last reported in this editor, whatever the width then.
        private var reservedHeights: [LivePreviewBlockKey: CGFloat] = [:]
        private static let reservedHeightsKeptBeyondBlocks = 64
        /// Heights measured by every editor, for blocks this editor has not measured yet.
        /// Shared across editors on purpose: they are disposable, bounded, and main-actor only.
        private static var sharedMeasuredHeights = MeasuredBlockHeightCache(capacity: 2_000)
        /// Blocks whose measured height changed while the text could not be styled.
        private var blockKeysAwaitingRestyle: Set<LivePreviewBlockKey> = []
        /// The rendered blocks' views on screen.
        private var widgetHosts: [LivePreviewBlockKey: UIHostingController<AnyView>] = [:]
        /// Views taken off screen, kept to be shown again; dropped on a memory warning.
        private var detachedWidgets = DetachedWidgetPool<UIHostingController<AnyView>>(budgetMegabytes: 24)
        private var memoryWarningObserver: NSObjectProtocol?
        var widgetSignature: LivePreviewWidgetSignature?
        /// Consecutive layout passes that placed, moved, or could not place a rendered block.
        private var unsettledPlacementPasses = 0
        /// Later tries for a rendered block still missing after the passes above, which can
        /// happen when TextKit lays out the viewport only after the view settles.
        private var delayedPlacementTries = 0
        /// The text column's width when rendered blocks were last placed, and the placement
        /// waiting for a new width to settle.
        private var placedColumnWidth: CGFloat = 0
        private var placementAfterWidthChange: DispatchWorkItem?
        /// A heading the view keeps at its top while rendered blocks above it settle their
        /// heights, until the deadline or until the person scrolls.
        private var pinnedHeading: (location: Int, deadline: TimeInterval)?
        /// Pastes and drops whose content is still loading or saving.
        private var pendingInsertionRequests = PendingInsertionRequests()
        /// The text revision the open suggestions were found at, and the revisions of accepted
        /// suggestions whose edits are still being made. Their edits arrive after
        /// asynchronous work and are moved past typing that happened meanwhile.
        private var completionContextRevision: Int?
        private var acceptedCompletionRevisions: [Int] = []
        /// Only a few are kept: the edits use the latest.
        private static let maximumAcceptedCompletionRevisions = 8

        init(session: MarkdownSession, configuration: EditorConfiguration) {
            self.session = session
            self.configuration = configuration
        }

        private var styler: MarkdownTextStyler {
            MarkdownTextStyler(configuration: configuration, accentColor: UIColor(graphiteHex: configuration.accentHex) ?? .tintColor)
        }
        private var isLivePreview: Bool { configuration.mode == .livePreview && environment != nil }
        /// What decides which blocks are rendered besides the configuration.
        var renderedBlockPolicy: [Bool] { [environment != nil, environment?.updateProperties != nil] }
        var textRevision: Int { textState.history.revision }

        // MARK: Character edits

        /// Follows every change to the text view's characters. The text storage reports a
        /// change before UIKit's selection callback runs against the new text, and on paths
        /// that never call `shouldChangeTextIn`: `insertText`, `replace(_:withText:)`,
        /// Backspace, undo and redo, find and replace, and setting the text.
        func observeCharacterEdits(in textView: UITextView) {
            characterEditObserver = NotificationCenter.default.addObserver(forName: NSTextStorage.didProcessEditingNotification,
                                                                           object: textView.textStorage, queue: nil) { [weak self, weak textView] notification in
                guard let textStorage = notification.object as? NSTextStorage, textStorage.editedMask.contains(.editedCharacters) else { return }
                let edit = CharacterEdit(editedRange: textStorage.editedRange, changeInLength: textStorage.changeInLength)
                MainActor.assumeIsolated {
                    guard let self, let textView else { return }
                    self.recordCharacterEdit(edit, in: textView)
                }
            }
        }

        func stopObservingCharacterEdits() {
            if let characterEditObserver { NotificationCenter.default.removeObserver(characterEditObserver) }
            characterEditObserver = nil
        }

        func observeMemoryWarnings() {
            memoryWarningObserver = NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification,
                                                                           object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.detachedWidgets.removeAll() }
            }
        }

        func stopObservingMemoryWarnings() {
            if let memoryWarningObserver { NotificationCenter.default.removeObserver(memoryWarningObserver) }
            memoryWarningObserver = nil
        }

        private func recordCharacterEdit(_ edit: CharacterEdit, in textView: UITextView) {
            guard textState.recordCharacterEdit(edit, revealedRange: revealedRange) else { return }
            // UIKit reports `textViewDidChange` after its own edits and Graphite settles its
            // own; this catches a path that does neither, once UIKit's edit is done.
            DispatchQueue.main.async { [weak self, weak textView] in
                guard let self, let textView, self.textState.cachesDescribeOldText, textView.markedTextRange == nil else { return }
                self.textViewDidChange(textView)
            }
        }

        /// The text as an immutable snapshot: the one the blocks were found in while it is
        /// current, a fresh copy otherwise. Reading `UITextView.text` copies the whole note;
        /// the text storage's `string` bridges to its live backing store, which changes with
        /// the next edit, so the copy is made explicitly.
        private func currentSource(of textView: UITextView) -> NSString {
            if !textState.cachesDescribeOldText, textState.source.length == textView.textStorage.length { return textState.source }
            return NSString(string: textView.textStorage.string)
        }

        /// Whether blocks, folds, and revealed lines describe the text on screen, so they
        /// can be styled or acted on.
        private func canStyle(_ textView: UITextView) -> Bool {
            !textState.cachesDescribeOldText && textView.markedTextRange == nil
        }

        // MARK: Styling

        func rebuildBlocks(in textView: UITextView, forcesBlockScan: Bool = false) {
            let source = currentSource(of: textView)
            textState.update(source: source, findsBlocks: isLivePreview, forcesBlockScan: forcesBlockScan, isRendered: isRendered)
            forgetHeightsOfRemovedBlocks()
            foldableRegions = source.length <= Self.maximumFoldingLength ? NoteFolding.regions(in: source as String) : []
            revealedRange = revealedLines(in: textView)
        }

        /// Heights are keyed by content, so every edited version of a measured block leaves one
        /// behind; they are forgotten once they clearly outnumber the blocks in the note.
        private func forgetHeightsOfRemovedBlocks() {
            guard reservedHeights.count > 2 * blockEntries.count + Self.reservedHeightsKeptBeyondBlocks else { return }
            let keysInNote = Set(blockEntries.map(\.key))
            reservedHeights = reservedHeights.filter { key, _ in keysInNote.contains(key) }
            blockKeysAwaitingRestyle.formIntersection(keysInNote)
        }

        /// Frontmatter stays as text when the Properties view is off.
        private func isRendered(_ block: LivePreviewBlock) -> Bool {
            block.kind != .frontmatter || environment?.updateProperties != nil
        }

        func restyleEverything(in textView: UITextView) {
            appliedFoldedKeys = session.foldedKeys
            // The pending edit is styled with the rest, so its blocks must describe the text.
            if textState.cachesDescribeOldText { rebuildBlocks(in: textView) }
            textState.discardUnstyledEdit()
            styler.applyStyles(to: textView.textStorage, editedRange: NSRange(location: 0, length: 0), restyleEverything: true,
                               revealedRange: revealedRange, concealedBlocks: concealedBlocks(in: textView), foldedRegions: foldedRegions,
                               blockContextCheckpoints: blockContextCheckpoints)
            textView.typingAttributes = styler.baseAttributes
            textView.setNeedsLayout()
        }

        private func restyle(_ range: NSRange, in textView: UITextView) {
            let selectedRange = textView.selectedRange
            styler.applyStyles(to: textView.textStorage, editedRange: range, restyleEverything: false,
                               revealedRange: revealedRange, concealedBlocks: concealedBlocks(in: textView), foldedRegions: foldedRegions,
                               blockContextCheckpoints: blockContextCheckpoints)
            textView.selectedRange = selectedRange
            textView.typingAttributes = styler.baseAttributes
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
                revealedRange = revealedLines(in: textView)
                restyleEverything(in: textView)
                restyleBlocksAwaitingRestyle(in: textView)
                return
            }
            guard textState.hasUnstyledEdit else { return }
            revealedRange = revealedLines(in: textView)
            guard let plan = textState.takeRestylePlan(revealedRange: revealedRange) else { return }
            switch plan {
            case .everything:
                restyleEverything(in: textView)
            case .ranges(let ranges):
                for range in ranges { restyle(range, in: textView) }
                textView.setNeedsLayout()
            }
            restyleBlocksAwaitingRestyle(in: textView)
        }

        /// Whether the cursor is in a block, so its source shows.
        private func isActive(_ entry: LivePreviewBlockEntry, selection: NSRange, in source: NSString) -> Bool {
            isEditing && LivePreviewBlockActivity.isActive(blockRange: entry.range, selection: selection, in: source)
        }

        private func concealedBlocks(in textView: UITextView) -> [ConcealedBlock] {
            guard isLivePreview, !textState.cachesDescribeOldText else { return [] }
            let source = currentSource(of: textView)
            let selection = textView.selectedRange
            let columnWidth = (textView as? MarkdownTextView)?.contentColumnWidth ?? textView.bounds.width
            let folded = foldedRegions
            return blockEntries.compactMap { entry in
                // A block that runs past the text is stale; styling it would raise.
                guard NSMaxRange(entry.range) <= source.length else { return nil }
                // A folded section hides its blocks too.
                guard NoteFolding.regions(hiding: entry.range.location, in: folded).isEmpty else { return nil }
                guard !isActive(entry, selection: selection, in: source) else { return nil }
                return ConcealedBlock(range: entry.range, reservedHeight: reservedHeight(of: entry, columnWidth: columnWidth))
            }
        }

        /// The height reserved for a rendered block: the one its view last reported in this
        /// editor, else one measured at this width and text size by an earlier editor, else
        /// an estimate. The view corrects the latter two when it reports its height.
        private func reservedHeight(of entry: LivePreviewBlockEntry, columnWidth: CGFloat) -> CGFloat {
            if let reservedHeight = reservedHeights[entry.key] { return reservedHeight }
            if let sharedKey = MeasuredBlockHeightCache.Key(blockKey: entry.key, columnWidth: columnWidth, textSize: configuration.textSize),
               let measuredHeight = Self.sharedMeasuredHeights.height(for: sharedKey) {
                return measuredHeight
            }
            return estimatedHeight(of: entry.block, columnWidth: columnWidth)
        }

        private func estimatedHeight(of block: LivePreviewBlock, columnWidth: CGFloat) -> CGFloat {
            switch block.kind {
            case .frontmatter: return 44 + 34 * CGFloat(block.markdown.components(separatedBy: "\n").count - 2)
            case .table: return 40 * CGFloat(block.markdown.components(separatedBy: "\n").count - 1) + 16
            case .mathBlock: return 72
            case .horizontalRule: return 28
            case .callout: return 56 + 30 * CGFloat(block.markdown.components(separatedBy: "\n").count - 1)
            case .baseDefinition: return EmbeddedBaseView.defaultHeight
            case .embed(let embed):
                let fileExtension = (WikiLinkResolver.pathPart(embed.target) as NSString).pathExtension.lowercased()
                if MediaFileKind.videoExtensions.contains(fileExtension) { return columnWidth * 9 / 16 + 8 }
                if MediaFileKind.audioExtensions.contains(fileExtension) { return 96 }
                if fileExtension == "pdf" { return 570 }
                if fileExtension == "base" { return EmbeddedBaseView.defaultHeight }
                if DocumentKind(fileExtension: fileExtension) == .image { return 280 }
                return 60
            }
        }

        /// The lines whose markup shows. Nothing shows while the note is only being read:
        /// a cursor left at the top must not turn the properties back into YAML.
        private func revealedLines(in textView: UITextView) -> NSRange? {
            guard isEditing else { return nil }
            let source = currentSource(of: textView)
            let selection = textView.selectedRange
            guard selection.location <= source.length else { return nil }
            return source.lineRange(for: NSRange(location: selection.location, length: min(selection.length, source.length - selection.location)))
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
            if textState.cachesDescribeOldText {
                rebuildBlocks(in: textView)
            } else {
                revealedRange = revealedLines(in: textView)
            }
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
            textView.insertLinkToVaultFile = actions.insertLinkToVaultFile == nil ? nil : { [weak self] path, request in
                guard let self, let insertLinkToVaultFile = self.actions.insertLinkToVaultFile else { return }
                self.pendingInsertionRequests.remember(request)
                insertLinkToVaultFile(path, request.range)
            }
        }

        /// The keyboard toolbar's optional buttons.
        struct KeyboardToolbarButtons: Equatable {
            let attach, choosePhoto, takePhoto, draw: Bool
        }

        /// Builds the keyboard toolbar again when its optional buttons change, such as when
        /// Drawings is turned on or off while the note is open. Its buttons call the pane's
        /// current actions, not the ones from when the toolbar was built.
        func updateKeyboardToolbar(of textView: MarkdownTextView) {
            let buttons = KeyboardToolbarButtons(attach: actions.attach != nil, choosePhoto: actions.choosePhoto != nil,
                                                 takePhoto: actions.takePhoto != nil, draw: actions.draw != nil)
            guard buttons != keyboardToolbarButtons else { return }
            keyboardToolbarButtons = buttons
            var toolbarActions = EditorActions()
            if buttons.attach { toolbarActions.attach = { [weak self] in self?.actions.attach?() } }
            if buttons.choosePhoto { toolbarActions.choosePhoto = { [weak self] in self?.actions.choosePhoto?() } }
            if buttons.takePhoto { toolbarActions.takePhoto = { [weak self] in self?.actions.takePhoto?() } }
            if buttons.draw { toolbarActions.draw = { [weak self] in self?.actions.draw?() } }
            textView.inputAccessoryView = EditorKeyboardToolbar(actions: toolbarActions) { [weak self, weak textView] command in
                guard let self, let textView else { return }
                self.run(command, in: textView)
            }
            if textView.isFirstResponder { textView.reloadInputViews() }
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
            guard let start = textView.position(from: textView.beginningOfDocument, offset: replacedRange.location),
                  let end = textView.position(from: start, offset: replacedRange.length),
                  let textRange = textView.textRange(from: start, to: end) else { return }
            let edit = CharacterEdit(editedRange: replacementRange, changeInLength: newSource.length - oldSource.length)
            let selection = TextRangeMapping.insertionTarget(textView.selectedRange, through: edit)
            isPerformingEdit = true
            textView.replace(textRange, withText: newSource.substring(with: replacementRange))
            isPerformingEdit = false
            if NSMaxRange(selection) <= textView.textStorage.length { textView.selectedRange = selection }
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
                guard behavior.continuesLists, MarkdownEditing.listLine(line.trimmingCharacters(in: .newlines))?.isListItem == true || selection.length > 0 else { return nil }
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
            if edit.range.length > 0 || !edit.replacement.isEmpty,
               let start = textView.position(from: textView.beginningOfDocument, offset: edit.range.location),
               let end = textView.position(from: start, offset: edit.range.length),
               let textRange = textView.textRange(from: start, to: end) {
                isPerformingEdit = true
                textView.replace(textRange, withText: edit.replacement)
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
            let context = LinkCompletion.context(in: currentSource(of: textView), cursor: textView.selectedRange.location)
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
                switch link(atCharacter: textView.selectedRange.location, in: textView, skipsRevealedLines: false) {
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
            actions.beginEditing?()
            isEditing = true
            // A tap that starts editing is turned into a cursor position after this call.
            // Revealing the markup of the old cursor's line now would invalidate the layout
            // below it, and the tap would land at the end of the note; the lines are revealed
            // once the cursor is in place.
            DispatchQueue.main.async { [weak self, weak textView] in
                guard let self, let textView, self.isEditing else { return }
                self.updateRevealedLines(in: textView)
                self.placeWidgetsAgain(in: textView)
            }
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            isEditing = false
            // A suggestion chosen as the keyboard closes still gets its edits.
            recordAcceptedCompletion()
            completionContextRevision = nil
            session.completion.update(context: nil, caretRect: .zero)
            updateRevealedLines(in: textView)
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
            guard abs(width - placedColumnWidth) > 0.5 else { return }
            placedColumnWidth = width
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
            updateRevealedLines(in: textView)
            // During an edit the selection is reported before the text; `textViewDidChange`
            // updates the suggestions right after, for the same selection.
            guard !textState.cachesDescribeOldText else { return }
            updateCompletion(in: textView)
        }

        /// Restyles the lines and rendered blocks whose markup starts or stops showing.
        private func updateRevealedLines(in textView: UITextView) {
            // During an edit, UIKit reports the new selection before the new text; the edit
            // restyles the revealed lines once it settles.
            guard isLivePreview, canStyle(textView) else { return }
            // An edit whose styling waited for an IME composition that ended without
            // `textViewDidChange` is styled now, revealed lines included.
            if textState.hasUnstyledEdit {
                settleTextChange(in: textView)
                return
            }
            let previousRevealedRange = revealedRange
            let newRevealedRange = revealedLines(in: textView)
            guard previousRevealedRange != newRevealedRange else { return }
            revealedRange = newRevealedRange
            let changedRanges = RevealedLinesChange.restyledRanges(from: previousRevealedRange, to: newRevealedRange, in: currentSource(of: textView))
            guard !changedRanges.isEmpty else { return }
            for changedRange in changedRanges {
                // A block's source shows or hides with the cursor as a unit.
                var affectedRange = changedRange
                for entry in blockEntries where NSIntersectionRange(entry.range, affectedRange).length > 0 || NSLocationInRange(affectedRange.location, entry.range) {
                    affectedRange = NSUnionRange(affectedRange, entry.range)
                }
                restyle(affectedRange, in: textView)
            }
            textView.setNeedsLayout()
        }

        private func publish(_ textView: UITextView) {
            let text = currentSource(of: textView) as String
            session.text = text
            lastSynchronizedText = text
            session.selection = textView.selectedRange
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
        /// has already laid out on screen are used: forcing layout elsewhere would move the
        /// estimated positions of the visible text, and the views would drift from it.
        func positionWidgets(in textView: MarkdownTextView) {
            guard isLivePreview, let environment, let textLayoutManager = textView.textLayoutManager,
                  let contentStorage = textLayoutManager.textContentManager as? NSTextContentStorage,
                  let viewportRange = textLayoutManager.textViewportLayoutController.viewportRange else {
                removeAllWidgets()
                return
            }
            // Mid-edit, the blocks describe the text before it; the views stay until it settles.
            guard !textState.cachesDescribeOldText else { return }
            let selection = textView.selectedRange
            var concealedBlocksByStart: [Int: LivePreviewBlockEntry] = [:]
            let source = currentSource(of: textView)
            let folded = foldedRegions
            // In note order, as the blocks are.
            let concealedEntries = blockEntries.filter { entry in
                NSMaxRange(entry.range) <= source.length && !isActive(entry, selection: selection, in: source)
                    && NoteFolding.regions(hiding: entry.range.location, in: folded).isEmpty
            }
            for entry in concealedEntries { concealedBlocksByStart[entry.range.location] = entry }
            var keysInUse = Set<LivePreviewBlockKey>()
            var didMoveWidget = false
            let documentStart = contentStorage.documentRange.location
            // A block whose concealed first lines are just above the viewport still shows
            // its view in the viewport, so the scan starts at that block.
            let viewportStart = contentStorage.offset(from: documentStart, to: viewportRange.location)
            let enumerationStartOffset = concealedBlocksByStart.values
                .filter { entry in entry.range.location < viewportStart && NSMaxRange(entry.range) >= viewportStart }
                .map { entry in entry.range.location }.min() ?? viewportStart
            let enumerationStart = contentStorage.location(documentStart, offsetBy: enumerationStartOffset) ?? viewportRange.location
            textLayoutManager.enumerateTextLayoutFragments(from: enumerationStart, options: []) { fragment in
                let fragmentStart = contentStorage.offset(from: documentStart, to: fragment.rangeInElement.location)
                // TextKit may not have laid out a block's first lines when they are above the
                // viewport. Its concealed lines are 0.01 points tall, so whichever of its lines
                // comes first starts at the block's top.
                let containingIndex = LivePreviewBlockLookup.index(ofElementContaining: fragmentStart, in: concealedEntries) { entry in entry.range }
                if let entry = containingIndex.map({ index in concealedEntries[index] }), !keysInUse.contains(entry.key) {
                    keysInUse.insert(entry.key)
                    let width = textView.contentColumnWidth
                    let height = reservedHeight(of: entry, columnWidth: width)
                    let frame = CGRect(x: textView.textContainerInset.left + textView.textContainer.lineFragmentPadding,
                                       y: fragment.layoutFragmentFrame.minY + textView.textContainerInset.top, width: width, height: height)
                    let host = widgetHost(for: entry, environment: environment, textView: textView)
                    if host.view.superview == nil { textView.addSubview(host.view) }
                    if host.view.frame != frame {
                        host.view.frame = frame
                        didMoveWidget = true
                    }
                }
                // Stop after the viewport; rendered blocks there appear as it scrolls.
                return fragment.rangeInElement.location.compare(viewportRange.endLocation) == .orderedAscending
            }
            for (key, host) in widgetHosts where !keysInUse.contains(key) {
                host.view.removeFromSuperview()
                widgetHosts[key] = nil
                // A block still in the note can scroll back into view, or the cursor can leave it.
                if let entry = blockEntries.first(where: { candidate in candidate.key == key }),
                   let estimatedMegabytes = DetachedWidgetPool<UIHostingController<AnyView>>.estimatedMegabytes(of: entry.block.kind) {
                    detachedWidgets.keep(host, for: key, estimatedMegabytes: estimatedMegabytes)
                }
            }
            // After a jump (the keyboard closing, a scroll to a heading) TextKit can finish
            // laying out the viewport after this pass; try again once it has.
            let viewportEnd = contentStorage.offset(from: documentStart, to: viewportRange.endLocation)
            let viewportCharacters = NSRange(location: enumerationStartOffset, length: max(0, viewportEnd - enumerationStartOffset))
            let isMissingBlock = concealedBlocksByStart.values.contains { entry in
                NSIntersectionRange(entry.range, viewportCharacters).length > 0 && !keysInUse.contains(entry.key)
            }
            // A placed view can change the height it reserves, and TextKit then moves the text
            // after this pass; one more pass on the next turn of the run loop follows it.
            if (isMissingBlock || didMoveWidget) && unsettledPlacementPasses < 6 {
                unsettledPlacementPasses += 1
                DispatchQueue.main.async { [weak textView] in textView?.setNeedsLayout() }
            } else if isMissingBlock && delayedPlacementTries < 3 {
                // Still missing after the quick passes: try again once the view has settled,
                // rather than leaving a gap until the next scroll.
                delayedPlacementTries += 1
                unsettledPlacementPasses = 0
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak textView] in textView?.setNeedsLayout() }
            } else if !isMissingBlock && !didMoveWidget {
                unsettledPlacementPasses = 0
                delayedPlacementTries = 0
            }
            keepPinnedHeadingAtTop(in: textView)
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            guard let textView = scrollView as? MarkdownTextView else { return }
            positionWidgets(in: textView)
            positionFoldButtons(in: textView)
            if session.completion.context != nil { updateCompletion(in: textView) }
        }

        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
            pinnedHeading = nil
        }

        /// The view on screen for a block, else the one kept since it was last on screen,
        /// else a new one.
        private func widgetHost(for entry: LivePreviewBlockEntry, environment: LivePreviewEnvironment, textView: MarkdownTextView) -> UIHostingController<AnyView> {
            if let host = widgetHosts[entry.key] { return host }
            if let host = detachedWidgets.take(entry.key) {
                widgetHosts[entry.key] = host
                return host
            }
            return makeWidgetHost(for: entry, environment: environment, textView: textView)
        }

        private func makeWidgetHost(for entry: LivePreviewBlockEntry, environment: LivePreviewEnvironment, textView: MarkdownTextView) -> UIHostingController<AnyView> {
            let host = UIHostingController(rootView: widgetRootView(for: entry, environment: environment, textView: textView))
            host.view.backgroundColor = .clear
            host.sizingOptions = []
            widgetHosts[entry.key] = host
            return host
        }

        /// Gives the rendered blocks on screen, and those kept off screen, the current
        /// environment and appearance; only the blocks that read the index when nothing
        /// else changed. Kept views of blocks no longer in the note are dropped, so none is
        /// shown again with an older environment.
        func refreshWidgets(in textView: MarkdownTextView, onlyThoseReadingIndex: Bool = false) {
            guard let environment, !widgetHosts.isEmpty || !detachedWidgets.isEmpty else { return }
            if !detachedWidgets.isEmpty { detachedWidgets.removeHosts(notIn: Set(blockEntries.map(\.key))) }
            for entry in blockEntries where !onlyThoseReadingIndex || LivePreviewWidgetSignature.readsIndex(entry.block.kind) {
                guard let host = widgetHosts[entry.key] ?? detachedWidgets.host(for: entry.key) else { continue }
                host.rootView = widgetRootView(for: entry, environment: environment, textView: textView)
            }
        }

        /// A hosted view does not inherit SwiftUI's environment from the editor, so the
        /// appearance and accent are passed in explicitly. A host is reused while its block
        /// moves with edits elsewhere, so its actions find the block by key when they run.
        private func widgetRootView(for entry: LivePreviewBlockEntry, environment: LivePreviewEnvironment, textView: MarkdownTextView) -> AnyView {
            let accent = Color(graphiteHex: configuration.accentHex) ?? .accentColor
            let key = entry.key
            let widget = LivePreviewWidgetView(block: entry.block, environment: environment, revealSource: { [weak self, weak textView] in
                guard let self, let textView, self.canStyle(textView),
                      let currentEntry = self.blockEntries.first(where: { candidate in candidate.key == key }) else { return }
                textView.beginEditing()
                textView.selectedRange = NSRange(location: currentEntry.range.location, length: 0)
                self.textViewDidChangeSelection(textView)
            }, reportHeight: { [weak self, weak textView] height in
                guard let self, let textView else { return }
                self.updateReservedHeight(height, for: key, in: textView)
            })
            return AnyView(widget
                .environment(\.colorScheme, textView.traitCollection.userInterfaceStyle == .dark ? .dark : .light)
                .tint(accent)
                .environment(\.accent, accent))
        }

        private func updateReservedHeight(_ height: CGFloat, for key: LivePreviewBlockKey, in textView: MarkdownTextView) {
            guard height > 1 else { return }
            // Measured at the width the view was laid out at, which can lag the text view's.
            let measuredWidth = widgetHosts[key]?.view.bounds.width ?? textView.contentColumnWidth
            let sharedKey = MeasuredBlockHeightCache.Key(blockKey: key, columnWidth: measuredWidth, textSize: configuration.textSize)
            // The height the styling reserved: this editor's last report, else an earlier editor's.
            let styledHeight = reservedHeights[key] ?? sharedKey.flatMap { sharedKey in Self.sharedMeasuredHeights.height(for: sharedKey) }
            if let sharedKey { Self.sharedMeasuredHeights.record(height, for: sharedKey) }
            if let styledHeight, abs(styledHeight - height) <= 1 {
                reservedHeights[key] = styledHeight
                return
            }
            reservedHeights[key] = height
            // Styling now would disturb an IME composition, and mid-edit the block's range
            // describes older text; the edit restyles the block once it settles.
            guard canStyle(textView), !textState.hasUnstyledEdit else {
                blockKeysAwaitingRestyle.insert(key)
                return
            }
            guard let currentEntry = blockEntries.first(where: { candidate in candidate.key == key }) else { return }
            restyle(currentEntry.range, in: textView)
            textView.setNeedsLayout()
        }

        /// Applies heights measured while the text could not be styled.
        private func restyleBlocksAwaitingRestyle(in textView: UITextView) {
            guard !blockKeysAwaitingRestyle.isEmpty else { return }
            let keys = blockKeysAwaitingRestyle
            blockKeysAwaitingRestyle.removeAll()
            for entry in blockEntries where keys.contains(entry.key) { restyle(entry.range, in: textView) }
            textView.setNeedsLayout()
        }

        /// When rendered blocks settle their heights after TextKit laid out the viewport, the
        /// text below them moves down and the laid-out part can end above the bottom of the
        /// view: lines there have no rendered blocks or fold chevrons until the next scroll.
        /// The viewport is laid out once more then.
        func layOutViewportAgainIfShort(in textView: MarkdownTextView) {
            guard !isViewportRelayoutPending, let textLayoutManager = textView.textLayoutManager,
                  let viewportRange = textLayoutManager.textViewportLayoutController.viewportRange,
                  viewportRange.endLocation.compare(textLayoutManager.documentRange.endLocation) == .orderedAscending else { return }
            var laidOutBottom: CGFloat = 0
            textLayoutManager.enumerateTextLayoutFragments(from: viewportRange.location, options: []) { fragment in
                laidOutBottom = max(laidOutBottom, fragment.layoutFragmentFrame.maxY)
                return fragment.rangeInElement.location.compare(viewportRange.endLocation) == .orderedAscending
            }
            let visibleBottom = textView.contentOffset.y + textView.bounds.height - textView.textContainerInset.top
            guard laidOutBottom > 0, laidOutBottom < visibleBottom - 1 else { return }
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
            var keys = session.foldedKeys
            var changed = false
            for region in previouslyFolded where !foldableRegions.contains(where: { candidate in candidate.key == region.key }) {
                keys.remove(region.key)
                changed = true
                let headerStart = region.headerRange.location + (editLocation < region.headerRange.location ? lengthChange : 0)
                if let moved = foldableRegions.first(where: { candidate in candidate.headerRange.location == headerStart }) { keys.insert(moved.key) }
            }
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
            let folded = foldedRegions
            var regionsByStart: [Int: FoldableRegion] = [:]
            for region in foldableRegions where NoteFolding.regions(hiding: region.headerRange.location, in: folded).isEmpty {
                if regionsByStart[region.headerRange.location] == nil { regionsByStart[region.headerRange.location] = region }
            }
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
                    let size: CGFloat = 22
                    let firstLineBounds = firstLine.typographicBounds
                    buttons.chevron.frame = CGRect(x: max(2, fragmentOrigin.x + textStartX - size - 4),
                                                   y: fragmentOrigin.y + firstLineBounds.minY + (firstLineBounds.height - size) / 2, width: size, height: size)
                    buttons.chevron.setImage(UIImage(systemName: isFolded ? "chevron.right" : "chevron.down",
                                                     withConfiguration: UIImage.SymbolConfiguration(pointSize: 11, weight: .semibold)), for: .normal)
                    buttons.chevron.alpha = isFolded ? 1 : 0.4
                    buttons.chevron.accessibilityLabel = isFolded ? "Unfold" : "Fold"
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
            for host in widgetHosts.values { host.view.removeFromSuperview() }
            widgetHosts.removeAll()
            detachedWidgets.removeAll()
        }

        // MARK: Drawn replacements

        nonisolated func textLayoutManager(_ textLayoutManager: NSTextLayoutManager, textLayoutFragmentFor location: NSTextLocation,
                                           in textElement: NSTextElement) -> NSTextLayoutFragment {
            ConcealedReplacementLayoutFragment(textElement: textElement, range: textElement.elementRange)
        }

        // MARK: Links, tasks, and headings

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
                    // ⌘ opens the link in a new tab and ⌥⌘ beside the note, as in Obsidian.
                    let modifierFlags = recognizer.modifierFlags
                    if modifierFlags.contains(.command), let followLinkElsewhere = actions.followLinkElsewhere {
                        followLinkElsewhere(target, isWiki, modifierFlags.contains(.alternate) ? .otherGroup : .newTab)
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
            let lineRange = source.lineRange(for: NSRange(location: characterIndex, length: 0))
            if let revealedRange, NSIntersectionRange(lineRange, revealedRange).length > 0 || lineRange.location == revealedRange.location { return nil }
            return LivePreviewTapTargets.taskCheckboxRange(at: characterIndex, in: source)
        }

        /// Checks or unchecks a task through the text view, so the change can be undone.
        private func toggleTask(_ checkboxRange: NSRange, in textView: UITextView) {
            let source = currentSource(of: textView)
            let stateRange = NSRange(location: checkboxRange.location + 1, length: 1)
            guard NSMaxRange(stateRange) <= source.length else { return }
            let isChecked = source.substring(with: stateRange) != " "
            guard let start = textView.position(from: textView.beginningOfDocument, offset: stateRange.location),
                  let end = textView.position(from: start, offset: 1), let stateTextRange = textView.textRange(from: start, to: end) else { return }
            let selectedRange = textView.selectedRange
            isPerformingEdit = true
            textView.replace(stateTextRange, withText: isChecked ? " " : "x")
            isPerformingEdit = false
            textView.selectedRange = selectedRange
            if textState.cachesDescribeOldText || session.text != textView.text { textViewDidChange(textView) }
        }

        /// A link under the finger on a line whose markup is concealed, as in Obsidian's
        /// Live Preview, where a tap on a link follows it instead of placing the cursor.
        private func link(at point: CGPoint, in textView: UITextView) -> LinkInText? {
            guard isLivePreview, let position = textView.closestPosition(to: point) else { return nil }
            return link(atCharacter: textView.offset(from: textView.beginningOfDocument, to: position), in: textView, skipsRevealedLines: true)
        }

        /// The link around a character. Taps skip the lines around the cursor, whose markup
        /// is showing and which are being edited; the keyboard's link commands do not. A
        /// link written in code or math is text.
        func link(atCharacter characterIndex: Int, in textView: UITextView, skipsRevealedLines: Bool) -> LinkInText? {
            let source = currentSource(of: textView)
            guard characterIndex <= source.length, source.length > 0 else { return nil }
            if skipsRevealedLines {
                guard characterIndex < source.length else { return nil }
                if let revealedRange, canStyle(textView), NSLocationInRange(characterIndex, revealedRange) { return nil }
            }
            let lineRange = source.lineRange(for: NSRange(location: characterIndex, length: 0))
            guard let link = LinkLocator.link(in: source.substring(with: lineRange), at: characterIndex - lineRange.location, includesEnd: !skipsRevealedLines),
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
            let accent = UIColor(graphiteHex: configuration.accentHex) ?? .tintColor
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
        /// measured heights. A heading near the end of the note stops where the note ends,
        /// as the jump itself does.
        private func keepPinnedHeadingAtTop(in textView: UITextView) {
            guard let pinnedHeading else { return }
            guard ProcessInfo.processInfo.systemUptime < pinnedHeading.deadline else {
                self.pinnedHeading = nil
                return
            }
            guard let textLayoutManager = textView.textLayoutManager,
                  let contentStorage = textLayoutManager.textContentManager as? NSTextContentStorage,
                  let location = contentStorage.location(contentStorage.documentRange.location, offsetBy: pinnedHeading.location),
                  let fragment = textLayoutManager.textLayoutFragment(for: location) else { return }
            let targetOffset = fragment.layoutFragmentFrame.minY + textView.textContainerInset.top - 12
            let clampedOffset = min(max(-textView.adjustedContentInset.top, targetOffset), maximumContentOffset(of: textView, layoutManager: textLayoutManager))
            if abs(textView.contentOffset.y - clampedOffset) > 1 {
                textView.setContentOffset(CGPoint(x: textView.contentOffset.x, y: clampedOffset), animated: false)
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
            pinnedHeading = (characterLocation, ProcessInfo.processInfo.systemUptime + 1.5)
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
    /// Saves pasted or dropped files and images, and links vault items; set by the coordinator.
    var insertAttachment: ((_ data: Data, _ stem: String, _ fileExtension: String, _ range: NSRange) -> Void)?
    var insertLinkToVaultFile: ((VaultPath, NSRange) -> Void)?
    /// Tells the person that a pasted or dropped file could not be read; set by the coordinator.
    var reportUnreadableItem: (() -> Void)?
    /// Follows the link a click lands on and says whether there was one; set by the coordinator.
    var followLinkOnClick: ((_ characterIndex: Int, _ modifierFlags: NSEvent.ModifierFlags) -> Bool)?
    /// Called when the view takes keyboard focus; set by the coordinator.
    var didBecomeFirstResponder: (() -> Void)?
    /// Called when the view enters a window or first gets a width, the two things a jump
    /// needs to measure the note; set by the coordinator.
    var didBecomeMeasurable: ((MarkdownMacTextView) -> Void)?

    private var canInsertAttachments: Bool { insertAttachment != nil || insertLinkToVaultFile != nil }

    override func becomeFirstResponder() -> Bool {
        let didBecome = super.becomeFirstResponder()
        if didBecome { didBecomeFirstResponder?() }
        return didBecome
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { didBecomeMeasurable?(self) }
    }

    override func setFrameSize(_ newSize: NSSize) {
        let hadWidth = frame.width > 0
        super.setFrameSize(newSize)
        if !hadWidth, newSize.width > 0 { didBecomeMeasurable?(self) }
    }

    override func mouseDown(with event: NSEvent) {
        let characterIndex = characterIndexForInsertion(at: convert(event.locationInWindow, from: nil))
        if event.clickCount == 1, followLinkOnClick?(characterIndex, event.modifierFlags) == true { return }
        super.mouseDown(with: event)
    }

    // MARK: Paste and drop

    override func paste(_ sender: Any?) {
        if canInsertAttachments, insertAttachments(from: .general, at: selectedRange()) { return }
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

/// The Mac has no layout fragment that draws bullets, checkboxes, quote bars, heading
/// separators, and formulas over their hidden source, so that source stays visible there,
/// in the color the drawing would have had.
enum UndrawnReplacementStyling {
    static func showSource(in textStorage: NSTextStorage, range: NSRange, baseFont: NSFont) {
        let checkedRange = NSIntersectionRange(range, NSRange(location: 0, length: textStorage.length))
        guard checkedRange.length > 0 else { return }
        var replacements: [(range: NSRange, replacement: ConcealedReplacement)] = []
        textStorage.enumerateAttribute(ConcealedReplacement.attributeKey, in: checkedRange) { value, attributeRange, _ in
            guard let rawValue = value as? String, let replacement = ConcealedReplacement(rawValue: rawValue) else { return }
            replacements.append((attributeRange, replacement))
        }
        guard !replacements.isEmpty else { return }
        textStorage.beginEditing()
        for (replacedRange, replacement) in replacements {
            let color = textStorage.attribute(ConcealedReplacement.colorAttributeKey, at: replacedRange.location, effectiveRange: nil) as? NSColor ?? .secondaryLabelColor
            for key in [ConcealedReplacement.attributeKey, ConcealedReplacement.colorAttributeKey, ConcealedReplacement.mathAttributeKey, .kern] {
                textStorage.removeAttribute(key, range: replacedRange)
            }
            switch replacement {
            case .inlineMath:
                // Styled as Source mode styles math.
                textStorage.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: baseFont.pointSize * 0.9, weight: .regular), range: replacedRange)
                textStorage.addAttribute(.foregroundColor, value: NSColor.systemIndigo, range: replacedRange)
            case .uncheckedTask, .checkedTask:
                textStorage.addAttribute(.foregroundColor, value: color, range: replacedRange)
                showListMarker(before: replacedRange.location, in: textStorage, baseFont: baseFont)
            case .bullet, .subpathSeparator, .quoteBar:
                textStorage.addAttribute(.foregroundColor, value: color, range: replacedRange)
            }
        }
        textStorage.endEditing()
    }

    /// A drawn checkbox stands in for its list marker, which is hidden with nothing
    /// marking it; on the Mac the marker shows with the checkbox's source.
    private static func showListMarker(before checkboxLocation: Int, in textStorage: NSTextStorage, baseFont: NSFont) {
        let lineStart = textStorage.mutableString.lineRange(for: NSRange(location: checkboxLocation, length: 0)).location
        let prefixRange = NSRange(location: lineStart, length: checkboxLocation - lineStart)
        guard prefixRange.length > 0 else { return }
        var hiddenRanges: [NSRange] = []
        textStorage.enumerateAttribute(.font, in: prefixRange) { value, fontRange, _ in
            if let font = value as? NSFont, font.pointSize < 1 { hiddenRanges.append(fontRange) }
        }
        for hiddenRange in hiddenRanges {
            textStorage.addAttribute(.font, value: baseFont, range: hiddenRange)
            textStorage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: hiddenRange)
        }
    }
}

struct NativeMarkdownEditor: NSViewRepresentable {
    @Bindable var session: MarkdownSession
    let configuration: EditorConfiguration
    let headingScrollRequest: HeadingScrollRequest?
    let actions: EditorActions
    let follow: (String, Bool) -> Void

    /// Rendered blocks are iPad-only, so the Mac does not use `environment`; it is accepted
    /// so both editors share one call. The Mac has no keyboard toolbar either: of `actions`,
    /// it uses pasting, dropping, following links elsewhere, and focusing the note's side.
    init(session: MarkdownSession, configuration: EditorConfiguration, environment: LivePreviewEnvironment? = nil,
         headingScrollRequest: HeadingScrollRequest?, actions: EditorActions = EditorActions(), follow: @escaping (String, Bool) -> Void) {
        self.session = session
        self.configuration = configuration
        self.headingScrollRequest = headingScrollRequest
        self.actions = actions
        self.follow = follow
    }

    func makeCoordinator() -> Coordinator { Coordinator(session: session, configuration: configuration) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = MarkdownMacTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? MarkdownMacTextView else { return scrollView }
        let coordinator = context.coordinator
        coordinator.actions = actions
        coordinator.follow = follow
        textView.isRichText = false
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
        coordinator.restyleEverything(in: textView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.session = session
        coordinator.actions = actions
        coordinator.follow = follow
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if coordinator.configuration != configuration {
            coordinator.configuration = configuration
            coordinator.restyleEverything(in: textView)
        }
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
        coordinator.performPendingJumpIfReady(in: textView)
    }

    static func dismantleNSView(_ scrollView: NSScrollView, coordinator: Coordinator) {
        coordinator.session.isEditorAttached = false
        coordinator.stopObservingCharacterEdits()
        guard let textView = scrollView.documentView as? NSTextView else { return }
        coordinator.recordScrollLocation(of: textView)
    }

    /// On the Mac, Live Preview conceals markup away from the cursor's line; rendered blocks
    /// are iPad-only for now, so they stay as styled source here.
    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var session: MarkdownSession
        var configuration: EditorConfiguration
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
        /// The text last styled and the edits styling has not caught up with, so each edit
        /// restyles only the lines it changed. The Mac finds no rendered blocks.
        private let textState = LivePreviewTextState()
        private var characterEditObserver: NSObjectProtocol?
        /// The cursor's line, whose markup shows in Live Preview.
        private(set) var revealedRange: NSRange?
        /// The text last given to or taken from the session; see the iPad coordinator.
        var lastSynchronizedText = ""
        /// Pastes and drops whose content is still loading or saving.
        private var pendingInsertionRequests = PendingInsertionRequests()

        init(session: MarkdownSession, configuration: EditorConfiguration) {
            self.session = session
            self.configuration = configuration
        }

        private var styler: MarkdownTextStyler { MarkdownTextStyler(configuration: configuration, accentColor: NSColor(graphiteHex: configuration.accentHex) ?? .controlAccentColor) }

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
            textView.didBecomeFirstResponder = { [weak self] in self?.actions.beginEditing?() }
            textView.didBecomeMeasurable = { [weak self] measurableView in
                // Not from inside the window change or layout itself.
                DispatchQueue.main.async { [weak self, weak measurableView] in
                    guard let self, let measurableView else { return }
                    self.performPendingJumpIfReady(in: measurableView)
                }
            }
            observeCharacterEdits(in: textView)
        }

        // MARK: Character edits

        /// Follows every change to the characters, whichever path made it, so the lines it
        /// changed are restyled and nothing is styled with ranges from the older text.
        func observeCharacterEdits(in textView: NSTextView) {
            guard let textStorage = textView.textStorage else { return }
            characterEditObserver = NotificationCenter.default.addObserver(forName: NSTextStorage.didProcessEditingNotification,
                                                                           object: textStorage, queue: nil) { [weak self, weak textView] notification in
                guard let textStorage = notification.object as? NSTextStorage, textStorage.editedMask.contains(.editedCharacters) else { return }
                let edit = CharacterEdit(editedRange: textStorage.editedRange, changeInLength: textStorage.changeInLength)
                MainActor.assumeIsolated {
                    guard let self, let textView else { return }
                    self.recordCharacterEdit(edit, in: textView)
                }
            }
        }

        func stopObservingCharacterEdits() {
            if let characterEditObserver { NotificationCenter.default.removeObserver(characterEditObserver) }
            characterEditObserver = nil
        }

        private func recordCharacterEdit(_ edit: CharacterEdit, in textView: NSTextView) {
            guard textState.recordCharacterEdit(edit, revealedRange: revealedRange) else { return }
            // AppKit reports `textDidChange` after its own edits; this catches a path that
            // does not, once the edit is done.
            DispatchQueue.main.async { [weak self, weak textView] in
                guard let self, let textView, self.textState.cachesDescribeOldText, !textView.hasMarkedText() else { return }
                self.settleTextChange(in: textView)
                self.publish(textView)
            }
        }

        /// The text as an immutable snapshot: the one last styled while it is current. The
        /// text storage's `string` bridges to its live backing store, so the copy is explicit.
        private func currentSource(of textView: NSTextView) -> NSString {
            guard let textStorage = textView.textStorage else { return NSString(string: textView.string) }
            if !textState.cachesDescribeOldText, textState.source.length == textStorage.length { return textState.source }
            return NSString(string: textStorage.string)
        }

        // MARK: Styling

        func restyleEverything(in textView: NSTextView) {
            guard let textStorage = textView.textStorage else { return }
            textState.update(source: currentSource(of: textView), findsBlocks: false, isRendered: { _ in true })
            textState.discardUnstyledEdit()
            revealedRange = revealedLines(in: textView)
            styler.applyStyles(to: textStorage, editedRange: NSRange(location: 0, length: 0), restyleEverything: true, revealedRange: revealedRange, concealedBlocks: [])
            UndrawnReplacementStyling.showSource(in: textStorage, range: NSRange(location: 0, length: textStorage.length), baseFont: styler.baseFont)
            textView.typingAttributes = styler.baseAttributes
        }

        private func restyle(_ range: NSRange, in textView: NSTextView) {
            guard let textStorage = textView.textStorage, textStorage.length > 0 else { return }
            let location = min(range.location, textStorage.length)
            let lineRange = textStorage.mutableString.lineRange(for: NSRange(location: location, length: min(range.length, textStorage.length - location)))
            styler.applyStyles(to: textStorage, editedRange: lineRange, restyleEverything: false, revealedRange: revealedRange, concealedBlocks: [])
            UndrawnReplacementStyling.showSource(in: textStorage, range: lineRange, baseFont: styler.baseFont)
            textView.typingAttributes = styler.baseAttributes
        }

        /// Restyles what the edits since the last styling changed, once no text is marked:
        /// styling would disturb an input method's composition.
        private func settleTextChange(in textView: NSTextView) {
            guard !textView.hasMarkedText(), textState.cachesDescribeOldText || textState.hasUnstyledEdit else { return }
            textState.update(source: currentSource(of: textView), findsBlocks: false, isRendered: { _ in true })
            revealedRange = revealedLines(in: textView)
            guard let plan = textState.takeRestylePlan(revealedRange: revealedRange) else { return }
            switch plan {
            case .everything: restyleEverything(in: textView)
            case .ranges(let ranges): for range in ranges { restyle(range, in: textView) }
            }
        }

        /// The cursor's line, measured in the text on screen.
        private func revealedLines(in textView: NSTextView) -> NSRange? {
            guard let textStorage = textView.textStorage else { return nil }
            let selection = textView.selectedRange()
            guard selection.location <= textStorage.length else { return nil }
            return textStorage.mutableString.lineRange(for: NSRange(location: selection.location, length: 0))
        }

        /// Restyles the lines whose markup starts or stops showing as the cursor moves.
        private func updateRevealedLines(in textView: NSTextView) {
            // Mid-edit, the new selection arrives before the new text; the edit restyles
            // the revealed lines once it settles.
            guard configuration.mode == .livePreview, !textView.hasMarkedText(), !textState.cachesDescribeOldText, !textState.hasUnstyledEdit else { return }
            let previousRevealedRange = revealedRange
            let newRevealedRange = revealedLines(in: textView)
            guard newRevealedRange != previousRevealedRange else { return }
            revealedRange = newRevealedRange
            for range in RevealedLinesChange.restyledRanges(from: previousRevealedRange, to: newRevealedRange, in: currentSource(of: textView)) {
                restyle(range, in: textView)
            }
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            settleTextChange(in: textView)
            publish(textView)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            session.selection = textView.selectedRange()
            updateRevealedLines(in: textView)
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
            guard textView.shouldChangeText(in: replacedRange, replacementString: replacement) else {
                textView.string = newText
                restyleEverything(in: textView)
                return
            }
            textStorage.replaceCharacters(in: replacedRange, with: replacement)
            textView.didChangeText()
            if NSMaxRange(selection) <= textStorage.length { textView.setSelectedRange(selection) }
        }

        // MARK: Links

        /// Follows the link at a clicked character, as a tap does on the iPad: ⌘ opens it
        /// in a new tab and ⌥⌘ beside the note.
        func followLink(atCharacter characterIndex: Int, modifierFlags: NSEvent.ModifierFlags, in textView: NSTextView) -> Bool {
            guard let link = link(atCharacter: characterIndex, in: textView) else { return false }
            switch link {
            case .note(let target, let isWiki):
                if modifierFlags.contains(.command), let followLinkElsewhere = actions.followLinkElsewhere {
                    followLinkElsewhere(target, isWiki, modifierFlags.contains(.option) ? .otherGroup : .newTab)
                } else {
                    follow(target, isWiki)
                }
            case .web(let location):
                NSWorkspace.shared.open(location)
            }
            return true
        }

        /// The link at a character in Live Preview, on a line whose markup is concealed.
        /// The cursor's line shows its markup and is being edited, so a click there places
        /// the cursor; a link written in code or math is text.
        func link(atCharacter characterIndex: Int, in textView: NSTextView) -> LinkInText? {
            guard configuration.mode == .livePreview, !textState.cachesDescribeOldText else { return nil }
            let source = currentSource(of: textView)
            guard characterIndex < source.length else { return nil }
            if let revealedRange, NSLocationInRange(characterIndex, revealedRange) { return nil }
            let lineRange = source.lineRange(for: NSRange(location: characterIndex, length: 0))
            guard let link = LinkLocator.link(in: source.substring(with: lineRange), at: characterIndex - lineRange.location, includesEnd: false),
                  !LivePreviewTapTargets.isInsideCode(characterIndex, in: source) else { return nil }
            return link
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

        /// Remembers the character at the top of the view in the session.
        func recordScrollLocation(of textView: NSTextView) {
            let visibleTop = textView.visibleRect.minY
            guard visibleTop > 1 else {
                session.savedScrollLocation = nil
                return
            }
            guard let textLayoutManager = textView.textLayoutManager, let contentManager = textLayoutManager.textContentManager,
                  let fragment = textLayoutManager.textLayoutFragment(for: CGPoint(x: 0, y: visibleTop + 12 - textView.textContainerOrigin.y)) else { return }
            session.savedScrollLocation = contentManager.offset(from: contentManager.documentRange.location, to: fragment.rangeInElement.location)
        }
    }
}
#endif

extension NativeMarkdownEditor {
    /// Shown when a pasted or dropped item's content cannot be read, so nothing is added.
    static let unreadableItemMessage = "An item could not be read, so it was not added to the note."
}

/// What Live Preview's rendered blocks show besides their source, in two parts: the
/// appearance and settings every block shows, and the index state that only some blocks
/// read. A save changes the index state, so after each pause in typing only the blocks
/// that read it are given the new state; the others keep their views untouched.
struct LivePreviewWidgetSignature: Equatable {
    let appearance: String
    let index: String

    /// `notePath` is where the blocks' links are followed from; the note can be renamed.
    init(environment: LivePreviewEnvironment?, accentHex: String, notePath: String) {
        guard let environment else {
            appearance = ""
            index = ""
            return
        }
        let palette = environment.paletteHexByName.sorted { leftEntry, rightEntry in leftEntry.key < rightEntry.key }
            .map { entry in "\(entry.key)=\(entry.value)" }.joined(separator: ",")
        let declaredPropertyTypes = environment.declaredPropertyTypes.sorted { leftEntry, rightEntry in leftEntry.key < rightEntry.key }
            .map { entry in "\(entry.key)=\(entry.value.rawValue)" }.joined(separator: ",")
        appearance = [String(environment.textSize), String(environment.colorsEnabled), palette, accentHex,
                      String(environment.updateProperties != nil), declaredPropertyTypes, notePath].joined(separator: "|")
        index = [String(environment.indexVersion), String(environment.baseContext?.isIndexComplete ?? false)].joined(separator: "|")
    }

    /// Whether a block's view reads the index: a base runs its query again, an embed not
    /// found yet looks for its file again, and a callout can contain either.
    static func readsIndex(_ kind: LivePreviewBlock.Kind) -> Bool {
        switch kind {
        case .embed, .baseDefinition, .callout: true
        case .frontmatter, .table, .mathBlock, .horizontalRule: false
        }
    }
}

/// Rendered-block views taken off screen, kept so a block that scrolls back into view, or
/// that the cursor leaves, shows again without being built again: building a table's view
/// takes tens of milliseconds. Memory bounds the pool, estimated per view from its block's
/// kind; the views taken off longest ago go first once the estimate passes the budget.
struct DetachedWidgetPool<Host> {
    private var hostsByKey: [LivePreviewBlockKey: (host: Host, estimatedMegabytes: Int)] = [:]
    /// Oldest first.
    private var detachmentOrder: [LivePreviewBlockKey] = []
    private var estimatedMegabytesInPool = 0
    let budgetMegabytes: Int

    init(budgetMegabytes: Int) {
        self.budgetMegabytes = budgetMegabytes
    }

    var isEmpty: Bool { hostsByKey.isEmpty }
    var keys: [LivePreviewBlockKey] { detachmentOrder }

    /// A view's estimated memory, from measured views: a 12-by-4 table about 6 MB,
    /// properties about 4 MB, a callout or math block under 1 MB; an embed can hold a
    /// decoded image. Nil for audio and video, which are never kept: a player kept off
    /// screen could go on playing.
    static func estimatedMegabytes(of kind: LivePreviewBlock.Kind) -> Int? {
        switch kind {
        case .table, .baseDefinition: return 6
        case .frontmatter: return 4
        case .mathBlock, .callout, .horizontalRule: return 1
        case .embed(let embed):
            let fileExtension = (WikiLinkResolver.pathPart(embed.target) as NSString).pathExtension.lowercased()
            if MediaFileKind.videoExtensions.contains(fileExtension) || MediaFileKind.audioExtensions.contains(fileExtension) { return nil }
            return 12
        }
    }

    /// Keeps a view taken off screen, dropping the oldest kept views past the budget.
    mutating func keep(_ host: Host, for key: LivePreviewBlockKey, estimatedMegabytes: Int) {
        _ = take(key)
        guard estimatedMegabytes <= budgetMegabytes else { return }
        hostsByKey[key] = (host, estimatedMegabytes)
        detachmentOrder.append(key)
        estimatedMegabytesInPool += estimatedMegabytes
        while estimatedMegabytesInPool > budgetMegabytes, let oldestKey = detachmentOrder.first {
            _ = take(oldestKey)
        }
    }

    /// Takes a kept view out of the pool to show it again.
    mutating func take(_ key: LivePreviewBlockKey) -> Host? {
        guard let kept = hostsByKey.removeValue(forKey: key) else { return nil }
        detachmentOrder.removeAll { keptKey in keptKey == key }
        estimatedMegabytesInPool -= kept.estimatedMegabytes
        return kept.host
    }

    /// A kept view, left in the pool, such as to give it a new appearance.
    func host(for key: LivePreviewBlockKey) -> Host? {
        hostsByKey[key]?.host
    }

    /// Drops the kept views of blocks no longer in the note.
    mutating func removeHosts(notIn keysInNote: Set<LivePreviewBlockKey>) {
        for key in detachmentOrder where !keysInNote.contains(key) { _ = take(key) }
    }

    mutating func removeAll() {
        hostsByKey.removeAll()
        detachmentOrder.removeAll()
        estimatedMegabytesInPool = 0
    }
}

/// Heights rendered blocks measured, shared by every editor, so a note opened again lays
/// its blocks out at their measured heights at once instead of at estimates that each
/// block then corrects with a restyle and a visible jump. A height holds for one column
/// width and text size. Past the capacity, the heights recorded longest ago go first.
struct MeasuredBlockHeightCache {
    struct Key: Hashable {
        let blockKey: LivePreviewBlockKey
        let columnWidth: Int
        let textSize: Double

        /// Nil for a width that is not a finite number of points, as before the first layout.
        init?(blockKey: LivePreviewBlockKey, columnWidth: CGFloat, textSize: Double) {
            guard let wholeColumnWidth = Int(exactly: columnWidth.rounded()), wholeColumnWidth > 0 else { return nil }
            self.blockKey = blockKey
            self.columnWidth = wholeColumnWidth
            self.textSize = textSize
        }
    }

    private var heightsByKey: [Key: CGFloat] = [:]
    /// Oldest first.
    private var recordingOrder: [Key] = []
    let capacity: Int

    init(capacity: Int) {
        self.capacity = capacity
    }

    var count: Int { heightsByKey.count }

    func height(for key: Key) -> CGFloat? {
        heightsByKey[key]
    }

    mutating func record(_ height: CGFloat, for key: Key) {
        if heightsByKey.updateValue(height, forKey: key) == nil { recordingOrder.append(key) }
        guard recordingOrder.count > capacity else { return }
        // Dropping a quarter at a time keeps the cost of shifting the order off most records.
        let droppedKeys = recordingOrder.prefix(max(1, capacity / 4))
        for droppedKey in droppedKeys { heightsByKey[droppedKey] = nil }
        recordingOrder.removeFirst(droppedKeys.count)
    }
}

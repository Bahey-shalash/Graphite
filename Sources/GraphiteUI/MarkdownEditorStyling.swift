#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif
import GraphiteCore

/// The text view a note is edited in, as the shared styling sees it: UIKit's `UITextView`
/// on the iPad, AppKit's `NSTextView` on the Mac, both laid out by TextKit 2 over a text
/// storage.
@MainActor
protocol MarkdownStyledTextView: AnyObject, Sendable {
    /// The characters being edited, with their attributes.
    var styledTextStorage: NSTextStorage { get }
    /// The selection, in the text storage's UTF-16 units.
    var styledSelection: NSRange { get set }
    /// Whether an input method is composing text, which styling would disturb.
    var isComposingText: Bool { get }
    /// The width of the text column, which rendered blocks' views take.
    var renderedBlockColumnWidth: CGFloat { get }
    var typingAttributes: [NSAttributedString.Key: Any] { get set }
}

#if canImport(UIKit)
extension UITextView: MarkdownStyledTextView {
    var styledTextStorage: NSTextStorage { textStorage }
    var styledSelection: NSRange {
        get { selectedRange }
        set { selectedRange = newValue }
    }
    var isComposingText: Bool { markedTextRange != nil }
    var renderedBlockColumnWidth: CGFloat { (self as? MarkdownTextView)?.contentColumnWidth ?? bounds.width }
}
#else
extension NSTextView: MarkdownStyledTextView {
    /// A TextKit 2 text view always has its content storage's text storage; an empty one
    /// stands in otherwise, which styling leaves alone.
    var styledTextStorage: NSTextStorage { textStorage ?? NSTextStorage() }
    var styledSelection: NSRange {
        get { selectedRange() }
        set { setSelectedRange(newValue) }
    }
    var isComposingText: Bool { hasMarkedText() }
    var renderedBlockColumnWidth: CGFloat {
        guard let textContainer else { return 0 }
        return textContainer.size.width - 2 * textContainer.lineFragmentPadding
    }
}
#endif

/// The styling of a note's text as it is edited, the same in the iPad's and the Mac's
/// editors: the text it last styled and the edits since (`LivePreviewTextState`), so each
/// edit restyles only the lines it changed; the markup the selection reveals in Live
/// Preview; and the rendered blocks drawn over concealed source. Each editor says when to
/// style, from its text view's callbacks, and what follows a restyle (`didRestyle`).
@MainActor
final class MarkdownEditorStyling {
    var configuration: EditorConfiguration {
        didSet { if configuration != oldValue { cachedStyler = nil } }
    }
    /// What Live Preview's rendered blocks read; nil in Source mode.
    var environment: LivePreviewEnvironment?
    /// Whether the selection reveals markup and rendered blocks' sources: always on the
    /// Mac, and on the iPad while the note is being edited. A cursor left at the top of a
    /// note only read must not turn its properties back into YAML.
    var revealsMarkupAtSelection = true
    /// When the properties show their YAML; see `PropertiesSourceVisibility`.
    var propertiesSource: PropertiesSourceVisibility
    /// The sections folded away, which hide their lines and blocks (the iPad's folds).
    var foldedRegions: () -> [FoldableRegion] = { [] }
    /// Runs after any restyle, so the editor places its rendered blocks again.
    var didRestyle: (any MarkdownStyledTextView) -> Void = { _ in }

    /// The text last styled and the edits styling has not caught up with, and the rendered
    /// blocks found in it.
    let textState = LivePreviewTextState()
    /// The markup the styling shows as written; see `RevealedMarkup`.
    private(set) var revealedMarkup: RevealedMarkup?
    /// Scanner state at line starts of the text storage, so a restyle scans from the
    /// nearest line before it instead of the note's start.
    let blockContextCheckpoints = MarkdownBlockContextCheckpoints()
    let renderedBlocks: LivePreviewRenderedBlocks
    private var characterEditObserver: NSObjectProtocol?

    init(configuration: EditorConfiguration, propertiesSource: PropertiesSourceVisibility, detachedViewsBudgetMegabytes: Int) {
        self.configuration = configuration
        self.propertiesSource = propertiesSource
        renderedBlocks = LivePreviewRenderedBlocks(detachedViewsBudgetMegabytes: detachedViewsBudgetMegabytes)
    }

    /// Made once per configuration: it was made, its accent color parsed, on every use,
    /// several times for each keystroke and cursor move.
    private var styler: MarkdownTextStyler {
        if let cachedStyler { return cachedStyler }
        #if canImport(UIKit)
        let styler = MarkdownTextStyler(configuration: configuration, accentColor: UIColor.graphiteAccent(hex: configuration.accentHex) ?? .tintColor)
        #else
        let styler = MarkdownTextStyler(configuration: configuration, accentColor: NSColor.graphiteAccent(hex: configuration.accentHex) ?? .controlAccentColor)
        #endif
        cachedStyler = styler
        return styler
    }
    private var cachedStyler: MarkdownTextStyler?

    /// The attributes of plain text, for what is typed next.
    var baseAttributes: [NSAttributedString.Key: Any] { styler.baseAttributes }

    /// Whether Live Preview draws its blocks as views.
    var rendersBlocks: Bool { configuration.mode == .livePreview && environment != nil }
    /// Whether the frontmatter is rendered as properties; without the Properties view it
    /// stays styled source.
    var rendersProperties: Bool { rendersBlocks && environment?.updateProperties != nil }
    /// What decides which blocks are rendered; a change finds the blocks again.
    var renderedBlockPolicy: [String] {
        [String(rendersBlocks), String(rendersProperties), pluginCodeBlockLanguages.sorted().joined(separator: ",")]
    }
    /// Languages community plugins draw in Live Preview; none without the plugin runtime.
    private var pluginCodeBlockLanguages: Set<String> {
        environment?.pluginCodeBlocks == nil ? [] : environment?.pluginCodeBlockLanguages ?? []
    }

    // MARK: Character edits

    /// Follows every change to the characters, whichever path made it (typing, undo and
    /// redo, find and replace, insertions, setting the text), so the lines it changed are
    /// restyled and nothing is styled with ranges from the older text. The text storage
    /// reports a change before the text view's own callbacks run. `settle` runs on the next
    /// turn of the run loop for a change the text view did not report.
    func observeCharacterEdits(in textView: any MarkdownStyledTextView, settle: @escaping @MainActor @Sendable () -> Void) {
        stopObservingCharacterEdits()
        characterEditObserver = NotificationCenter.default.addObserver(forName: NSTextStorage.didProcessEditingNotification,
                                                                       object: textView.styledTextStorage, queue: nil) { [weak self, weak textView] notification in
            guard let textStorage = notification.object as? NSTextStorage, textStorage.editedMask.contains(.editedCharacters) else { return }
            let edit = CharacterEdit(editedRange: textStorage.editedRange, changeInLength: textStorage.changeInLength)
            MainActor.assumeIsolated {
                guard let self, let textView,
                      self.textState.recordCharacterEdit(edit, revealedRange: self.revealedMarkup?.shownLineRange) else { return }
                DispatchQueue.main.async { [weak self, weak textView] in
                    guard let self, let textView, self.textState.cachesDescribeOldText, !textView.isComposingText else { return }
                    settle()
                }
            }
        }
    }

    func stopObservingCharacterEdits() {
        if let characterEditObserver { NotificationCenter.default.removeObserver(characterEditObserver) }
        characterEditObserver = nil
    }

    /// The text as an immutable snapshot: the one last styled while it is current, a fresh
    /// copy otherwise. The text storage's `string` bridges to its live backing store, which
    /// changes with the next edit, so the copy is made explicitly.
    func currentSource(of textView: any MarkdownStyledTextView) -> NSString {
        let textStorage = textView.styledTextStorage
        if !textState.cachesDescribeOldText, textState.source.length == textStorage.length { return textState.source }
        return NSString(string: textStorage.string)
    }

    /// Whether blocks and the revealed markup describe the text on screen, and no input
    /// method is composing, so the text can be styled or acted on.
    func canStyle(_ textView: any MarkdownStyledTextView) -> Bool {
        !textState.cachesDescribeOldText && !textView.isComposingText
    }

    // MARK: Styling

    /// Takes in the text, finding its rendered blocks, or moving them past the edits since.
    /// - Parameter forcesBlockScan: Finds the blocks again, after a change in which are rendered.
    func updateTextState(of textView: any MarkdownStyledTextView, forcesBlockScan: Bool = false) {
        let rendersProperties = rendersProperties
        textState.update(source: currentSource(of: textView), findsBlocks: rendersBlocks, forcesBlockScan: forcesBlockScan,
                         pluginCodeBlockLanguages: pluginCodeBlockLanguages,
                         isRendered: { block in block.kind != .frontmatter || rendersProperties })
        renderedBlocks.forgetHeights(ofBlocksNotIn: textState.blockEntries)
    }

    /// Takes the markup the selection reveals now as the one styled.
    func revealMarkupAtSelection(of textView: any MarkdownStyledTextView) {
        revealedMarkup = markupRevealedBySelection(in: textView)
    }

    /// The markup the selection shows as written.
    private func markupRevealedBySelection(in textView: any MarkdownStyledTextView) -> RevealedMarkup? {
        guard revealsMarkupAtSelection else { return nil }
        let source = currentSource(of: textView)
        let selection = textView.styledSelection
        guard selection.location <= source.length else { return nil }
        return RevealedMarkup(selection: selection, in: source)
    }

    /// Styles the whole note, the waiting edit included, with the markup the selection reveals.
    func restyleEverything(in textView: any MarkdownStyledTextView) {
        // The pending edit is styled with the rest, so its blocks must describe the text.
        if textState.cachesDescribeOldText { updateTextState(of: textView) }
        textState.discardUnstyledEdit()
        revealedMarkup = markupRevealedBySelection(in: textView)
        let textStorage = textView.styledTextStorage
        styler.applyStyles(to: textStorage, editedRange: NSRange(location: 0, length: 0), restyleEverything: true, revealedMarkup: revealedMarkup,
                           concealedBlocks: concealedBlocks(in: textView, restyledRange: NSRange(location: 0, length: textStorage.length)),
                           foldedRegions: foldedRegions(), blockContextCheckpoints: blockContextCheckpoints)
        textView.typingAttributes = styler.baseAttributes
        didRestyle(textView)
    }

    /// Restyles the lines of `range`, with the line on each side and the blocks and folded
    /// sections they touch. The selection stays where it was.
    func restyle(_ range: NSRange, in textView: any MarkdownStyledTextView) {
        let textStorage = textView.styledTextStorage
        guard textStorage.length > 0 else { return }
        let selection = textView.styledSelection
        styler.applyStyles(to: textStorage, editedRange: range, restyleEverything: false, revealedMarkup: revealedMarkup,
                           concealedBlocks: concealedBlocks(in: textView, restyledRange: MarkdownTextStyler.linesRestyled(for: range, in: textStorage.mutableString)),
                           foldedRegions: foldedRegions(), blockContextCheckpoints: blockContextCheckpoints)
        // Set only when styling moved it: setting the selection costs UIKit tens of
        // milliseconds far down a long note.
        if textView.styledSelection != selection { textView.styledSelection = selection }
        textView.typingAttributes = styler.baseAttributes
        didRestyle(textView)
    }

    /// Restyles what the edits since the last styling changed, with the markup the selection
    /// reveals now, and the blocks whose height changed meanwhile. The text state must
    /// describe the text, and no input method compose.
    func restyleUnstyledEdit(in textView: any MarkdownStyledTextView) {
        guard textState.hasUnstyledEdit else { return }
        revealedMarkup = markupRevealedBySelection(in: textView)
        guard let plan = textState.takeRestylePlan(revealedRange: revealedMarkup?.shownLineRange) else { return }
        switch plan {
        case .everything: restyleEverything(in: textView)
        case .ranges(let ranges): for range in ranges { restyle(range, in: textView) }
        }
        restyleBlocksAwaitingRestyle(in: textView)
    }

    /// Restyles the markup that starts or stops showing as the selection moves: the markers
    /// of the inline elements it reaches and leaves, the markers of the lines it moves
    /// between, and the rendered blocks the cursor enters or leaves. Returns whether any
    /// text was restyled. Mid-edit, the new selection arrives before the new text; the edit
    /// restyles the revealed markup once it settles.
    @discardableResult
    func restyleRevealedMarkup(in textView: any MarkdownStyledTextView) -> Bool {
        guard configuration.mode == .livePreview, canStyle(textView), !textState.hasUnstyledEdit else { return false }
        let previousMarkup = revealedMarkup
        let newMarkup = markupRevealedBySelection(in: textView)
        guard newMarkup != previousMarkup else { return false }
        revealedMarkup = newMarkup
        // A block's source shows or hides with the cursor as a unit; properties that follow
        // "Edit Source" do not.
        let blockEntries = textState.blockEntries
        let blocksChangingActivity = rendersBlocks ? LivePreviewBlockActivity.indicesOfBlocksChangingActivity(
            from: previousMarkup?.selection, to: newMarkup?.selection, blockRanges: blockEntries.map(\.range), in: currentSource(of: textView)) : []
        let propertiesFollowCursor = propertiesSource == .whileTheCursorIsInIt
        let restyledBlockIndices = blocksChangingActivity.filter { blockIndex in propertiesFollowCursor || blockEntries[blockIndex].block.kind != .frontmatter }
        for blockIndex in restyledBlockIndices { restyle(blockEntries[blockIndex].range, in: textView) }
        let selection = textView.styledSelection
        let restyledRanges = styler.applyRevealedMarkupChange(to: textView.styledTextStorage, from: previousMarkup, to: newMarkup,
                                                              concealedBlocks: concealedBlocks(in: textView, restyledRange: nil), foldedRegions: foldedRegions(),
                                                              blockContextCheckpoints: blockContextCheckpoints)
        guard !restyledBlockIndices.isEmpty || !restyledRanges.isEmpty else { return false }
        if textView.styledSelection != selection { textView.styledSelection = selection }
        textView.typingAttributes = styler.baseAttributes
        didRestyle(textView)
        return true
    }

    // MARK: Rendered blocks

    /// The blocks whose source is concealed under their views, in note order: every block
    /// the selection is not in (all of them while the selection reveals nothing), none that
    /// a folded section hides, and the properties as `propertiesSource` says.
    func concealedEntries(in textView: any MarkdownStyledTextView) -> [LivePreviewBlockEntry] {
        guard rendersBlocks, !textState.cachesDescribeOldText else { return [] }
        let source = currentSource(of: textView)
        let key = ConcealedEntriesKey(textRevision: textState.revision, sourceLength: source.length,
                                      selection: revealsMarkupAtSelection ? textView.styledSelection : nil,
                                      propertiesSource: propertiesSource, foldedRegions: foldedRegions())
        // Asked for on every frame of a scroll, and by each spelling mark, while none of what
        // it depends on changes; worked out again only when something does.
        if let concealedEntriesCache, concealedEntriesCache.key == key { return concealedEntriesCache.entries }
        let entries = LivePreviewRenderedBlocks.concealedEntries(textState.blockEntries, in: source, selection: key.selection,
                                                                 propertiesSource: propertiesSource, foldedRegions: key.foldedRegions)
        concealedEntriesCache = (key, entries)
        return entries
    }

    /// What the concealed blocks are worked out from.
    private struct ConcealedEntriesKey: Equatable {
        let textRevision: Int
        let sourceLength: Int
        let selection: NSRange?
        let propertiesSource: PropertiesSourceVisibility
        let foldedRegions: [FoldableRegion]
    }

    private var concealedEntriesCache: (key: ConcealedEntriesKey, entries: [LivePreviewBlockEntry])?

    /// - Parameter restyledRange: The lines being restyled, whose blocks' heights are kept
    ///   as the ones the text reserves; nil when the styling leaves the blocks alone.
    private func concealedBlocks(in textView: any MarkdownStyledTextView, restyledRange: NSRange?) -> [ConcealedBlock] {
        renderedBlocks.concealedBlocks(for: concealedEntries(in: textView), columnWidth: textView.renderedBlockColumnWidth, configuration: configuration,
                                       restyledRange: restyledRange)
    }

    /// Reserves the height a block's view measured, restyling the block only when it
    /// differs from what its lines reserve. Styling now would disturb an input method's
    /// composition, and mid-edit the block's range describes older text; the edit restyles
    /// the block once it settles.
    func reserveMeasuredHeight(_ height: CGFloat, forBlockWithKey key: LivePreviewBlockKey, isFrontmatter: Bool, in textView: any MarkdownStyledTextView) {
        guard renderedBlocks.recordMeasuredHeight(height, forBlockWithKey: key, isFrontmatter: isFrontmatter,
                                                  columnWidth: textView.renderedBlockColumnWidth, configuration: configuration) else { return }
        guard canStyle(textView), !textState.hasUnstyledEdit else {
            renderedBlocks.awaitRestyle(ofBlockWithKey: key)
            return
        }
        guard let entry = textState.blockEntries.first(where: { candidate in candidate.key == key }) else { return }
        restyle(entry.range, in: textView)
    }

    /// Applies heights measured while the text could not be styled.
    func restyleBlocksAwaitingRestyle(in textView: any MarkdownStyledTextView) {
        let keys = renderedBlocks.takeKeysAwaitingRestyle()
        guard !keys.isEmpty else { return }
        for entry in textState.blockEntries where keys.contains(entry.key) { restyle(entry.range, in: textView) }
    }

    /// Restyles the blocks a placement pass found reserving another height than the one now
    /// known for them, on the next turn of the run loop: not inside the layout the pass is
    /// part of.
    func restyleLater(_ entries: [LivePreviewBlockEntry], in textView: any MarkdownStyledTextView) {
        guard !entries.isEmpty, !textState.hasUnstyledEdit else { return }
        let keys = Set(entries.map(\.key))
        DispatchQueue.main.async { [weak self, weak textView] in
            guard let self, let textView, self.canStyle(textView), !self.textState.hasUnstyledEdit else { return }
            for entry in self.textState.blockEntries where keys.contains(entry.key) { self.restyle(entry.range, in: textView) }
        }
    }
}

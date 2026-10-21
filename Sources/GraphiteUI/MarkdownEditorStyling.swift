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
    /// The pane's width inside its margins, which a base's view takes.
    var renderedBlockPaneWidth: CGFloat { get }
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
    var renderedBlockPaneWidth: CGFloat { (self as? MarkdownTextView)?.paneContentWidth ?? renderedBlockColumnWidth }
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
    var renderedBlockPaneWidth: CGFloat { (self as? MarkdownMacTextView)?.paneContentWidth ?? renderedBlockColumnWidth }
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
                self?.renderedBlocks.moveBlockEditedInItsView(through: edit)
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
        codeBlockShowingFences = codeBlockTouchedBySelection(in: textView)
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
        case .ranges(let ranges):
            for range in ranges { restyle(range, in: textView) }
            restyleCodeBlockFencesChangingVisibility(in: textView)
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
        codeBlockShowingFences = codeBlockTouchedBySelection(in: textView)
        guard !restyledBlockIndices.isEmpty || !restyledRanges.isEmpty else { return false }
        if textView.styledSelection != selection { textView.styledSelection = selection }
        textView.typingAttributes = styler.baseAttributes
        didRestyle(textView)
        return true
    }

    // MARK: Code block fences

    /// The code block whose fences Live Preview shows, because the selection touches it.
    /// A selection that moves restyles the fences it reaches and leaves itself
    /// (`applyRevealedMarkupChange`); an edit that moves it out of a block, such as Return
    /// at the end of the closing fence, restyles them here.
    private var codeBlockShowingFences: FencedCodeBlock?

    private func codeBlockTouchedBySelection(in textView: any MarkdownStyledTextView) -> FencedCodeBlock? {
        guard configuration.mode == .livePreview, let revealedMarkup else { return nil }
        return styler.fencedCodeBlock(touchedBy: revealedMarkup.selection, in: textView.styledTextStorage, source: currentSource(of: textView),
                                      blockContextCheckpoints: blockContextCheckpoints)
    }

    /// Restyles the fence lines of the code block the selection entered and of the one it
    /// left after an edit.
    private func restyleCodeBlockFencesChangingVisibility(in textView: any MarkdownStyledTextView) {
        guard canStyle(textView) else { return }
        let touchedBlock = codeBlockTouchedBySelection(in: textView)
        guard touchedBlock?.codeStart != codeBlockShowingFences?.codeStart else { return }
        let changedBlocks = [codeBlockShowingFences, touchedBlock].compactMap { block in block }
        codeBlockShowingFences = touchedBlock
        let source = currentSource(of: textView)
        for block in changedBlocks {
            for fenceLine in MarkdownTextStyler.fenceLineRanges(of: block, in: source) { restyle(fenceLine, in: textView) }
        }
    }

    // MARK: Formatting code

    /// The fenced code block the selection is in, with its code when the selection entered
    /// it. Leaving a block whose code changed meanwhile formats it; a block only read,
    /// scrolled or moved through is never rewritten.
    private struct VisitedCodeBlock {
        let block: FencedCodeBlock
        let codeAtEntry: String
    }

    private var visitedCodeBlock: VisitedCodeBlock?

    /// Follows the selection into and out of fenced code. Returns the edit that formats the
    /// block the selection left, or the one it is in when `editingEnded`, when its code
    /// changed while the selection was in it; nil otherwise, and when the code is already
    /// formatted or its language is not formatted.
    func codeFormattingEdit(afterSelectionChangeIn textView: any MarkdownStyledTextView, editingEnded: Bool) -> MarkdownTextEdit? {
        guard configuration.formatsCodeBlocks, canStyle(textView) else {
            if !configuration.formatsCodeBlocks { visitedCodeBlock = nil }
            return nil
        }
        let source = currentSource(of: textView)
        let selection = textView.styledSelection
        guard let visited = visitedCodeBlock else {
            if !editingEnded { visitedCodeBlock = codeBlock(at: selection.location, in: textView, source: source) }
            return nil
        }
        if !editingEnded, visited.block.contains(selection.location, in: source), visited.block.contains(NSMaxRange(selection), in: source) { return nil }
        visitedCodeBlock = nil
        let edit = formattingEdit(of: visited, in: source, selection: selection)
        // Moving straight into another block: it is followed from now, unless the edit
        // above it is about to move it.
        if edit == nil, !editingEnded { visitedCodeBlock = codeBlock(at: selection.location, in: textView, source: source) }
        return edit
    }

    /// The formattable block whose code holds `location`, with its code now.
    private func codeBlock(at location: Int, in textView: any MarkdownStyledTextView, source: NSString) -> VisitedCodeBlock? {
        let textStorage = textView.styledTextStorage
        guard location <= source.length, textStorage.length == source.length else { return nil }
        let lineRange = source.lineRange(for: NSRange(location: location, length: 0))
        // Prose is answered from the block context alone, which the checkpoints keep cheap.
        guard blockContextCheckpoints.blockContext(atLineStart: lineRange.location, in: textStorage, source: source) == .fencedCode else { return nil }
        let codeLine = blockContextCheckpoints.spans(in: textStorage, source: source, range: NSRange(location: lineRange.location, length: 0))
            .first { span in span.style == .codeBlock && span.range.location >= lineRange.location && span.range.location <= NSMaxRange(lineRange) }
        // Quoted code (in a callout) would need its `>` markers kept on every line; it is left alone.
        guard let block = codeLine?.fencedCodeBlock, block.quoteDepth == 0, let language = CodeLanguage.named(block.language),
              CodeFormatter.formats(language) else { return nil }
        return VisitedCodeBlock(block: block, codeAtEntry: source.substring(with: block.codeRange(in: source)))
    }

    private func formattingEdit(of visited: VisitedCodeBlock, in source: NSString, selection: NSRange) -> MarkdownTextEdit? {
        let block = visited.block
        // The block must still start where it was found: the line before its code opens it.
        guard block.codeStart > 0, block.codeStart <= source.length,
              let opening = MarkdownFenceSyntax.opening(source.substring(with: source.lineRange(for: NSRange(location: block.codeStart - 1, length: 0)))
                .trimmingCharacters(in: .whitespacesAndNewlines)), opening.fence == block.fence,
              let language = CodeLanguage.named(block.language) else { return nil }
        let codeRange = block.codeRange(in: source)
        let code = source.substring(with: codeRange)
        guard code != visited.codeAtEntry, let formatted = CodeFormatter.formatted(code, language: language), formatted != code else { return nil }
        let formattedLength = (formatted as NSString).length
        let selectionAfter: NSRange
        if selection.location >= NSMaxRange(codeRange) {
            selectionAfter = NSRange(location: selection.location + formattedLength - codeRange.length, length: selection.length)
        } else if selection.location > codeRange.location {
            // Editing ended inside the block: the cursor stays as near its place as it can.
            selectionAfter = NSRange(location: min(selection.location, codeRange.location + formattedLength), length: 0)
        } else {
            selectionAfter = selection
        }
        return MarkdownTextEdit(range: codeRange, replacement: formatted, selectionAfter: selectionAfter)
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
        renderedBlocks.concealedBlocks(for: concealedEntries(in: textView),
                                       widths: RenderedBlockWidths(column: textView.renderedBlockColumnWidth, pane: textView.renderedBlockPaneWidth),
                                       configuration: configuration,
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

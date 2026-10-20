#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif
import SwiftUI
import GraphiteCore

#if canImport(UIKit)
/// The hosted SwiftUI view drawn over a rendered block's concealed source.
typealias RenderedBlockHost = UIHostingController<AnyView>
/// The text view the rendered blocks' views are placed in.
typealias RenderedBlockTextView = UIView
#else
typealias RenderedBlockHost = RenderedBlockHostingView
typealias RenderedBlockTextView = NSView

/// A rendered block's hosting view, which answers a secondary click with the block's
/// menu: SwiftUI's hosting view does not offer an AppKit view's `menu`.
final class RenderedBlockHostingView: NSHostingView<AnyView> {
    weak var blockMenu: RenderedBlockEditSourceMenu?

    override func menu(for event: NSEvent) -> NSMenu? {
        blockMenu?.makeMenu(at: convert(event.locationInWindow, from: nil), isFlipped: isFlipped, height: bounds.height) ?? super.menu(for: event)
    }
}
#endif

extension RenderedBlockHost {
    /// The view placed in the text view over the block.
    var placedView: RenderedBlockTextView {
        #if canImport(UIKit)
        view
        #else
        self
        #endif
    }

    /// Takes the view out of the text view. On the iPad, whatever inside it has the keyboard
    /// gives it up first: UIKit hands the first responder of a removed view to the view
    /// around it, so the note began editing, its cursor at its start and the properties
    /// showing their YAML, after a drag that started on a property scrolled them away.
    func removeFromTextView() {
        #if canImport(UIKit)
        view.endEditing(true)
        #else
        // As on the iPad: a field inside the view, such as a table cell's editor, ends its
        // editing (writing what was typed) before the view goes.
        if let window = placedView.window, let responder = window.firstResponder as? NSView, responder.isDescendant(of: placedView) {
            window.makeFirstResponder(nil)
        }
        #endif
        placedView.removeFromSuperview()
    }

    /// A host whose frame comes from the text's layout, not from its content.
    /// A block's view takes no part in the window's safe areas, which it moves through on
    /// every frame of a scroll.
    static func makeRenderedBlockHost(root: RenderedBlockRoot) -> RenderedBlockHost {
        let menu = RenderedBlockEditSourceMenu(revealSource: root.revealSource)
        let rootView = AnyView(root.view.environment(\.renderedBlockMenuContext, menu.context))
        #if canImport(UIKit)
        let host = UIHostingController(rootView: rootView)
        host.view.backgroundColor = .clear
        host.sizingOptions = []
        host.safeAreaRegions = []
        #else
        let host = RenderedBlockHostingView(rootView: rootView)
        host.sizingOptions = []
        host.safeAreaRegions = []
        #endif
        menu.install(on: host.placedView)
        objc_setAssociatedObject(host, &RenderedBlockEditSourceMenu.associationKey, menu, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return host
    }

    /// Shows another state of the block, as after an edit or a change of appearance.
    func update(root: RenderedBlockRoot) {
        guard let menu = objc_getAssociatedObject(self, &RenderedBlockEditSourceMenu.associationKey) as? RenderedBlockEditSourceMenu else {
            rootView = root.view
            return
        }
        // The same context as before, so what the view put in it stays.
        rootView = AnyView(root.view.environment(\.renderedBlockMenuContext, menu.context))
        menu.revealSource = root.revealSource
    }
}

/// When the note's properties show their YAML instead of their view.
enum PropertiesSourceVisibility: Equatable {
    /// While the cursor is in the YAML, as any rendered block's source shows.
    case whileTheCursorIsInIt
    /// Only after the view's "Edit Source" set `isShown`, until the cursor leaves the
    /// YAML, as Obsidian keeps the properties above the note.
    case afterEditSource(isShown: Bool)
}

/// Where a text view's column is, which rendered blocks' views take.
struct RenderedBlockColumn: Equatable {
    /// The column's left edge in the text view, past the text container's padding.
    let minX: CGFloat
    /// The text container's top in the text view, which layout fragments are measured from.
    let textContainerTop: CGFloat
    let width: CGFloat
}

/// What a placement pass found in the viewport.
struct RenderedBlockPlacement {
    /// Blocks in the viewport, placed or waiting for TextKit to lay their lines out.
    var keysInUse = Set<LivePreviewBlockKey>()
    /// Blocks in the viewport whose fragment TextKit has not laid out since a restyle
    /// replaced it; their views stay where they are until it has.
    var keysAwaitingLayout = Set<LivePreviewBlockKey>()
    /// Blocks whose lines reserve another height than the one now known for them, as one
    /// measured at a new width or by another editor.
    var entriesToRestyle: [LivePreviewBlockEntry] = []
    var didMoveView = false
    /// Whether a concealed block in the viewport's characters got no view.
    var isMissingBlock = false
}

/// Live Preview's rendered blocks, for the editor on every platform: the views drawn over
/// the concealed source of tables, math, callouts, embeds, bases and the note's properties,
/// and the heights their lines reserve in the text. TextKit 2 lays out the viewport on the
/// iPad and the Mac alike, so the views are placed from the same layout fragments; only
/// the moment a pass runs is the platform's.
@MainActor
final class LivePreviewRenderedBlocks {
    /// Heights the views of every editor measured, so a note opened again reserves its
    /// blocks' heights at once instead of correcting estimates with visible jumps.
    private static var measuredHeights = MeasuredBlockHeightCache(capacity: 2_000)
    /// The heights the views reported in this editor, by block; and the properties view's
    /// last one, which holds across edits that give the frontmatter a new key.
    private var reportedHeights: [LivePreviewBlockKey: CGFloat] = [:]
    private var reportedPropertiesHeight: CGFloat?
    /// Estimates, kept with the width they were made for: counting a table's lines for
    /// each placement pass would cost every scroll. A note styled before its text view has
    /// a width estimates again once it has one.
    private var estimatedHeights: [LivePreviewBlockKey: (columnWidth: CGFloat, height: CGFloat)] = [:]
    /// The heights the concealed blocks reserve in the text now, which their views are given.
    private var heightsKeptInText: [LivePreviewBlockKey: CGFloat] = [:]
    /// Blocks whose measured height changed while the text could not be styled.
    private var keysAwaitingRestyle: Set<LivePreviewBlockKey> = []

    /// The views on screen, by block, and those taken off screen, kept so a block that
    /// scrolls back into view, or that the cursor leaves, shows again without being built
    /// again.
    private var hosts: [LivePreviewBlockKey: RenderedBlockHost] = [:]
    private var detachedHosts: DetachedWidgetPool<RenderedBlockHost>
    /// The note's properties keep one view while they are edited, so a field being typed
    /// in keeps its state when the frontmatter's key changes; and the key it was built for.
    private var propertiesHost: RenderedBlockHost?
    private var propertiesHostBlockKey: LivePreviewBlockKey?
    /// The environment and appearance the views were last given.
    private var signature: LivePreviewWidgetSignature?
    /// A table whose own view is editing it: its key, where it starts in the note (moved
    /// through every edit before it), and the editor editing it. Each edit gives the table a
    /// new key, and its view, its measured height and the cell being typed in pass to the
    /// table found at the same place, as the properties keep their view.
    private(set) var blockEditedInItsView: (key: LivePreviewBlockKey, location: Int, owner: ObjectIdentifier)?
    /// Views that passed to a new key and have not yet been given that block's root view.
    private var keysAwaitingRootView: Set<LivePreviewBlockKey> = []

    init(detachedViewsBudgetMegabytes: Int) {
        detachedHosts = DetachedWidgetPool(budgetMegabytes: detachedViewsBudgetMegabytes)
    }

    // MARK: Concealment

    /// The blocks whose source is concealed under their views, in note order: those the
    /// selection is not in, while `selection` is set (nil while the note is only read), and
    /// that no folded section hides; the properties as `propertiesSource` says.
    static func concealedEntries(_ entries: [LivePreviewBlockEntry], in source: NSString, selection: NSRange?,
                                 propertiesSource: PropertiesSourceVisibility, foldedRegions: [FoldableRegion] = []) -> [LivePreviewBlockEntry] {
        entries.filter { entry in
            // A block that runs past the text is stale; styling it would raise.
            guard NSMaxRange(entry.range) <= source.length else { return false }
            guard foldedRegions.isEmpty || NoteFolding.regions(hiding: entry.range.location, in: foldedRegions).isEmpty else { return false }
            if entry.block.kind == .frontmatter, case .afterEditSource(let isShown) = propertiesSource {
                return entry.range.location == 0 && !isShown
            }
            guard let selection else { return true }
            return !LivePreviewBlockActivity.isActive(blockRange: entry.range, selection: selection, in: source)
        }
    }

    /// The concealed blocks as the styler takes them, each with the height its lines
    /// reserve. Those in `restyledRange`, the lines being styled, record that height as
    /// the one kept in the text; nil when the styling leaves the blocks alone.
    func concealedBlocks(for concealedEntries: [LivePreviewBlockEntry], columnWidth: CGFloat, configuration: EditorConfiguration,
                         restyledRange: NSRange?) -> [ConcealedBlock] {
        concealedEntries.map { entry in
            let height = reservedHeight(of: entry, columnWidth: columnWidth, configuration: configuration)
            if let restyledRange, NSIntersectionRange(entry.range, restyledRange).length > 0 || NSLocationInRange(restyledRange.location, entry.range) {
                heightsKeptInText[entry.key] = height
            }
            return ConcealedBlock(range: entry.range, reservedHeight: height)
        }
    }

    // MARK: Heights

    /// The height a block's lines reserve: the one its view last reported in this editor,
    /// else one measured at this width by any editor, else, for the properties, the height
    /// their view last had (each edit gives them a new key, and their height rarely
    /// changes), else an estimate. The view corrects the last two when it reports.
    func reservedHeight(of entry: LivePreviewBlockEntry, columnWidth: CGFloat, configuration: EditorConfiguration) -> CGFloat {
        adoptBlockEditedInItsView(entry)
        if let reportedHeight = reportedHeights[entry.key] { return reportedHeight }
        if let key = Self.measuredHeightKey(for: entry.key, columnWidth: columnWidth, configuration: configuration),
           let measuredHeight = Self.measuredHeights.height(for: key) {
            return measuredHeight
        }
        if entry.block.kind == .frontmatter, let reportedPropertiesHeight { return reportedPropertiesHeight }
        if let estimate = estimatedHeights[entry.key], estimate.columnWidth == columnWidth { return estimate.height }
        let estimatedHeight = LivePreviewBlockHeightEstimate.height(of: entry.block, columnWidth: columnWidth)
        estimatedHeights[entry.key] = (columnWidth, estimatedHeight)
        return estimatedHeight
    }

    private static func measuredHeightKey(for blockKey: LivePreviewBlockKey, columnWidth: CGFloat, configuration: EditorConfiguration) -> MeasuredBlockHeightCache.Key? {
        MeasuredBlockHeightCache.Key(blockKey: blockKey, columnWidth: columnWidth, textSize: configuration.textSize,
                                     typography: configuration.typography, themeFingerprint: configuration.theme?.tokens.fingerprint ?? "")
    }

    /// Records the height a block's view measured, and tells whether the block's lines must
    /// be restyled to reserve it: whether it differs from the height they reserve now.
    /// - Parameter columnWidth: The column's width, for a view not yet laid out; a view's
    ///   own width is the one it measured at, which can lag the column's.
    func recordMeasuredHeight(_ height: CGFloat, forBlockWithKey key: LivePreviewBlockKey, isFrontmatter: Bool, columnWidth: CGFloat,
                              configuration: EditorConfiguration) -> Bool {
        guard height > 1 else { return false }
        let measuredWidth = (isFrontmatter ? propertiesHost : hosts[key])?.placedView.bounds.width ?? columnWidth
        if let measuredKey = Self.measuredHeightKey(for: key, columnWidth: measuredWidth, configuration: configuration) {
            Self.measuredHeights.record(height, for: measuredKey)
        }
        if isFrontmatter { reportedPropertiesHeight = height }
        // Within a point of what the text reserves, the reserved height is kept, so the
        // block is not restyled for a rounding.
        if let styledHeight = heightsKeptInText[key] ?? reportedHeights[key], abs(styledHeight - height) <= 1 {
            reportedHeights[key] = styledHeight
            return false
        }
        reportedHeights[key] = height
        return true
    }

    /// Remembers a block to restyle once the text can be styled: during an input method's
    /// composition, or while the blocks describe the text before an edit.
    func awaitRestyle(ofBlockWithKey key: LivePreviewBlockKey) {
        keysAwaitingRestyle.insert(key)
    }

    /// The blocks whose height changed while the text could not be styled, forgotten here.
    func takeKeysAwaitingRestyle() -> Set<LivePreviewBlockKey> {
        defer { keysAwaitingRestyle.removeAll() }
        return keysAwaitingRestyle
    }

    /// Whether a block with a view on screen that starts before `location` has not reported
    /// its height in this editor yet, as a base still loading its rows: the text above
    /// `location` will still change its height. The entries are in note order.
    func hasPlacedBlockAwaitingHeight(before location: Int, in entries: [LivePreviewBlockEntry]) -> Bool {
        entries.lazy.prefix { entry in entry.range.location < location }.contains { entry in
            hosts[entry.key] != nil && reportedHeights[entry.key] == nil
        }
    }

    /// Heights are kept by content, so every edited version of a measured block leaves one
    /// behind; they are forgotten once they clearly outnumber the blocks in the note.
    func forgetHeights(ofBlocksNotIn entries: [LivePreviewBlockEntry]) {
        guard reportedHeights.count + estimatedHeights.count > 4 * entries.count + 64 else { return }
        let keysInNote = Set(entries.map(\.key))
        reportedHeights = reportedHeights.filter { key, _ in keysInNote.contains(key) }
        estimatedHeights = estimatedHeights.filter { key, _ in keysInNote.contains(key) }
        heightsKeptInText = heightsKeptInText.filter { key, _ in keysInNote.contains(key) }
        keysAwaitingRestyle.formIntersection(keysInNote)
    }

    // MARK: Editing in a block's view

    /// Keeps a table's view across the edits its view makes, until its editor, `owner`, ends.
    func beginEditingInView(blockWithKey key: LivePreviewBlockKey, at location: Int, owner: ObjectIdentifier) {
        editingInViewGeneration += 1
        blockEditedInItsView = (key, location, owner)
    }

    /// Stops keeping the view a moment later: the edit written as editing ended gives the
    /// block a new key only once the note is styled again, and its view must pass to it.
    /// Only the editor that began keeps the view: one table's editor ending as a tap moves
    /// editing to another table must not let the other table's view go. Editing begun again
    /// meanwhile keeps it.
    func endEditingInView(owner: ObjectIdentifier) {
        guard blockEditedInItsView?.owner == owner else { return }
        let generation = editingInViewGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.editingInViewReleaseDelay) { [weak self] in
            guard let self, self.editingInViewGeneration == generation, self.blockEditedInItsView?.owner == owner else { return }
            self.blockEditedInItsView = nil
        }
    }

    /// Moves the edited table's start through a character edit: an edit before it shifts it,
    /// one at or after its start (the table's own cells) leaves it. An edit over its start
    /// leaves it where that edit begins.
    func moveBlockEditedInItsView(through edit: CharacterEdit) {
        guard let edited = blockEditedInItsView else { return }
        let replacedRange = edit.replacedRange
        guard replacedRange.location < edited.location else { return }
        let location = NSMaxRange(replacedRange) <= edited.location ? edited.location + edit.changeInLength : replacedRange.location
        blockEditedInItsView = (edited.key, location, edited.owner)
    }

    private var editingInViewGeneration = 0
    private static let editingInViewReleaseDelay: TimeInterval = 0.5

    /// The table `owner` is editing, among `entries`: the table at its place first, since an
    /// edit gives it a new key and an identical table can then have the key it had; else by
    /// its key.
    func entryEditedInItsView(by owner: ObjectIdentifier, in entries: [LivePreviewBlockEntry]) -> LivePreviewBlockEntry? {
        guard let edited = blockEditedInItsView, edited.owner == owner else { return nil }
        return entries.first { entry in entry.range.location == edited.location && entry.block.kind == .table }
            ?? entries.first { entry in entry.key == edited.key }
    }

    /// The source range of the block a view edits: while `editor` edits it, the table at the
    /// place kept for it (an identical table can have the key an edit replaced), found again
    /// in `source` when the blocks no longer list it, as when they are let go for Source mode
    /// and the editor writes its last draft; otherwise the block with `key`. Nil when neither
    /// is in the note.
    func rangeOfBlock(withKey key: LivePreviewBlockKey, editedBy editor: ObjectIdentifier, in entries: [LivePreviewBlockEntry], source: NSString) -> NSRange? {
        let range: NSRange?
        if let location = locationEditedInItsView(by: editor) {
            range = entryEditedInItsView(by: editor, in: entries)?.range
                ?? LivePreviewBlockScanner.blocks(in: source).first { block in block.kind == .table && block.range.location == location }?.range
        } else {
            range = entries.first { entry in entry.key == key }?.range
        }
        guard let range, NSMaxRange(range) <= source.length else { return nil }
        return range
    }

    /// Where the table `owner` is editing starts, while it keeps its view.
    func locationEditedInItsView(by owner: ObjectIdentifier) -> Int? {
        guard let edited = blockEditedInItsView, edited.owner == owner else { return nil }
        return edited.location
    }

    /// Gives the table at the edited block's place the view and heights its last key had:
    /// the edit came from that view, which must not be built again (it would lose the cell
    /// being typed in) or jump to an estimated height.
    private func adoptBlockEditedInItsView(_ entry: LivePreviewBlockEntry) {
        guard let edited = blockEditedInItsView, edited.key != entry.key, edited.location == entry.range.location,
              entry.block.kind == .table else { return }
        blockEditedInItsView = (entry.key, edited.location, edited.owner)
        if let height = reportedHeights.removeValue(forKey: edited.key) { reportedHeights[entry.key] = height }
        if let height = heightsKeptInText[edited.key] { heightsKeptInText[entry.key] = height }
        if let host = hosts.removeValue(forKey: edited.key) ?? detachedHosts.take(edited.key) {
            hosts[entry.key] = host
            keysAwaitingRootView.insert(entry.key)
        }
    }

    // MARK: Placement

    /// Places the views of the concealed blocks TextKit has laid out for the viewport, over
    /// each block's first line. Only fragments laid out for the viewport are used: their
    /// frames say where the text on screen is drawn, and forcing layout elsewhere would
    /// move the estimated positions of the visible text. A hidden line is a hundredth of a
    /// point tall, so any of a block's lines starts where the block does, also for a block
    /// that begins above the viewport. Views of blocks not placed stay until
    /// `detachViews(except:entries:)`. Nil when TextKit has no viewport to place on yet.
    func placeViews(of concealedEntries: [LivePreviewBlockEntry], in textView: RenderedBlockTextView, textLayoutManager: NSTextLayoutManager,
                    column: RenderedBlockColumn, configuration: EditorConfiguration,
                    makeRootView: (LivePreviewBlockEntry) -> RenderedBlockRoot) -> RenderedBlockPlacement? {
        guard let viewportRange = textLayoutManager.textViewportLayoutController.viewportRange,
              let contentManager = textLayoutManager.textContentManager else { return nil }
        var placement = RenderedBlockPlacement()
        let documentStart = contentManager.documentRange.location
        textLayoutManager.enumerateTextLayoutFragments(from: viewportRange.location, options: []) { fragment in
            // A fragment from the viewport's end on is not laid out with it; rendered
            // blocks there appear as it scrolls.
            guard fragment.rangeInElement.location.compare(viewportRange.endLocation) == .orderedAscending else { return false }
            let fragmentStart = contentManager.offset(from: documentStart, to: fragment.rangeInElement.location)
            guard let index = LivePreviewBlockLookup.index(ofElementContaining: fragmentStart, in: concealedEntries, range: { entry in entry.range }) else { return true }
            let entry = concealedEntries[index]
            guard !placement.keysInUse.contains(entry.key) else { return true }
            placement.keysInUse.insert(entry.key)
            // A paragraph a restyle changed has a new fragment, without a frame until
            // TextKit lays out the viewport again.
            guard fragment.state == .layoutAvailable else {
                placement.keysAwaitingLayout.insert(entry.key)
                return true
            }
            let reservedHeight = reservedHeight(of: entry, columnWidth: column.width, configuration: configuration)
            if let keptHeight = heightsKeptInText[entry.key], abs(keptHeight - reservedHeight) > 1 { placement.entriesToRestyle.append(entry) }
            // The view takes the height its lines reserve now, so it covers them exactly.
            let frame = CGRect(x: column.minX, y: fragment.layoutFragmentFrame.minY + column.textContainerTop,
                               width: column.width, height: heightsKeptInText[entry.key] ?? reservedHeight)
            let placedView = host(for: entry, makeRootView: makeRootView).placedView
            if placedView.frame != frame {
                placedView.frame = frame
                placement.didMoveView = true
            }
            if placedView.superview !== textView { textView.addSubview(placedView) }
            return true
        }
        let viewportStart = contentManager.offset(from: documentStart, to: viewportRange.location)
        let viewportEnd = contentManager.offset(from: documentStart, to: viewportRange.endLocation)
        let viewportCharacters = NSRange(location: viewportStart, length: max(0, viewportEnd - viewportStart))
        placement.isMissingBlock = !placement.keysAwaitingLayout.isEmpty || concealedEntries.contains { entry in
            NSIntersectionRange(entry.range, viewportCharacters).length > 0 && !placement.keysInUse.contains(entry.key)
        }
        return placement
    }

    // MARK: Views

    var hasViews: Bool { !hosts.isEmpty || propertiesHost != nil || !detachedHosts.isEmpty }

    /// The view for a block on screen, else the one kept since it was last on screen, else
    /// a new one. The properties keep one view as they are edited.
    private func host(for entry: LivePreviewBlockEntry, makeRootView: (LivePreviewBlockEntry) -> RenderedBlockRoot) -> RenderedBlockHost {
        if entry.block.kind == .frontmatter {
            let host = propertiesHost ?? RenderedBlockHost.makeRenderedBlockHost(root: makeRootView(entry))
            if propertiesHost == nil {
                propertiesHost = host
            } else if propertiesHostBlockKey != entry.key {
                host.update(root: makeRootView(entry))
            }
            propertiesHostBlockKey = entry.key
            return host
        }
        adoptBlockEditedInItsView(entry)
        if let host = hosts[entry.key] {
            if keysAwaitingRootView.remove(entry.key) != nil { host.update(root: makeRootView(entry)) }
            return host
        }
        let host = detachedHosts.take(entry.key) ?? RenderedBlockHost.makeRenderedBlockHost(root: makeRootView(entry))
        hosts[entry.key] = host
        return host
    }

    /// Takes off screen the views of blocks not in `keysInUse`, keeping those that can
    /// scroll back into view or that the cursor can leave, within the pool's memory budget.
    /// The properties' view stays while the frontmatter is in use, though its key changes
    /// with each edit, so it is not taken away for a frame and put back.
    func detachViews(except keysInUse: Set<LivePreviewBlockKey>, entries: [LivePreviewBlockEntry]) {
        if !entries.contains(where: { entry in entry.block.kind == .frontmatter && keysInUse.contains(entry.key) }) {
            propertiesHost?.removeFromTextView()
        }
        // Looked up by key: searching every block for each view leaving the screen was slow
        // for a note of many blocks.
        // The view editing its block stays while that edit gives the block a new key.
        let leavingKeys = hosts.keys.filter { key in !keysInUse.contains(key) && key != blockEditedInItsView?.key }
        guard !leavingKeys.isEmpty else { return }
        var entriesByKey: [LivePreviewBlockKey: LivePreviewBlockEntry] = [:]
        for entry in entries where entriesByKey[entry.key] == nil { entriesByKey[entry.key] = entry }
        for key in leavingKeys {
            guard let host = hosts[key] else { continue }
            host.removeFromTextView()
            hosts[key] = nil
            if let entry = entriesByKey[key],
               let estimatedMegabytes = DetachedWidgetPool<RenderedBlockHost>.estimatedMegabytes(of: entry.block) {
                detachedHosts.keep(host, for: key, estimatedMegabytes: estimatedMegabytes)
            }
        }
    }

    func removeAllViews() {
        propertiesHost?.removeFromTextView()
        // Removing a table's view ends its cell editor, which writes its draft into the note
        // first, finding the table at the place still kept for it.
        for host in hosts.values { host.removeFromTextView() }
        blockEditedInItsView = nil
        keysAwaitingRootView.removeAll()
        hosts.removeAll()
        detachedHosts.removeAll()
    }

    /// Lets go of the views kept off screen, as when the system runs low on memory.
    func dropDetachedViews() {
        detachedHosts.removeAll()
    }

    /// Gives the views the environment and appearance `signature` describes, in place,
    /// keeping their own state (a base's chosen view, a property being typed in); only
    /// those that read the index when nothing else changed. Returns whether it changed.
    func refreshViews(for signature: LivePreviewWidgetSignature, entries: [LivePreviewBlockEntry], makeRootView: (LivePreviewBlockEntry) -> RenderedBlockRoot) -> Bool {
        guard signature != self.signature else { return false }
        let changesOnlyIndex = self.signature?.appearance == signature.appearance && self.signature?.drawingVersion == signature.drawingVersion
        self.signature = signature
        refreshViews(entries: entries, onlyThoseReadingIndex: changesOnlyIndex, makeRootView: makeRootView)
        return true
    }

    /// Gives the views on screen, and those kept off screen, new root views. Kept views of
    /// blocks no longer in the note are dropped, so none shows again with an older environment.
    func refreshViews(entries: [LivePreviewBlockEntry], onlyThoseReadingIndex: Bool = false, makeRootView: (LivePreviewBlockEntry) -> RenderedBlockRoot) {
        guard hasViews else { return }
        detachedHosts.removeHosts(notIn: Set(entries.map(\.key)))
        for entry in entries where !onlyThoseReadingIndex || LivePreviewWidgetSignature.readsIndex(entry.block) {
            if entry.block.kind == .frontmatter {
                guard let propertiesHost else { continue }
                propertiesHost.update(root: makeRootView(entry))
                propertiesHostBlockKey = entry.key
            } else if let host = hosts[entry.key] ?? detachedHosts.host(for: entry.key) {
                host.update(root: makeRootView(entry))
            }
        }
    }

    /// A block's view, with the vault's fonts, theme and accent passed in: a hosted view
    /// does not inherit SwiftUI's environment from the editor. A view is kept while its
    /// block moves with edits elsewhere, so its actions find the block by key when they run.
    /// - Parameter colorScheme: Passed where the hosted view does not take the appearance
    ///   from the text view it is in, as on the iPad.
    /// - Parameter sourceEditing: How a table's view edits its cells in the note; nil leaves
    ///   the table to be edited as source.
    static func rootView(for entry: LivePreviewBlockEntry, environment: LivePreviewEnvironment, accentHex: String, colorScheme: ColorScheme?,
                         revealSource: @escaping () -> Void, reportHeight: @escaping (CGFloat) -> Void,
                         sourceEditing: RenderedBlockSourceEditing? = nil) -> RenderedBlockRoot {
        let accent = Color.graphiteAccent(hex: accentHex) ?? .accentColor
        let widget = LivePreviewWidgetView(block: entry.block, environment: environment, revealSource: revealSource, reportHeight: reportHeight,
                                           sourceEditing: entry.block.kind == .table ? sourceEditing : nil)
            .environment(\.lassoNoteDestination, environment.lassoNoteDestination)
            .environment(\.noteTypography, environment.typography)
            .environment(\.noteTheme, environment.theme)
            .environment(\.codeColorTheme, environment.codeColorTheme)
            .tint(accent)
            .environment(\.accent, accent)
        guard let colorScheme else { return RenderedBlockRoot(view: AnyView(widget), revealSource: revealSource) }
        return RenderedBlockRoot(view: AnyView(widget.environment(\.colorScheme, colorScheme)), revealSource: revealSource)
    }
}

/// A rendered block's view, and how it shows the block's source, for its "Edit Source" menu.
struct RenderedBlockRoot {
    let view: AnyView
    let revealSource: () -> Void
}

/// An item a rendered block's view adds to its menu, above "Edit Source".
struct RenderedBlockMenuItem {
    let title: String
    var symbolName: String? = nil
    var isEnabled = true
    /// Shown as a submenu when not empty.
    var children: [RenderedBlockMenuItem] = []
    var action: (() -> Void)? = nil
}

/// What a block's view adds to its menu, for the point the menu opens at, in the view's
/// coordinates. Each block view's menu keeps one and gives it to the view through the
/// environment, so the view fills it in once and it stays across new root views.
@MainActor
final class RenderedBlockMenuContext {
    var itemsAtPoint: ((CGPoint) -> [RenderedBlockMenuItem])?
}

extension EnvironmentValues {
    @Entry var renderedBlockMenuContext: RenderedBlockMenuContext? = nil
}

/// A rendered block's menu (a long press on the iPad, a secondary click on the Mac), on the
/// block's view itself: what the view adds for the point, such as a table's row and column
/// commands, then "Edit Source". SwiftUI's context menu worked out its menu, symbol image
/// included, every time the block's view was drawn, which on the iPad was a large part of
/// every frame of a scroll; this menu is made when it opens.
@MainActor
final class RenderedBlockEditSourceMenu: NSObject {
    nonisolated(unsafe) static var associationKey: UInt8 = 0
    static let title = "Edit Source"
    static let symbolName = "chevron.left.forwardslash.chevron.right"
    var revealSource: () -> Void
    let context = RenderedBlockMenuContext()

    init(revealSource: @escaping () -> Void) {
        self.revealSource = revealSource
    }

    #if canImport(UIKit)
    func install(on view: UIView) {
        view.addInteraction(UIContextMenuInteraction(delegate: self))
    }
    #else
    func install(on view: NSView) {
        if let hostingView = view as? RenderedBlockHostingView {
            hostingView.blockMenu = self
        } else {
            view.menu = makeMenu(at: nil)
        }
    }

    /// - Parameter point: Where the menu opens, in the view; nil for the menu without the
    ///   view's own items. AppKit measures from the bottom of a view that is not flipped.
    func makeMenu(at point: CGPoint?, isFlipped: Bool = true, height: CGFloat = 0) -> NSMenu {
        let menu = NSMenu()
        // Items say themselves whether they can be chosen (a header row cannot be deleted).
        menu.autoenablesItems = false
        if let point, let itemsAtPoint = context.itemsAtPoint {
            let topDownPoint = isFlipped ? point : CGPoint(x: point.x, y: height - point.y)
            let items = itemsAtPoint(topDownPoint)
            for item in items { menu.addItem(menuItem(for: item)) }
            if !items.isEmpty { menu.addItem(.separator()) }
        }
        menu.addItem(menuItem(for: RenderedBlockMenuItem(title: Self.title, symbolName: Self.symbolName, action: { [weak self] in self?.revealSource() })))
        return menu
    }

    private func menuItem(for item: RenderedBlockMenuItem) -> NSMenuItem {
        let nativeItem = NSMenuItem(title: item.title, action: nil, keyEquivalent: "")
        if item.children.isEmpty, let action = item.action {
            // The item's target is weak; the item keeps it as its represented object.
            let target = RenderedBlockMenuAction(action)
            nativeItem.target = target
            nativeItem.action = #selector(RenderedBlockMenuAction.performAction)
            nativeItem.representedObject = target
        }
        nativeItem.isEnabled = item.isEnabled
        if let symbolName = item.symbolName { nativeItem.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) }
        if !item.children.isEmpty {
            let submenu = NSMenu(title: item.title)
            submenu.autoenablesItems = false
            for child in item.children { submenu.addItem(menuItem(for: child)) }
            nativeItem.submenu = submenu
        }
        return nativeItem
    }

    #endif
}

#if canImport(AppKit) && !canImport(UIKit)
/// A menu item's action, kept by the item: AppKit menu items take a selector, not a closure.
private final class RenderedBlockMenuAction: NSObject {
    let action: () -> Void
    init(_ action: @escaping () -> Void) { self.action = action }
    @objc func performAction() { action() }
}
#endif

#if canImport(UIKit)
extension RenderedBlockEditSourceMenu: UIContextMenuInteractionDelegate {
    func contextMenuInteraction(_ interaction: UIContextMenuInteraction, configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {
        UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in self?.makeMenu(at: location) }
    }

    func makeMenu(at point: CGPoint? = nil) -> UIMenu {
        let viewItems = point.flatMap { point in context.itemsAtPoint?(point) } ?? []
        let editSource = UIAction(title: Self.title, image: UIImage(systemName: Self.symbolName)) { [weak self] _ in self?.revealSource() }
        guard !viewItems.isEmpty else { return UIMenu(children: [editSource]) }
        return UIMenu(children: [UIMenu(options: .displayInline, children: viewItems.map(Self.menuElement(for:))), editSource])
    }

    private static func menuElement(for item: RenderedBlockMenuItem) -> UIMenuElement {
        let image = item.symbolName.flatMap { symbolName in UIImage(systemName: symbolName) }
        if !item.children.isEmpty { return UIMenu(title: item.title, image: image, children: item.children.map(menuElement(for:))) }
        let action = item.action
        return UIAction(title: item.title, image: image, attributes: item.isEnabled ? [] : .disabled) { _ in action?() }
    }
}
#endif

/// What Live Preview's rendered blocks show besides their source, in two parts: the
/// appearance and settings every block shows, and the index state that only some blocks
/// read. A save changes the index state, so after each pause in typing only the blocks
/// that read it are given the new state; the others keep their views untouched.
struct LivePreviewWidgetSignature: Equatable {
    let appearance: String
    let index: String
    /// Changes when a file the vault shows changes, such as a drawing saved; every block
    /// that shows a file looks it up again.
    let drawingVersion: Int

    /// `notePath` is where the blocks' links are followed from; the note can be renamed.
    init(environment: LivePreviewEnvironment?, accentHex: String, notePath: String) {
        guard let environment else {
            appearance = ""
            index = ""
            drawingVersion = 0
            return
        }
        drawingVersion = environment.drawingVersion
        let palette = environment.paletteHexByName.sorted { leftEntry, rightEntry in leftEntry.key < rightEntry.key }
            .map { entry in "\(entry.key)=\(entry.value)" }.joined(separator: ",")
        let declaredPropertyTypes = environment.declaredPropertyTypes.sorted { leftEntry, rightEntry in leftEntry.key < rightEntry.key }
            .map { entry in "\(entry.key)=\(entry.value.rawValue)" }.joined(separator: ",")
        appearance = [String(environment.textSize), String(describing: environment.typography), environment.theme?.tokens.fingerprint ?? "", String(environment.colorsEnabled), palette, accentHex,
                      String(environment.updateProperties != nil), declaredPropertyTypes, notePath].joined(separator: "|")
        index = [String(environment.indexVersion), String(environment.baseContext?.isIndexComplete ?? false)].joined(separator: "|")
    }

    /// Whether a block's view reads the index: a base runs its query again, an embed not
    /// found yet looks for its file again, and a callout can contain either. The index
    /// changes with every save, so a callout of text only was drawn again each time typing
    /// paused.
    static func readsIndex(_ block: LivePreviewBlock) -> Bool {
        switch block.kind {
        case .embed, .baseDefinition: true
        case .callout: block.markdown.contains("![") || block.markdown.contains("base")
        case .frontmatter, .table, .mathBlock, .horizontalRule, .pluginCodeBlock: false
        }
    }
}

/// Rendered-block views taken off screen, kept so a block that scrolls back into view, or
/// that the cursor leaves, shows again without being built again: building a table's view
/// takes tens of milliseconds. Memory bounds the pool, estimated per view from its block's
/// kind; the views taken off longest ago go first once the estimate passes the budget.
struct DetachedWidgetPool<Host> {
    private var hostsByKey: [LivePreviewBlockKey: (host: Host, estimatedMegabytes: Double, sequence: Int)] = [:]
    /// The views kept, in the order they were taken off screen, oldest first. Taking a
    /// view back leaves its entry here, matched by sequence number, so keeping and taking
    /// cost the same however many views are kept: removing from the list each time grew
    /// with the pool, which now holds many more views.
    private var detachmentOrder: [(key: LivePreviewBlockKey, sequence: Int)] = []
    private var detachmentOrderStart = 0
    private var nextSequence = 0
    private var estimatedMegabytesInPool: Double = 0
    let budgetMegabytes: Int

    init(budgetMegabytes: Int) {
        self.budgetMegabytes = budgetMegabytes
    }

    var isEmpty: Bool { hostsByKey.isEmpty }
    var keys: [LivePreviewBlockKey] {
        detachmentOrder[detachmentOrderStart...].filter { kept in hostsByKey[kept.key]?.sequence == kept.sequence }.map(\.key)
    }

    /// A view's estimated memory, from measured views: a 12-by-4 table about 6 MB,
    /// properties about 4 MB, a callout or math block under 1 MB; an embed can hold a
    /// decoded image. Nil for audio and video, which are never kept: a player kept off
    /// screen could go on playing.
    ///
    /// Tables, callouts and formulas are estimated from their size: every table counted as
    /// large as that 12-by-4 one, so a note of small tables kept a few sections' views and
    /// built every other one again as it scrolled back (measured 2026-10-16: views of
    /// three-row tables, two-line callouts and short formulas take about 0.2 MB each).
    static func estimatedMegabytes(of block: LivePreviewBlock) -> Double? {
        switch block.kind {
        case .table:
            let rows = block.markdown.split(separator: "\n").filter { line in line.contains("|") }
            let columns = rows.first.map { header in header.split(separator: "|", omittingEmptySubsequences: true).count } ?? 1
            return 0.15 + 0.12 * Double(max(1, rows.count - 1) * max(1, columns))
        case .baseDefinition: return 6
        case .frontmatter: return 4
        case .mathBlock, .callout:
            return 0.15 + 0.05 * Double(block.markdown.split(separator: "\n", omittingEmptySubsequences: false).count)
        case .horizontalRule: return 0.1
        // A copy of what a plugin drew is a web view of its own.
        case .pluginCodeBlock: return 8
        case .embed(let embed):
            let fileExtension = (WikiLinkResolver.pathPart(embed.target) as NSString).pathExtension.lowercased()
            if DocumentKind.videoFileExtensions.contains(fileExtension) || DocumentKind.audioFileExtensions.contains(fileExtension) { return nil }
            return 12
        }
    }

    /// Keeps a view taken off screen, dropping the oldest kept views past the budget.
    mutating func keep(_ host: Host, for key: LivePreviewBlockKey, estimatedMegabytes: Double) {
        _ = take(key)
        guard estimatedMegabytes <= Double(budgetMegabytes) else { return }
        hostsByKey[key] = (host, estimatedMegabytes, nextSequence)
        detachmentOrder.append((key, nextSequence))
        nextSequence += 1
        estimatedMegabytesInPool += estimatedMegabytes
        while estimatedMegabytesInPool > Double(budgetMegabytes), detachmentOrderStart < detachmentOrder.count {
            let oldest = detachmentOrder[detachmentOrderStart]
            detachmentOrderStart += 1
            if hostsByKey[oldest.key]?.sequence == oldest.sequence { _ = take(oldest.key) }
        }
        // The entries passed over are dropped once they are most of the list.
        if detachmentOrderStart > 64, detachmentOrderStart * 2 > detachmentOrder.count {
            detachmentOrder.removeFirst(detachmentOrderStart)
            detachmentOrderStart = 0
        }
    }

    /// Takes a kept view out of the pool to show it again.
    mutating func take(_ key: LivePreviewBlockKey) -> Host? {
        guard let kept = hostsByKey.removeValue(forKey: key) else { return nil }
        estimatedMegabytesInPool -= kept.estimatedMegabytes
        return kept.host
    }

    /// A kept view, left in the pool, such as to give it a new appearance.
    func host(for key: LivePreviewBlockKey) -> Host? {
        hostsByKey[key]?.host
    }

    /// Drops the kept views of blocks no longer in the note.
    mutating func removeHosts(notIn keysInNote: Set<LivePreviewBlockKey>) {
        for key in Array(hostsByKey.keys) where !keysInNote.contains(key) { _ = take(key) }
    }

    mutating func removeAll() {
        hostsByKey.removeAll()
        detachmentOrder.removeAll()
        detachmentOrderStart = 0
        estimatedMegabytesInPool = 0
    }
}

/// The height a rendered block's view is given before it has measured itself, from what its
/// source says of its size; the view's own height replaces it.
enum LivePreviewBlockHeightEstimate {
    static func height(of block: LivePreviewBlock, columnWidth: CGFloat) -> CGFloat {
        switch block.kind {
        case .frontmatter: return 44 + 34 * CGFloat(block.markdown.components(separatedBy: "\n").count - 2)
        case .table: return 40 * CGFloat(block.markdown.components(separatedBy: "\n").count - 1) + 16
        case .mathBlock: return 72
        case .horizontalRule: return 28
        case .callout: return 56 + 30 * CGFloat(block.markdown.components(separatedBy: "\n").count - 1)
        case .baseDefinition: return EmbeddedBaseView.defaultHeight
        case .pluginCodeBlock: return 120
        case .embed(let embed):
            let fileExtension = (WikiLinkResolver.pathPart(embed.target) as NSString).pathExtension.lowercased()
            if DocumentKind.videoFileExtensions.contains(fileExtension) { return columnWidth * 9 / 16 + 8 }
            if DocumentKind.audioFileExtensions.contains(fileExtension) { return 96 }
            if fileExtension == "pdf" { return 570 }
            if fileExtension == "base" { return EmbeddedBaseView.defaultHeight }
            if DocumentKind(fileExtension: fileExtension) == .image { return 280 }
            return 60
        }
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
        /// A block's height also changes with the fonts it is drawn in.
        let typography: NoteTypography
        /// And with the theme's sizes, spacing and borders.
        let themeFingerprint: String

        /// Nil for a width that is not a finite number of points, as before the first layout.
        init?(blockKey: LivePreviewBlockKey, columnWidth: CGFloat, textSize: Double, typography: NoteTypography = .standard, themeFingerprint: String = "") {
            guard let wholeColumnWidth = Int(exactly: columnWidth.rounded()), wholeColumnWidth > 0 else { return nil }
            self.blockKey = blockKey
            self.columnWidth = wholeColumnWidth
            self.textSize = textSize
            self.typography = typography
            self.themeFingerprint = themeFingerprint
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

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
typealias RenderedBlockHost = NSHostingView<AnyView>
typealias RenderedBlockTextView = NSView
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

    /// A host whose frame comes from the text's layout, not from its content.
    static func makeRenderedBlockHost(rootView: AnyView) -> RenderedBlockHost {
        #if canImport(UIKit)
        let host = UIHostingController(rootView: rootView)
        host.view.backgroundColor = .clear
        host.sizingOptions = []
        return host
        #else
        let host = NSHostingView(rootView: rootView)
        host.sizingOptions = []
        return host
        #endif
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
                    makeRootView: (LivePreviewBlockEntry) -> AnyView) -> RenderedBlockPlacement? {
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
    private func host(for entry: LivePreviewBlockEntry, makeRootView: (LivePreviewBlockEntry) -> AnyView) -> RenderedBlockHost {
        if entry.block.kind == .frontmatter {
            let host = propertiesHost ?? RenderedBlockHost.makeRenderedBlockHost(rootView: makeRootView(entry))
            if propertiesHost == nil {
                propertiesHost = host
            } else if propertiesHostBlockKey != entry.key {
                host.rootView = makeRootView(entry)
            }
            propertiesHostBlockKey = entry.key
            return host
        }
        if let host = hosts[entry.key] { return host }
        let host = detachedHosts.take(entry.key) ?? RenderedBlockHost.makeRenderedBlockHost(rootView: makeRootView(entry))
        hosts[entry.key] = host
        return host
    }

    /// Takes off screen the views of blocks not in `keysInUse`, keeping those that can
    /// scroll back into view or that the cursor can leave, within the pool's memory budget.
    /// The properties' view stays while the frontmatter is in use, though its key changes
    /// with each edit, so it is not taken away for a frame and put back.
    func detachViews(except keysInUse: Set<LivePreviewBlockKey>, entries: [LivePreviewBlockEntry]) {
        if !entries.contains(where: { entry in entry.block.kind == .frontmatter && keysInUse.contains(entry.key) }) {
            propertiesHost?.placedView.removeFromSuperview()
        }
        for (key, host) in hosts where !keysInUse.contains(key) {
            host.placedView.removeFromSuperview()
            hosts[key] = nil
            if let entry = entries.first(where: { candidate in candidate.key == key }),
               let estimatedMegabytes = DetachedWidgetPool<RenderedBlockHost>.estimatedMegabytes(of: entry.block.kind) {
                detachedHosts.keep(host, for: key, estimatedMegabytes: estimatedMegabytes)
            }
        }
    }

    func removeAllViews() {
        propertiesHost?.placedView.removeFromSuperview()
        for host in hosts.values { host.placedView.removeFromSuperview() }
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
    func refreshViews(for signature: LivePreviewWidgetSignature, entries: [LivePreviewBlockEntry], makeRootView: (LivePreviewBlockEntry) -> AnyView) -> Bool {
        guard signature != self.signature else { return false }
        let changesOnlyIndex = self.signature?.appearance == signature.appearance && self.signature?.drawingVersion == signature.drawingVersion
        self.signature = signature
        refreshViews(entries: entries, onlyThoseReadingIndex: changesOnlyIndex, makeRootView: makeRootView)
        return true
    }

    /// Gives the views on screen, and those kept off screen, new root views. Kept views of
    /// blocks no longer in the note are dropped, so none shows again with an older environment.
    func refreshViews(entries: [LivePreviewBlockEntry], onlyThoseReadingIndex: Bool = false, makeRootView: (LivePreviewBlockEntry) -> AnyView) {
        guard hasViews else { return }
        detachedHosts.removeHosts(notIn: Set(entries.map(\.key)))
        for entry in entries where !onlyThoseReadingIndex || LivePreviewWidgetSignature.readsIndex(entry.block.kind) {
            if entry.block.kind == .frontmatter {
                guard let propertiesHost else { continue }
                propertiesHost.rootView = makeRootView(entry)
                propertiesHostBlockKey = entry.key
            } else if let host = hosts[entry.key] ?? detachedHosts.host(for: entry.key) {
                host.rootView = makeRootView(entry)
            }
        }
    }

    /// A block's view, with the vault's fonts, theme and accent passed in: a hosted view
    /// does not inherit SwiftUI's environment from the editor. A view is kept while its
    /// block moves with edits elsewhere, so its actions find the block by key when they run.
    /// - Parameter colorScheme: Passed where the hosted view does not take the appearance
    ///   from the text view it is in, as on the iPad.
    static func rootView(for entry: LivePreviewBlockEntry, environment: LivePreviewEnvironment, accentHex: String, colorScheme: ColorScheme?,
                         revealSource: @escaping () -> Void, reportHeight: @escaping (CGFloat) -> Void) -> AnyView {
        let accent = Color.graphiteAccent(hex: accentHex) ?? .accentColor
        let widget = LivePreviewWidgetView(block: entry.block, environment: environment, revealSource: revealSource, reportHeight: reportHeight)
            .environment(\.lassoNoteDestination, environment.lassoNoteDestination)
            .environment(\.noteTypography, environment.typography)
            .environment(\.noteTheme, environment.theme)
            .tint(accent)
            .environment(\.accent, accent)
        guard let colorScheme else { return AnyView(widget) }
        return AnyView(widget.environment(\.colorScheme, colorScheme))
    }
}

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
    /// found yet looks for its file again, and a callout can contain either.
    static func readsIndex(_ kind: LivePreviewBlock.Kind) -> Bool {
        switch kind {
        case .embed, .baseDefinition, .callout: true
        case .frontmatter, .table, .mathBlock, .horizontalRule, .pluginCodeBlock: false
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
        // A copy of what a plugin drew is a web view of its own.
        case .pluginCodeBlock: return 8
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
            if MediaFileKind.videoExtensions.contains(fileExtension) { return columnWidth * 9 / 16 + 8 }
            if MediaFileKind.audioExtensions.contains(fileExtension) { return 96 }
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

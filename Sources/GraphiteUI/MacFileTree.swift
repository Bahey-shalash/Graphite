#if os(macOS)
import AppKit
import SwiftUI
import UniformTypeIdentifiers
import GraphiteCore

/// The Mac's file tree: AppKit's outline view, as in Finder's and NetNewsWire's sidebars.
///
/// The outline view asks for a row only when it is about to show it, so a vault with tens of
/// thousands of files at its root lists at once. SwiftUI's list kept a view for every row on
/// the Mac: with 24,712 files at the root, the main thread stayed busy 7 to 10 s after the
/// vault opened (measured 2026-10-15). Folders list their contents when they first expand,
/// and again when the vault changes on disk while they are expanded.
struct MacFileTree: NSViewRepresentable {
    @Bindable var workspace: WorkspaceModel
    let typography: NoteTypography
    /// A file to show, with the folders above it expanded; set back to nil once shown.
    @Binding var fileToReveal: VaultPath?
    let requestCreation: (CreationKind, VaultPath) -> Void

    func makeCoordinator() -> FileTreeController {
        FileTreeController(workspace: workspace)
    }

    func makeNSView(context: Context) -> NSScrollView {
        context.coordinator.makeScrollView()
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let controller = context.coordinator
        controller.requestCreation = requestCreation
        // Read here, so a change to any of them updates the tree, and only to them.
        controller.update(FileTreeController.State(
            rootEntries: workspace.rootEntries,
            expandedFolders: workspace.expandedFolders,
            selection: workspace.selection,
            directoryVersion: workspace.directoryVersion,
            sortOrder: workspace.vaultSettings.fileSortOrder,
            conflictedPaths: workspace.conflictedPaths,
            showsFileExtensions: workspace.preferences.showsFileExtensions,
            typography: typography))
        if let fileToReveal {
            controller.reveal(fileToReveal)
            DispatchQueue.main.async { self.fileToReveal = nil }
        }
    }
}

/// A file or folder of the tree. A node is kept for as long as its path is listed, so the
/// outline view, which knows rows by their item, keeps a folder's expansion and a file's
/// selection when its folder is listed again.
@MainActor
final class FileTreeNode {
    let path: VaultPath
    var entry: VaultEntry
    /// A folder's contents as last listed; nil until it is listed.
    var children: [FileTreeNode]?
    weak var parent: FileTreeNode?

    init(entry: VaultEntry, parent: FileTreeNode?) {
        path = entry.path
        self.entry = entry
        self.parent = parent
    }
}

/// The outline view's data source and delegate.
@MainActor
final class FileTreeController: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate {
    /// What the tree shows, from the workspace.
    struct State: Equatable {
        var rootEntries: [VaultEntry] = []
        var expandedFolders: Set<VaultPath> = []
        var selection: VaultPath?
        var directoryVersion = 0
        var sortOrder = FileSortOrder.alphabetical
        var conflictedPaths: Set<VaultPath> = []
        var showsFileExtensions = false
        var typography = NoteTypography.standard
    }

    let workspace: WorkspaceModel
    var requestCreation: (CreationKind, VaultPath) -> Void = { _, _ in }
    private(set) var outlineView: FileTreeOutlineView?
    private var state = State()
    private var rootNodes: [FileTreeNode] = []
    /// Every node listed, by path, so a listing reuses the nodes already made.
    private var nodesByPath: [VaultPath: FileTreeNode] = [:]
    /// Folders whose contents are being listed.
    private var foldersBeingListed: Set<VaultPath> = []
    /// Set while the tree expands, folds or selects rows itself, so the delegate does not
    /// take that for the person's doing.
    private var isApplyingState = false
    /// A file to show once the folders above it are listed.
    private var pendingReveal: VaultPath?

    static let cellIdentifier = NSUserInterfaceItemIdentifier("FileTreeCell")
    static let vaultItemType = NSPasteboard.PasteboardType(UTType.graphiteVaultItem.identifier)

    init(workspace: WorkspaceModel) {
        self.workspace = workspace
    }

    func makeScrollView() -> NSScrollView {
        let outlineView = FileTreeOutlineView()
        outlineView.controller = self
        outlineView.autoresizingMask = [.width]
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Name"))
        column.resizingMask = .autoresizingMask
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column
        outlineView.headerView = nil
        outlineView.style = .sourceList
        // The system's sidebar row size (System Settings › Appearance › Sidebar icon size).
        outlineView.rowSizeStyle = .default
        outlineView.floatsGroupRows = false
        outlineView.indentationPerLevel = 14
        outlineView.autoresizesOutlineColumn = false
        outlineView.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        outlineView.backgroundColor = .clear
        outlineView.allowsEmptySelection = true
        outlineView.allowsMultipleSelection = false
        outlineView.dataSource = self
        outlineView.delegate = self
        outlineView.target = self
        outlineView.action = #selector(rowClicked(_:))
        outlineView.setAccessibilityLabel("Files")
        outlineView.registerForDraggedTypes([Self.vaultItemType])
        outlineView.setDraggingSourceOperationMask([.move], forLocal: true)
        outlineView.setDraggingSourceOperationMask([], forLocal: false)
        self.outlineView = outlineView

        let scrollView = NSScrollView()
        scrollView.documentView = outlineView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        // The sidebar's material shows through, as behind SwiftUI's sidebar list.
        scrollView.drawsBackground = false
        return scrollView
    }

    // MARK: Following the workspace

    func update(_ newState: State) {
        guard newState != state, let outlineView else { return }
        let previousState = state
        state = newState
        isApplyingState = true
        defer { isApplyingState = false }
        let listsAgain = newState.directoryVersion != previousState.directoryVersion || newState.sortOrder != previousState.sortOrder
        if newState.rootEntries != previousState.rootEntries || listsAgain {
            rootNodes = nodes(for: newState.rootEntries, parent: nil, reusing: rootNodes)
            if listsAgain { forgetContentsOfFoldersOutsideTree() }
            outlineView.reloadData()
            if listsAgain { listExpandedFoldersAgain() }
            expandFolders(newState.expandedFolders)
        } else if newState.expandedFolders != previousState.expandedFolders {
            for path in previousState.expandedFolders.subtracting(newState.expandedFolders) {
                if let node = nodesByPath[path] { outlineView.collapseItem(node) }
            }
            expandFolders(newState.expandedFolders)
        } else if newState.conflictedPaths != previousState.conflictedPaths || newState.showsFileExtensions != previousState.showsFileExtensions
                    || newState.typography != previousState.typography {
            // Only what the rows draw changed: the rows on screen are drawn again.
            outlineView.reloadData(forRowIndexes: IndexSet(integersIn: 0..<outlineView.numberOfRows), columnIndexes: IndexSet(integer: 0))
        }
        selectOpenFile()
    }

    /// The nodes for a listing, reusing the node already made for each path still listed.
    private func nodes(for entries: [VaultEntry], parent: FileTreeNode?, reusing previousNodes: [FileTreeNode]) -> [FileTreeNode] {
        let listedPaths = Set(entries.map(\.path))
        for node in previousNodes where !listedPaths.contains(node.path) { forget(node) }
        return entries.map { entry in
            if let node = nodesByPath[entry.path], node.entry.isDirectory == entry.isDirectory {
                node.entry = entry
                node.parent = parent
                return node
            }
            let node = FileTreeNode(entry: entry, parent: parent)
            nodesByPath[entry.path] = node
            return node
        }
    }

    private func forget(_ node: FileTreeNode) {
        nodesByPath[node.path] = nil
        for child in node.children ?? [] { forget(child) }
    }

    /// A folder folded while the vault changed is listed again when it next expands.
    private func forgetContentsOfFoldersOutsideTree() {
        for node in nodesByPath.values where node.children != nil && !state.expandedFolders.contains(node.path) {
            for child in node.children ?? [] { forget(child) }
            node.children = nil
        }
    }

    private func listExpandedFoldersAgain() {
        for path in state.expandedFolders {
            if let node = nodesByPath[path], node.children != nil { list(node) }
        }
    }

    /// Expands every folder in `folders` whose parent is expanded, outermost first, listing
    /// those not listed yet; the others expand once their parent's listing arrives.
    private func expandFolders(_ folders: Set<VaultPath>) {
        guard let outlineView else { return }
        for path in folders.sorted(by: { leftPath, rightPath in leftPath.rawValue.count < rightPath.rawValue.count }) {
            guard let node = nodesByPath[path], node.entry.isDirectory, isShown(node) else { continue }
            if node.children == nil { list(node) }
            if !outlineView.isItemExpanded(node) { outlineView.expandItem(node) }
        }
    }

    /// Whether every folder above the node is expanded, so its row can show.
    private func isShown(_ node: FileTreeNode) -> Bool {
        var ancestor = node.parent
        while let folder = ancestor {
            guard outlineView?.isItemExpanded(folder) == true else { return false }
            ancestor = folder.parent
        }
        return true
    }

    /// Lists a folder's contents in the background, and shows them once they differ.
    private func list(_ node: FileTreeNode) {
        guard let store = workspace.store, !foldersBeingListed.contains(node.path) else { return }
        foldersBeingListed.insert(node.path)
        let sortOrder = state.sortOrder
        Task { [weak self] in
            defer { self?.foldersBeingListed.remove(node.path) }
            do {
                let listedEntries = try await store.children(of: node.path, sortedBy: sortOrder)
                self?.show(listedEntries, in: node)
            } catch {
                // A folder another app removed or renamed goes away with its parent's next
                // listing; that is not an error to report.
                guard let self, self.workspace.isDirectory(node.path) else { return }
                self.workspace.errorMessage = error.localizedDescription
            }
        }
    }

    private func show(_ listedEntries: [VaultEntry], in node: FileTreeNode) {
        guard nodesByPath[node.path] === node, let outlineView else { return }
        workspace.checkConflictVersions(of: listedEntries.lazy.filter { entry in !entry.isDirectory }.map(\.path))
        if let children = node.children, children.map(\.entry) == listedEntries { return revealPendingFile() }
        isApplyingState = true
        defer { isApplyingState = false }
        node.children = nodes(for: listedEntries, parent: node, reusing: node.children ?? [])
        outlineView.reloadItem(node, reloadChildren: true)
        expandFolders(state.expandedFolders)
        selectOpenFile()
        revealPendingFile()
    }

    private func selectOpenFile() {
        guard let outlineView else { return }
        let row = state.selection.flatMap { path in nodesByPath[path] }.map { node in outlineView.row(forItem: node) } ?? -1
        guard row != outlineView.selectedRow else { return }
        // A folder the person picked stays selected while the open file's row is hidden.
        if row < 0, let selectedNode = outlineView.item(atRow: outlineView.selectedRow) as? FileTreeNode, selectedNode.entry.isDirectory { return }
        let wasApplyingState = isApplyingState
        isApplyingState = true
        defer { isApplyingState = wasApplyingState }
        if row >= 0 {
            outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        } else {
            outlineView.deselectAll(nil)
        }
    }

    // MARK: Revealing a file

    /// Shows a file's row: the folders above it expand, which the workspace has already
    /// recorded (`revealCurrentFile`), and the row scrolls to the middle once it exists.
    func reveal(_ path: VaultPath) {
        pendingReveal = path
        revealPendingFile()
    }

    private func revealPendingFile() {
        guard let path = pendingReveal, let outlineView, let node = nodesByPath[path] else { return }
        let row = outlineView.row(forItem: node)
        guard row >= 0 else { return }
        pendingReveal = nil
        guard let scrollView = outlineView.enclosingScrollView else { return }
        let clipView = scrollView.contentView
        let rowFrame = outlineView.rect(ofRow: row)
        let highestOrigin = max(0, outlineView.bounds.height - clipView.bounds.height)
        clipView.scroll(to: NSPoint(x: 0, y: min(highestOrigin, max(0, rowFrame.midY - clipView.bounds.height / 2))))
        scrollView.reflectScrolledClipView(clipView)
    }

    // MARK: Data source

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        guard let node = item as? FileTreeNode else { return rootNodes.count }
        return node.children?.count ?? 0
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        guard let node = item as? FileTreeNode else { return rootNodes[index] }
        // A folder not listed yet has no children to ask for.
        guard let children = node.children, children.indices.contains(index) else { return node }
        return children[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        (item as? FileTreeNode)?.entry.isDirectory ?? false
    }

    // MARK: Delegate

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let node = item as? FileTreeNode else { return nil }
        let cell = outlineView.makeView(withIdentifier: Self.cellIdentifier, owner: self) as? FileTreeCellView ?? FileTreeCellView()
        cell.identifier = Self.cellIdentifier
        cell.configure(title: node.entry.isDirectory ? node.path.name : node.path.stem, extensionSuffix: extensionSuffix(of: node.entry),
                       hasConflictVersions: state.conflictedPaths.contains(node.path),
                       font: NoteTypography.font(state.typography.interfaceFamily, size: NSFont.systemFontSize, weight: .regular))
        cell.setAccessibilityLabel(workspace.preferences.displayName(for: node.path))
        return cell
    }

    /// The extension after the name, muted so the name reads first: always for files other
    /// than notes, and for notes where Settings shows extensions.
    private func extensionSuffix(of entry: VaultEntry) -> String? {
        guard !entry.isDirectory else { return nil }
        let fileExtension = (entry.path.name as NSString).pathExtension
        guard !fileExtension.isEmpty else { return nil }
        if entry.kind == .markdown && !state.showsFileExtensions { return nil }
        return "." + fileExtension
    }

    func outlineView(_ outlineView: NSOutlineView, typeSelectStringFor tableColumn: NSTableColumn?, item: Any) -> String? {
        (item as? FileTreeNode)?.path.name
    }

    /// Picking a file opens it, with the mouse or the arrow keys, as a note does in Notes.
    func outlineViewSelectionDidChange(_ notification: Notification) {
        guard !isApplyingState, let outlineView,
              let node = outlineView.item(atRow: outlineView.selectedRow) as? FileTreeNode, !node.entry.isDirectory,
              node.path != workspace.selection else { return }
        Task { await workspace.open(node.path) }
    }

    func outlineViewItemDidExpand(_ notification: Notification) {
        guard let node = notification.userInfo?["NSObject"] as? FileTreeNode else { return }
        if node.children == nil { list(node) }
        guard !isApplyingState else { return }
        state.expandedFolders.insert(node.path)
        workspace.expandedFolders.insert(node.path)
    }

    func outlineViewItemDidCollapse(_ notification: Notification) {
        guard !isApplyingState, let node = notification.userInfo?["NSObject"] as? FileTreeNode else { return }
        state.expandedFolders.remove(node.path)
        workspace.expandedFolders.remove(node.path)
    }

    /// A click on a folder's name folds or unfolds it, as in Obsidian; a click on its
    /// disclosure triangle is the outline view's own.
    @objc private func rowClicked(_ sender: NSOutlineView) {
        let row = sender.clickedRow
        guard row >= 0, let node = sender.item(atRow: row) as? FileTreeNode, node.entry.isDirectory,
              let event = NSApp.currentEvent else { return }
        let clickLocation = sender.convert(event.locationInWindow, from: nil)
        guard !sender.frameOfOutlineCell(atRow: row).contains(clickLocation) else { return }
        if sender.isItemExpanded(node) { sender.collapseItem(node) } else { sender.expandItem(node) }
    }

    // MARK: Menus

    /// The menu of the file or folder clicked: the SwiftUI menu the iPad's rows show,
    /// drawn as an AppKit menu.
    func menu(forRow row: Int) -> NSMenu? {
        guard let outlineView, let node = outlineView.item(atRow: row) as? FileTreeNode else { return nil }
        let menuContent = VaultEntryMenu(entry: node.entry, workspace: workspace, requestCreation: requestCreation)
        return NSHostingMenu(rootView: menuContent)
    }

    // MARK: Dragging

    func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem item: Any) -> (any NSPasteboardWriting)? {
        guard let node = item as? FileTreeNode, let data = try? JSONEncoder().encode(VaultItemTransfer(path: node.path.rawValue)) else { return nil }
        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setData(data, forType: Self.vaultItemType)
        return pasteboardItem
    }

    /// A drop on a folder moves into it; on a file, into the file's folder, as in Obsidian;
    /// elsewhere, to the vault's root. The folder that would receive the drop is highlighted.
    func outlineView(_ outlineView: NSOutlineView, validateDrop info: any NSDraggingInfo, proposedItem item: Any?, proposedChildIndex index: Int) -> NSDragOperation {
        let destination = dropDestination(for: item as? FileTreeNode)
        let paths = draggedPaths(in: info)
        guard paths.contains(where: { path in Self.canMove(path, into: destination?.path ?? .root) }) else { return [] }
        outlineView.setDropItem(destination, dropChildIndex: NSOutlineViewDropOnItemIndex)
        return .move
    }

    func outlineView(_ outlineView: NSOutlineView, acceptDrop info: any NSDraggingInfo, item: Any?, childIndex index: Int) -> Bool {
        let folder = dropDestination(for: item as? FileTreeNode)?.path ?? .root
        let paths = draggedPaths(in: info).filter { path in Self.canMove(path, into: folder) }
        guard !paths.isEmpty else { return false }
        Task { for path in paths { await workspace.move(path, into: folder) } }
        return true
    }

    private func dropDestination(for node: FileTreeNode?) -> FileTreeNode? {
        guard let node else { return nil }
        return node.entry.isDirectory ? node : node.parent
    }

    private func draggedPaths(in info: any NSDraggingInfo) -> [VaultPath] {
        (info.draggingPasteboard.pasteboardItems ?? []).compactMap { pasteboardItem in
            guard let data = pasteboardItem.data(forType: Self.vaultItemType),
                  let item = try? JSONDecoder().decode(VaultItemTransfer.self, from: data) else { return nil }
            return try? VaultPath(item.path)
        }
    }

    /// An item moves only to another folder, and never into itself.
    static func canMove(_ path: VaultPath, into folder: VaultPath) -> Bool {
        path.parent != folder && path != folder && !folder.rawValue.hasPrefix(path.rawValue + "/")
    }
}

/// The file tree's outline view, which asks its controller for the clicked row's menu.
final class FileTreeOutlineView: NSOutlineView {
    weak var controller: FileTreeController?

    override func menu(for event: NSEvent) -> NSMenu? {
        // The outline view records the clicked row, and draws its outline, while finding its own menu.
        _ = super.menu(for: event)
        guard clickedRow >= 0 else { return nil }
        return controller?.menu(forRow: clickedRow)
    }
}

/// A row of the file tree: the name, the extension muted after it, and a mark for a file
/// that has other versions. Laid out by hand rather than with constraints, as NetNewsWire's
/// sidebar cells are: there is one per visible row, and they are laid out as the list scrolls.
final class FileTreeCellView: NSTableCellView {
    private let titleField = NSTextField(labelWithString: "")
    private let conflictMarker = NSImageView()
    private var title = ""
    private var extensionSuffix: String?
    private var font = NSFont.systemFont(ofSize: NSFont.systemFontSize)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        titleField.lineBreakMode = .byTruncatingTail
        titleField.cell?.truncatesLastVisibleLine = true
        titleField.allowsDefaultTighteningForTruncation = false
        // Not the cell's `textField`: the table gives that field a single color, which drew
        // the muted extension in the name's color. The selected style is set here instead.
        titleField.allowsEditingTextAttributes = true
        addSubview(titleField)
        conflictMarker.image = NSImage(systemSymbolName: "square.on.square", accessibilityDescription: ConflictVersionsText.markerDescription)
        conflictMarker.contentTintColor = .systemOrange
        conflictMarker.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 11, weight: .regular)
        conflictMarker.isHidden = true
        addSubview(conflictMarker)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func configure(title: String, extensionSuffix: String?, hasConflictVersions: Bool, font: NSFont) {
        let changed = title != self.title || extensionSuffix != self.extensionSuffix || font != self.font
        self.title = title
        self.extensionSuffix = extensionSuffix
        self.font = font
        if changed { updateTitle() }
        if conflictMarker.isHidden == hasConflictVersions {
            conflictMarker.isHidden = !hasConflictVersions
            needsLayout = true
        }
    }

    /// The title as drawn, name and extension.
    var drawnTitle: NSAttributedString { titleField.attributedStringValue }

    /// A selected row is drawn in the accent color, where the muted extension turns white too.
    override var backgroundStyle: NSView.BackgroundStyle {
        didSet { if backgroundStyle != oldValue { updateTitle() } }
    }

    private func updateTitle() {
        let isEmphasized = backgroundStyle == .emphasized
        let attributedTitle = NSMutableAttributedString(string: title, attributes: [
            .font: font, .foregroundColor: isEmphasized ? NSColor.alternateSelectedControlTextColor : NSColor.labelColor,
        ])
        if let extensionSuffix {
            attributedTitle.append(NSAttributedString(string: extensionSuffix, attributes: [
                .font: font, .foregroundColor: isEmphasized ? NSColor.alternateSelectedControlTextColor.withAlphaComponent(0.75) : NSColor.secondaryLabelColor,
            ]))
        }
        titleField.attributedStringValue = attributedTitle
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let markerWidth: CGFloat = conflictMarker.isHidden ? 0 : 18
        let titleHeight = ceil(titleField.intrinsicContentSize.height)
        let titleFrame = NSRect(x: 2, y: floor((bounds.height - titleHeight) / 2), width: max(0, bounds.width - 4 - markerWidth), height: titleHeight)
        if titleField.frame != titleFrame { titleField.frame = titleFrame }
        if !conflictMarker.isHidden {
            let markerFrame = NSRect(x: bounds.width - markerWidth, y: floor((bounds.height - 16) / 2), width: 16, height: 16)
            if conflictMarker.frame != markerFrame { conflictMarker.frame = markerFrame }
        }
    }
}
#endif

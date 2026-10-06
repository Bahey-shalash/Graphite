import SwiftUI
import UniformTypeIdentifiers
import GraphiteCore
import GraphiteApple

/// A tab being dragged to another place in a tab bar.
struct TabTransfer: Codable, Transferable {
    let tabID: UUID
    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .graphiteTab)
    }
}

extension UTType {
    /// Declared in the app's Info.plist; used only for drags inside Graphite.
    static let graphiteTab = UTType(exportedAs: "com.graphite.study.tab")
}

/// The documents area: one group of tabs, or two side by side with a divider that can be
/// dragged, as after Obsidian's "Split right". In a narrow window only the focused side
/// is shown.
struct WorkspacePanes: View {
    @Bindable var workspace: WorkspaceModel
    @Binding var showsLinksInspector: Bool
    let create: (CreationKind) -> Void
    let showQuickSwitcher: () -> Void
    /// False while something covers the panes, such as the quick switcher, so a touch on
    /// it does not focus the side beneath.
    var acceptsFocusTouches = true
    var showsTabBar = true
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    /// The split when a divider drag began.
    @State private var dragStartFraction: Double?
    /// Where each side is in the window, to focus the side a touch lands on.
    @State private var groupFrames: [UUID: CGRect] = [:]
    /// The documents area's width, which decides where documents put Write, Undo and Redo:
    /// the window's toolbar spans this area, whichever side is focused.
    @State private var detailWidth: CGFloat?

    private var showsBothGroups: Bool { workspace.layout.isSplit && horizontalSizeClass != .compact }

    var body: some View {
        panes
            .onGeometryChange(for: CGFloat.self) { geometry in geometry.size.width } action: { width in detailWidth = width }
            .environment(\.usesDocumentControlRow, DocumentToolbarLayout.usesControlRow(detailWidth: detailWidth, horizontalSizeClass: horizontalSizeClass))
            #if canImport(UIKit)
            // A touch anywhere on a side focuses it, so the toolbar and new files follow. The
            // touch is only observed: a SwiftUI gesture over the editor would compete with
            // its own taps, and the cursor would land in the wrong place.
            .background {
                if showsBothGroups && acceptsFocusTouches {
                    WindowTouchObserver { windowPoint in
                        guard let groupID = groupFrames.first(where: { _, frame in frame.contains(windowPoint) })?.key else { return }
                        workspace.focusGroup(groupID)
                    }
                }
            }
            #endif
    }

    @ViewBuilder private var panes: some View {
        if showsBothGroups {
            GeometryReader { geometry in
                // Read again here: the reader's content can update after a side closes and
                // before the check above does.
                let groups = workspace.layout.groups
                let availableWidth = max(geometry.size.width - SplitDivider.width, 1)
                if groups.count > 1 {
                    HStack(spacing: 0) {
                        pane(for: groups[0])
                            .frame(width: availableWidth * workspace.layout.splitFraction)
                        SplitDivider(fraction: workspace.layout.splitFraction) { translation in
                            let startFraction = dragStartFraction ?? workspace.layout.splitFraction
                            dragStartFraction = startFraction
                            workspace.layout.splitFraction = startFraction + translation / availableWidth
                        } endDrag: {
                            dragStartFraction = nil
                        } setFraction: { fraction in
                            workspace.layout.splitFraction = fraction
                        }
                        pane(for: groups[1])
                    }
                    .coordinateSpace(.named(SplitDivider.coordinateSpaceName))
                } else {
                    pane(for: workspace.layout.focusedGroup)
                }
            }
        } else {
            pane(for: workspace.layout.focusedGroup)
        }
    }

    private func pane(for group: TabGroup) -> some View {
        TabGroupPane(workspace: workspace, group: group, isFocused: group.id == workspace.layout.focusedGroupID,
                     showsBothGroups: showsBothGroups, showsLinksInspector: $showsLinksInspector,
                     create: create, showQuickSwitcher: showQuickSwitcher, showsTabBar: showsTabBar)
            .id(group.id)
            .onGeometryChange(for: CGRect.self) { geometry in geometry.frame(in: .global) } action: { frame in groupFrames[group.id] = frame }
            .onDisappear { groupFrames[group.id] = nil }
    }
}

/// One side of the split: its tabs, and the active tab's document.
private struct TabGroupPane: View {
    @Bindable var workspace: WorkspaceModel
    let group: TabGroup
    let isFocused: Bool
    let showsBothGroups: Bool
    @Binding var showsLinksInspector: Bool
    let create: (CreationKind) -> Void
    let showQuickSwitcher: () -> Void
    let showsTabBar: Bool
    @Environment(\.usesDocumentControlRow) private var usesDocumentControlRowSetting
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    /// This side's width, which decides whether its tab bar has room for Write, Undo and
    /// Redo.
    @State private var width: CGFloat?

    var body: some View {
        let tab = group.activeTab
        let showsDocumentControlsInTabBar = DocumentToolbarLayout.showsControlsInTabBar(
            usesControlRow: usesDocumentControlRowSetting ?? DocumentToolbarLayout.usesControlRow(detailWidth: nil, horizontalSizeClass: horizontalSizeClass),
            showsTabBar: showsTabBar, tabBarWidth: width)
        // Compact widths keep Apple's palette; there is no fixed bar to place.
        let showsPencilToolsInTabBar = horizontalSizeClass != .compact && DocumentToolbarLayout.showsPencilToolsInTabBar(
            showsTabBar: showsTabBar, tabBarWidth: width, showsDocumentControls: showsDocumentControlsInTabBar)
        VStack(spacing: 0) {
            if showsTabBar {
                TabBar(workspace: workspace, group: group, isFocused: isFocused, showsBothGroups: showsBothGroups,
                       showsDocumentControls: showsDocumentControlsInTabBar, showsPencilTools: showsPencilToolsInTabBar)
                Hairline()
            }
            ConflictVersionsBanner(workspace: workspace, path: tab.path)
            TabDocumentView(workspace: workspace, tab: tab, document: workspace.document(for: tab.id), isFocused: isFocused,
                            showsLinksInspector: $showsLinksInspector, create: create, showQuickSwitcher: showQuickSwitcher)
                .id(tab.id)
                .environment(\.showsDocumentControlsInTabBar, showsDocumentControlsInTabBar)
                .environment(\.showsPencilToolsInTabBar, showsPencilToolsInTabBar)
        }
        .onGeometryChange(for: CGFloat.self) { geometry in geometry.size.width } action: { newWidth in width = newWidth }
        #if !canImport(UIKit)
        // A click anywhere on this side focuses it, so the toolbar and new files follow.
        .simultaneousGesture(TapGesture().onEnded { workspace.focusGroup(group.id) })
        #endif
    }
}

// MARK: Tab bar

private struct TabBar: View {
    @Bindable var workspace: WorkspaceModel
    let group: TabGroup
    let isFocused: Bool
    let showsBothGroups: Bool
    /// Whether the bar ends with Undo, Redo and Write of the active tab's document.
    let showsDocumentControls: Bool
    /// Whether the bar has room for the fixed bar's tools, for a PDF written on in the active tab.
    let showsPencilTools: Bool

    @State private var isDropTargeted = false
    @Environment(\.accent) private var accent
    private var layout: TabLayout { workspace.layout }
    private var groupIndex: Int { layout.groups.firstIndex { candidate in candidate.id == group.id } ?? 0 }
    /// The room at each end of the row of tabs.
    private static let tabsInset: CGFloat = 8
    @AppStorage(PencilToolbarStyle.preferenceKey) private var pencilToolbarStyle = PencilToolbarStyle.floating
    /// Whether tabs stay narrow enough for the tab area the fixed bar's tools leave them:
    /// wherever those tools can share this tab bar, whichever tab is shown, so tabs keep
    /// their width when a PDF and a note take turns.
    private var keepsTabsBesidePencilTools: Bool { showsPencilTools && pencilToolbarStyle == .fixed }

    var body: some View {
        HStack(spacing: 4) {
            ScrollViewReader { scrollProxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 2) {
                        ForEach(Array(group.tabs.enumerated()), id: \.element.id) { position, tab in
                            TabItem(tab: tab, title: title(of: tab), isActive: tab.id == group.activeTabID,
                                    marksFocus: isFocused && showsBothGroups,
                                    activate: { workspace.activateTab(tab.id) },
                                    close: { Task { await workspace.closeTab(tab.id) } },
                                    maximumWidth: keepsTabsBesidePencilTools ? DocumentToolbarLayout.minimumTabsWidthBesidePencilTools - 2 * Self.tabsInset : 220)
                                .contextMenu { tabMenu(for: tab) }
                                .draggable(TabTransfer(tabID: tab.id)) {
                                    Label(title(of: tab), systemImage: tab.path.map { path in DocumentKind(path: path).systemImage } ?? "doc")
                                        .padding(8).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                                }
                                // A tab dropped on another goes before it.
                                .dropDestination(for: TabTransfer.self) { items, _ in moveDroppedTabs(items, to: position) }
                                .id(tab.id)
                        }
                    }
                    .padding(.horizontal, Self.tabsInset)
                    .frame(maxHeight: .infinity)
                }
                .frame(minWidth: showsPencilTools ? DocumentToolbarLayout.minimumTabsWidthBesidePencilTools : nil)
                // Past the last tab, a dropped tab goes to the end.
                .dropDestination(for: TabTransfer.self) { items, _ in moveDroppedTabs(items, to: group.tabs.count) }
                .onChange(of: group.activeTabID) { _, activeTabID in
                    withAnimation(.snappy) { scrollProxy.scrollTo(activeTabID, anchor: .center) }
                }
                // A restored side opens with its active tab in view, once the bar has its width.
                .task(id: group.id) {
                    await Task.yield()
                    scrollProxy.scrollTo(group.activeTabID, anchor: .center)
                }
            }
            #if canImport(UIKit)
            if showsPencilTools {
                let document = workspace.document(for: group.activeTabID)
                // A tab whose file is still loading has the sessions of the file before it.
                if let session = document.pdfSession, group.activeTab.path != nil, document.loadedPath == group.activeTab.path {
                    Hairline(axis: .vertical).frame(height: 18)
                    TabBarPencilTools(session: session, isFocused: isFocused)
                        .layoutPriority(1)
                }
            }
            #endif
            if showsDocumentControls {
                TabBarDocumentControls(tab: group.activeTab, document: workspace.document(for: group.activeTabID),
                                       defaultEditingMode: workspace.preferences.defaultEditingMode)
                    .padding(.horizontal, 4)
            }
            if showsDocumentControls || showsPencilTools {
                Hairline(axis: .vertical).frame(height: 18)
            }
            groupButtons
                .padding(.leading, 2).padding(.trailing, 8)
        }
        .frame(height: GraphiteChrome.barHeight)
        // The page's own color, so the tabs read as the document's header rather than a
        // band of their own.
        .background(isDropTargeted ? AnyShapeStyle(accent.opacity(0.12)) : AnyShapeStyle(GraphiteChrome.barBackground))
        // A file dragged from the sidebar opens in a new tab on this side.
        .dropDestination(for: VaultItemTransfer.self) { items, _ in
            let paths = items.compactMap { item in try? VaultPath(item.path) }.filter { path in !workspace.isDirectory(path) }
            guard !paths.isEmpty else { return false }
            workspace.focusGroup(group.id)
            Task { for path in paths { await workspace.open(path, placement: .newTab) } }
            return true
        } isTargeted: { isTargeted in isDropTargeted = isTargeted }
    }

    private func moveDroppedTabs(_ items: [TabTransfer], to position: Int) -> Bool {
        guard let item = items.first, layout.tab(withID: item.tabID) != nil else { return false }
        workspace.moveTab(item.tabID, toGroup: group.id, at: position)
        return true
    }

    @ViewBuilder private var groupButtons: some View {
        HStack(spacing: 2) {
            Button("New Tab", systemImage: "plus") { workspace.openNewTab(inGroup: group.id) }
                .help("New tab (⌘T)")
            if layout.isSplit && !showsBothGroups {
                // Only one side fits; this shows the other one.
                Button("Show Other Side", systemImage: "arrow.left.arrow.right") {
                    if let other = layout.otherGroup(than: group.id) { workspace.focusGroup(other.id) }
                }
            } else if layout.isSplit {
                Button("Close This Side", systemImage: "xmark.rectangle") { Task { await workspace.closeGroup(group.id) } }
                    .help("Close this side of the split and its tabs")
            } else {
                Button("Split Right", systemImage: "rectangle.split.2x1") { workspace.splitRight() }
                    .help("Open a second side, to keep a note beside a PDF")
            }
        }
        .labelStyle(.iconOnly)
        .buttonStyle(QuietIconButtonStyle())
    }

    @ViewBuilder private func tabMenu(for tab: WorkspaceTab) -> some View {
        Button("Close", systemImage: "xmark") { Task { await workspace.closeTab(tab.id) } }
        Button("Close Other Tabs", systemImage: "xmark.square") { Task { await workspace.closeOtherTabs(keeping: tab.id) } }
            .disabled(group.tabs.count == 1)
        Divider()
        Button(tab.isPinned ? "Unpin" : "Pin", systemImage: tab.isPinned ? "pin.slash" : "pin") { workspace.togglePin(tab.id) }
        Button(groupIndex == 0 ? "Move to the Right" : "Move to the Left", systemImage: groupIndex == 0 ? "rectangle.righthalf.inset.filled.arrow.right" : "rectangle.lefthalf.inset.filled.arrow.left") {
            workspace.moveTabToOtherGroup(tab.id)
        }
        .disabled(!layout.isSplit && group.tabs.count == 1 && tab.path == nil)
        if let path = tab.path {
            Divider()
            Button("Reveal in Sidebar", systemImage: "scope") {
                workspace.activateTab(tab.id)
                workspace.revealCurrentFile()
            }
            Button("Rename…", systemImage: "pencil") { workspace.fileSheet = .rename(path) }
        }
    }

    private func title(of tab: WorkspaceTab) -> String {
        tab.path.map { path in workspace.preferences.displayName(for: path) } ?? "New Tab"
    }
}

/// A tab as Minimal draws one: the name alone, muted until it is the tab in use, which
/// takes full strength text and a faint fill. Notes, which most tabs show, go without an
/// icon; other files keep a small one. The close button shows on the tab in use and under
/// the pointer, and keeps its room on the others so a tab does not change width when it
/// is chosen; every tab can be closed from its menu and by VoiceOver.
private struct TabItem: View {
    let tab: WorkspaceTab
    let title: String
    let isActive: Bool
    /// Marks the active tab of the focused side when both sides are shown.
    let marksFocus: Bool
    let activate: () -> Void
    let close: () -> Void
    /// The widest the tab grows; beside the Pencil tools, what their tab area shows, so a
    /// long name ends with an ellipsis and keeps its close button instead of being cut off.
    var maximumWidth: CGFloat = 220
    @Environment(\.accent) private var accent
    @State private var isPointerOver = false

    private var kindSymbol: String? {
        guard let path = tab.path else { return nil }
        let kind = DocumentKind(path: path)
        return kind == .markdown ? nil : kind.systemImage
    }

    private var showsCloseButton: Bool { isActive || isPointerOver }

    var body: some View {
        HStack(spacing: 6) {
            if let kindSymbol {
                Image(systemName: kindSymbol)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            Text(title)
                .font(.subheadline)
                .fontWeight(isActive ? .medium : .regular)
                .foregroundStyle(isActive ? .primary : .secondary)
                .lineLimit(1)
            if tab.isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .accessibilityLabel("Pinned")
            } else {
                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .tint(.secondary)
                .opacity(showsCloseButton ? 1 : 0)
                .allowsHitTesting(showsCloseButton)
                .accessibilityHidden(!showsCloseButton)
                .accessibilityLabel("Close \(title)")
            }
        }
        .padding(.leading, 12).padding(.trailing, tab.isPinned ? 12 : 6)
        .frame(minWidth: min(88, maximumWidth), maxWidth: maximumWidth, minHeight: 30)
        .background(isActive ? GraphiteChrome.selectedFill : Color.clear,
                    in: RoundedRectangle(cornerRadius: GraphiteChrome.cornerRadius, style: .continuous))
        .overlay(alignment: .bottom) {
            if isActive && marksFocus {
                Capsule().fill(accent).frame(height: 2).padding(.horizontal, 12)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: GraphiteChrome.cornerRadius, style: .continuous))
        .onTapGesture(perform: activate)
        .onHover { isOver in isPointerOver = isOver }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction(named: "Close", close)
    }
}

/// A muted icon button with a faint fill while pressed, for the small buttons of bars
/// outside the window's toolbar.
struct QuietIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15))
            .foregroundStyle(.secondary)
            .frame(width: 32, height: 30)
            .background(configuration.isPressed ? GraphiteChrome.selectedFill : Color.clear,
                        in: RoundedRectangle(cornerRadius: GraphiteChrome.cornerRadius, style: .continuous))
            .contentShape(Rectangle())
    }
}

// MARK: Divider

/// The line between the two sides; dragging it resizes them, and a double tap evens them.
private struct SplitDivider: View {
    static let width: CGFloat = 11
    static let coordinateSpaceName = "WorkspacePanes"
    let fraction: Double
    let drag: (CGFloat) -> Void
    let endDrag: () -> Void
    let setFraction: (Double) -> Void

    var body: some View {
        ZStack {
            Rectangle().fill(.separator).frame(width: 1)
            Capsule().fill(.tertiary).frame(width: 5, height: 40)
        }
        .frame(width: Self.width)
        .frame(maxHeight: .infinity)
        .contentShape(Rectangle())
        // Measured in the panes' space: the divider itself moves while it is dragged.
        .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .named(Self.coordinateSpaceName))
            .onChanged { value in drag(value.translation.width) }
            .onEnded { _ in endDrag() })
        .onTapGesture(count: 2) { setFraction(0.5) }
        .accessibilityElement()
        .accessibilityLabel("Divider between the two sides")
        .accessibilityValue("\(Int((fraction * 100).rounded())) percent for the left side")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: setFraction(fraction + 0.05)
            case .decrement: setFraction(fraction - 0.05)
            @unknown default: break
            }
        }
    }
}

// MARK: Tab content

/// The document of one tab, loaded when the tab is first shown.
private struct TabDocumentView: View {
    @Bindable var workspace: WorkspaceModel
    let tab: WorkspaceTab
    @Bindable var document: TabDocument
    let isFocused: Bool
    @Binding var showsLinksInspector: Bool
    let create: (CreationKind) -> Void
    let showQuickSwitcher: () -> Void

    /// Drawing on a standalone image saves the drawing beside it; nil where drawings are off
    /// or the file is not a raster image Graphite can decode.
    private func drawOnImageAction(for path: VaultPath) -> (() -> Void)? {
        #if canImport(UIKit)
        guard workspace.preferences.isEnabled(.drawings), DrawableImages.canDrawOn(path) else { return nil }
        return { Task { await workspace.beginDrawingOnImage(at: path, fromNote: nil) } }
        #else
        return nil
        #endif
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay { if document.isOpening { DelayedProgressView() } }
            .task(id: tab.path) { await workspace.loadDocumentIfNeeded(for: tab.id) }
    }

    @ViewBuilder private var content: some View {
        if let path = tab.path {
            if document.loadedPath == path {
                loadedContent(path)
            } else if let failure = document.loadFailure, failure.path == path, failure.needsPassword {
                PDFPasswordPrompt(fileName: path.name, message: failure.message) { password in
                    Task { await workspace.unlockPDF(inTab: tab.id, password: password) }
                }
            } else if let failure = document.loadFailure, failure.path == path {
                ContentUnavailableView {
                    Label("“\(path.name)” Can't Be Opened", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(failure.message)
                } actions: {
                    HStack {
                        Button("Try Again", systemImage: "arrow.clockwise") { Task { await workspace.retryLoading(tabID: tab.id) } }
                        Button("Close Tab", systemImage: "xmark") { Task { await workspace.closeTab(tab.id) } }
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                // Loading; the overlay shows progress once it takes long enough to notice.
                Color.clear
            }
        } else {
            EmptyTabView(workspace: workspace, tabID: tab.id, create: create, showQuickSwitcher: showQuickSwitcher)
        }
    }

    @ViewBuilder private func loadedContent(_ path: VaultPath) -> some View {
        if let session = document.markdownSession {
            MarkdownPane(session: session, workspace: workspace, document: document, tabID: tab.id, isFocused: isFocused,
                         showsLinksInspector: $showsLinksInspector)
                .id(ObjectIdentifier(session))
        } else if let session = document.pdfSession {
            PDFPane(session: session, isFocused: isFocused, focus: { workspace.activateTab(tab.id) }, linkActions: pdfLinkActions(for: path)) { location in
                Task { await workspace.resolvePDFConflict(opening: location, inTab: tab.id) }
            }
        } else if let session = document.canvasSession {
            CanvasPane(session: session, workspace: workspace, tabID: tab.id, isFocused: isFocused)
                .id(ObjectIdentifier(session))
        } else if let root = workspace.folderAccess?.root, let location = try? path.url(in: root) {
            switch DocumentKind(path: path) {
            case .base where workspace.preferences.isEnabled(.bases):
                if let store = workspace.store, let index = workspace.index {
                    BaseDocumentView(path: path, viewName: document.baseViewRequest.flatMap { request in request.path == path ? request.viewName : nil },
                                     store: store, index: index, contentVersion: workspace.indexVersion,
                                     isIndexComplete: workspace.hasCompletedIndexScan,
                                     open: { target in Task { await workspace.open(target) } },
                                     filesChanged: { paths in workspace.filesSavedOutsideEditors(paths) })
                }
            case .media:
                // One player per file: its playback, size and duration are not carried over
                // when the tab opens another recording or video.
                Group {
                    if MediaFileKind.audioExtensions.contains(path.fileExtension) {
                        EmbeddedAudioPlayer(location: location, name: path.name)
                    } else {
                        EmbeddedMediaPlayer(location: location)
                    }
                }
                .id(path)
                .padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
            case .image, .pdf:
                // A PDF reaches here only when it is a Graphite drawing (see WorkspaceModel.load).
                ImagePane(location: location, path: path, drawingVersion: workspace.drawingVersion, isFocused: isFocused, editDrawing: {
                    #if canImport(UIKit)
                    Task { await workspace.beginEditingDrawing(at: path) }
                    #endif
                }, drawOnImage: drawOnImageAction(for: path))
            default:
                FilePreviewPane(location: location)
            }
        }
    }
}

extension TabDocumentView {
    /// Links to the PDF's pages and quotes from it, for the note on the other side when
    /// there is one, else for the pasteboard.
    fileprivate func pdfLinkActions(for pdf: VaultPath) -> PDFLinkActions {
        let note = workspace.noteOnOtherSide(of: tab.id)
        let workspace = workspace
        return PDFLinkActions(
            copyLink: { pageIndex in
                Task { Pasteboard.copy(await workspace.pdfPageLink(to: pdf, pageIndex: pageIndex, for: note?.path)) }
            },
            copyQuote: { pageIndex, text in
                Task { Pasteboard.copy(PDFCitation.quote(text, link: await workspace.pdfPageLink(to: pdf, pageIndex: pageIndex, for: note?.path))) }
            },
            quoteInNote: note.map { note in
                { pageIndex, text in
                    Task {
                        let quote = PDFCitation.quote(text, link: await workspace.pdfPageLink(to: pdf, pageIndex: pageIndex, for: note.path))
                        // At the cursor once the person has placed it; else at the end, so
                        // quotes collect in reading order.
                        let endOfNote = NSRange(location: (note.text as NSString).length, length: 0)
                        note.insertBlock(quote, at: note.hasPlacedCursor ? nil : endOfNote, separatedByBlankLines: true)
                    }
                }
            },
            noteName: note.map { note in workspace.preferences.displayName(for: note.path) })
    }
}

/// Plain text on the system pasteboard.
enum Pasteboard {
    static func copy(_ text: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = text
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }
}

/// Asks for the password of a protected PDF. The password stays in memory until Graphite quits.
private struct PDFPasswordPrompt: View {
    let fileName: String
    let message: String
    let unlock: (String) -> Void
    @State private var password = ""
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        ContentUnavailableView {
            Label("“\(fileName)” Is Locked", systemImage: "lock.doc")
        } description: {
            Text(message + " Graphite shows protected PDFs without changing them.")
        } actions: {
            HStack {
                SecureField("Password", text: $password)
                    .textContentType(.password)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 240)
                    .focused($isFieldFocused)
                    .onSubmit(submit)
                Button("Unlock", action: submit)
                    .buttonStyle(.borderedProminent)
                    .disabled(password.isEmpty)
            }
        }
        .onAppear { isFieldFocused = true }
    }

    private func submit() {
        guard !password.isEmpty else { return }
        unlock(password)
        password = ""
    }
}

/// A new tab, as Obsidian shows it: a short column of quiet links to create or find a
/// file, then recent files. It fits a phone's width, where a row of buttons did not.
private struct EmptyTabView: View {
    @Bindable var workspace: WorkspaceModel
    let tabID: UUID
    let create: (CreationKind) -> Void
    let showQuickSwitcher: () -> Void
    @Environment(\.accent) private var accent
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    private static let recentFileCount = 6

    private var recentFiles: [VaultPath] {
        workspace.existingRecentFiles(limit: Self.recentFileCount, excluding: Set(workspace.layout.allTabs.compactMap(\.path)))
    }

    private var canClose: Bool { workspace.layout.isSplit || workspace.layout.focusedGroup.tabs.count > 1 }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 36) {
                VStack(alignment: .leading, spacing: 14) {
                    Text("No file is open")
                        .font(.title3.weight(.semibold))
                        .padding(.bottom, 4)
                    action("Create new note", shortcut: "⌘N") { focusThen { create(.note) } }
                    action("Create new notebook") { focusThen { create(.notebook) } }
                    if workspace.preferences.isEnabled(.bases) {
                        action("Create new base") { focusThen { create(.base) } }
                    }
                    if workspace.preferences.isEnabled(.canvas) {
                        action("Create new canvas") { focusThen { create(.canvas) } }
                    }
                    action("Go to file", shortcut: "⌘O") { focusThen(showQuickSwitcher) }
                    if canClose {
                        action("Close", shortcut: "⌘W") { Task { await workspace.closeTab(tabID) } }
                    }
                }
                if !recentFiles.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Recent files")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.bottom, 6)
                        ForEach(recentFiles, id: \.self) { path in
                            Button {
                                focusThen { Task { await workspace.open(path) } }
                            } label: {
                                HStack(spacing: 8) {
                                    Text(workspace.preferences.displayName(for: path))
                                        .foregroundStyle(Color.primary)
                                        .lineLimit(1)
                                    if !path.parent.rawValue.isEmpty {
                                        Text(path.parent.rawValue)
                                            .font(.footnote)
                                            .foregroundStyle(Color.secondary)
                                            .lineLimit(1)
                                            .truncationMode(.head)
                                    }
                                    Spacer(minLength: 0)
                                }
                                .padding(.vertical, 6)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .frame(maxWidth: 360, alignment: .leading)
            .padding(.horizontal, 28)
            .padding(.vertical, 56)
            .frame(maxWidth: .infinity)
        }
    }

    /// A link in the accent, with its keyboard shortcut muted beside it where it has one.
    private func action(_ title: String, shortcut: String? = nil, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            HStack(spacing: 8) {
                Text(title).foregroundStyle(accent)
                // A phone has no keyboard to press them on.
                if let shortcut, horizontalSizeClass != .compact {
                    Text(shortcut)
                        .font(.footnote.monospaced())
                        .foregroundStyle(Color.secondary)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Focuses this tab first, so what is created or chosen opens here.
    private func focusThen(_ action: () -> Void) {
        workspace.activateTab(tabID)
        action()
    }
}

#if canImport(UIKit)
/// Reports where touches begin anywhere in the window, without taking part in gesture
/// recognition: the recognizer fails at once and never delays or cancels a touch.
private struct WindowTouchObserver: UIViewRepresentable {
    let touchBegan: (CGPoint) -> Void

    func makeUIView(context: Context) -> ObserverAnchorView {
        let view = ObserverAnchorView()
        view.isUserInteractionEnabled = false
        view.touchBegan = touchBegan
        return view
    }

    func updateUIView(_ view: ObserverAnchorView, context: Context) {
        view.touchBegan = touchBegan
    }

    static func dismantleUIView(_ view: ObserverAnchorView, coordinator: ()) {
        view.removeRecognizer()
    }

    final class ObserverAnchorView: UIView {
        var touchBegan: ((CGPoint) -> Void)? {
            didSet { recognizer.touchBegan = touchBegan }
        }
        private let recognizer = PassiveTouchRecognizer()

        override func didMoveToWindow() {
            super.didMoveToWindow()
            recognizer.view?.removeGestureRecognizer(recognizer)
            window?.addGestureRecognizer(recognizer)
        }

        func removeRecognizer() {
            recognizer.view?.removeGestureRecognizer(recognizer)
        }
    }

    final class PassiveTouchRecognizer: UIGestureRecognizer {
        var touchBegan: ((CGPoint) -> Void)?

        override init(target: Any? = nil, action: Selector? = nil) {
            super.init(target: target, action: action)
            cancelsTouchesInView = false
            delaysTouchesBegan = false
            delaysTouchesEnded = false
        }

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
            defer { state = .failed }
            // Only touches on the window's own content: a sheet, a menu, or a popover in
            // front of the panes does not focus the side beneath it.
            guard let touch = touches.first, let window = view as? UIWindow, let rootViewController = window.rootViewController,
                  rootViewController.presentedViewController == nil,
                  let touchedView = touch.view, touchedView.isDescendant(of: rootViewController.view) else { return }
            touchBegan?(touch.location(in: window))
        }

        override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool { false }
        override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    }
}
#endif

/// Appears only when opening takes long enough to notice, avoiding a flash.
struct DelayedProgressView: View {
    @State private var isVisible = false
    var body: some View {
        ProgressView().controlSize(.large)
            .opacity(isVisible ? 1 : 0)
            .task {
                do { try await Task.sleep(for: .milliseconds(300)); isVisible = true } catch {}
            }
    }
}

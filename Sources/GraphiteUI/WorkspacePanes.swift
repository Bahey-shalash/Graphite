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
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    /// The split when a divider drag began.
    @State private var dragStartFraction: Double?
    /// Where each side is in the window, to focus the side a touch lands on.
    @State private var groupFrames: [UUID: CGRect] = [:]

    private var showsBothGroups: Bool { workspace.layout.isSplit && horizontalSizeClass != .compact }

    var body: some View {
        panes
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
                     create: create, showQuickSwitcher: showQuickSwitcher)
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

    var body: some View {
        let tab = group.activeTab
        VStack(spacing: 0) {
            TabBar(workspace: workspace, group: group, isFocused: isFocused, showsBothGroups: showsBothGroups)
            Divider()
            TabDocumentView(workspace: workspace, tab: tab, document: workspace.document(for: tab.id), isFocused: isFocused,
                            showsLinksInspector: $showsLinksInspector, create: create, showQuickSwitcher: showQuickSwitcher)
                .id(tab.id)
        }
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

    @State private var isDropTargeted = false
    @Environment(\.accent) private var accent
    private var layout: TabLayout { workspace.layout }
    private var groupIndex: Int { layout.groups.firstIndex { candidate in candidate.id == group.id } ?? 0 }

    var body: some View {
        HStack(spacing: 4) {
            ScrollViewReader { scrollProxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 2) {
                        ForEach(Array(group.tabs.enumerated()), id: \.element.id) { position, tab in
                            TabItem(tab: tab, title: title(of: tab), isActive: tab.id == group.activeTabID,
                                    marksFocus: isFocused && showsBothGroups,
                                    activate: { workspace.activateTab(tab.id) },
                                    close: { Task { await workspace.closeTab(tab.id) } })
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
                    .padding(.horizontal, 6)
                    .frame(maxHeight: .infinity)
                }
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
            Divider().frame(height: 20)
            groupButtons
                .padding(.leading, 6).padding(.trailing, 8)
        }
        .frame(height: 40)
        .background(isDropTargeted ? AnyShapeStyle(accent.opacity(0.18)) : AnyShapeStyle(TabBarColors.bar))
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
        HStack(spacing: 14) {
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
        .buttonStyle(.borderless)
        .tint(.primary)
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

private struct TabItem: View {
    let tab: WorkspaceTab
    let title: String
    let isActive: Bool
    /// Marks the active tab of the focused side when both sides are shown.
    let marksFocus: Bool
    let activate: () -> Void
    let close: () -> Void
    @Environment(\.accent) private var accent

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: tab.path.map { path in DocumentKind(path: path).systemImage } ?? "doc")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.callout)
                .foregroundStyle(isActive ? .primary : .secondary)
                .lineLimit(1)
            if tab.isPinned {
                Image(systemName: "pin.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Pinned")
            } else {
                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(.caption2.weight(.semibold))
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .tint(.secondary)
                .accessibilityLabel("Close \(title)")
            }
        }
        .padding(.leading, 10).padding(.trailing, tab.isPinned ? 10 : 4)
        .frame(minWidth: 96, maxWidth: 220, minHeight: 32)
        .background(isActive ? TabBarColors.activeTab : Color.clear, in: RoundedRectangle(cornerRadius: 8))
        .overlay(alignment: .bottom) {
            if isActive && marksFocus {
                Capsule().fill(accent).frame(height: 2).padding(.horizontal, 10)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .onTapGesture(perform: activate)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction(named: "Close", close)
    }
}

private enum TabBarColors {
    #if canImport(UIKit)
    static let bar = Color(uiColor: .secondarySystemBackground)
    static let activeTab = Color(uiColor: .systemBackground)
    #else
    static let bar = Color(nsColor: .underPageBackgroundColor)
    static let activeTab = Color(nsColor: .textBackgroundColor)
    #endif
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
                ImagePane(location: location, path: path, drawingVersion: workspace.drawingVersion, isFocused: isFocused) {
                    #if canImport(UIKit)
                    Task { await workspace.beginEditingDrawing(at: path) }
                    #endif
                }
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

/// A new tab, as Obsidian shows it: ways to create or find a file, and recent files.
private struct EmptyTabView: View {
    @Bindable var workspace: WorkspaceModel
    let tabID: UUID
    let create: (CreationKind) -> Void
    let showQuickSwitcher: () -> Void
    private static let recentFileCount = 6

    private var recentFiles: [VaultPath] {
        workspace.existingRecentFiles(limit: Self.recentFileCount, excluding: Set(workspace.layout.allTabs.compactMap(\.path)))
    }

    private var canClose: Bool { workspace.layout.isSplit || workspace.layout.focusedGroup.tabs.count > 1 }

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                ContentUnavailableView {
                    Label("No File Open", systemImage: "doc.text")
                } description: {
                    Text("Choose a file in the sidebar, find one, or create a new one.")
                } actions: {
                    VStack(spacing: 12) {
                        HStack {
                            Button("New Note", systemImage: "square.and.pencil") { focusThen { create(.note) } }
                            Button("New Notebook", systemImage: "book.closed") { focusThen { create(.notebook) } }
                            if workspace.preferences.isEnabled(.bases) {
                                Button("New Base", systemImage: "tablecells") { focusThen { create(.base) } }
                            }
                        }
                        HStack {
                            Button("Go to File…", systemImage: "doc.text.magnifyingglass") { focusThen(showQuickSwitcher) }
                            if canClose {
                                Button("Close Tab", systemImage: "xmark") { Task { await workspace.closeTab(tabID) } }
                            }
                        }
                    }
                    .buttonStyle(.bordered)
                }
                if !recentFiles.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Recent files").font(.headline).padding(.bottom, 4)
                        ForEach(recentFiles, id: \.self) { path in
                            Button {
                                focusThen { Task { await workspace.open(path) } }
                            } label: {
                                Label(workspace.preferences.displayName(for: path), systemImage: DocumentKind(path: path).systemImage)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.borderless)
                            .padding(.vertical, 4)
                        }
                    }
                    .frame(maxWidth: 360)
                }
            }
            .padding(.vertical, 40)
            .frame(maxWidth: .infinity)
        }
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

import SwiftUI
import QuickLook
import GraphiteCore
import GraphiteApple
import GraphiteIndex

public struct GraphiteRootView: View {
    @State private var workspace = WorkspaceModel()
    /// The Mac shows Settings in its own window (`GraphiteMacScenes`).
    @State private var showsSettings = false
    /// Settings › Read Aloud › Floating Player; off keeps the controls in the toolbar.
    @AppStorage("GraphiteReadAloudFloatingPlayer") private var usesFloatingPlayer = true
    /// `graphite://` links wait until the last vault has reopened.
    @State private var isVaultRestored = false
    @State private var pendingLinks: [URL] = []
    @State private var opensVaultManagerAfterSettings = false
    @State private var creation: CreationRequest?
    @State private var showsInspector = false
    @State private var activePalette: ActivePalette?
    @State private var columnVisibility = NavigationSplitViewVisibility.automatic
    /// On a phone the split view is one stack: the document comes first, as in Obsidian
    /// mobile, and the file list is a step back.
    @State private var preferredCompactColumn = NavigationSplitViewColumn.detail
    @State private var showsTabSwitcher = false
    /// Whether the software keyboard, or the note's keyboard toolbar alone with a hardware
    /// keyboard, is on screen.
    @State private var isKeyboardShown = false
    @State private var focusMode = WorkspaceFocusMode()
    /// In automatic mode an iPad shows only the detail column when the window is taller
    /// than wide, so toggling the sidebar has to know the window's shape.
    @State private var isWindowTallerThanWide = false
    /// True until the remembered vault has opened or failed to, so the welcome screen does
    /// not flash up before the vault appears.
    @State private var isRestoringVault = true
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #if os(macOS)
    @Environment(\.openSettings) private var openSettings
    #endif

    private enum ActivePalette { case quickSwitcher, commandPalette, templatePicker }

    /// A phone, or an iPad window as narrow as one. Tabs then live behind the tab button of
    /// the bottom bar, which also moves between files, and the navigation bar holds only the
    /// document's own controls.
    private var isCompactWidth: Bool { horizontalSizeClass == .compact }

    public init() {}

    /// For tests: the root view of a workspace already opened on a vault, which it does not
    /// replace with the last vault this device opened.
    init(workspace: WorkspaceModel) {
        _workspace = State(initialValue: workspace)
        _isRestoringVault = State(initialValue: false)
    }

    /// The root view of a workspace other scenes share, as the Mac's Settings window does.
    init(reopeningLastVaultIn workspace: WorkspaceModel) {
        _workspace = State(initialValue: workspace)
    }

    public var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility, preferredCompactColumn: $preferredCompactColumn) {
            // The binding of a stored state, which SwiftUI sees as the same each time: a binding
            // made anew for each update made the iPad's sidebar update again without end, and
            // the app never drew its first frame. The Mac's sidebar has no Settings button.
            VaultSidebar(workspace: workspace, creation: $creation, showsSettings: $showsSettings, showsVaultManager: $workspace.isVaultManagerPresented,
                         showDocument: showDocumentColumn)
                .navigationSplitViewColumnWidth(min: 260, ideal: 320, max: 480)
        } detail: {
            detailColumn
                .overlay {
                    if usesFloatingPlayer && workspace.readAloud.isActive && !workspace.recording.state.isActive && workspace.preferences.isEnabled(.readAloud) {
                        ReadAloudFloatingPlayer(reader: workspace.readAloud, navigator: workspace.readAloudNavigator)
                    }
                }
        }
        .onGeometryChange(for: Bool.self) { geometry in geometry.size.height > geometry.size.width } action: { isTallerThanWide in
            isWindowTallerThanWide = isTallerThanWide
        }
        .tint(workspace.preferences.accentColor)
        .onChange(of: columnVisibility) { _, requestedVisibility in
            if focusMode.isActive, requestedVisibility != .detailOnly {
                focusMode.leave(columnVisibility: &columnVisibility, showsInspector: &showsInspector)
                columnVisibility = requestedVisibility
            }
        }
        .onChange(of: showsInspector) { _, requestedInspector in
            if focusMode.isActive, requestedInspector {
                focusMode.leave(columnVisibility: &columnVisibility, showsInspector: &showsInspector)
                showsInspector = true
            }
        }
        .environment(\.accent, workspace.preferences.accentColor)
        // Notes, embeds and content lists draw in the vault's fonts (Settings › Appearance › Font).
        .environment(\.noteTypography, workspace.noteTypography)
        // Notes take the vault's Obsidian theme (Settings › Appearance › Use the Vault's Obsidian Theme).
        .environment(\.noteTheme, workspace.noteTheme)
        // Code blocks take the code theme chosen in Settings › Editor.
        .environment(\.codeColorTheme, workspace.preferences.codeColorTheme)
        // The menu bar's commands and their shortcuts act on this window (`GraphiteCommands`).
        .focusedSceneValue(\.workspaceMenuActions, WorkspaceMenuActions(workspace: workspace, window: windowActions,
                                                                          showCommandPalette: { activePalette = .commandPalette },
                                                                          save: { Task { await save() } }))
        .overlay { paletteOverlay }
        .animation(GraphiteMotion.animation(.snappy(duration: 0.18)), value: activePalette)
        #if canImport(UIKit)
        .sheet(isPresented: $showsSettings, onDismiss: {
            if opensVaultManagerAfterSettings { opensVaultManagerAfterSettings = false; workspace.isVaultManagerPresented = true }
        }) {
            SettingsView(workspace: workspace) { opensVaultManagerAfterSettings = true }
                .tint(workspace.preferences.accentColor)
                .presentationSizing(.page)
        }
        #endif
        .sheet(isPresented: $workspace.isVaultManagerPresented) {
            NavigationStack { VaultManagerView(workspace: workspace) }
                .tint(workspace.preferences.accentColor)
                .frame(minWidth: 480, minHeight: 360)
        }
        .sheet(isPresented: $showsTabSwitcher) {
            TabSwitcher(workspace: workspace)
                .tint(workspace.preferences.accentColor)
        }
        .sheet(isPresented: Binding(get: { workspace.readAloud.showsReader }, set: { showsReader in workspace.readAloud.showsReader = showsReader })) {
            ReadAloudReader(reader: workspace.readAloud)
                .tint(workspace.preferences.accentColor)
        }
        .onChange(of: workspace.recording.state) { _, state in
            // Narration does not reconfigure an active lecture recording's audio session.
            if state.isActive { workspace.readAloud.stop(); workspace.readAloud.showsReader = false }
        }
        .sheet(item: $creation) { request in
            let directory = workspace.newFileDirectory(request.directory)
            CreateDocumentSheet(kind: request.kind, folderDescription: directory.rawValue.isEmpty ? workspace.title : directory.rawValue) { name, paper, pageCount in
                Task {
                    switch request.kind {
                    case .note: await workspace.createNote(named: name, in: request.directory)
                    case .notebook: await workspace.createNotebook(named: name, paper: paper, pageCount: pageCount, in: request.directory)
                    case .base: await workspace.createBase(named: name, in: request.directory)
                    case .canvas: await workspace.createCanvas(named: name, in: request.directory)
                    }
                }
            }
        }
        .modifier(FileManagementPresentation(workspace: workspace))
        .modifier(CommunityPluginPresentation(workspace: workspace) { showSettings() })
        #if canImport(UIKit)
        .fullScreenCover(isPresented: $workspace.isGraphPresented) {
            VaultGraphScreen(workspace: workspace).tint(workspace.preferences.accentColor)
        }
        #else
        .sheet(isPresented: $workspace.isGraphPresented) {
            // The graph has no size of its own: without the page size it was drawn 470 by 152
            // points, its nodes squeezed into a line.
            VaultGraphScreen(workspace: workspace).tint(workspace.preferences.accentColor).presentationSizing(.page)
        }
        #endif
        #if canImport(UIKit)
        .fullScreenCover(isPresented: $workspace.isMapPresented) {
            VaultMapScreen(workspace: workspace).tint(workspace.preferences.accentColor)
        }
        #else
        .sheet(isPresented: $workspace.isMapPresented) {
            // A map wants room: the page size a Mac sheet offers, not its content's size.
            VaultMapScreen(workspace: workspace).tint(workspace.preferences.accentColor).presentationSizing(.page)
        }
        #endif
        .sheet(item: $workspace.fileRecoveryRequest) { request in
            FileRecoverySheet(workspace: workspace, request: request)
                .tint(workspace.preferences.accentColor)
        }
        #if canImport(UIKit)
        .fullScreenCover(item: $workspace.viewedImage) { path in
            if let root = workspace.folderAccess?.root, let location = try? path.url(in: root) {
                ImageViewer(location: location, title: path.name, drawOnImage: drawOnViewedImage(path))
            }
        }
        .fullScreenCover(item: $workspace.drawingEditorRequest) { request in
            DrawingEditor(request: request, noteDestination: workspace.lassoNoteDestination(for: request)) { content, format in
                try await workspace.saveDrawing(content, format: format, for: request)
            } exportCopy: { content, format in
                try await workspace.exportDrawingCopy(content, format: format, title: request.title)
            } preserveDraft: { content in
                guard let vaultIdentifier = workspace.currentVaultIdentifier else { return }
                Self.draftIdentifiersOpenInThisProcess.insert(request.id)
                DrawingEditorDraftStore.shared.preserve(DrawingEditorDraft(request: request, vaultIdentifier: vaultIdentifier)) {
                    try await DrawingFileService().draftFileData(for: content)
                }
            } removeDraft: {
                DrawingEditorDraftStore.shared.removeDraft(withIdentifier: request.id)
            }
        }
        .onChange(of: workspace.currentVaultIdentifier) { _, vaultIdentifier in
            if let vaultIdentifier { Task { await reopenDrawingDraft(forVault: vaultIdentifier) } }
        }
        #else
        // Tapping an image or choosing View Full Screen shows it in Quick Look, which zooms.
        .quickLookPreview(Binding(get: {
            guard let root = workspace.folderAccess?.root else { return nil }
            return workspace.viewedImage.flatMap { path in try? path.url(in: root) }
        }, set: { location in if location == nil { workspace.viewedImage = nil } }))
        #endif
        .messageAlert($workspace.errorMessage)
        .task {
            await workspace.restoreVault()
            isRestoringVault = false
            // Links that arrived while the last vault reopened, as when one launched Graphite.
            isVaultRestored = true
            let links = pendingLinks
            pendingLinks = []
            for link in links { await workspace.handle(link) }
        }
        // A search asked for from anywhere (⇧⌘F, a tag, a link) shows where it happens.
        .onChange(of: workspace.searchFocusRequest) { showSidebar() }
        // A plugin's sidebar view asked to be shown.
        .onChange(of: workspace.communityPlugins.sidebarViewRequest) { _, request in if request != nil { showSidebar() } }
        // A file opened from the list, a link or a search shows on a phone at once.
        .onChange(of: workspace.selection) { _, selection in
            if selection != nil { showDocumentColumn() }
        }
        #if canImport(UIKit)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in isKeyboardShown = true }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in isKeyboardShown = false }
        #endif
        .onOpenURL { url in
            if isVaultRestored { Task { await workspace.handle(url) } } else { pendingLinks.append(url) }
        }
        .onChange(of: scenePhase) { previousPhase, phase in
            // Taken at once as Graphite stops being active, not in the save that follows: by
            // the time that task runs, iPadOS can have resized the window for its app switcher
            // snapshots, and an editor laid out again then reports a line further down.
            if previousPhase == .active { workspace.rememberPlacesOfOpenDocuments() }
            if phase == .active {
                Task { await workspace.checkOpenDocumentsForExternalChanges(); await workspace.refreshDirectory(); await workspace.reloadVaultSettings() }
            } else {
                // Reading goes on in the background and on the lock screen, like an audiobook.
                saveBeforeLeavingScreen()
            }
        }
        .alert("Unfinished Recording", isPresented: Binding(get: { workspace.recordingRecoveryOffer != nil }, set: { isPresented in
            if !isPresented { workspace.recordingRecoveryOffer = nil }
        }), presenting: workspace.recordingRecoveryOffer) { unfinished in
            Button("Save to Vault") { Task { await workspace.recover(unfinished) } }
            Button("Delete Recording", role: .destructive) { workspace.discard(unfinished) }
            Button("Not Now", role: .cancel) {}
        } message: { unfinished in
            Text(recoveryMessage(for: unfinished))
        }
        .onChange(of: workspace.recording.lastCompletedURL) { _, completedLocation in
            if let completedLocation { Task { await workspace.recordingDidFinish(at: completedLocation) } }
        }
        .preferredColorScheme(workspace.preferences.appearanceMode.colorScheme)
    }

    private func recoveryMessage(for unfinished: RecoverableRecording) -> String {
        let started = unfinished.startedAt.formatted(date: .abbreviated, time: .shortened)
        let size = ByteCountFormatter.string(fromByteCount: Int64(unfinished.byteCount), countStyle: .file)
        let place = unfinished.destination.map { destination in "as “\(destination.name)” in “\(destination.parent.rawValue.isEmpty ? workspace.title : destination.parent.rawValue)”" }
            ?? "in this vault"
        return "A recording started \(started) (\(size)) was not finished, as when Graphite is closed while recording. It can be saved \(place), up to where it stopped."
    }

    private var detailColumn: some View {
        documentArea
            // Nothing a document view holds carries over to another vault.
            .id(workspace.currentVaultIdentifier)
            .overlay { RecordingPreviewOverlay(workspace: workspace) }
            .overlay(alignment: .top) { NoticeBanner(notice: $workspace.notice) }
            .onChange(of: workspace.selection) { workspace.notice = nil }
            // Editable, so the title bar's menu offers Rename, as for documents in Files.
            .modifier(DocumentTitle(title: titleBinding, isCompactWidth: isCompactWidth))
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { detailToolbar }
            #if canImport(UIKit)
            .toolbar { compactBottomBar }
            #endif
            .environment(\.showTemplatePicker, templatePickerAction)
            .environment(\.workspaceMoreMenuActions, isCompactWidth ? nil : workspaceMoreMenuActions)
            .environment(\.renameDocument, isCompactWidth ? DocumentRenameAction {
                if let path = workspace.selection { workspace.fileSheet = .rename(path) }
            } : nil)
            .inspector(isPresented: Binding(get: { showsInspector && workspace.markdownSession != nil }, set: { isPresented in showsInspector = isPresented })) {
                if let note = workspace.markdownSession { NoteLinksInspector(session: note, workspace: workspace).inspectorColumnWidth(min: 240, ideal: 280) }
            }
    }

    private var titleBinding: Binding<String> {
        Binding(get: { workspace.selection.map(displayName(for:)) ?? "" }, set: { newTitle in
            guard let path = workspace.selection else { return }
            let fileExtension = (path.name as NSString).pathExtension
            var newName = newTitle.trimmingCharacters(in: .whitespaces)
            if !fileExtension.isEmpty, newName.lowercased().hasSuffix("." + fileExtension.lowercased()) { newName = String(newName.dropLast(fileExtension.count + 1)) }
            Task { await workspace.rename(path, to: newName) }
        })
    }

    @ToolbarContentBuilder private var detailToolbar: some ToolbarContent {
        // A compact width moves these to the bottom bar (`compactBottomBar`), as Obsidian
        // mobile does, where they do not crowd the back button and the title. A regular
        // width keeps Back and Forward here and puts the Quick Switcher, the command palette
        // and Focus in the document's More menu (`WorkspaceMoreMenuItems`), so the toolbar
        // stays short enough for the title; Exit Focus stays in view while Focus hides the rest.
        if workspace.store != nil && !isCompactWidth {
            ToolbarItemGroup(placement: .navigation) {
                if focusMode.isActive {
                    Button("Exit Focus", systemImage: "arrow.down.right.and.arrow.up.left") { toggleFocusMode() }
                        .accessibilityIdentifier("workspaceFocusMode")
                        .help("Restore sidebars and tabs")
                        .tint(.primary)
                } else {
                    Group {
                        Button("Back", systemImage: "chevron.backward") { Task { await workspace.goBack() } }
                            .disabled(!workspace.history.canGoBack)
                        Button("Forward", systemImage: "chevron.forward") { Task { await workspace.goForward() } }
                            .disabled(!workspace.history.canGoForward)
                    }
                    .tint(.primary)
                }
            }
            // Notes, PDFs and canvases end their own More menu with these commands; other
            // documents and an empty tab have no menu of their own, so the window shows one.
            if !focusedDocumentHasMoreMenu {
                ToolbarItem(placement: .primaryAction) {
                    Menu("More", systemImage: "ellipsis") { WorkspaceMoreMenuItems() }
                        .tint(.primary)
                }
            }
        }
        if workspace.store != nil && showsRecordingControl {
            ToolbarItem(placement: .primaryAction) {
                RecordingControl(workspace: workspace)
                    .tint(.primary)
            }
        }
        if workspace.readAloud.isActive && !usesFloatingPlayer, workspace.preferences.isEnabled(.readAloud) {
            ToolbarItemGroup(placement: .primaryAction) {
                ReadAloudToolbarControls(reader: workspace.readAloud, isDisabled: workspace.recording.state.isActive,
                                         accentColor: workspace.preferences.accentColor)
                    .tint(.primary)
            }
        }
    }

    /// Whether the focused document puts a More menu of its own in the toolbar.
    private var focusedDocumentHasMoreMenu: Bool {
        workspace.markdownSession != nil || workspace.pdfSession != nil || workspace.canvasSession != nil
    }

    private var workspaceMoreMenuActions: WorkspaceMoreMenuActions {
        WorkspaceMoreMenuActions(showQuickSwitcher: { activePalette = .quickSwitcher },
                                 showCommandPalette: { activePalette = .commandPalette },
                                 toggleFocusMode: toggleFocusMode)
    }

    /// Whether the window's toolbar shows the recording control. A compact width shows it
    /// only while there is a recording to follow or a message about one: its navigation bar
    /// holds the document's own controls beside the title, and a recording starts from the
    /// command palette.
    private var showsRecordingControl: Bool {
        let recording = workspace.recording
        let hasRecordingToFollow = !recording.canStartRecording || recording.message != nil
        if isCompactWidth { return hasRecordingToFollow }
        return workspace.preferences.isEnabled(.audioRecorder) || recording.state.isActive
    }

    #if canImport(UIKit)
    /// Obsidian mobile's navigation bar: back and forward through the files seen, find a
    /// file, a new note, the open tabs, and the command palette. Only in compact widths;
    /// a PDF hides it while the palette docks at the bottom of the screen.
    @ToolbarContentBuilder private var compactBottomBar: some ToolbarContent {
        // The keyboard, and the note's keyboard toolbar, take over while typing, as in
        // Obsidian mobile; the two bars would otherwise stand one over the other.
        if workspace.store != nil && isCompactWidth && !isKeyboardShown && workspace.markdownSession?.isTyping != true {
            ToolbarItemGroup(placement: .bottomBar) {
                Group {
                    Button("Back", systemImage: "chevron.backward") { Task { await workspace.goBack() } }
                        .disabled(!workspace.history.canGoBack)
                    Button("Forward", systemImage: "chevron.forward") { Task { await workspace.goForward() } }
                        .disabled(!workspace.history.canGoForward)
                    Spacer()
                    Button("Quick Switcher", systemImage: "magnifyingglass") { activePalette = .quickSwitcher }
                    Spacer()
                    Button("New Note", systemImage: "square.and.pencil") { creation = CreationRequest(kind: .note) }
                    Spacer()
                    Button { showsTabSwitcher = true } label: {
                        TabCountLabel(count: workspace.layout.allTabs.count)
                    }
                    .accessibilityLabel("Tabs")
                    .accessibilityValue(workspace.layout.allTabs.count == 1 ? "1 open" : "\(workspace.layout.allTabs.count) open")
                    Spacer()
                    Button("Command Palette", systemImage: "command") { activePalette = .commandPalette }
                }
                .tint(.primary)
            }
        }
    }
    #endif

    @ViewBuilder private var paletteOverlay: some View {
        if let activePalette, workspace.store != nil {
            PaletteOverlay(close: { self.activePalette = nil }) {
                switch activePalette {
                case .quickSwitcher:
                    QuickSwitcher(workspace: workspace) { self.activePalette = nil }
                case .templatePicker:
                    TemplatePicker(workspace: workspace) { self.activePalette = nil }
                case .commandPalette:
                    CommandPalette(commands: WorkspaceCommandList.commands(for: workspace, window: windowActions),
                                   recentCommandIdentifiers: Binding(get: { workspace.preferences.recentCommandIdentifiers },
                                                                     set: { identifiers in workspace.preferences.recentCommandIdentifiers = identifiers })) {
                        self.activePalette = nil
                    }
                }
            }
        }
    }

    @ViewBuilder private var documentArea: some View {
        if workspace.store == nil && isRestoringVault && workspace.vaultLibrary.list.mostRecentlyOpened != nil {
            DelayedProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if workspace.store == nil {
            VaultManagerView(workspace: workspace, isPresentedAsSheet: false)
                .frame(maxWidth: 600)
                .frame(maxWidth: .infinity)
        } else {
            WorkspacePanes(workspace: workspace, showsLinksInspector: $showsInspector,
                           create: { kind in creation = CreationRequest(kind: kind) },
                           showQuickSwitcher: { activePalette = .quickSwitcher },
                           acceptsFocusTouches: activePalette == nil, showsTabBar: !focusMode.isActive && !isCompactWidth)
        }
    }

    private var windowActions: WindowActions {
        WindowActions(showQuickSwitcher: { activePalette = .quickSwitcher },
                      showSettings: showSettings,
                      showVaultManager: { workspace.isVaultManagerPresented = true },
                      toggleLinksInspector: { showsInspector.toggle() },
                      toggleSidebar: {
                          if isCompactWidth {
                              preferredCompactColumn = preferredCompactColumn == .sidebar ? .detail : .sidebar
                          } else {
                              columnVisibility = Self.sidebarVisibility(toggling: columnVisibility, automaticHidesSidebar: automaticHidesSidebar)
                          }
                      },
                      showSidebar: showSidebar,
                      showLinksInspector: { showsInspector = true },
                      create: { kind in creation = CreationRequest(kind: kind) },
                      showTemplatePicker: showTemplatePicker,
                      toggleFocusMode: toggleFocusMode)
    }

    private func showSettings() {
        #if os(macOS)
        openSettings()
        #else
        showsSettings = true
        #endif
    }

    private var templatePickerAction: TemplatePickerAction? {
        guard workspace.preferences.isEnabled(.templates) else { return nil }
        return TemplatePickerAction { showTemplatePicker() }
    }

    /// Opens the template list; the command palette closes first, so the list opens after it.
    private func showTemplatePicker() {
        guard workspace.markdownSession != nil else { return }
        if activePalette == nil { activePalette = .templatePicker; return }
        activePalette = nil
        Task {
            try? await Task.sleep(for: .milliseconds(250))
            activePalette = .templatePicker
        }
    }

    private func displayName(for path: VaultPath) -> String {
        workspace.preferences.displayName(for: path)
    }

    private func save() async {
        do { try await workspace.saveOpenDocuments() }
        catch { workspace.errorMessage = error.localizedDescription }
    }

    private func saveBeforeLeavingScreen() {
        #if canImport(UIKit)
        // Without it the system can suspend a slow coordinated write, such as one to iCloud
        // Drive, as soon as the app is off screen, and end the app before it finishes.
        let backgroundTask = BackgroundTaskAssertion(name: "Save open documents")
        Task {
            await save()
            // Plugins' views of files (an Excalidraw drawing) save what they hold too, as when
            // Obsidian closes; their writes go through the vault like any plugin write.
            await workspace.communityPlugins.saveOpenFileViews()
            backgroundTask.end()
        }
        #else
        Task {
            await save()
            await workspace.communityPlugins.saveOpenFileViews()
        }
        #endif
    }

    static func sidebarVisibility(toggling visibility: NavigationSplitViewVisibility, automaticHidesSidebar: Bool) -> NavigationSplitViewVisibility {
        isSidebarHidden(visibility, automaticHidesSidebar: automaticHidesSidebar) ? .all : .detailOnly
    }

    /// The visibility that shows the sidebar, which holds the search field; a sidebar
    /// already on screen stays as it is.
    static func sidebarVisibility(revealing visibility: NavigationSplitViewVisibility, automaticHidesSidebar: Bool) -> NavigationSplitViewVisibility {
        isSidebarHidden(visibility, automaticHidesSidebar: automaticHidesSidebar) ? .all : visibility
    }

    private static func isSidebarHidden(_ visibility: NavigationSplitViewVisibility, automaticHidesSidebar: Bool) -> Bool {
        visibility == .detailOnly || (visibility == .automatic && automaticHidesSidebar)
    }

    /// In automatic mode an iPad shows only the detail column while the window is taller
    /// than wide.
    private var automaticHidesSidebar: Bool {
        #if os(iOS)
        isWindowTallerThanWide
        #else
        false
        #endif
    }

    private func showSidebar() {
        focusMode.leave(columnVisibility: &columnVisibility, showsInspector: &showsInspector)
        if isCompactWidth { preferredCompactColumn = .sidebar }
        columnVisibility = Self.sidebarVisibility(revealing: columnVisibility, automaticHidesSidebar: automaticHidesSidebar)
    }

    /// On a phone, shows the document rather than the file list; elsewhere both are shown
    /// as they are.
    private func showDocumentColumn() {
        if isCompactWidth { preferredCompactColumn = .detail }
    }

    private func toggleFocusMode() {
        withAnimation(GraphiteMotion.animation(.snappy)) {
            if focusMode.isActive {
                focusMode.leave(columnVisibility: &columnVisibility, showsInspector: &showsInspector)
            } else {
                focusMode.enter(columnVisibility: &columnVisibility, showsInspector: &showsInspector)
            }
        }
    }

    #if canImport(UIKit)
    /// Closes the full-screen viewer and opens the drawing editor over its image; nil where
    /// the image did not come from a note, is not a picture to draw on, or drawings are off.
    private func drawOnViewedImage(_ path: VaultPath) -> (() -> Void)? {
        guard workspace.preferences.isEnabled(.drawings), DrawableImages.canDrawOn(path), let notePath = workspace.viewedImageNote else { return nil }
        return {
            workspace.viewedImage = nil
            Task { await workspace.beginDrawingOnImage(at: path, fromNote: notePath) }
        }
    }

    /// Drafts whose editor this process has open or has already reopened. Only a draft left
    /// by an ended process is reopened, never one still open in another window.
    @MainActor private static var draftIdentifiersOpenInThisProcess: Set<UUID> = []

    /// Reopens a drawing whose editor was open when the system ended the app, with its
    /// unsaved strokes, as if the app had never left.
    private func reopenDrawingDraft(forVault vaultIdentifier: UUID) async {
        let recoveredDrafts = await DrawingEditorDraftStore.shared.drafts(forVault: vaultIdentifier)
        guard let recoveredDraft = recoveredDrafts.first(where: { recoveredDraft in !Self.draftIdentifiersOpenInThisProcess.contains(recoveredDraft.draft.requestIdentifier) }),
              workspace.currentVaultIdentifier == vaultIdentifier, workspace.drawingEditorRequest == nil,
              let root = workspace.folderAccess?.root else { return }
        Self.draftIdentifiersOpenInThisProcess.insert(recoveredDraft.draft.requestIdentifier)
        do {
            let request = try recoveredDraft.editorRequest(inVaultAt: root)
            // A new drawing's embed goes into its note, which must be open when it is saved.
            if case .newDrawing(let notePath, _) = request.target, workspace.openMarkdownSession(at: notePath) == nil {
                _ = await workspace.open(notePath)
            }
            workspace.drawingEditorRequest = request
        } catch {
            DrawingEditorDraftStore.shared.removeDraft(withIdentifier: recoveredDraft.draft.requestIdentifier)
        }
    }
    #endif
}

#if canImport(UIKit)
/// Keeps the app running in the background until `end()`, or until the system's time runs out.
@MainActor
private final class BackgroundTaskAssertion {
    private var identifier = UIBackgroundTaskIdentifier.invalid

    init(name: String) {
        identifier = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
            MainActor.assumeIsolated { self?.end() }
        }
    }

    func end() {
        guard identifier != .invalid else { return }
        UIApplication.shared.endBackgroundTask(identifier)
        identifier = .invalid
    }
}
#endif

// MARK: Creation

private enum PaperSizePreset: String, CaseIterable, Identifiable {
    case a4, letter, custom
    var id: String { rawValue }
    var title: String {
        switch self {
        case .a4: "A4"
        case .letter: "US Letter"
        case .custom: "Custom"
        }
    }
    /// Portrait size in PDF points.
    var portraitSize: CGSize? {
        switch self {
        case .a4: CGSize(width: 595.28, height: 841.89)
        case .letter: CGSize(width: 612, height: 792)
        case .custom: nil
        }
    }
}

/// The page sizes a new notebook can have (`PDFTemplateGenerator` accepts the same).
enum CustomPaperSize {
    /// 1 to 40 inches, in PDF points.
    static let sideLengthRange: ClosedRange<Double> = 72...2880

    static func problem(with size: CGSize) -> String? {
        let isValid = [Double(size.width), Double(size.height)].allSatisfy { sideLength in sideLength.isFinite && sideLengthRange.contains(sideLength) }
        return isValid ? nil : "Width and height must be from 72 to 2,880 points (1 to 40 inches)."
    }
}

private struct CreateDocumentSheet: View {
    let kind: CreationKind
    /// Where the new file goes, as the sheet describes it.
    let folderDescription: String
    let create: (String, PaperSpecification, Int) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @FocusState private var isNameFocused: Bool
    @State private var paper = PaperTemplate.dotted
    /// Spacing and colors start as Settings has them.
    @State private var paperStyle = GraphitePreferences.storedNotebookPaper(template: .dotted)
    @State private var sizePreset = PaperSizePreset.a4
    @State private var isLandscape = false
    @State private var customWidth = 595.28
    @State private var customHeight = 841.89
    @State private var pageCount = 1

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(kind.namePrompt, text: $name)
                        .focused($isNameFocused)
                        .submitLabel(.done)
                        .onSubmit(createIfNamed)
                } footer: {
                    if let problem = nameProblem, !name.isEmpty { Text(problem).foregroundStyle(.red) }
                    else { Text("In “\(folderDescription)”") }
                }
                if kind == .notebook {
                    Section("Paper") {
                        Picker("Template", selection: $paper) { ForEach(PaperTemplate.allCases) { template in Text(template.title).tag(template) } }
                        if paper != .blank {
                            Picker("Spacing", selection: $paperStyle.spacing) {
                                ForEach(NotebookPaperSpacing.choices, id: \.self) { spacing in Text(NotebookPaperSpacing.title(of: spacing)).tag(spacing) }
                            }
                            Picker("Line Color", selection: $paperStyle.lineColor) {
                                ForEach(DrawingPaperLineColor.allCases) { lineColor in Text(lineColor.title).tag(lineColor) }
                            }
                            Picker("Line Strength", selection: $paperStyle.lineStrength) {
                                ForEach(DrawingPaperLineStrength.allCases) { strength in Text(strength.title).tag(strength) }
                            }
                        }
                        Picker("Paper Color", selection: Binding(
                            get: { DrawingBackground.allCases.first { color in color.colorHex == (paperStyle.paperColorHex ?? DrawingBackground.white.colorHex) } ?? .white },
                            set: { color in paperStyle.paperColorHex = color == .white ? nil : color.colorHex })) {
                            ForEach(DrawingBackground.allCases.filter { color in color != .transparent }) { color in Text(color.title).tag(color) }
                        }
                        Picker("Size", selection: $sizePreset) { ForEach(PaperSizePreset.allCases) { preset in Text(preset.title).tag(preset) } }
                        if sizePreset == .custom {
                            TextField("Width in points", value: $customWidth, format: .number)
                            TextField("Height in points", value: $customHeight, format: .number)
                            if let sizeProblem { Text(sizeProblem).font(.footnote).foregroundStyle(.red) }
                        } else {
                            Toggle("Landscape", isOn: $isLandscape)
                        }
                        Stepper("\(pageCount) \(pageCount == 1 ? "page" : "pages")", value: $pageCount, in: 1...1000)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(kind.title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create", action: createIfNamed).disabled(nameProblem != nil || sizeProblem != nil)
                }
            }
        }
        // A note needs only its name: the Mac's sheet takes its form's height rather than
        // leaving half of it empty; a notebook's paper options make it taller.
        #if os(macOS)
        .frame(minWidth: 380, minHeight: kind == .notebook ? 320 : 180)
        #else
        .frame(minWidth: 360, minHeight: 320)
        #endif
        .onAppear { isNameFocused = true }
    }

    private var nameProblem: String? {
        FileNameRules.problem(with: name.trimmingCharacters(in: .whitespacesAndNewlines), isNote: kind == .note)
    }

    /// Checked here, before the sheet closes, so a size the notebook cannot have keeps what
    /// the user entered.
    private var sizeProblem: String? {
        kind == .notebook ? CustomPaperSize.problem(with: pageSize) : nil
    }

    private func createIfNamed() {
        guard nameProblem == nil, sizeProblem == nil else { return }
        var specification = paperStyle.sized(pageSize)
        specification.template = paper
        create(name.trimmingCharacters(in: .whitespacesAndNewlines), specification, pageCount)
        dismiss()
    }

    private var pageSize: CGSize {
        guard let portraitSize = sizePreset.portraitSize else { return CGSize(width: customWidth, height: customHeight) }
        return isLandscape ? CGSize(width: portraitSize.height, height: portraitSize.width) : portraitSize
    }
}

/// The document's name in the navigation bar. A compact width shows it as a plain title,
/// which truncates to make room for the document's controls; the editable title, with its
/// Rename menu, kept its full width beside a long file name and sent Write, Undo and More
/// into an overflow menu. Rename is in the document's More menu there.
private struct DocumentTitle: ViewModifier {
    @Binding var title: String
    let isCompactWidth: Bool

    func body(content: Content) -> some View {
        if isCompactWidth {
            content.navigationTitle(title)
        } else {
            content.navigationTitle($title)
        }
    }
}

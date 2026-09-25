import SwiftUI
import QuickLook
import GraphiteCore
import GraphiteApple
import GraphiteIndex

public struct GraphiteRootView: View {
    @State private var workspace = WorkspaceModel()
    @State private var showsSettings = false
    /// `graphite://` links wait until the last vault has reopened.
    @State private var isVaultRestored = false
    @State private var pendingLinks: [URL] = []
    @State private var showsVaultManager = false
    @State private var opensVaultManagerAfterSettings = false
    @State private var creation: CreationRequest?
    @State private var showsInspector = false
    @State private var activePalette: ActivePalette?
    @State private var columnVisibility = NavigationSplitViewVisibility.automatic
    /// In automatic mode an iPad shows only the detail column when the window is taller
    /// than wide, so toggling the sidebar has to know the window's shape.
    @State private var isWindowTallerThanWide = false
    /// True until the remembered vault has opened or failed to, so the welcome screen does
    /// not flash up before the vault appears.
    @State private var isRestoringVault = true
    @Environment(\.scenePhase) private var scenePhase

    private enum ActivePalette { case quickSwitcher, commandPalette, templatePicker }

    public init() {}

    public var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            VaultSidebar(workspace: workspace, creation: $creation, showsSettings: $showsSettings, showsVaultManager: $showsVaultManager)
                .navigationSplitViewColumnWidth(min: 260, ideal: 360, max: 480)
        } detail: {
            detailColumn
        }
        .onGeometryChange(for: Bool.self) { geometry in geometry.size.height > geometry.size.width } action: { isTallerThanWide in
            isWindowTallerThanWide = isTallerThanWide
        }
        .tint(workspace.preferences.accentColor)
        .environment(\.accent, workspace.preferences.accentColor)
        // The menu bar's commands and their shortcuts act on this window (`GraphiteCommands`).
        .focusedSceneValue(\.workspaceMenuActions, WorkspaceMenuActions(workspace: workspace, window: windowActions,
                                                                          showCommandPalette: { activePalette = .commandPalette },
                                                                          save: { Task { await save() } }))
        .overlay { paletteOverlay }
        .animation(.snappy(duration: 0.18), value: activePalette)
        .sheet(isPresented: $showsSettings, onDismiss: {
            if opensVaultManagerAfterSettings { opensVaultManagerAfterSettings = false; showsVaultManager = true }
        }) {
            SettingsView(workspace: workspace) { opensVaultManagerAfterSettings = true }
                .tint(workspace.preferences.accentColor)
                .presentationSizing(.page)
        }
        .sheet(isPresented: $showsVaultManager) {
            NavigationStack { VaultManagerView(workspace: workspace) }
                .tint(workspace.preferences.accentColor)
                .frame(minWidth: 420, minHeight: 480)
        }
        .sheet(item: $creation) { request in
            let directory = workspace.newFileDirectory(request.directory)
            CreateDocumentSheet(kind: request.kind, folderDescription: directory.rawValue.isEmpty ? workspace.title : directory.rawValue) { name, paper, pageCount in
                Task {
                    switch request.kind {
                    case .note: await workspace.createNote(named: name, in: request.directory)
                    case .notebook: await workspace.createNotebook(named: name, paper: paper, pageCount: pageCount, in: request.directory)
                    case .base: await workspace.createBase(named: name, in: request.directory)
                    }
                }
            }
        }
        .modifier(FileManagementPresentation(workspace: workspace))
        #if canImport(UIKit)
        .fullScreenCover(isPresented: $workspace.isGraphPresented) {
            VaultGraphScreen(workspace: workspace).tint(workspace.preferences.accentColor)
        }
        #else
        .sheet(isPresented: $workspace.isGraphPresented) {
            VaultGraphScreen(workspace: workspace).tint(workspace.preferences.accentColor)
        }
        #endif
        .sheet(item: $workspace.fileRecoveryRequest) { request in
            FileRecoverySheet(workspace: workspace, request: request)
                .tint(workspace.preferences.accentColor)
        }
        #if canImport(UIKit)
        .fullScreenCover(item: $workspace.viewedImage) { path in
            if let root = workspace.folderAccess?.root, let location = try? path.url(in: root) {
                ImageViewer(location: location, title: path.name)
            }
        }
        .fullScreenCover(item: $workspace.drawingEditorRequest) { request in
            DrawingEditor(request: request) { content, format in
                try await workspace.saveDrawing(content, format: format, for: request)
            } exportCopy: { content, format in
                try await workspace.exportDrawingCopy(content, format: format, title: request.title)
            } preserveDraft: { content in
                guard let vaultIdentifier = workspace.currentVaultIdentifier else { return }
                Self.draftIdentifiersOpenInThisProcess.insert(request.id)
                DrawingEditorDraftStore.shared.preserve(DrawingEditorDraft(request: request, vaultIdentifier: vaultIdentifier)) {
                    try await DrawingFileService().fileData(for: content, format: .svg)
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
        .alert("Graphite", isPresented: Binding(get: { workspace.errorMessage != nil }, set: { isPresented in if !isPresented { workspace.errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(workspace.errorMessage ?? "") }
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
        .onOpenURL { url in
            if isVaultRestored { Task { await workspace.handle(url) } } else { pendingLinks.append(url) }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await workspace.checkOpenDocumentsForExternalChanges(); await workspace.refreshDirectory(); await workspace.reloadVaultSettings() }
            } else { saveBeforeLeavingScreen() }
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
            // Editable, so the title bar's menu offers Rename, as for documents in Files.
            .navigationTitle(titleBinding)
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { detailToolbar }
            .environment(\.showTemplatePicker, templatePickerAction)
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
        if workspace.store != nil {
            ToolbarItemGroup(placement: .navigation) {
                Group {
                    Button("Back", systemImage: "chevron.left") { Task { await workspace.goBack() } }
                        .disabled(!workspace.history.canGoBack)
                    Button("Forward", systemImage: "chevron.right") { Task { await workspace.goForward() } }
                        .disabled(!workspace.history.canGoForward)
                    Button("Quick Switcher", systemImage: "doc.text.magnifyingglass") { activePalette = .quickSwitcher }
                    Button("Command Palette", systemImage: "command") { activePalette = .commandPalette }
                }
                .tint(.primary)
            }
        }
        if workspace.store != nil && (workspace.preferences.isEnabled(.audioRecorder) || workspace.recording.state.isActive) {
            ToolbarItem(placement: .primaryAction) {
                RecordingControl(controller: workspace.recording, start: { Task { await workspace.startRecording() } },
                                 retrySaving: { Task { await workspace.retryRecordingPublication() } })
                    .tint(.primary)
            }
        }
    }

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
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
        } else {
            WorkspacePanes(workspace: workspace, showsLinksInspector: $showsInspector,
                           create: { kind in creation = CreationRequest(kind: kind) },
                           showQuickSwitcher: { activePalette = .quickSwitcher },
                           acceptsFocusTouches: activePalette == nil)
        }
    }

    private var windowActions: WindowActions {
        WindowActions(showQuickSwitcher: { activePalette = .quickSwitcher },
                      showSettings: { showsSettings = true },
                      showVaultManager: { showsVaultManager = true },
                      toggleLinksInspector: { showsInspector.toggle() },
                      toggleSidebar: {
                          columnVisibility = Self.sidebarVisibility(toggling: columnVisibility, automaticHidesSidebar: automaticHidesSidebar)
                      },
                      showSidebar: showSidebar,
                      showLinksInspector: { showsInspector = true },
                      create: { kind in creation = CreationRequest(kind: kind) },
                      showTemplatePicker: showTemplatePicker)
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
            backgroundTask.end()
        }
        #else
        Task { await save() }
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
        columnVisibility = Self.sidebarVisibility(revealing: columnVisibility, automaticHidesSidebar: automaticHidesSidebar)
    }

    #if canImport(UIKit)
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
        .frame(minWidth: 360, minHeight: 320)
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
        create(name.trimmingCharacters(in: .whitespacesAndNewlines), PaperSpecification(template: paper, width: pageSize.width, height: pageSize.height), pageCount)
        dismiss()
    }

    private var pageSize: CGSize {
        guard let portraitSize = sizePreset.portraitSize else { return CGSize(width: customWidth, height: customHeight) }
        return isLandscape ? CGSize(width: portraitSize.height, height: portraitSize.width) : portraitSize
    }
}

// MARK: Recording

private struct RecordingControl: View {
    @Bindable var controller: RecordingController
    let start: () -> Void
    /// Saves a recording that could not be saved into the vault, to a destination the
    /// workspace works out again.
    let retrySaving: () -> Void
    @State private var showsDiscardConfirmation = false

    var body: some View {
        control
            .confirmationDialog("Delete this recording?", isPresented: $showsDiscardConfirmation, titleVisibility: .visible) {
                Button("Delete Recording", role: .destructive) { controller.discardRecoveredRecording() }
            } message: {
                Text("It could not be saved into the vault, and this is its only copy.")
            }
    }

    @ViewBuilder private var control: some View {
        if controller.canStartRecording && controller.message == nil {
            Button("Record Lecture", systemImage: "mic") { start() }
        } else {
            // One menu, not a row of buttons: a toolbar gives a custom view one narrow slot,
            // which cut the row's Pause and Stop buttons off.
            Menu {
                if let message = controller.message { Text(message) }
                if controller.state == .recording { Button("Pause", systemImage: "pause.fill") { controller.pause() } }
                if controller.state.canResume { Button("Resume", systemImage: "record.circle") { controller.resume() } }
                if controller.state.canStop { Button("Stop and Save", systemImage: "stop.fill") { controller.stop() } }
                if controller.state == .requestingPermission { Button("Cancel", systemImage: "xmark") { controller.cancelStart() } }
                if controller.state == .failed && controller.recoveryURL != nil {
                    Button("Try Saving Again") { retrySaving() }
                    Button("Discard Recording…", systemImage: "trash", role: .destructive) { showsDiscardConfirmation = true }
                }
                // A recording waiting to be saved or discarded is the only copy of its lecture.
                if controller.canStartRecording { Button("Record Lecture", systemImage: "mic") { start() } }
            } label: {
                HStack(spacing: 6) {
                    if controller.state.canStart {
                        Image(systemName: "exclamationmark.circle").foregroundStyle(.orange)
                    } else {
                        Circle().fill(controller.state == .recording ? Color.red : Color.orange).frame(width: 8, height: 8)
                        switch controller.state {
                        case .requestingPermission: Text("Starting…")
                        case .finalizing: Text("Saving…")
                        default:
                            TimelineView(.periodic(from: .now, by: 1)) { _ in
                                Text(Duration.seconds(controller.elapsedSeconds).formatted(.time(pattern: .hourMinuteSecond))).monospacedDigit()
                            }
                        }
                    }
                }
                .font(.callout)
            }
            .accessibilityLabel(accessibilityDescription)
        }
    }

    private var accessibilityDescription: String {
        switch controller.state {
        case .requestingPermission: "Recording is starting"
        case .recording: "Recording"
        case .paused, .interrupted: "Recording paused"
        case .finalizing: "Saving the recording"
        case .idle, .failed: "Recording problem"
        }
    }
}

import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import GraphiteCore
import GraphiteApple

struct MarkdownPane: View {
    @Bindable var session: MarkdownSession
    @Bindable var workspace: WorkspaceModel
    /// The tab the note is open in, which keeps the heading to show.
    @Bindable var document: TabDocument
    let tabID: UUID
    /// Whether this note's side of the split is focused; only then does the window's
    /// toolbar show its buttons.
    let isFocused: Bool
    @Binding var showsLinksInspector: Bool
    @State private var showsAttachmentPicker = false
    @State private var showsPhotoPicker = false
    @State private var showsCamera = false
    @State private var pickedPhotos: [PhotosPickerItem] = []
    @State private var showsLinkPicker = false
    @State private var showsReloadConfirmation = false
    @Environment(\.showTemplatePicker) private var showTemplatePicker
    /// An editable drawing embedded where the cursor is, if any.
    @State private var drawingAtCursor: VaultPath?

    init(session: MarkdownSession, workspace: WorkspaceModel, document: TabDocument, tabID: UUID, isFocused: Bool, showsLinksInspector: Binding<Bool>) {
        self.session = session
        self.workspace = workspace
        self.document = document
        self.tabID = tabID
        self.isFocused = isFocused
        _showsLinksInspector = showsLinksInspector
    }

    /// Kept by the session, so commands and the keyboard can switch it too.
    private var viewMode: NoteViewMode {
        get { session.viewMode }
        nonmutating set { session.viewMode = newValue }
    }

    private var preferences: GraphitePreferences { workspace.preferences }
    private var isEditing: Bool { viewMode != .reading }

    var body: some View {
        VStack(spacing: 0) {
            banner
            if viewMode == .reading, let root = workspace.folderAccess?.root, let index = workspace.index {
                MarkdownPreview(source: session.text, path: session.path, root: root, index: index, configuration: readingConfiguration,
                                headingScrollRequest: $document.headingScrollRequest,
                                handledScrollToken: Binding(get: { session.handledHeadingScrollToken }, set: { token in session.handledHeadingScrollToken = token }),
                                navigate: { target, isWiki in follow(target, isWiki: isWiki) },
                                openPDF: { path, pageIndex in
                                    workspace.activateTab(tabID)
                                    Task { await workspace.open(path, pdfPageIndex: pageIndex) }
                                },
                                updateProperties: preferences.isEnabled(.properties) ? { properties in session.replaceProperties(properties) } : nil,
                                baseContext: workspace.baseEmbedContext(for: session.path),
                                folding: ReadingFolding(foldedKeys: session.foldedKeys) { [session] key in
                                    if session.foldedKeys.contains(key) { session.foldedKeys.remove(key) } else { session.foldedKeys.insert(key) }
                                },
                                blocksCache: session.readingBlocksCache)
                .environment(\.readingImageActions, ReadingImageActions(providerIdentity: ObjectIdentifier(workspace),
                                                                        viewImage: { [workspace] path in workspace.viewedImage = path },
                                                                        editDrawing: drawingEditor))
            } else {
                NativeMarkdownEditor(session: session, configuration: editorConfiguration, environment: livePreviewEnvironment,
                                     headingScrollRequest: document.headingScrollRequest, actions: editorActions) { target, isWiki in
                    follow(target, isWiki: isWiki)
                }
                .overlay(alignment: .topLeading) { completionPopup }
                .onAppear { session.completion.suggest(from: workspace, for: session) }
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if preferences.isEnabled(.wordCount) { WordCountLabel(session: session).padding(12) }
        }
        .toolbar { if isFocused { toolbarContent } }
        // The text and the cursor change at every keystroke. Only these small views read
        // them, so typing and moving the cursor do not rebuild the pane and its toolbar.
        .background {
            AutosaveDriver(session: session)
            DrawingAtCursorTracker(session: session, workspace: workspace, drawingAtCursor: $drawingAtCursor)
        }
        // The Properties view reads the types assigned in `.obsidian/types.json`; they are
        // read again as the index takes in changed files.
        .task(id: "\(session.path.rawValue)|\(workspace.indexVersion)") { await session.loadDeclaredPropertyTypes() }
        // A jump to a heading or match inside a folded section unfolds it, in either view.
        .onChange(of: document.headingScrollRequest?.token) {
            if let request = document.headingScrollRequest { session.unfold(toShow: request) }
        }
        .confirmationDialog("Replace your unsaved text with the version saved by the other app?", isPresented: $showsReloadConfirmation, titleVisibility: .visible) {
            Button("Use Other Version", role: .destructive) { Task { do { try await session.reload() } catch { workspace.errorMessage = error.localizedDescription } } }
        }
        .fileImporter(isPresented: $showsAttachmentPicker, allowedContentTypes: [.item]) { result in
            switch result {
            case .success(let location): Task { await workspace.importAttachment(from: location, into: session) }
            case .failure(let error): workspace.errorMessage = error.localizedDescription
            }
        }
        .photosPicker(isPresented: $showsPhotoPicker, selection: $pickedPhotos, maxSelectionCount: 10, matching: .images,
                      preferredItemEncoding: .compatible)
        .onChange(of: pickedPhotos) { _, items in
            guard !items.isEmpty else { return }
            pickedPhotos = []
            Task { await insertPickedPhotos(items) }
        }
        #if canImport(UIKit)
        .fullScreenCover(isPresented: $showsCamera) {
            CameraCapture { image in Task { await insertCameraPhoto(image) } }
                .ignoresSafeArea()
        }
        #endif
        .sheet(isPresented: $showsLinkPicker) { LinkPicker(workspace: workspace, notePath: session.path) { link in session.insert(link) } }
    }

    /// Link and tag suggestions just below the cursor, or above it near the bottom.
    @ViewBuilder private var completionPopup: some View {
        if session.completion.isVisible {
            GeometryReader { geometry in
                let caret = session.completion.caretRect
                let popupHeight = min(CompletionPopup.maximumHeight, CGFloat(session.completion.items.count) * 48 + 8)
                let fitsBelow = caret.maxY + 6 + popupHeight <= geometry.size.height
                let popupOriginX = min(max(caret.minX - 12, 8), max(geometry.size.width - CompletionPopup.width - 8, 8))
                let popupOriginY = fitsBelow ? caret.maxY + 6 : max(caret.minY - popupHeight - 6, 8)
                CompletionPopup(model: session.completion)
                    .offset(x: popupOriginX, y: popupOriginY)
            }
            .transition(.opacity)
        }
    }

    @ViewBuilder private var banner: some View {
        if session.hasExternalConflict {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text("This note changed in another app. Your edits are still here.").font(.callout)
                Spacer()
                Button("Save a Copy") { Task { await saveCopy() } }
                Button("Use Other Version") { showsReloadConfirmation = true }
            }
            .padding(.horizontal, 20).padding(.vertical, 12)
            .background(.orange.opacity(0.12))
        } else if let errorMessage = session.errorMessage {
            Label(errorMessage, systemImage: "exclamationmark.circle")
                .font(.callout).foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20).padding(.vertical, 10)
                .background(.red.opacity(0.08))
        }
    }

    private var readingConfiguration: ReadingConfiguration {
        ReadingConfiguration(usesReadableLineLength: preferences.usesReadableLineLength, usesStrictLineBreaks: workspace.vaultSettings.usesStrictLineBreaks,
                             colorsEnabled: preferences.isEnabled(.colors), paletteHexByName: paletteHexByName,
                             showsProperties: preferences.isEnabled(.properties), declaredPropertyTypes: session.declaredPropertyTypes, inlineTitle: preferences.showsInlineTitle ? preferences.displayName(for: session.path) : nil,
                             textSize: preferences.textSize, drawingVersion: workspace.drawingVersion, indexVersion: workspace.indexVersion)
    }

    private var editorConfiguration: EditorConfiguration {
        EditorConfiguration(mode: viewMode == .source ? .source : .livePreview, usesReadableLineLength: preferences.usesReadableLineLength,
                            textSize: preferences.textSize, usesSpellChecking: preferences.usesSpellChecking,
                            colorsEnabled: preferences.isEnabled(.colors), paletteHexByName: paletteHexByName,
                            editingBehavior: EditingBehavior(settings: workspace.vaultSettings), accentHex: preferences.accentHex,
                            inlineTitle: preferences.showsInlineTitle ? preferences.displayName(for: session.path) : nil)
    }

    /// The editor toolbar's buttons that need this pane.
    private var editorActions: EditorActions {
        var actions = EditorActions()
        actions.attach = { showsAttachmentPicker = true }
        actions.choosePhoto = { showsPhotoPicker = true }
        #if canImport(UIKit)
        if UIImagePickerController.isSourceTypeAvailable(.camera) { actions.takePhoto = { showsCamera = true } }
        #endif
        actions.insertAttachment = { [workspace, session] data, stem, fileExtension, range in
            Task { await workspace.saveAttachment(data, stem: stem, fileExtension: fileExtension, into: session, at: range) }
        }
        actions.insertLinkToVaultFile = { [workspace, session] path, range in
            Task { await workspace.insertLink(to: path, into: session, at: range) }
        }
        #if canImport(UIKit)
        if preferences.isEnabled(.drawings) { actions.draw = { [workspace, session] in workspace.beginNewDrawing(in: session) } }
        #endif
        actions.beginEditing = { [workspace, tabID] in workspace.activateTab(tabID) }
        actions.followLinkElsewhere = { [workspace, session] target, isWiki, placement in
            Task { await workspace.follow(target, from: session.path, isWiki: isWiki, placement: placement) }
        }
        return actions
    }

    /// Follows a link from this note. Its tab is focused first, so the link opens on this
    /// side of the split even when the other side was focused.
    private func follow(_ target: String, isWiki: Bool) {
        workspace.activateTab(tabID)
        Task { await workspace.follow(target, from: session.path, isWiki: isWiki) }
    }

    /// Applies an editing command from a menu to the note.
    private func run(_ command: EditorCommand) {
        guard let edit = MarkdownEditing.edit(for: command, in: session.text as NSString, selection: session.selection,
                                              indentUnit: workspace.vaultSettings.indentUnit, tabSize: workspace.vaultSettings.tabSize) else { return }
        session.apply(edit)
    }

    /// What Live Preview's rendered blocks need; nil in Source mode.
    private var livePreviewEnvironment: LivePreviewEnvironment? {
        guard viewMode == .livePreview, let root = workspace.folderAccess?.root else { return nil }
        let notePath = session.path
        return LivePreviewEnvironment(
            root: root, textSize: preferences.textSize, colorsEnabled: preferences.isEnabled(.colors), paletteHexByName: paletteHexByName,
            drawingVersion: workspace.drawingVersion,
            resolve: { [workspace] target, isWiki in await workspace.resolveLink(target, from: notePath, isWiki: isWiki) },
            open: { [workspace] path in Task { await workspace.open(path) } },
            follow: { [workspace] target, isWiki in Task { await workspace.follow(target, from: notePath, isWiki: isWiki) } },
            updateProperties: preferences.isEnabled(.properties) ? { [session] properties in session.replaceProperties(properties) } : nil,
            declaredPropertyTypes: session.declaredPropertyTypes,
            baseContext: workspace.baseEmbedContext(for: notePath),
            viewImage: { [workspace] path in workspace.viewedImage = path },
            editDrawing: drawingEditor, indexVersion: workspace.indexVersion,
            // Reading view's column, a little wider than Live Preview's, bounds the decode.
            embeddedImageColumnWidth: preferences.usesReadableLineLength ? ReadingConfiguration.readableColumnWidth : nil)
    }

    /// Opens a drawing in the editor, where the platform and preferences allow it.
    private var drawingEditor: ((VaultPath) -> Void)? {
        #if canImport(UIKit)
        guard preferences.isEnabled(.drawings) else { return nil }
        return { [workspace] path in Task { await workspace.beginEditingDrawing(at: path) } }
        #else
        return nil
        #endif
    }

    private var paletteHexByName: [String: String] {
        Dictionary(preferences.colorPalette.map { color in (color.name, color.hex) }, uniquingKeysWith: { firstHex, _ in firstHex })
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        // Neutral icons, as in Obsidian; the accent is kept for links, selection, and toggles.
        ToolbarItemGroup(placement: .primaryAction) { Group {
            if isEditing {
                Menu("Format", systemImage: "textformat") {
                    Menu("Heading", systemImage: "number") {
                        ForEach(1...6, id: \.self) { level in
                            Button("Heading \(level)") { run(.heading(level)) }
                        }
                    }
                    Button("Bold", systemImage: "bold") { run(.bold) }
                    Button("Italic", systemImage: "italic") { run(.italic) }
                    Button("Strikethrough", systemImage: "strikethrough") { run(.strikethrough) }
                    Button("Highlight", systemImage: "highlighter") { run(.highlight) }
                    Button("Code", systemImage: "chevron.left.forwardslash.chevron.right") { run(.code) }
                    Button("Inline Math", systemImage: "function") { run(.math) }
                    Button("Comment", systemImage: "eye.slash") { run(.comment) }
                    if preferences.isEnabled(.colors) {
                        Menu("Color", systemImage: "paintpalette") {
                            ForEach(preferences.colorPalette) { color in
                                Button(color.name) { session.insert("~={\(color.hex)}\(Self.selectedText(in: session, placeholder: color.name))=~") }
                            }
                        }
                    }
                    Divider()
                    Button("Bulleted List", systemImage: "list.bullet") { run(.bulletList) }
                    Button("Numbered List", systemImage: "list.number") { run(.numberedList) }
                    Button("Task", systemImage: "checklist") { run(.task) }
                    Button("Table", systemImage: "tablecells") { session.insertBlock("| Column | Column |\n| --- | --- |\n|  |  |") }
                    Button("Math Block", systemImage: "function") { session.insertBlock("$$\n\n$$") }
                    Button("Callout", systemImage: "text.bubble") { session.insertBlock("> [!note]\n> ") }
                }
                Menu("Insert", systemImage: "paperclip") {
                    Button("Link to Note…", systemImage: "link") { showsLinkPicker = true }
                    Button("Photo Library…", systemImage: "photo.on.rectangle") { showsPhotoPicker = true }
                    #if canImport(UIKit)
                    if UIImagePickerController.isSourceTypeAvailable(.camera) { Button("Take Photo…", systemImage: "camera") { showsCamera = true } }
                    #endif
                    Button("Attachment…", systemImage: "doc.badge.plus") { showsAttachmentPicker = true }
                    if let showTemplatePicker {
                        Button("Template…", systemImage: "doc.on.doc") {
                            workspace.activateTab(tabID)
                            showTemplatePicker.show()
                        }
                    }
                }
                #if canImport(UIKit)
                if preferences.isEnabled(.drawings) {
                    if let drawingAtCursor {
                        Button("Edit Drawing", systemImage: "pencil.tip.crop.circle") { Task { await workspace.beginEditingDrawing(at: drawingAtCursor) } }
                    } else {
                        Button("Draw", systemImage: "pencil.tip.crop.circle.badge.plus") { workspace.beginNewDrawing(in: session) }
                    }
                }
                #endif
            }
            Button(isEditing ? "Read" : "Edit", systemImage: isEditing ? "book" : "pencil.line") {
                session.toggleReadingView(editingMode: preferences.defaultEditingMode)
            }
            .help(isEditing ? "Current view: editing. Switch to reading." : "Current view: reading. Switch to editing.")
            Menu("More", systemImage: "ellipsis.circle") {
                Picker("View", selection: $session.viewMode) {
                    Label("Reading view", systemImage: "book").tag(NoteViewMode.reading)
                    Label("Live Preview", systemImage: "eye").tag(NoteViewMode.livePreview)
                    Label("Source mode", systemImage: "chevron.left.forwardslash.chevron.right").tag(NoteViewMode.source)
                }
                .pickerStyle(.inline)
                Button("Fold All", systemImage: "rectangle.compress.vertical") { session.foldAll() }
                Button("Unfold All", systemImage: "rectangle.expand.vertical") { session.unfoldAll() }
                    .disabled(session.foldedKeys.isEmpty)
                Button("Save Now", systemImage: "square.and.arrow.down") { Task { try? await session.save() } }
                Button("Copy Graphite URL", systemImage: "link") { Pasteboard.copy(workspace.openingLink(to: session.path)) }
                if preferences.isEnabled(.bookmarks) {
                    let isBookmarked = workspace.bookmarks.fileBookmark(for: session.path) != nil
                    Button(isBookmarked ? "Remove Bookmark" : "Bookmark", systemImage: isBookmarked ? "bookmark.slash" : "bookmark") {
                        Task { await workspace.toggleBookmark(session.path) }
                    }
                }
                if preferences.isEnabled(.fileRecovery) {
                    Button("File Recovery…", systemImage: "clock.arrow.circlepath") { workspace.fileRecoveryRequest = FileRecoveryRequest(path: session.path) }
                }
            }
            Button("Sidebar", systemImage: "sidebar.right") { showsLinksInspector.toggle() }
        }.tint(.primary) }
    }

    /// The selected text, or a placeholder so the markup is visible when nothing is selected.
    private static func selectedText(in session: MarkdownSession, placeholder: String) -> String {
        let source = session.text as NSString
        let range = session.selection
        guard range.length > 0, NSMaxRange(range) <= source.length else { return placeholder }
        return source.substring(with: range)
    }

    /// Photos arrive as JPEG, PNG, or GIF (the picker's compatible encoding turns HEIC
    /// into JPEG, which Obsidian can show).
    private func insertPickedPhotos(_ items: [PhotosPickerItem]) async {
        for item in items {
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else { continue }
                let type = item.supportedContentTypes.first { type in type.conforms(to: .image) }
                let fileExtension = type.flatMap { type in type == .heic || type == .heif ? "jpg" : type.preferredFilenameExtension } ?? "jpg"
                await workspace.saveAttachment(data, stem: WorkspaceModel.pastedImageStem(), fileExtension: fileExtension == "jpeg" ? "jpg" : fileExtension, into: session)
            } catch { workspace.errorMessage = error.localizedDescription }
        }
    }

    #if canImport(UIKit)
    /// A full-resolution camera photo takes long enough to encode that it is done off the
    /// main thread.
    private func insertCameraPhoto(_ image: UIImage) async {
        let photoData = await Task.detached(priority: .userInitiated) { image.jpegData(compressionQuality: 0.85) }.value
        guard let photoData else {
            workspace.errorMessage = "The photo could not be saved. Take it again."
            return
        }
        await workspace.saveAttachment(photoData, stem: CameraCapture.photoStem(), fileExtension: "jpg", into: session)
    }
    #endif

    private func saveCopy() async {
        do { let path = try await session.saveSeparateCopy(); await workspace.refreshDirectory(); await workspace.open(path) }
        catch { workspace.errorMessage = error.localizedDescription }
    }

}

/// Saves the note once typing pauses.
private struct AutosaveDriver: View {
    let session: MarkdownSession

    var body: some View {
        Color.clear.task(id: session.text) {
            do {
                try await Task.sleep(for: .milliseconds(900))
                try await session.save()
            } catch is CancellationError {
            } catch { session.errorMessage = error.localizedDescription }
        }
    }
}

/// Finds an editable drawing embedded where the cursor rests, for the toolbar's Edit
/// Drawing button.
private struct DrawingAtCursorTracker: View {
    let session: MarkdownSession
    let workspace: WorkspaceModel
    @Binding var drawingAtCursor: VaultPath?
    /// The embed last checked and what it was found to be, so moving the cursor within one
    /// embed does not read its file again.
    @State private var lastCheck: (key: DrawingCheckKey, drawing: VaultPath?)?

    /// What decides whether an embed is an editable drawing: its link, and the drawing and
    /// index versions, which change when a drawing is saved or a file changes.
    struct DrawingCheckKey: Equatable {
        let target: String
        let isWiki: Bool
        let drawingVersion: Int
        let indexVersion: Int
    }

    var body: some View {
        Color.clear.task(id: session.selection.location) { await findDrawingAtCursor() }
    }

    private func findDrawingAtCursor() async {
        do { try await Task.sleep(for: .milliseconds(150)) } catch { return }
        guard let root = workspace.folderAccess?.root,
              let embed = EmbedLocator.embed(at: session.selection.location, in: session.text as NSString),
              DrawingFormat(fileExtension: (WikiLinkResolver.pathPart(embed.target) as NSString).pathExtension) != nil else {
            drawingAtCursor = nil
            return
        }
        let key = DrawingCheckKey(target: embed.target, isWiki: embed.isWiki, drawingVersion: workspace.drawingVersion, indexVersion: workspace.indexVersion)
        if let lastCheck, lastCheck.key == key {
            drawingAtCursor = lastCheck.drawing
            return
        }
        guard let path = await workspace.resolveLink(embed.target, from: session.path, isWiki: embed.isWiki),
              let location = try? path.url(in: root) else {
            guard !Task.isCancelled else { return }
            lastCheck = (key, nil)
            drawingAtCursor = nil
            return
        }
        // The check reads the file; it is cancelled with this lookup when the cursor moves on
        // before it starts, so quick cursor moves do not stack reads.
        let check = Task.detached(priority: .userInitiated) { () -> Bool in
            guard !Task.isCancelled else { return false }
            return DrawingMetadataReader.hasEditableStrokes(at: location)
        }
        let isEditable = await withTaskCancellationHandler { await check.value } onCancel: { check.cancel() }
        guard !Task.isCancelled else { return }
        let drawing = isEditable ? path : nil
        lastCheck = (key, drawing)
        drawingAtCursor = drawing
    }
}

/// Obsidian's status-bar word and character count, without frontmatter. The text changes
/// with every keystroke, so it is counted off the main thread, once typing pauses.
private struct WordCountLabel: View {
    let session: MarkdownSession
    @State private var counts: NoteTextCounts?
    /// How long typing must pause before the note is counted again.
    private static let typingPause = Duration.milliseconds(300)

    var body: some View {
        // A ZStack, not a Group: a Group passes `.task` to its children, and before the
        // first count there is none, so the count would never start.
        ZStack {
            if let counts {
                Text("\(counts.wordCount.formatted()) words · \(counts.characterCount.formatted()) characters")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(.regularMaterial, in: Capsule())
                    .allowsHitTesting(false)
            }
        }
        .task(id: session.text) {
            // The first count, when the note opens, does not wait for a pause.
            if counts != nil {
                do { try await Task.sleep(for: Self.typingPause) } catch { return }
            }
            let textToCount = session.text
            let newCounts = await Task.detached(priority: .utility) { NoteTextCounts(countingBodyOf: textToCount) }.value
            guard !Task.isCancelled else { return }
            counts = newCounts
        }
    }
}

/// A note's words and characters as Obsidian's status bar counts them: after the
/// frontmatter, words separated by whitespace, characters as a person sees them.
struct NoteTextCounts: Equatable, Sendable {
    let wordCount: Int
    let characterCount: Int

    /// Counts in one pass over the text after the frontmatter, without parsing Markdown.
    init(countingBodyOf text: String) {
        let source = text as NSString
        let body = source.substring(from: FrontmatterLocator.length(in: source))
        var wordCount = 0
        var characterCount = 0
        var isInWord = false
        for character in body {
            characterCount += 1
            if character.isWhitespace || character.isNewline {
                isInWord = false
            } else if !isInWord {
                isInWord = true
                wordCount += 1
            }
        }
        self.wordCount = wordCount
        self.characterCount = characterCount
    }
}

private struct LinkPicker: View {
    @Bindable var workspace: WorkspaceModel
    /// The note the link goes into, from which a relative link starts.
    let notePath: VaultPath
    /// Inserts the finished link, in the vault's link style.
    let insert: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var paths: [VaultPath] = []

    var body: some View {
        NavigationStack {
            List(paths) { path in
                Button {
                    Task {
                        // Wikilink or Markdown link, and the path format, as the vault's settings ask.
                        insert(await workspace.linkText(for: path, in: notePath))
                        dismiss()
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(workspace.preferences.displayName(for: path))
                        if !path.parent.rawValue.isEmpty { Text(path.parent.rawValue).font(.caption).foregroundStyle(.secondary) }
                    }
                }
            }
            .overlay { if paths.isEmpty { ContentUnavailableView.search(text: query) } }
            .searchable(text: $query, prompt: "Find a note")
            .navigationTitle("Link to Note")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .task(id: query) {
                do {
                    try await Task.sleep(for: .milliseconds(150))
                    paths = try await workspace.index?.search(query).results.map(\.path).filter { path in DocumentKind(path: path) == .markdown } ?? []
                } catch is CancellationError {
                } catch { workspace.errorMessage = error.localizedDescription }
            }
        }
        .frame(minWidth: 340, minHeight: 450)
    }
}

/// Obsidian's right sidebar: outline, backlinks, outgoing links, tags.
struct NoteLinksInspector: View {
    let session: MarkdownSession
    @Bindable var workspace: WorkspaceModel
    @AppStorage("GraphiteInspectorPanel") private var selectedPanel: InspectorPanel = .outline
    @State private var outgoing: [OutgoingLink] = []
    @State private var linkedMentions: [MentionGroup] = []
    @State private var unlinkedMentions: [MentionGroup] = []
    @AppStorage("GraphiteShowsUnlinkedMentions") private var showsUnlinkedMentions = false
    @State private var isLoadingUnlinkedMentions = false
    @State private var tags: [String] = []
    @State private var footnotes: [(note: Footnotes.Note, location: Int)] = []
    @Environment(\.accent) private var accent
    @State private var outline: [OutlineHeading] = []

    struct OutlineHeading: Identifiable {
        let id: Int
        let level: Int
        let text: String
        let anchor: String
        /// Which of the headings with `anchor` this is, from zero, for notes where several headings read the same.
        let occurrence: Int
    }

    /// The outline of a note's body, each heading numbered among those that read the same,
    /// so a jump reaches that heading rather than the first of them.
    nonisolated static func outlineHeadings(in body: String) -> [OutlineHeading] {
        var occurrencesByAnchor: [String: Int] = [:]
        return NotePreviewDocument.outline(of: body).enumerated().map { headingIndex, heading in
            let occurrence = occurrencesByAnchor[heading.anchor, default: 0]
            occurrencesByAnchor[heading.anchor] = occurrence + 1
            return OutlineHeading(id: headingIndex, level: heading.level, text: heading.text, anchor: heading.anchor, occurrence: occurrence)
        }
    }

    /// A link this note makes, kept with its syntax: a Markdown link's target is a
    /// percent-encoded path relative to the note, which Wikilink rules would misread.
    struct OutgoingLink: Hashable {
        let target: String
        let isWiki: Bool
    }

    /// Each distinct link once, in target order.
    nonisolated static func outgoingLinks(in links: [NoteLink]) -> [OutgoingLink] {
        Set(links.map { link in OutgoingLink(target: link.target, isWiki: link.isWiki) }).sorted { leftLink, rightLink in
            leftLink.target != rightLink.target ? leftLink.target < rightLink.target : leftLink.isWiki && !rightLink.isWiki
        }
    }

    enum InspectorPanel: String, CaseIterable, Identifiable {
        case outline, backlinks, outgoingLinks, tags, footnotes, graph
        var id: String { rawValue }
        var plugin: CorePlugin {
            switch self {
            case .outline: .outline
            case .backlinks: .backlinks
            case .outgoingLinks: .outgoingLinks
            case .tags: .tags
            case .footnotes: .footnotes
            case .graph: .graph
            }
        }
    }

    private var availablePanels: [InspectorPanel] { InspectorPanel.allCases.filter { panel in workspace.preferences.isEnabled(panel.plugin) } }

    var body: some View {
        VStack(spacing: 0) {
            if availablePanels.isEmpty {
                ContentUnavailableView("No Panels", systemImage: "sidebar.right", description: Text("Turn on Outline, Backlinks, Outgoing links, or Tags view in Settings › Core plugins."))
            } else {
                Picker("Panel", selection: $selectedPanel) {
                    ForEach(availablePanels) { panel in Image(systemName: panel.plugin.systemImage).tag(panel).accessibilityLabel(panel.plugin.title) }
                }
                .pickerStyle(.segmented).padding(10)
                if selectedPanel == .graph {
                    LocalGraphPanel(session: session, workspace: workspace)
                } else {
                    List { panelContent }
                }
            }
        }
        .onAppear { selectAvailablePanel() }
        // Settings can turn off the shown panel's plugin while the sidebar stays open.
        .onChange(of: availablePanels) { selectAvailablePanel() }
        .task(id: session.text) {
            do {
                try await Task.sleep(for: .milliseconds(250))
                let text = session.text
                let semantics = try await Task.detached { try MarkdownSemantics.parse(text) }.value
                outgoing = Self.outgoingLinks(in: semantics.links); tags = semantics.tags
                footnotes = await Task.detached { Footnotes.listed(in: text) }.value
                outline = Self.outlineHeadings(in: semantics.body)
            } catch is CancellationError {
            } catch { workspace.errorMessage = error.localizedDescription }
        }
        // Mentions are in other notes: they change when the index takes in new contents,
        // not as this note is typed.
        .task(id: "\(selectedPanel)-\(workspace.indexVersion)-\(session.path.rawValue)") {
            guard selectedPanel == .backlinks else { return }
            await loadLinkedMentions()
            if showsUnlinkedMentions { await loadUnlinkedMentions() }
        }
        .onChange(of: showsUnlinkedMentions) { _, showsMentions in
            if showsMentions { Task { await loadUnlinkedMentions() } }
        }
    }

    private func selectAvailablePanel() {
        if !availablePanels.contains(selectedPanel), let firstPanel = availablePanels.first { selectedPanel = firstPanel }
    }

    private func loadLinkedMentions() async {
        let names = workspace.mentionNames(of: session.path, text: session.text)
        let groups = await workspace.linkedMentions(of: session.path, names: names)
        guard !Task.isCancelled else { return }
        linkedMentions = groups
    }

    private func loadUnlinkedMentions() async {
        isLoadingUnlinkedMentions = true
        defer { isLoadingUnlinkedMentions = false }
        let names = workspace.mentionNames(of: session.path, text: session.text)
        let groups = await workspace.unlinkedMentions(of: session.path, names: names)
        guard !Task.isCancelled else { return }
        unlinkedMentions = groups
    }

    private func linkMention(_ match: SearchMatch, in source: VaultPath) {
        Task {
            await workspace.linkMention(match, in: source, to: session.path)
            // The linked note leaves this list, and its link joins the linked mentions.
            unlinkedMentions = unlinkedMentions.compactMap { group in
                guard group.path == source else { return group }
                let remaining = group.matches.filter { remainingMatch in remainingMatch != match }
                return remaining.isEmpty ? nil : MentionGroup(path: group.path, matches: remaining)
            }
        }
    }

    /// A note that mentions this one, with its lines; each line opens the note there.
    @ViewBuilder private func mentionGroup(_ group: MentionGroup, linksMentions: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Button { Task { await workspace.open(group.path) } } label: {
                HStack {
                    Text(workspace.preferences.displayName(for: group.path)).lineLimit(1)
                    Spacer(minLength: 4)
                    if group.matches.count > 1 {
                        Text(group.matches.count.formatted()).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
            }
            .buttonStyle(.borderless)
            .tint(.primary)
            ForEach(group.matches, id: \.self) { match in
                HStack(alignment: .top, spacing: 6) {
                    Button { Task { await workspace.open(group.path, at: match) } } label: {
                        Text(match.highlightedExcerpt(accent: accent))
                            .font(.caption).foregroundStyle(Color.secondary).lineLimit(4)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 7).padding(.vertical, 5)
                            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 6))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .accessibilityHint("Opens the note at this line")
                    if linksMentions {
                        Button("Link") { linkMention(match, in: group.path) }
                            .font(.caption)
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .accessibilityHint("Turns these words into a link to this note")
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }

    /// Obsidian's "Bookmark heading" from the outline.
    @ViewBuilder private func headingBookmarkButton(_ heading: OutlineHeading) -> some View {
        let subpath = "#" + heading.text
        if !workspace.preferences.isEnabled(.bookmarks) {
            EmptyView()
        } else if let bookmark = workspace.bookmarks.fileBookmark(for: session.path, subpath: subpath) {
            Button("Remove Bookmark", systemImage: "bookmark.slash") { Task { await workspace.removeBookmark(bookmark) } }
        } else {
            Button("Bookmark Heading", systemImage: "bookmark") {
                let bookmark = Bookmark.file(session.path, subpath: subpath)
                Task { await workspace.updateBookmarks { bookmarks in bookmarks.add(bookmark) } }
            }
        }
    }

    @ViewBuilder private var panelContent: some View {
        switch selectedPanel {
        case .outline:
            Section("Outline") {
                if outline.isEmpty { Text("No headings").foregroundStyle(.secondary) }
                ForEach(outline) { heading in
                    // Headings read as text, as in Obsidian's outline, not as tinted links.
                    Button { workspace.headingScrollRequest = HeadingScrollRequest(anchor: heading.anchor, occurrence: heading.occurrence) } label: {
                        Text(heading.text).lineLimit(2)
                            .font(heading.level == 1 ? .callout.weight(.semibold) : .callout)
                            .foregroundStyle(heading.level <= 2 ? .primary : .secondary)
                            .padding(.leading, CGFloat(heading.level - 1) * 14)
                    }
                    .contextMenu { headingBookmarkButton(heading) }
                }
            }
        case .backlinks:
            Section("Linked mentions") {
                if linkedMentions.isEmpty { Text("No other notes link here").foregroundStyle(.secondary) }
                ForEach(linkedMentions) { group in mentionGroup(group, linksMentions: false) }
            }
            Section {
                DisclosureGroup(isExpanded: $showsUnlinkedMentions) {
                    if isLoadingUnlinkedMentions && unlinkedMentions.isEmpty {
                        ProgressView().frame(maxWidth: .infinity)
                    } else if unlinkedMentions.isEmpty {
                        Text("No other notes name this one without linking it").foregroundStyle(.secondary)
                    }
                    ForEach(unlinkedMentions) { group in mentionGroup(group, linksMentions: true) }
                } label: {
                    Text("Unlinked mentions")
                }
            } footer: {
                if showsUnlinkedMentions {
                    Text("Places where this note's name or an alias is written as text. Link turns the words into a link to this note.")
                }
            }
        case .outgoingLinks:
            Section("Outgoing Links") {
                if outgoing.isEmpty { Text("This note has no links").foregroundStyle(.secondary) }
                ForEach(outgoing, id: \.self) { link in
                    Button(link.target) { Task { await workspace.follow(link.target, from: session.path, isWiki: link.isWiki) } }
                }
            }
        case .footnotes:
            Section("Footnotes") {
                if footnotes.isEmpty { Text("No footnotes").foregroundStyle(.secondary) }
                ForEach(footnotes, id: \.note.number) { entry in
                    Button {
                        // Shows the footnote's reference in the note, marked.
                        workspace.headingScrollRequest = HeadingScrollRequest(anchor: "", textRange: NSRange(location: entry.location, length: 0))
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("\(entry.note.number)").font(.caption.monospacedDigit().weight(.semibold)).foregroundStyle(accent)
                            // Emphasis, code and links read as in the note; blocks are not expected in a footnote.
                            Text((try? AttributedString(markdown: entry.note.text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(entry.note.text))
                                .font(.callout).foregroundStyle(Color.primary).lineLimit(4).multilineTextAlignment(.leading)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        case .tags:
            Section("Tags") {
                if tags.isEmpty { Text("No tags").foregroundStyle(.secondary) }
                ForEach(tags, id: \.self) { tag in Button("#" + tag) { workspace.searchQuery = "#" + tag } }
            }
        case .graph:
            // Drawn in place of the list; see `body`.
            EmptyView()
        }
    }
}

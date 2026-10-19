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
    @State private var readingStartOffset: Int?
    @State private var showsReadingSections = false
    @State private var pendingReadingSection: (section: ReadAloudSection, source: String)?
    @Environment(\.showTemplatePicker) private var showTemplatePicker
    @Environment(\.renameDocument) private var renameDocument
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.usesDocumentControlRow) private var usesDocumentControlRowSetting
    @Environment(\.showsDocumentControlsInTabBar) private var showsDocumentControlsInTabBar
    /// An editable drawing embedded where the cursor is, if any.
    @State private var drawingAtCursor: VaultPath?
    /// An image embedded where the cursor is that can be drawn on, if any.
    @State private var imageAtCursor: VaultPath?

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
    /// The chosen note text size, grown with the system text size.
    private var noteTextSize: Double { GraphitePreferences.noteTextSize(Double(workspace.noteBaseFontSize), for: dynamicTypeSize) }
    private var isEditing: Bool { viewMode != .reading }

    var body: some View {
        VStack(spacing: 0) {
            banner
            if viewMode == .reading, let root = workspace.folderAccess?.root, let index = workspace.index {
                MarkdownPreview(source: session.text, path: session.path, root: root, index: index, configuration: readingConfiguration,
                                headingScrollRequest: $document.headingScrollRequest,
                                handledScrollToken: Binding(get: { session.handledHeadingScrollToken }, set: { token in session.handledHeadingScrollToken = token }),
                                navigate: { target, isWiki in follow(target, isWiki: isWiki) },
                                openPDF: openPDF,
                                updateProperties: preferences.isEnabled(.properties) ? { properties in session.replaceProperties(properties) } : nil,
                                baseContext: workspace.baseEmbedContext(for: session.path),
                                folding: ReadingFolding(foldedKeys: session.foldedKeys) { [session] key in
                                    if session.foldedKeys.contains(key) { session.foldedKeys.remove(key) } else { session.foldedKeys.insert(key) }
                                },
                                blocksCache: session.readingBlocksCache, savedPosition: session.readingPosition,
                                takeStartingLocation: { [session] in session.takeReadingStartLocation() },
                                toggleTask: { [session] note, location in await workspace.toggleReadingTask(at: location, in: note, shownBy: session) },
                                readingWord: ReadingWordSource { [readAloud = workspace.readAloud, path = session.path] in readAloud.highlight(in: path) },
                                followsReading: workspace.readAloud.shouldFollow(session.path),
                                suspendReadingFollow: { workspace.readAloud.suspendFollowing(in: session.path.rawValue) })
                .environment(\.readingImageActions, ReadingImageActions(providerIdentity: ObjectIdentifier(workspace),
                                                                        viewImage: viewImage, editDrawing: drawingEditor, drawOnImage: imageDrawing))
                .environment(\.communityPluginCodeBlocks, workspace.communityPlugins.isRuntimeRunning ? workspace.communityPlugins : nil)
                .modifier(QuickFontSizePinchModifier(adjustment: quickFontSizeAdjustment))
                .environment(\.lassoNoteDestination, LassoNoteDestination.note(session, in: workspace))
            } else {
                NativeMarkdownEditor(session: session, configuration: editorConfiguration, environment: livePreviewEnvironment,
                                     headingScrollRequest: document.headingScrollRequest, actions: editorActions,
                                     retention: workspace.markdownEditorRetention, retentionOwner: document,
                                     readAloudRange: workspace.readAloud.highlight(in: session.path),
                                     followsReading: workspace.readAloud.shouldFollow(session.path),
                                     suspendReadingFollow: { workspace.readAloud.suspendFollowing(in: session.path.rawValue) },
                                     readAloudHooks: readAloudHooks, contextMenu: editorContextMenuActions) { target, isWiki in
                    follow(target, isWiki: isWiki)
                }
                // The suggestions change at every keystroke; only this overlay reads them.
                .overlay(alignment: .topLeading) { CompletionPopupOverlay(model: session.completion) }
                .onAppear { session.completion.suggest(from: workspace, for: session) }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if usesDocumentControlRow, !showsDocumentControlsInTabBar, isFocused {
                DocumentControlRow(isWriting: isWritingBinding) {
                    #if canImport(UIKit)
                    if isEditing { UndoRedoButtons(availability: session.undoAvailability) }
                    #endif
                }
            }
        }
        // The theme's page color behind the note, in both views; Graphite's own without a theme.
        .background { NoteThemeBackground(theme: workspace.noteTheme) }
        // Under the title, as a PDF shows its page there, rather than over the note's text.
        .modifier(WordCountDisplay(session: session, isShown: preferences.isEnabled(.wordCount) && isFocused,
                                   isCompactWidth: isCompactWidth))
        .toolbar { if isFocused { toolbarContent } }
        .sheet(isPresented: $showsReadingSections, onDismiss: {
            if let pending = pendingReadingSection {
                pendingReadingSection = nil
                guard session.text == pending.source else {
                    workspace.errorMessage = "The note changed. Choose the reading section again."
                    return
                }
                startReading(range: pending.section.range, scope: pending.section.title)
            }
        }) {
            ReadAloudSectionPicker(source: session.text) { section, source in
                pendingReadingSection = (section, source)
            }
        }
        // Folding or unfolding while this note is read changes what is still to be read.
        .onChange(of: session.foldedKeys) { _, _ in workspace.readAloud.foldsDidChange(in: session.path, hiddenRanges: foldedRanges) }
        .onChange(of: workspace.calloutFolds.expansion(for: session.path.rawValue)) { _, _ in
            workspace.readAloud.foldsDidChange(in: session.path, hiddenRanges: foldedRanges)
        }
        .environment(\.calloutFoldNote, (workspace.calloutFolds, session.path.rawValue))
        // In the reading view, "Read from Here" after scrolling starts at the top block shown.
        .onChange(of: viewMode, initial: true) { _, mode in
            if mode == .reading {
                workspace.readAloudNavigator.visibleLocation = { [session] in session.readingPosition.topLocation() }
                // The reading view has no tap to read yet; "Read from Here" is in the player.
                workspace.readAloudNavigator.supportsTapToRead = false
            }
        }
        // The text and the cursor change at every keystroke. Only these small views read
        // them, so typing and moving the cursor do not rebuild the pane and its toolbar.
        .background {
            AutosaveDriver(session: session) { readingStartOffset = nil }
            DrawingAtCursorTracker(session: session, workspace: workspace, drawingAtCursor: $drawingAtCursor, imageAtCursor: $imageAtCursor)
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
                             showsProperties: preferences.isEnabled(.properties), declaredPropertyTypes: session.declaredPropertyTypes, inlineTitle: inlineTitle,
                             textSize: noteTextSize, drawingVersion: workspace.drawingVersion, indexVersion: workspace.indexVersion,
                             mapsReadAloudSourceLocations: workspace.readAloud.sourceIdentifier == session.path.rawValue
                                && (workspace.readAloud.isPreparing || workspace.readAloud.session.document != nil),
                             pluginCodeBlockLanguages: workspace.communityPlugins.codeBlockLanguages,
                             runsPluginPostProcessors: workspace.communityPlugins.runsMarkdownPostProcessors,
                             marksUnresolvedLinks: workspace.noteTheme != nil)
    }

    /// The note's name above its text, written as the tab and the title bar write it, so the
    /// three agree: with `.md` when Settings › Files and Links › Show File Extensions is on.
    private var inlineTitle: String? {
        preferences.showsInlineTitle ? preferences.displayName(for: session.path) : nil
    }

    private var editorConfiguration: EditorConfiguration {
        EditorConfiguration(mode: viewMode == .source ? .source : .livePreview, usesReadableLineLength: preferences.usesReadableLineLength,
                            textSize: noteTextSize, typography: workspace.noteTypography, theme: workspace.noteTheme, usesSpellChecking: preferences.usesSpellChecking,
                            formatsCodeBlocks: preferences.formatsCodeBlocks, colorsEnabled: preferences.isEnabled(.colors), paletteHexByName: paletteHexByName,
                            editingBehavior: EditingBehavior(settings: workspace.vaultSettings), accentHex: preferences.accentHex,
                            inlineTitle: inlineTitle)
    }

    /// Pinching the note changes the vault's font size, when Settings › Appearance › Font ›
    /// Quick Font Size Adjustment is on.
    private var quickFontSizeAdjustment: QuickFontSizeAdjustment? {
        guard workspace.adjustsNoteFontSizeQuickly else { return nil }
        return QuickFontSizeAdjustment(currentSize: { [workspace] in workspace.noteBaseFontSize },
                                       setSize: { [workspace] size in workspace.setNoteBaseFontSize(size) })
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
        if preferences.isEnabled(.drawings) {
            actions.draw = { [workspace, session] in workspace.beginNewDrawing(in: session) }
            // Only the focused side answers, so a PDF on the other side keeps its double-tap.
            // On a drawing or an image it opens that; elsewhere it starts a new drawing.
            if isFocused && preferences.drawsOnPencilDoubleTap {
                actions.drawOnPencilDoubleTap = { [workspace, session] in Task { await workspace.beginDrawingAtCursor(in: session) } }
            }
        }
        #endif
        actions.beginEditing = { [workspace, tabID] in workspace.activateTab(tabID) }
        actions.quickFontSize = quickFontSizeAdjustment
        let pluginHost = workspace.communityPlugins
        if pluginHost.isRuntimeRunning && (pluginHost.hasEditorSuggestions || pluginHost.hasEditorChangeListeners) {
            actions.pluginEditorDidChange = { [pluginHost, session] in pluginHost.editorDidChange(in: session) }
        }
        if pluginHost.isRuntimeRunning && pluginHost.hasPasteListeners {
            actions.pluginPaste = { [pluginHost, session] text, html in await pluginHost.offerPaste(into: session, text: text, html: html) }
        }
        if pluginHost.isRuntimeRunning && pluginHost.hasDropListeners {
            actions.pluginDrop = { [pluginHost, session] files, text in await pluginHost.offerDrop(into: session, files: files, text: text) }
        }
        if workspace.communityPlugins.hasEditorMenuItems {
            #if canImport(UIKit)
            actions.pluginEditMenuElement = { [host = workspace.communityPlugins] in host.editorMenuElement() }
            #elseif canImport(AppKit)
            actions.pluginContextMenuItems = { [host = workspace.communityPlugins] in await host.editorMenuItems() }
            #endif
        }
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

    /// Opens an embedded PDF in the PDF view at a zero-based page, for an embed's "Open in
    /// PDF View" in either view mode. Unlike a page link, which leaves the note focused, it
    /// takes the person to the PDF: to its tab, or to the other side where it is open.
    private func openPDF(_ path: VaultPath, at pageIndex: Int) {
        workspace.activateTab(tabID)
        Task { await workspace.open(path, pdfPageIndex: pageIndex) }
    }

    /// Applies an editing command from a menu to the note.
    private func run(_ command: EditorCommand) {
        guard let edit = MarkdownEditing.edit(for: command, in: session.text as NSString, selection: session.selection,
                                              indentUnit: workspace.vaultSettings.indentUnit, tabSize: workspace.vaultSettings.tabSize) else { return }
        session.apply(edit)
    }

    /// Wraps the selection in Obsidian's Colors syntax, or a placeholder when nothing is
    /// selected, so the markup shows. The toolbar's Color menu and the editor's context
    /// menu write it alike.
    private func insertColor(hex: String, placeholder: String) {
        session.insert("~={\(hex)}\(Self.selectedText(in: session, placeholder: placeholder))=~")
    }

    /// What the editor's context menu (right-click on the Mac, the edit menu on the iPad)
    /// does through this pane: the toolbar's own paths, so undo and the selection afterwards
    /// behave the same.
    private var editorContextMenuActions: EditorContextMenuActions {
        var openTemplatePicker: (() -> Void)?
        if let showTemplatePicker {
            openTemplatePicker = { [workspace, tabID] in
                workspace.activateTab(tabID)
                showTemplatePicker.show()
            }
        }
        return EditorContextMenuActions(
            run: { command in run(command) },
            noteState: { [session] in (session.text as NSString, session.selection) },
            apply: { [session] edit in session.apply(edit) },
            insertBlock: { [session] block in
                // After the selected text, which a block inserted over it would replace.
                session.insertBlock(block, at: NSRange(location: NSMaxRange(session.selection), length: 0))
            },
            colors: preferences.isEnabled(.colors) ? preferences.colorPalette : nil,
            insertColor: { hex, placeholder in insertColor(hex: hex, placeholder: placeholder) },
            linkToNote: { showsLinkPicker = true },
            template: openTemplatePicker)
    }

    /// What Live Preview's rendered blocks need; nil in Source mode.
    private var livePreviewEnvironment: LivePreviewEnvironment? {
        guard viewMode == .livePreview, let root = workspace.folderAccess?.root else { return nil }
        let notePath = session.path
        return LivePreviewEnvironment(
            calloutFoldNote: (workspace.calloutFolds, notePath.rawValue),
            root: root, textSize: noteTextSize, typography: workspace.noteTypography, theme: workspace.noteTheme, colorsEnabled: preferences.isEnabled(.colors), paletteHexByName: paletteHexByName,
            drawingVersion: workspace.drawingVersion,
            resolve: { [workspace] target, isWiki in await workspace.resolveLink(target, from: notePath, isWiki: isWiki) },
            open: { [workspace] path in Task { await workspace.open(path) } },
            follow: { [workspace] target, isWiki in Task { await workspace.follow(target, from: notePath, isWiki: isWiki) } },
            openPDF: openPDF,
            updateProperties: preferences.isEnabled(.properties) ? { [session] properties in session.replaceProperties(properties) } : nil,
            declaredPropertyTypes: session.declaredPropertyTypes,
            baseContext: workspace.baseEmbedContext(for: notePath),
            viewImage: viewImage, editDrawing: drawingEditor, drawOnImage: imageDrawing, indexVersion: workspace.indexVersion,
            // Reading view's column, a little wider than Live Preview's, bounds the decode.
            embeddedImageColumnWidth: preferences.usesReadableLineLength ? ReadingConfiguration.readableColumnWidth : nil,
            readingContext: LivePreviewReadingContext(controller: workspace.readAloud, path: session.path),
            lassoNoteDestination: LassoNoteDestination.note(session, in: workspace),
            pluginCodeBlocks: workspace.communityPlugins.isRuntimeRunning ? workspace.communityPlugins : nil,
            pluginCodeBlockLanguages: workspace.communityPlugins.codeBlockLanguages,
            notePath: notePath)
    }

    /// Opens a drawing in the editor, where the platform and preferences allow it.
    /// Shows an image full screen, remembering its note so the viewer can offer to draw on it.
    private var viewImage: (VaultPath) -> Void {
        { [workspace, session] path in
            workspace.viewedImageNote = session.path
            workspace.viewedImage = path
        }
    }

    /// Opens the drawing editor over an image of this note; the note then shows the drawing.
    private var imageDrawing: ((VaultPath) -> Void)? {
        #if canImport(UIKit)
        guard preferences.isEnabled(.drawings) else { return nil }
        return { [workspace, session] path in Task { await workspace.beginDrawingOnImage(at: path, fromNote: session.path) } }
        #else
        return nil
        #endif
    }

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
        // A compact width shows only Write and More, as Obsidian mobile's header does: the
        // keyboard's toolbar formats, attaches, draws, undoes and redoes while typing.
        ToolbarItemGroup(placement: .primaryAction) { Group {
            if isEditing && !isCompactWidth {
                // On an iPad the keyboard's toolbar formats and inserts while typing, so
                // Format and Insert wait in More, as on a phone; the Mac has no such toolbar.
                #if canImport(UIKit)
                drawButton
                #else
                Menu("Format", systemImage: "textformat") { formatMenuItems }
                Menu("Insert", systemImage: "paperclip") { insertMenuItems }
                #endif
            }
            if !usesDocumentControlRow {
                #if canImport(UIKit)
                // An iPad's keyboard toolbar leaves Undo and Redo to the toolbar, also when
                // the window is as narrow as a phone's.
                if isEditing && (!isCompactWidth || UIDevice.current.userInterfaceIdiom == .pad) {
                    UndoRedoButtons(availability: session.undoAvailability)
                }
                #endif
                DocumentModeToggle(isWriting: isWritingBinding)
            }
            Menu("More", systemImage: "ellipsis") { moreMenuItems }
            if !isCompactWidth {
                Button("Sidebar", systemImage: "sidebar.right") { showsLinksInspector.toggle() }
            }
        }.tint(.primary) }
    }

    @ViewBuilder private var formatMenuItems: some View {
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
                    Button(color.name) { insertColor(hex: color.hex, placeholder: color.name) }
                }
            }
        }
        Divider()
        Button("Bulleted List", systemImage: "list.bullet") { run(.bulletList) }
        Button("Numbered List", systemImage: "list.number") { run(.numberedList) }
        Button("Task", systemImage: "checklist") { run(.task) }
        Button("Table", systemImage: "tablecells") { session.insertBlock(EditorContextMenuContent.tableBlock) }
        Button("Math Block", systemImage: "function") { session.insertBlock(EditorContextMenuContent.mathBlock) }
        Button("Callout", systemImage: "text.bubble") { session.insertBlock(EditorContextMenuContent.calloutBlock) }
    }

    @ViewBuilder private var insertMenuItems: some View {
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
    /// Edits the drawing at the cursor, draws on the image there, or starts a new drawing.
    @ViewBuilder private var drawButton: some View {
        if preferences.isEnabled(.drawings) {
            if let drawingAtCursor {
                Button("Edit Drawing", systemImage: "pencil.tip.crop.circle") { Task { await workspace.beginEditingDrawing(at: drawingAtCursor) } }
            } else if let imageAtCursor {
                Button("Draw on Image", systemImage: "pencil.tip.crop.circle.badge.plus") {
                    Task { await workspace.beginDrawingOnImage(at: imageAtCursor, fromNote: session.path) }
                }
            } else {
                Button("Draw", systemImage: "pencil.tip.crop.circle.badge.plus") { workspace.beginNewDrawing(in: session) }
            }
        }
    }
    #endif

    @ViewBuilder private var readAloudMenu: some View {
        Menu("Read Aloud", systemImage: "speaker.wave.2") {
            Button("Read Document") { startReading() }
            Button("Choose Section…") { showsReadingSections = true }
            if isEditing {
                // These look at the selection when chosen, not while the menu is built: the
                // toolbar's menus followed the cursor and were all built again at every
                // keystroke.
                Button("Read Selection") {
                    guard session.selection.length > 0 else {
                        workspace.errorMessage = "Select the text to read first."
                        return
                    }
                    startReading(range: session.selection, scope: "Selected text")
                }
                Button("Read From Here") {
                    startReading(range: NSRange(location: session.selection.location, length: max(0, session.text.utf16.count - session.selection.location)), scope: "From cursor to end")
                }
                Divider()
                Button("Set Reading Start") { readingStartOffset = session.selection.location }
                if let start = readingStartOffset {
                    Button("Read Through Here") {
                        guard session.selection.location >= start else {
                            workspace.errorMessage = "Put the cursor after the reading start first."
                            return
                        }
                        let end = session.selection.length > 0 ? NSMaxRange(session.selection) : min(session.selection.location + 1, session.text.utf16.count)
                        startReading(range: NSRange(location: start, length: max(0, end - start)), scope: "Chosen start and end")
                    }
                }
            }
        }
        .disabled(workspace.recording.state.isActive)
        if workspace.recording.state.isActive { Text("Finish recording to read aloud.") }
    }

    @ViewBuilder private var moreMenuItems: some View {
        if preferences.isEnabled(.readAloud) { readAloudMenu }
        Picker("View", selection: $session.viewMode) {
            Label("Reading View", systemImage: "book").tag(NoteViewMode.reading)
            Label("Live Preview", systemImage: "eye").tag(NoteViewMode.livePreview)
            Label("Source Mode", systemImage: "chevron.left.forwardslash.chevron.right").tag(NoteViewMode.source)
        }
        .pickerStyle(.inline)
        #if canImport(UIKit)
        if isEditing {
            Section {
                Menu("Format", systemImage: "textformat") { formatMenuItems }
                Menu("Insert", systemImage: "paperclip") { insertMenuItems }
                if isCompactWidth { drawButton }
            }
        }
        #endif
        if isCompactWidth {
            Section {
                Button("Links and Outline", systemImage: "sidebar.right") { showsLinksInspector.toggle() }
                if let renameDocument { Button("Rename…", systemImage: "pencil") { renameDocument.rename() } }
            }
        }
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
        CommunityPluginFileActionsButton(host: workspace.communityPlugins, path: session.path, source: "more-options")
        WorkspaceMoreMenuItems()
    }

    private func startReading(range: NSRange? = nil, scope: String = "Whole note") {
        guard !workspace.recording.state.isActive else { return }
        workspace.readAloud.readMarkdown(session.text, path: session.path, range: range, scope: scope, paletteHexByName: paletteHexByName,
                                         hiddenRanges: foldedRanges)
        // The whole note goes on from where it was left; the player offers Start Over.
        if range == nil {
            workspace.readAloudNavigator.resumeWhenPrepared(at: workspace.readAloudNavigator.rememberedLocation(for: session.path.rawValue))
        }
    }

    /// Read Aloud's ways into the editor: tap to move reading, "Read from Here", the first
    /// visible line for the floating player's "Read from Here", and the highlight's place.
    private var readAloudHooks: ReadAloudEditorHooks {
        let reader = workspace.readAloud
        let navigator = workspace.readAloudNavigator
        let isReading = reader.sourceIdentifier == session.path.rawValue && reader.session.document != nil
        let session = session
        return ReadAloudEditorHooks(
            isReadingThisNote: isReading || navigator.rangeSelection != .off,
            tapped: { location in
                if let range = navigator.tapped(atSourceLocation: location) { startReading(range: range, scope: "Chosen start and end") }
            },
            readFromHere: { location in
                // The length when asked: read in the body, it made the pane depend on the text.
                let textLength = (session.text as NSString).length
                startReading(range: NSRange(location: location, length: max(0, textLength - location)), scope: "From here to the end")
            },
            registerVisibleLocation: { provider in
                navigator.visibleLocation = provider
                navigator.supportsTapToRead = true
            },
            reportHighlightFrame: { frame, window in
                if navigator.highlightFrameInWindow != frame { navigator.highlightFrameInWindow = frame }
                if navigator.windowBounds != window { navigator.windowBounds = window }
            })
    }

    /// What the person folded away in this note, which Read Aloud does not read.
    private var foldedRanges: [NSRange] {
        ReadAloudFolding.hiddenRanges(in: session.text, foldedKeys: session.foldedKeys,
                                      calloutExpansion: workspace.calloutFolds.expansion(for: session.path.rawValue))
    }

    private var usesDocumentControlRow: Bool {
        usesDocumentControlRowSetting ?? DocumentToolbarLayout.usesControlRow(detailWidth: nil, horizontalSizeClass: horizontalSizeClass)
    }

    /// A phone, or an iPad window as narrow as one: no tab bar, and a lean navigation bar.
    private var isCompactWidth: Bool { horizontalSizeClass == .compact }

    private var isWritingBinding: Binding<Bool> {
        Binding(get: { isEditing }, set: { shouldWrite in
            if shouldWrite != isEditing { session.toggleReadingView(editingMode: preferences.defaultEditingMode) }
        })
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

/// Saves the note once typing pauses, and says when the text changes. The pane's own body
/// does not read the text, so a keystroke updates this view rather than the whole pane.
private struct AutosaveDriver: View {
    let session: MarkdownSession
    let textDidChange: () -> Void

    var body: some View {
        Color.clear
            .onChange(of: session.text) { _, _ in textDidChange() }
            .task(id: session.text) {
            do {
                try await Task.sleep(for: .milliseconds(900))
                try await session.save()
            } catch is CancellationError {
            } catch { session.errorMessage = error.localizedDescription }
        }
    }
}

/// Finds an editable drawing, or an image that can be drawn on, embedded where the cursor
/// rests, for the toolbar's Edit Drawing and Draw on Image buttons.
private struct DrawingAtCursorTracker: View {
    let session: MarkdownSession
    let workspace: WorkspaceModel
    @Binding var drawingAtCursor: VaultPath?
    @Binding var imageAtCursor: VaultPath?
    /// The embed last checked and what it was found to be, so moving the cursor within one
    /// embed does not read its file again.
    @State private var lastCheck: (key: DrawingCheckKey, drawing: VaultPath?, image: VaultPath?)?

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
              let embed = EmbedLocator.embed(at: session.selection.location, in: session.text as NSString) else {
            drawingAtCursor = nil
            imageAtCursor = nil
            return
        }
        let fileExtension = (WikiLinkResolver.pathPart(embed.target) as NSString).pathExtension
        let isDrawingFormat = DrawingFormat(fileExtension: fileExtension) != nil
        guard isDrawingFormat || DocumentKind(fileExtension: fileExtension) == .image else {
            drawingAtCursor = nil
            imageAtCursor = nil
            return
        }
        let key = DrawingCheckKey(target: embed.target, isWiki: embed.isWiki, drawingVersion: workspace.drawingVersion, indexVersion: workspace.indexVersion)
        if let lastCheck, lastCheck.key == key {
            drawingAtCursor = lastCheck.drawing
            imageAtCursor = lastCheck.image
            return
        }
        guard let path = await workspace.resolveLink(embed.target, from: session.path, isWiki: embed.isWiki),
              let location = try? path.url(in: root) else {
            guard !Task.isCancelled else { return }
            lastCheck = (key, nil, nil)
            drawingAtCursor = nil
            imageAtCursor = nil
            return
        }
        // The check reads the file; it is cancelled with this lookup when the cursor moves on
        // before it starts, so quick cursor moves do not stack reads.
        let check = Task.detached(priority: .userInitiated) { () -> Bool in
            guard isDrawingFormat, !Task.isCancelled else { return false }
            return DrawingMetadataReader.hasEditableStrokes(at: location)
        }
        let isEditable = await withTaskCancellationHandler { await check.value } onCancel: { check.cancel() }
        guard !Task.isCancelled else { return }
        let drawing = isEditable ? path : nil
        let image = !isEditable && DrawableImages.canDrawOn(path) ? path : nil
        lastCheck = (key, drawing, image)
        drawingAtCursor = drawing
        imageAtCursor = image
    }
}

/// Obsidian's status-bar word and character count, without frontmatter. The text changes
/// with every keystroke, so it is counted off the main thread, once typing pauses.
/// The note's word and character counts, as Obsidian's Word count plugin shows them: under
/// the window's title, as its subtitle. A phone shows only the words, which fit beside the
/// title's width. Only this modifier reads the text, so typing does not rebuild the pane.
private struct WordCountDisplay: ViewModifier {
    let session: MarkdownSession
    let isShown: Bool
    let isCompactWidth: Bool
    @State private var counts: NoteTextCounts?
    /// How long typing must pause before the note is counted again.
    private static let typingPause = Duration.milliseconds(300)

    func body(content: Content) -> some View {
        // The text is read by the counter behind the note, not here: the subtitle set again
        // at every keystroke laid out the window's toolbar again and rebuilt its menus.
        countedContent(content)
            .background { WordCounter(session: session, isShown: isShown, counts: $counts) }
    }

    /// Counts the note once typing pauses.
    private struct WordCounter: View {
        let session: MarkdownSession
        let isShown: Bool
        @Binding var counts: NoteTextCounts?

        var body: some View {
            Color.clear.task(id: isShown ? session.text : nil) {
                guard isShown else { return }
                // The first count, when the note opens, does not wait for a pause.
                if counts != nil {
                    do { try await Task.sleep(for: WordCountDisplay.typingPause) } catch { return }
                }
                let textToCount = session.text
                let newCounts = await Task.detached(priority: .utility) { NoteTextCounts(countingBodyOf: textToCount) }.value
                guard !Task.isCancelled, newCounts != counts else { return }
                counts = newCounts
            }
        }
    }

    @ViewBuilder private func countedContent(_ content: Content) -> some View {
        // Always the same view, with an empty subtitle when there is nothing to show:
        // switching between the note with and without a subtitle made SwiftUI build the
        // note's editor again, losing its cursor and revealed markup.
        content.navigationSubtitle(Text(isShown ? counts.map(summary(of:)) ?? "" : ""))
    }

    private func summary(of counts: NoteTextCounts) -> String {
        let words = counts.wordCount == 1 ? "1 word" : "\(counts.wordCount.formatted()) words"
        return isCompactWidth ? words : "\(words) · \(counts.characterCount.formatted()) characters"
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
        case outline, backlinks, outgoingLinks, tags, footnotes, graph, map
        var id: String { rawValue }
        var plugin: CorePlugin {
            switch self {
            case .outline: .outline
            case .backlinks: .backlinks
            case .outgoingLinks: .outgoingLinks
            case .tags: .tags
            case .footnotes: .footnotes
            case .graph: .graph
            case .map: .map
            }
        }
    }

    private var availablePanels: [InspectorPanel] { InspectorPanel.allCases.filter { panel in workspace.preferences.isEnabled(panel.plugin) } }

    var body: some View {
        VStack(spacing: 0) {
            if availablePanels.isEmpty {
                ContentUnavailableView("No Panels", systemImage: "sidebar.right", description: Text("Turn on Outline, Backlinks, Outgoing Links, or Tags View in Settings › Core Plugins."))
            } else {
                Picker("Panel", selection: $selectedPanel) {
                    ForEach(availablePanels) { panel in Image(systemName: panel.plugin.systemImage).tag(panel).accessibilityLabel(panel.plugin.title) }
                }
                // The Mac otherwise writes the picker's own name, "Panel", before it.
                .pickerStyle(.segmented).labelsHidden().padding(10)
                if selectedPanel == .graph {
                    LocalGraphPanel(session: session, workspace: workspace)
                } else if selectedPanel == .map {
                    LocalMapPanel(session: session, workspace: workspace)
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
        // Another note's outline, links and mentions are not shown under this one while
        // its own are read.
        .onChange(of: session.path) {
            outline = []; outgoing = []; tags = []; footnotes = []
            linkedMentions = []; unlinkedMentions = []
        }
    }

    private func selectAvailablePanel() {
        if !availablePanels.contains(selectedPanel), let firstPanel = availablePanels.first { selectedPanel = firstPanel }
    }

    /// The mentions found are shown only while the note they were found for is: another
    /// note opened during a slow search kept the old note's list, and Link on one of its
    /// lines wrote a link to the wrong note.
    private func loadLinkedMentions() async {
        let path = session.path
        let names = workspace.mentionNames(of: path, text: session.text)
        let groups = await workspace.linkedMentions(of: path, names: names)
        guard !Task.isCancelled, session.path == path else { return }
        linkedMentions = groups
    }

    private func loadUnlinkedMentions() async {
        isLoadingUnlinkedMentions = true
        defer { isLoadingUnlinkedMentions = false }
        let path = session.path
        let names = workspace.mentionNames(of: path, text: session.text)
        let groups = await workspace.unlinkedMentions(of: path, names: names)
        guard !Task.isCancelled, session.path == path else { return }
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
                    Text(workspace.preferences.displayName(for: group.path)).lineLimit(1).interfaceFont(.body)
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
                            .interfaceFont(.caption).foregroundStyle(Color.secondary).lineLimit(4)
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
                            .interfaceFont(.callout, weight: heading.level == 1 ? .semibold : nil)
                            .foregroundStyle(heading.level <= 2 ? .primary : .secondary)
                            .padding(.leading, CGFloat(heading.level - 1) * 14)
                    }
                    .contextMenu { headingBookmarkButton(heading) }
                }
            }
        case .backlinks:
            Section("Linked Mentions") {
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
        case .graph, .map:
            // Drawn in place of the list; see `body`.
            EmptyView()
        }
    }
}

/// Link suggestions over the note, next to the cursor. A view of its own: read in the pane's
/// body, the suggestions, which change at every keystroke, rebuilt the whole pane.
private struct CompletionPopupOverlay: View {
    let model: CompletionModel

    var body: some View {
        if model.isVisible {
            GeometryReader { geometry in
                let caret = model.caretRect
                let popupHeight = min(CompletionPopup.maximumHeight, CGFloat(model.items.count) * 48 + 8)
                let fitsBelow = caret.maxY + 6 + popupHeight <= geometry.size.height
                let popupOriginX = min(max(caret.minX - 12, 8), max(geometry.size.width - CompletionPopup.width - 8, 8))
                let popupOriginY = fitsBelow ? caret.maxY + 6 : max(caret.minY - popupHeight - 6, 8)
                CompletionPopup(model: model)
                    .offset(x: popupOriginX, y: popupOriginY)
            }
            .transition(.opacity)
        }
    }
}

import SwiftUI
import ImageIO
import GraphiteCore
import GraphiteIndex

/// A `.canvas` file open in a tab: Obsidian's Canvas, the JSON Canvas format. Read shows
/// the board and follows links; Write selects, moves, resizes, connects, adds and edits,
/// with the same Write toggle, Undo, Redo and automatic saving as notes and PDFs.
struct CanvasPane: View {
    @Bindable var session: CanvasSession
    @Bindable var workspace: WorkspaceModel
    let tabID: UUID
    /// Whether this canvas's side of the split is focused; only then does the window's
    /// toolbar show its buttons.
    let isFocused: Bool
    @State private var renderCache = CanvasCardRenderCache()
    @State private var filePicker: CanvasFilePicker.Kind?
    @State private var showsReloadConfirmation = false
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.renameDocument) private var renameDocument
    @Environment(\.usesDocumentControlRow) private var usesDocumentControlRowSetting
    @Environment(\.showsDocumentControlsInTabBar) private var showsDocumentControlsInTabBar

    private var preferences: GraphitePreferences { workspace.preferences }
    private var usesDocumentControlRow: Bool {
        usesDocumentControlRowSetting ?? DocumentToolbarLayout.usesControlRow(detailWidth: nil, horizontalSizeClass: horizontalSizeClass)
    }

    var body: some View {
        VStack(spacing: 0) {
            banner
            if let cardEnvironment {
                CanvasBoardHost(session: session, environment: cardEnvironment)
                    .overlay(alignment: .topTrailing) { CanvasZoomControls(session: session).padding(12) }
                    .overlay(alignment: .bottom) {
                        if session.isWriting { CanvasAddBar(session: session, chooseFile: { kind in filePicker = kind }).padding(.bottom, 16) }
                    }
                    .overlay { if session.isWriting { CanvasSelectionBarPlacement(session: session, open: { path in open(path) }) } }
            }
        }
        #if canImport(UIKit)
        .safeAreaInset(edge: .top, spacing: 0) {
            if usesDocumentControlRow, !showsDocumentControlsInTabBar, isFocused {
                DocumentControlRow(isWriting: $session.isWriting) {
                    if session.isWriting { UndoRedoButtons(availability: session.undoAvailability) }
                }
            }
        }
        #endif
        .toolbar { if isFocused { toolbarContent } }
        .confirmationDialog("Replace your unsaved changes with the version saved by the other app?", isPresented: $showsReloadConfirmation, titleVisibility: .visible) {
            Button("Use Other Version", role: .destructive) { Task { do { try await session.reload() } catch { workspace.errorMessage = error.localizedDescription } } }
        }
        .sheet(item: $filePicker) { kind in
            CanvasFilePicker(workspace: workspace, kind: kind) { path in Task { await addFileCard(path) } }
        }
        .modifier(CanvasNameRequestAlert(session: session))
    }

    // MARK: What the cards need

    private var cardEnvironment: CanvasCardEnvironment? {
        guard let root = workspace.folderAccess?.root, let index = workspace.index else { return nil }
        let canvasPath = session.path
        return CanvasCardEnvironment(
            canvasPath: canvasPath, root: root, index: index, configuration: readingConfiguration, renderCache: renderCache,
            follow: { [workspace, tabID] target, isWiki, source in
                workspace.activateTab(tabID)
                Task { await workspace.follow(target, from: source, isWiki: isWiki) }
            },
            open: { path in open(path) },
            openPDF: { [workspace, tabID] path, pageIndex in
                workspace.activateTab(tabID)
                Task { await workspace.open(path, pdfPageIndex: pageIndex) }
            },
            baseContext: workspace.baseEmbedContext(for: canvasPath),
            imageActions: ReadingImageActions(providerIdentity: ObjectIdentifier(workspace), viewImage: { [workspace] path in
                workspace.viewedImageNote = nil
                workspace.viewedImage = path
            }, editDrawing: nil))
    }

    /// How Markdown on cards reads: as in reading view, without the properties, which an
    /// embedded note does not show either.
    private var readingConfiguration: ReadingConfiguration {
        ReadingConfiguration(usesReadableLineLength: false, usesStrictLineBreaks: workspace.vaultSettings.usesStrictLineBreaks,
                             colorsEnabled: preferences.isEnabled(.colors),
                             paletteHexByName: Dictionary(preferences.colorPalette.map { color in (color.name, color.hex) }, uniquingKeysWith: { firstHex, _ in firstHex }),
                             showsProperties: false, textSize: preferences.textSize, drawingVersion: workspace.drawingVersion, indexVersion: workspace.indexVersion)
    }

    /// Opens a file a card shows. This canvas's tab is focused first, so the file opens
    /// on this side of the split.
    private func open(_ path: VaultPath) {
        workspace.activateTab(tabID)
        Task { await workspace.open(path) }
    }

    private func addFileCard(_ path: VaultPath) async {
        guard let root = workspace.folderAccess?.root, let location = try? path.url(in: root) else { return }
        session.addFileCard(path, size: await CanvasFileCardSize.size(forFileAt: location, path: path))
    }

    // MARK: Banner and toolbar

    @ViewBuilder private var banner: some View {
        if session.hasExternalConflict {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text("This canvas changed in another app. Your changes are still here.").font(.callout)
                Spacer()
                Button("Save a Copy") { Task { await saveCopy() } }
                Button("Use Other Version") { showsReloadConfirmation = true }
            }
            .padding(.horizontal, 20).padding(.vertical, 12)
            .background(.orange.opacity(0.12))
        } else if let errorMessage = session.errorMessage {
            HStack(spacing: 12) {
                Label(errorMessage, systemImage: "exclamationmark.circle").font(.callout).foregroundStyle(.red)
                Spacer()
                Button("Dismiss") { session.errorMessage = nil }.font(.callout)
            }
            .padding(.horizontal, 20).padding(.vertical, 10)
            .background(.red.opacity(0.08))
        } else if session.file.unreadableNodeCount + session.file.unreadableEdgeCount > 0 {
            Label(Self.unreadableNotice(for: session.file), systemImage: "info.circle")
                .font(.callout).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20).padding(.vertical, 8)
                .background(.quaternary.opacity(0.4))
        }
    }

    /// What is said of entries Graphite cannot show: they are counted, and kept.
    static func unreadableNotice(for file: CanvasFile) -> String {
        var parts: [String] = []
        if file.unreadableNodeCount > 0 { parts.append(file.unreadableNodeCount == 1 ? "1 card" : "\(file.unreadableNodeCount) cards") }
        if file.unreadableEdgeCount > 0 { parts.append(file.unreadableEdgeCount == 1 ? "1 connection" : "\(file.unreadableEdgeCount) connections") }
        return parts.joined(separator: " and ") + " in this file cannot be shown. Graphite keeps them in the file as they are."
    }

    @ToolbarContentBuilder private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) { Group {
            #if canImport(UIKit)
            if !usesDocumentControlRow {
                if session.isWriting { UndoRedoButtons(availability: session.undoAvailability) }
                DocumentModeToggle(isWriting: $session.isWriting)
            }
            #endif
            Menu("More", systemImage: "ellipsis.circle") {
                Button("Zoom to Fit", systemImage: "arrow.up.left.and.arrow.down.right") { session.zoomToFit() }
                Button("Actual Size", systemImage: "1.magnifyingglass") { session.resetZoom() }
                if let renameDocument { Button("Rename…", systemImage: "pencil") { renameDocument.rename() } }
                if session.isWriting {
                    Divider()
                    Button("Select All", systemImage: "checkmark.circle") { session.selectAll() }
                        .keyboardShortcut("a", modifiers: .command)
                    Toggle("Snap to Grid", systemImage: "grid", isOn: $session.snapsToGrid)
                    Toggle("Snap to Objects", systemImage: "rectangle.split.2x1", isOn: $session.snapsToObjects)
                }
                Divider()
                Button("Save Now", systemImage: "square.and.arrow.down") { Task { try? await session.save() } }
                Button("Copy Graphite URL", systemImage: "link") { Pasteboard.copy(workspace.openingLink(to: session.path)) }
                if preferences.isEnabled(.bookmarks) {
                    let isBookmarked = workspace.bookmarks.fileBookmark(for: session.path) != nil
                    Button(isBookmarked ? "Remove Bookmark" : "Bookmark", systemImage: isBookmarked ? "bookmark.slash" : "bookmark") {
                        Task { await workspace.toggleBookmark(session.path) }
                    }
                }
            }
        }.tint(.primary) }
    }

    private func saveCopy() async {
        do {
            let path = try await session.saveSeparateCopy()
            await workspace.refreshDirectory()
            await workspace.open(path)
        } catch { workspace.errorMessage = error.localizedDescription }
    }
}

/// The size a new file card gets: a picture's follows its shape, a PDF's a page's.
enum CanvasFileCardSize {
    private static let pictureWidth: CGFloat = 400
    private static let pictureHeightRange: ClosedRange<CGFloat> = 80...1200

    static func size(forFileAt location: URL, path: VaultPath) async -> CGSize {
        let fileExtension = path.fileExtension
        if MediaFileKind.audioExtensions.contains(fileExtension) { return CGSize(width: 400, height: 120) }
        if MediaFileKind.videoExtensions.contains(fileExtension) { return CanvasSession.NewCardSize.media }
        switch DocumentKind(path: path) {
        case .image:
            let pixelSize = await Task.detached(priority: .userInitiated) { imagePixelSize(at: location) }.value
            guard let pixelSize, pixelSize.width > 0, pixelSize.height > 0 else { return CanvasSession.NewCardSize.media }
            let height = (pictureWidth * pixelSize.height / pixelSize.width).rounded()
            return CGSize(width: pictureWidth, height: min(max(height, pictureHeightRange.lowerBound), pictureHeightRange.upperBound))
        case .pdf:
            return CGSize(width: 400, height: 520)
        default:
            return CanvasSession.NewCardSize.note
        }
    }

    /// The picture's size from its header, without decoding it.
    private nonisolated static func imagePixelSize(at location: URL) -> CGSize? {
        guard let source = CGImageSourceCreateWithURL(location as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? CGFloat, let height = properties[kCGImagePropertyPixelHeight] as? CGFloat else { return nil }
        // A photo stored sideways is shown upright.
        let orientation = properties[kCGImagePropertyOrientation] as? Int ?? 1
        return orientation >= 5 ? CGSize(width: height, height: width) : CGSize(width: width, height: height)
    }
}

// MARK: Controls on the board

/// Zoom in, zoom out and "Zoom to fit", at the board's top-right corner as in Obsidian.
private struct CanvasZoomControls: View {
    let session: CanvasSession
    private static let zoomStep: CGFloat = 1.4

    var body: some View {
        VStack(spacing: 0) {
            Button("Zoom In", systemImage: "plus.magnifyingglass") { session.zoom(by: Self.zoomStep) }
                .disabled(session.viewport.scale >= CanvasViewport.maximumScale)
            Divider().frame(width: 28)
            Button("Zoom Out", systemImage: "minus.magnifyingglass") { session.zoom(by: 1 / Self.zoomStep) }
                .disabled(session.viewport.scale <= CanvasViewport.minimumScale)
            Divider().frame(width: 28)
            Button("Zoom to Fit", systemImage: "arrow.up.left.and.arrow.down.right") { session.zoomToFit() }
                .accessibilityIdentifier("canvasZoomToFit")
        }
        .labelStyle(.iconOnly)
        .buttonStyle(CanvasBarButtonStyle())
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(.separator) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Zoom")
        .accessibilityValue("\(Int((session.viewport.scale * 100).rounded())) percent")
    }
}

/// A square button of the board's floating bars, large enough for a finger.
private struct CanvasBarButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
            .foregroundStyle(isEnabled ? .primary : .tertiary)
            .opacity(configuration.isPressed ? 0.5 : 1)
    }
}

/// The cards that can be added, at the bottom of the board while writing, as in Obsidian.
private struct CanvasAddBar: View {
    let session: CanvasSession
    let chooseFile: (CanvasFilePicker.Kind) -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button("Add Text Card", systemImage: "note.text.badge.plus") { session.addTextCard() }
                .accessibilityIdentifier("canvasAddText")
            Button("Add Note from Vault", systemImage: "doc.text") { chooseFile(.note) }
            Button("Add Media from Vault", systemImage: "photo") { chooseFile(.media) }
            Button("Add Web Link", systemImage: "globe") { session.endEditing(); session.nameRequest = .webAddress }
            Button("Add Group", systemImage: "rectangle.dashed") { session.addGroup() }
        }
        .labelStyle(.iconOnly)
        .buttonStyle(CanvasBarButtonStyle())
        .padding(.horizontal, 6)
        .background(.regularMaterial, in: Capsule())
        .overlay { Capsule().strokeBorder(.separator) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Add to canvas")
    }
}

/// Puts the selection's bar just above the selection, or below it near the top of the
/// board, and keeps it on screen when the selection is not.
private struct CanvasSelectionBarPlacement: View {
    let session: CanvasSession
    let open: (VaultPath) -> Void
    @State private var barSize = CGSize(width: 240, height: 48)
    private static let gap: CGFloat = 40

    var body: some View {
        // Hidden during a drag, which would drag the bar along under the finger.
        let isDragging = !session.previewFrames.isEmpty || session.selectionRectangle != nil || session.pendingConnection != nil
        if session.hasSelection, !isDragging, let selectionBounds = session.selectionBounds {
            GeometryReader { geometry in
                let selectionFrame = session.viewport.viewFrame(forBoardFrame: selectionBounds)
                let halfWidth = barSize.width / 2, halfHeight = barSize.height / 2
                let fitsAbove = selectionFrame.minY - Self.gap - halfHeight >= halfHeight + 8
                let centerY = fitsAbove ? selectionFrame.minY - Self.gap : selectionFrame.maxY + Self.gap
                CanvasSelectionBar(session: session, open: open)
                    .onGeometryChange(for: CGSize.self) { barGeometry in barGeometry.size } action: { size in barSize = size }
                    .position(x: min(max(selectionFrame.midX, halfWidth + 8), max(geometry.size.width - halfWidth - 8, halfWidth + 8)),
                              y: min(max(centerY, halfHeight + 8), max(geometry.size.height - halfHeight - 80, halfHeight + 8)))
            }
        }
    }
}

/// What can be done with the selected cards and connections.
private struct CanvasSelectionBar: View {
    let session: CanvasSession
    let open: (VaultPath) -> Void
    @State private var showsColors = false

    var body: some View {
        let nodes = session.selectedNodes, edges = session.selectedEdges
        let onlyNode = nodes.count == 1 && edges.isEmpty ? nodes.first : nil
        let onlyEdge = edges.count == 1 && nodes.isEmpty ? edges.first : nil
        HStack(spacing: 0) {
            if session.textEdit != nil {
                Button("Done") { session.endEditing() }
                    .font(.body.weight(.semibold))
                    .padding(.horizontal, 10)
                    .accessibilityIdentifier("canvasDoneEditing")
            } else {
                Button("Delete", systemImage: "trash") { session.deleteSelection() }
                    .keyboardShortcut(.delete, modifiers: [])
                    .accessibilityIdentifier("canvasDelete")
                Button("Color", systemImage: "paintpalette") { showsColors = true }
                    .popover(isPresented: $showsColors) {
                        CanvasColorChooser(currentColor: Self.sharedColor(of: nodes, edges)) { color in
                            session.setColorOfSelection(color)
                            showsColors = false
                        }
                    }
                Button("Zoom to Selection", systemImage: "arrow.up.left.and.arrow.down.right") { session.zoomToSelection() }
                if let onlyNode {
                    switch onlyNode.content {
                    case .text: Button("Edit Text", systemImage: "pencil") { session.beginEditingText(of: onlyNode.id) }
                    case .group: Button("Rename Group", systemImage: "pencil") { session.nameRequest = .groupLabel(nodeIdentifier: onlyNode.id) }
                    case .file(let path, _):
                        if let vaultPath = try? VaultPath(path) { Button("Open File", systemImage: "arrow.up.forward.square") { open(vaultPath) } }
                    case .link, .unknown: EmptyView()
                    }
                }
                if let onlyEdge {
                    Button("Edit Label", systemImage: "character.cursor.ibeam") { session.nameRequest = .edgeLabel(edgeIdentifier: onlyEdge.id) }
                }
                if !edges.isEmpty && nodes.isEmpty { lineEndsMenu(for: edges) }
                if !nodes.isEmpty {
                    Button("Duplicate", systemImage: "plus.square.on.square") { session.duplicateSelection() }
                        .keyboardShortcut("d", modifiers: .command)
                    Menu("Arrange", systemImage: "square.3.layers.3d") {
                        Button("Bring to Front", systemImage: "square.3.layers.3d.top.filled") { session.bringSelectionToFront() }
                        Button("Send to Back", systemImage: "square.3.layers.3d.bottom.filled") { session.sendSelectionToBack() }
                        Divider()
                        Button("Group Selection", systemImage: "rectangle.dashed") { session.addGroup() }
                    }
                }
            }
        }
        .labelStyle(.iconOnly)
        .buttonStyle(CanvasBarButtonStyle())
        .menuStyle(.button)
        .padding(.horizontal, 6)
        .background(.regularMaterial, in: Capsule())
        .overlay { Capsule().strokeBorder(.separator) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Selection")
    }

    /// The color every selected card and connection has, when they all have the same.
    private static func sharedColor(of nodes: [CanvasNode], _ edges: [CanvasEdge]) -> CanvasColor? {
        let colors = Set(nodes.map(\.color) + edges.map(\.color))
        return colors.count == 1 ? colors.first ?? nil : nil
    }

    /// Where a connection has arrows, named in words, with the current choice checked.
    private func lineEndsMenu(for edges: [CanvasEdge]) -> some View {
        let choices: [(title: String, fromEnd: CanvasEdgeEnd, toEnd: CanvasEdgeEnd)] = [
            ("Arrow at the End", .none, .arrow), ("Arrow at the Start", .arrow, .none), ("Arrows at Both Ends", .arrow, .arrow), ("No Arrows", .none, .none),
        ]
        return Menu("Line Ends", systemImage: "arrow.left.and.right") {
            ForEach(choices, id: \.title) { choice in
                let isCurrent = edges.allSatisfy { edge in edge.fromEnd == choice.fromEnd && edge.toEnd == choice.toEnd }
                Button { session.setEndsOfSelectedEdges(fromEnd: choice.fromEnd, toEnd: choice.toEnd) } label: {
                    if isCurrent { Label(choice.title, systemImage: "checkmark") } else { Text(choice.title) }
                }
            }
        }
    }
}

/// The six colors of the format by name, no color, and a color of one's own. The current
/// choice carries a check mark, so it is not told by its ring alone.
private struct CanvasColorChooser: View {
    let currentColor: CanvasColor?
    let choose: (CanvasColor?) -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var customColor = Color.blue

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                ForEach(CanvasColor.presets, id: \.self) { preset in
                    Button { choose(preset) } label: {
                        Circle().fill(CanvasPalette.color(preset, colorScheme: colorScheme))
                            .frame(width: 36, height: 36)
                            .overlay { if currentColor == preset { Image(systemName: "checkmark").font(.body.weight(.bold)).foregroundStyle(.white) } }
                            .overlay { Circle().strokeBorder(.primary.opacity(currentColor == preset ? 0.9 : 0.15), lineWidth: currentColor == preset ? 3 : 1) }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(preset.name)
                    .accessibilityAddTraits(currentColor == preset ? .isSelected : [])
                }
            }
            Button { choose(nil) } label: {
                Label("No Color", systemImage: currentColor == nil ? "checkmark.circle" : "circle.slash")
            }
            .accessibilityAddTraits(currentColor == nil ? .isSelected : [])
            Divider()
            HStack {
                ColorPicker("Custom Color", selection: $customColor, supportsOpacity: false)
                Button("Apply") {
                    if let hex = customColor.sRGBHex, let color = CanvasColor(text: hex) { choose(color) }
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(16)
        .frame(minWidth: 300)
        .presentationCompactAdaptation(.popover)
        .onAppear {
            if case .custom(let red, let green, let blue)? = currentColor {
                customColor = Color(.sRGB, red: Double(red) / 255, green: Double(green) / 255, blue: Double(blue) / 255)
            }
        }
    }
}

// MARK: Names and files

/// Asks for a group's name, a connection's label, or a web address, in a small alert.
private struct CanvasNameRequestAlert: ViewModifier {
    let session: CanvasSession
    @State private var text = ""

    func body(content: Content) -> some View {
        let request = session.nameRequest
        content
            .alert(title(for: request), isPresented: Binding(get: { session.nameRequest != nil }, set: { isPresented in if !isPresented { session.nameRequest = nil } }),
                   presenting: request) { request in
                TextField(prompt(for: request), text: $text)
                    #if canImport(UIKit)
                    .textInputAutocapitalization(request == .webAddress ? .never : .sentences)
                    .keyboardType(request == .webAddress ? .URL : .default)
                    #endif
                    .autocorrectionDisabled(request == .webAddress)
                Button(request == .webAddress ? "Add" : "Done") { apply(text, to: request) }
                Button("Cancel", role: .cancel) {}
            }
            .onChange(of: request) { _, newRequest in
                guard let newRequest else { return }
                text = currentText(for: newRequest)
            }
    }

    private func title(for request: CanvasNameRequest?) -> String {
        switch request {
        case .groupLabel: "Group Name"
        case .edgeLabel: "Connection Label"
        case .webAddress, nil: "Add Web Link"
        }
    }

    private func prompt(for request: CanvasNameRequest) -> String {
        switch request {
        case .groupLabel: "Name"
        case .edgeLabel: "Label"
        case .webAddress: "https://…"
        }
    }

    private func currentText(for request: CanvasNameRequest) -> String {
        switch request {
        case .groupLabel(let nodeIdentifier):
            if case .group(let label, _, _)? = session.file.node(withIdentifier: nodeIdentifier)?.content { return label ?? "" }
            return ""
        case .edgeLabel(let edgeIdentifier): return session.file.edge(withIdentifier: edgeIdentifier)?.label ?? ""
        case .webAddress: return ""
        }
    }

    private func apply(_ text: String, to request: CanvasNameRequest) {
        switch request {
        case .groupLabel(let nodeIdentifier): session.setGroupLabel(text, nodeIdentifier: nodeIdentifier)
        case .edgeLabel(let edgeIdentifier): session.setEdgeLabel(text, edgeIdentifier: edgeIdentifier)
        case .webAddress: session.addLinkCard(address: text)
        }
    }
}

/// Chooses a file of the vault for a new card: a note, or a picture, PDF, recording or
/// video. Recent files are listed until something is typed.
struct CanvasFilePicker: View {
    enum Kind: String, Identifiable {
        case note, media
        var id: String { rawValue }

        func includes(_ path: VaultPath) -> Bool {
            switch DocumentKind(path: path) {
            case .markdown: self == .note
            case .image, .pdf, .media: self == .media
            case .base, .canvas, .other: false
            }
        }
    }

    @Bindable var workspace: WorkspaceModel
    let kind: Kind
    let choose: (VaultPath) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var paths: [VaultPath] = []
    private static let recentFileCount = 30
    private static let matchLimit = 200

    var body: some View {
        NavigationStack {
            List(paths) { path in
                Button {
                    choose(path)
                    dismiss()
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(workspace.preferences.displayName(for: path))
                            if !path.parent.rawValue.isEmpty { Text(path.parent.rawValue).font(.caption).foregroundStyle(.secondary) }
                        }
                    } icon: { Image(systemName: DocumentKind(path: path).systemImage) }
                }
            }
            .overlay {
                if paths.isEmpty {
                    if query.trimmingCharacters(in: .whitespaces).isEmpty {
                        ContentUnavailableView(kind == .note ? "Find a Note" : "Find a File", systemImage: "magnifyingglass", description: Text("Type part of its name."))
                    } else {
                        ContentUnavailableView.search(text: query)
                    }
                }
            }
            .searchable(text: $query, prompt: kind == .note ? "Find a note" : "Find a picture, PDF, recording, or video")
            .navigationTitle(kind == .note ? "Add Note from Vault" : "Add Media from Vault")
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .task(id: query) {
                let trimmedQuery = query.trimmingCharacters(in: .whitespaces)
                guard !trimmedQuery.isEmpty else {
                    paths = workspace.existingRecentFiles(limit: Self.recentFileCount).filter(kind.includes)
                    return
                }
                do {
                    try await Task.sleep(for: .milliseconds(150))
                    let matches = try await workspace.index?.quickSwitcherMatches(for: trimmedQuery, limit: Self.matchLimit) ?? []
                    var seenPaths: Set<VaultPath> = []
                    paths = matches.map(\.path).filter { path in kind.includes(path) && seenPaths.insert(path).inserted }
                } catch is CancellationError {
                } catch { workspace.errorMessage = error.localizedDescription }
            }
        }
        .frame(minWidth: 340, minHeight: 450)
    }
}

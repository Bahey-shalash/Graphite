import SwiftUI
import PDFKit
import UniformTypeIdentifiers
import GraphiteCore
import GraphiteApple

/// Device preference keys for PDF annotation.
enum PDFAnnotationPreferenceKey {
    static let drawsWithFinger = "GraphitePDFDrawsWithFinger"
    static let showsToolPicker = "GraphitePDFShowsToolPicker"
    /// Shared with the drawing editor: the shape tool is on or off for every canvas.
    static let drawsShapes = "GraphiteDrawsShapes"
    /// Lines or dots shown on PDF pages while writing, and their spacing; never saved.
    static let writingGuidePattern = "GraphitePDFWritingGuidePattern"
    static let writingGuideSpacing = "GraphitePDFWritingGuideSpacing"

    /// Light gray, so the guides stay behind the page's own content.
    static func writingGuides(pattern: DrawingPaperPattern, spacing: DrawingPaperSpacing) -> DrawingPaper {
        DrawingPaper(pattern: pattern, appearsInSavedDrawing: false, spacing: spacing, lineColor: .gray, lineStrength: .light)
    }
}

/// A PDF open as a notebook or slide deck: Pencil ink on every page, text markup, page
/// thumbnails and page management, with automatic saving.
struct PDFPane: View {
    let session: PDFSession
    /// Whether this PDF's side of the split is focused; only then does the window's
    /// toolbar show its buttons.
    var isFocused = true
    /// Focuses this PDF's side when drawing or text selection begins on it.
    var focus: () -> Void = {}
    /// Links to pages and quotes for notes, from the selection menu and the toolbar.
    var linkActions: PDFLinkActions?
    var readAloud: ReadAloudController?
    /// Moves reading around, and the Read Aloud pen's start and end.
    var readAloudNavigator: ReadAloudNavigator?
    var isRecording = false
    let resolveConflict: (URL) -> Void

    var body: some View {
        // The workspace replaces the session when the file is reloaded. The PDF view, its
        // canvases, and the page commands belong to one session, so they are rebuilt.
        PDFPaneContent(session: session, isFocused: isFocused, focus: focus, linkActions: linkActions,
                       readAloud: readAloud, readAloudNavigator: readAloudNavigator, isRecording: isRecording, resolveConflict: resolveConflict)
            .id(ObjectIdentifier(session))
    }
}

private struct PDFPaneContent: View {
    @Bindable var session: PDFSession
    let isFocused: Bool
    let focus: () -> Void
    let linkActions: PDFLinkActions?
    let readAloud: ReadAloudController?
    let readAloudNavigator: ReadAloudNavigator?
    let isRecording: Bool
    let resolveConflict: (URL) -> Void
    @State private var commands: PDFPageCommands
    @State private var thumbnailRenderer = PDFThumbnailRenderer()
    @State private var showsPages = false
    @State private var showsPageJump = false
    @State private var showsReloadConfirmation = false
    @State private var showsSignatureConfirmation = false
    @State private var showsReadingPageRange = false
    @State private var showsReadingSection = false
    @State private var pendingReadingPageRange: (first: Int, last: Int)?
    @State private var readingStart: PDFReadAloudEndpoint?
    @AppStorage(PDFAnnotationPreferenceKey.drawsWithFinger) private var drawsWithFinger = false
    @AppStorage(PDFAnnotationPreferenceKey.showsToolPicker) private var showsToolPicker = true
    @Environment(\.renameDocument) private var renameDocument
    #if canImport(UIKit)
    @AppStorage(PDFAnnotationPreferenceKey.drawsShapes) private var drawsShapes = false
    @AppStorage(PDFAnnotationPreferenceKey.writingGuidePattern) private var writingGuidePattern = DrawingPaperPattern.plain
    @AppStorage(PDFAnnotationPreferenceKey.writingGuideSpacing) private var writingGuideSpacing = DrawingPaperSpacing.standard
    @AppStorage(PencilToolbarStyle.preferenceKey) private var toolbarStyle = PencilToolbarStyle.floating
    @State private var toolbox = PencilToolbox.shared
    @State private var pictureSource: PDFPictureSource?
    /// The fixed bar takes the place of the floating palette; compact layouts keep the palette.
    private var usesFixedToolbar: Bool { toolbarStyle == .fixed && horizontalSizeClass != .compact }
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.usesDocumentControlRow) private var usesDocumentControlRowSetting
    @Environment(\.showsDocumentControlsInTabBar) private var showsDocumentControlsInTabBar
    @Environment(\.showsPencilToolsInTabBar) private var showsPencilToolsInTabBar
    private var usesDocumentControlRow: Bool {
        usesDocumentControlRowSetting ?? DocumentToolbarLayout.usesControlRow(detailWidth: nil, horizontalSizeClass: horizontalSizeClass)
    }
    /// A phone, or an iPad window as narrow as one: a lean navigation bar, and the bottom
    /// bar gives way to the palette while writing.
    private var isCompactWidth: Bool { horizontalSizeClass == .compact }
    #endif

    init(session: PDFSession, isFocused: Bool, focus: @escaping () -> Void, linkActions: PDFLinkActions?,
         readAloud: ReadAloudController?, readAloudNavigator: ReadAloudNavigator?, isRecording: Bool, resolveConflict: @escaping (URL) -> Void) {
        self.session = session
        self.isFocused = isFocused
        self.focus = focus
        self.linkActions = linkActions
        self.readAloud = readAloud
        self.readAloudNavigator = readAloudNavigator
        self.isRecording = isRecording
        self.resolveConflict = resolveConflict
        _commands = State(initialValue: PDFPageCommands(session: session))
    }

    /// While this PDF is read, where its highlighted word is, for the floating player.
    private var reportReadingHighlightFrame: ((CGRect?, CGRect?) -> Void)? {
        guard let readAloud, let readAloudNavigator else { return nil }
        let path = session.location.path
        return { frame, window in
            guard readAloud.sourceIdentifier == path else { return }
            if readAloudNavigator.highlightFrameInWindow != frame { readAloudNavigator.highlightFrameInWindow = frame }
            if readAloudNavigator.windowBounds != window { readAloudNavigator.windowBounds = window }
        }
    }

    private var readAloudMarkers: [PDFReadAloudMarker] {
        guard let readAloudNavigator else { return [] }
        let marks = readAloudNavigator.penMarks(for: session.location.path)
        return marks.enumerated().compactMap { index, mark in
            mark.located(in: session.document).map { located in PDFReadAloudMarker(pageIndex: located.pageIndex, bounds: located.bounds, isStart: index == 0) }
        }
    }

    /// A tap of the Read Aloud pen: the first reads from the word, the second reads exactly
    /// from the first word to this one (`ReadAloudNavigator.penTapped`).
    private func readWithPen(_ tap: PDFReadAloudPenTap) {
        guard let readAloud, let readAloudNavigator else { return }
        switch tap {
        case .page(let pageIndex):
            readAloudNavigator.clearPenMarks()
            readAloud.readPDF(session, firstPageIndex: pageIndex, lastPageIndex: session.pageCount - 1)
        case .word(let pageIndex, let range, let bounds):
            var mark = ReadAloudNavigator.PenMark(sourceIdentifier: session.location.path, pageIndex: pageIndex, range: range, bounds: bounds)
            if let pageText = session.document.page(at: pageIndex)?.string as NSString?, NSMaxRange(range) <= pageText.length {
                let contextStart = max(0, range.location - 40)
                let contextEnd = min(pageText.length, NSMaxRange(range) + 40)
                mark.context = pageText.substring(with: NSRange(location: contextStart, length: contextEnd - contextStart))
                mark.wordOffsetInContext = range.location - contextStart
            }
            switch readAloudNavigator.penTapped(mark) {
            case .readFrom(let start):
                readAloud.readPDFRange(session, start: PDFReadAloudEndpoint(pageIndex: start.pageIndex, offset: start.range.location, revision: session.readingTextVersion))
            case .readRange(let start, let end):
                let session = session
                // Repeat finds both words again by their text, in case pages moved meanwhile.
                let read = {
                    guard let start = start.located(in: session.document), let end = end.located(in: session.document) else { return }
                    readAloud.readPDFRange(session, start: PDFReadAloudEndpoint(pageIndex: start.pageIndex, offset: start.range.location, revision: session.readingTextVersion),
                                           end: PDFReadAloudEndpoint(pageIndex: end.pageIndex, offset: NSMaxRange(end.range), revision: session.readingTextVersion))
                }
                readAloudNavigator.readingPenRange(replay: read)
                read()
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            statusBanner
            HStack(spacing: 0) {
                if showsPages {
                    PDFPagesSidebar(session: session, commands: commands, renderer: thumbnailRenderer)
                        .frame(width: 210)
                        .transition(GraphiteMotion.slide(from: .leading))
                    Divider()
                }
                // The tool picker belongs to the focused side; it would cover the other one.
                // A protected PDF is not annotated, so PDFKit's own text selection applies.
                GraphitePDFView(session: session,
                                input: annotationInput,
                                initialPageIndex: session.currentPageIndex > 0 ? session.currentPageIndex : nil, beginInteraction: focus,
                                linkActions: linkActions,
                                beginWritingWithPencil: session.isProtected ? nil : { focus(); session.isWriting = true },
                                readingHighlights: readAloud?.highlights(in: session) ?? [],
                                followsReading: readAloud?.shouldFollow(session) ?? false,
                                suspendReadingFollow: { readAloud?.suspendFollowing(in: session.location.path) },
                                reportReadingHighlightFrame: reportReadingHighlightFrame,
                                readAloudPen: readAloud == nil || readAloudNavigator == nil ? nil : { tap in readWithPen(tap) },
                                readAloudMarkers: readAloudMarkers,
                                reportPaletteFrame: readAloudNavigator.map { navigator in { frame in
                                    if navigator.coveredFrameInWindow != frame { navigator.coveredFrameInWindow = frame }
                                } })
                    .ignoresSafeArea(edges: .bottom)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            #if canImport(UIKit)
            VStack(spacing: 0) {
                let showsControlRow = usesDocumentControlRow && !showsDocumentControlsInTabBar && isFocused && !session.isProtected
                // The bar stays while a picture is arranged: removing it would move the page
                // under the finger.
                let showsFixedToolbar = !showsPencilToolsInTabBar
                    && session.showsFixedPencilTools(style: toolbarStyle, showsTools: showsToolPicker, horizontalSizeClass: horizontalSizeClass, isFocused: isFocused)
                if showsControlRow && showsFixedToolbar {
                    // One row for both, as in Focus, where no tab bar holds the controls.
                    PencilToolbar(toolbox: toolbox, drawsShapes: $drawsShapes,
                                  addImage: { pictureSource = .photoLibrary }, undoAvailability: session.undoAvailability,
                                  offersReadAloudPen: readAloud != nil) {
                        EmptyView()
                    } trailingControls: {
                        HStack(spacing: 12) {
                            UndoRedoButtons(availability: session.undoAvailability)
                                .buttonStyle(.borderless)
                                .tint(.secondary)
                            DocumentModeToggle(isWriting: $session.isWriting, drawsOwnBackground: true)
                        }
                    }
                } else if showsControlRow {
                    DocumentControlRow(isWriting: $session.isWriting) {
                        UndoRedoButtons(availability: session.undoAvailability)
                    }
                } else if showsFixedToolbar {
                    PencilToolbar(toolbox: toolbox, drawsShapes: $drawsShapes,
                                  addImage: { pictureSource = .photoLibrary }, undoAvailability: session.undoAvailability,
                                  offersReadAloudPen: readAloud != nil)
                }
            }
            #endif
        }
        #if canImport(UIKit)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if session.isWriting, session.selectedPicture != nil { PDFPictureArrangementBar(session: session) }
        }
        // A phone's palette docks at the bottom of the screen, over the bar that moves
        // between files; the bar comes back when the palette goes.
        .toolbar(isCompactWidth && annotationInput.showsToolPicker ? .hidden : .automatic, for: .bottomBar)
        .modifier(PDFPictureAdding(session: session, source: $pictureSource))
        // Reading is not arranging, and neither is taking up a tool.
        .onChange(of: session.isWriting) { _, isWriting in if !isWriting { session.selectedPicture = nil } }
        .onChange(of: toolbox.selection) { _, _ in session.selectedPicture = nil }
        #endif
        .onChange(of: session.readingTextVersion) { _, _ in readingStart = nil }
        .onAppear {
            // Maps the snapshot now, before an autosave can replace it, so thumbnails are
            // drawn from the file rather than from the live document.
            thumbnailRenderer.prepare(for: session.document)
            // An embed of this PDF that starts annotating saves this pane's edits first.
            EmbeddedPDFSessions.shared.add(session)
        }
        .onDisappear {
            thumbnailRenderer.removeThumbnails()
            EmbeddedPDFSessions.shared.remove(session)
        }
        .toolbar { if isFocused { toolbarContent } }
        .sheet(isPresented: $showsReadingPageRange, onDismiss: {
            if let range = pendingReadingPageRange {
                pendingReadingPageRange = nil
                readAloud?.readPDF(session, firstPageIndex: range.first, lastPageIndex: range.last)
            }
        }) {
            ReadAloudPDFRangePicker(pageCount: session.pageCount, startingPageIndex: session.currentPageIndex) { first, last in
                pendingReadingPageRange = (first, last)
            }
        }
        .sheet(isPresented: $showsReadingSection, onDismiss: {
            if let range = pendingReadingPageRange {
                pendingReadingPageRange = nil
                readAloud?.readPDF(session, firstPageIndex: range.first, lastPageIndex: range.last)
            }
        }) {
            ReadAloudPDFSectionPicker(entries: session.outlineEntries, pageCount: session.pageCount) { pages in
                pendingReadingPageRange = (pages.lowerBound, pages.upperBound)
            }
        }
        // The page shown sits under the title rather than in the toolbar, which leaves the
        // title room; a phone shows it in More, beside Go to Page.
        .modifier(NavigationSubtitle(text: isFocused && !isCompactWidthOnAnyPlatform ? "Page \(session.currentPageIndex + 1) of \(session.pageCount)" : nil))
        .modifier(PDFPageCommandDialogs(commands: commands))
        .confirmationDialog(session.hasExternalConflict ? "Reload the PDF and discard the unsaved edits in this editor?" : "Discard the edits that could not be saved and reload the PDF?",
                            isPresented: $showsReloadConfirmation, titleVisibility: .visible) {
            Button(session.hasExternalConflict ? "Reload External Version" : "Discard Edits", role: .destructive) { resolveConflict(session.location) }
        }
        .confirmationDialog("Edit this signed PDF?", isPresented: $showsSignatureConfirmation, titleVisibility: .visible) {
            Button("Edit and Invalidate Signature", role: .destructive) { session.acceptsSignatureInvalidation = true }
        } message: {
            Text("Saving any change rewrites the file, and PDF apps will then report its signature as invalid. To keep the signed original, duplicate the file and edit the copy.")
        }
    }

    private var annotationInput: PDFAnnotationInput {
        let isAnnotating = session.isWriting && !session.isProtected
        #if canImport(UIKit)
        // The palette gives way to the fixed bar, and to the bar that arranges a picture.
        return PDFAnnotationInput(isEnabled: isAnnotating, drawsWithFinger: drawsWithFinger,
                                  showsToolPicker: showsToolPicker && isFocused && isAnnotating && !usesFixedToolbar && session.selectedPicture == nil,
                                  drawsShapes: drawsShapes, isFocused: isFocused && isAnnotating,
                                  fixedTool: usesFixedToolbar ? toolbox.selection : nil,
                                  writingGuides: PDFAnnotationPreferenceKey.writingGuides(pattern: writingGuidePattern, spacing: writingGuideSpacing))
        #else
        return PDFAnnotationInput(isEnabled: isAnnotating, drawsWithFinger: drawsWithFinger, showsToolPicker: false)
        #endif
    }

    @ViewBuilder private var statusBanner: some View {
        if session.isPasswordProtected && session.errorMessage == nil {
            HStack(spacing: 10) {
                Image(systemName: "lock.fill").foregroundStyle(.secondary)
                Text("This PDF is protected by a password, so Graphite shows it without changing it: ink, markup and page changes are off.")
                    .font(.callout).foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 20).padding(.vertical, 10)
            .background(.quaternary.opacity(0.5))
        } else if session.isProtected && session.errorMessage == nil {
            HStack(spacing: 10) {
                Image(systemName: "signature").foregroundStyle(.secondary)
                Text("This PDF is digitally signed. Changing it would invalidate the signature, so ink, markup and page changes are off.")
                    .font(.callout).foregroundStyle(.secondary)
                Spacer()
                Button("Edit Anyway") { showsSignatureConfirmation = true }
            }
            .padding(.horizontal, 20).padding(.vertical, 10)
            .background(.quaternary.opacity(0.5))
        } else if session.hasExternalConflict {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text("This PDF changed in another app. Your annotations are still here.").font(.callout)
                Spacer()
                Button("Save a Copy", action: saveSeparateCopy)
                Button("Use Other Version") { showsReloadConfirmation = true }
            }
            .padding(.horizontal, 20).padding(.vertical, 12)
            .background(.orange.opacity(0.12))
        } else if let errorMessage = session.errorMessage {
            HStack {
                Label(errorMessage, systemImage: "exclamationmark.circle").font(.callout).foregroundStyle(.red)
                Spacer()
                // A save that keeps failing would otherwise hold the tab: opening another
                // file or vault saves first and stops when that fails.
                if session.hasFailedSave && session.hasUnsavedChanges {
                    Button("Save a Copy", action: saveSeparateCopy)
                    Button("Discard Edits") { showsReloadConfirmation = true }
                }
                Button("Dismiss", systemImage: "xmark") { session.errorMessage = nil }.labelStyle(.iconOnly).buttonStyle(.borderless)
            }
            .padding(.horizontal, 20).padding(.vertical, 10)
            .background(.red.opacity(0.08))
        }
    }

    /// Writes the PDF with the unsaved edits to a new file beside it and shows that file.
    private func saveSeparateCopy() {
        Task {
            do { resolveConflict(try await session.saveSeparateCopy()) }
            catch { session.errorMessage = error.localizedDescription }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        // Neutral icons, as in Obsidian; the accent is kept for selection and toggles. A
        // compact width shows only Undo, Redo, Write and More: the pages, the search and
        // adding pages are in More, and while writing, the palette has its own Undo and Redo.
        ToolbarItemGroup(placement: .primaryAction) { Group {
            if !isCompactWidthOnAnyPlatform {
                Button(showsPages ? "Hide Pages" : "Show Pages", systemImage: "square.grid.2x2") {
                    withAnimation(GraphiteMotion.animation(.snappy)) { showsPages.toggle() }
                }
                #if canImport(UIKit)
                Button("Find in PDF", systemImage: "magnifyingglass") { presentFindNavigator() }
                #endif
            }
            if !session.isProtected {
                if !isCompactWidthOnAnyPlatform {
                    PDFAddPageMenu(commands: commands, insertionIndexAfter: session.currentPageIndex + 1, insertionIndexBefore: session.currentPageIndex)
                }
                #if canImport(UIKit)
                if !usesDocumentControlRow {
                    // The floating palette has Undo and Redo of its own.
                    if !annotationInput.showsToolPicker && (!isCompactWidth || session.isWriting) {
                        UndoRedoButtons(availability: session.undoAvailability)
                    }
                    DocumentModeToggle(isWriting: $session.isWriting)
                }
                #else
                UndoRedoButtons(availability: session.undoAvailability)
                #endif
            }
            Menu("More", systemImage: "ellipsis") { moreMenuItems }
                // A sheet rather than a popover from the menu, which may not show once the
                // menu has closed.
                .sheet(isPresented: $showsPageJump) {
                    pageJumpField
                        .padding(20)
                        .presentationDetents([.height(140)])
                }
        }.tint(.primary) }
    }

    @ViewBuilder private var moreMenuItems: some View {
        if let readAloud {
            Menu("Read Aloud", systemImage: "speaker.wave.2") {
                Button("Read Document") {
                    // Goes on from the page where reading last stopped.
                    let remembered = ReadAloudNavigator.rememberedLocation(for: session.location.path) ?? 0
                    let first = min(max(0, remembered), max(0, session.pageCount - 1))
                    readAloud.readPDF(session, firstPageIndex: first, lastPageIndex: session.pageCount - 1)
                }
                Button("Read This Page") { readAloud.readPDF(session, firstPageIndex: session.currentPageIndex, lastPageIndex: session.currentPageIndex) }
                Button("Read From This Page") { readAloud.readPDF(session, firstPageIndex: session.currentPageIndex, lastPageIndex: session.pageCount - 1) }
                Button("Choose Page Range…") { showsReadingPageRange = true }
                Button("Read Section Pages…") { showsReadingSection = true }
                    .disabled(!session.outlineEntries.contains { $0.readingPages(in: session.outlineEntries, pageCount: session.pageCount) != nil })
                Button("Read Selection") {
                    readAloud.readPDFSelection(session)
                }.disabled(session.readAloudSelection == nil)
                Button("Read From Here") { readAloud.readPDFFromSelection(session) }
                    .disabled(session.readAloudSelection == nil)
                Divider()
                Button("Set Reading Start") {
                    do { readingStart = try PDFReadAloudSource.endpoint(in: session, isEnd: false) }
                    catch { session.errorMessage = error.localizedDescription }
                }.disabled(session.readAloudSelection == nil)
                if let readingStart {
                    Text("Start: page \(readingStart.pageIndex + 1)")
                    Button("Read Through Here") {
                        do { readAloud.readPDFRange(session, start: readingStart, end: try PDFReadAloudSource.endpoint(in: session, isEnd: true)) }
                        catch { session.errorMessage = error.localizedDescription }
                    }.disabled(session.readAloudSelection == nil)
                    Button("Clear Reading Start") { self.readingStart = nil }
                }
            }.disabled(isRecording || !session.document.allowsCopying)
        }
        if isCompactWidthOnAnyPlatform {
            Section {
                Button(showsPages ? "Hide Pages" : "Show Pages", systemImage: "square.grid.2x2") {
                    withAnimation(GraphiteMotion.animation(.snappy)) { showsPages.toggle() }
                }
                goToPageButton
                #if canImport(UIKit)
                Button("Find in PDF", systemImage: "magnifyingglass") { presentFindNavigator() }
                #endif
                if !session.isProtected {
                    PDFAddPageMenu(commands: commands, insertionIndexAfter: session.currentPageIndex + 1, insertionIndexBefore: session.currentPageIndex)
                }
                if let renameDocument { Button("Rename…", systemImage: "pencil") { renameDocument.rename() } }
            }
        }
        if let linkActions {
            Button("Copy Link to This Page", systemImage: "link") { linkActions.copyLink(session.currentPageIndex) }
            Divider()
        }
        if !session.isProtected {
            #if canImport(UIKit)
            if session.isWriting {
                Toggle("Show Pencil Tools", systemImage: "pencil.tip.crop.circle", isOn: $showsToolPicker)
            }
            Toggle("Draw with Finger", systemImage: "hand.draw", isOn: $drawsWithFinger)
            Toggle("Draw Shapes", systemImage: "square.on.circle", isOn: $drawsShapes)
            Menu("Writing Guides", systemImage: "square.grid.3x3") {
                Picker("Writing Guides", selection: $writingGuidePattern) {
                    ForEach(DrawingPaperPattern.allCases) { pattern in
                        Label(pattern == .plain ? "None" : pattern.title, systemImage: pattern.symbolName).tag(pattern)
                    }
                }
                Picker("Spacing", selection: $writingGuideSpacing) {
                    ForEach(DrawingPaperSpacing.allCases) { spacing in Text(spacing.title).tag(spacing) }
                }
                .disabled(writingGuidePattern == .plain)
            }
            if session.isWriting {
                Menu("Add Image", systemImage: "photo.badge.plus") {
                    PDFAddImageMenuContent(session: session, source: $pictureSource)
                }
            }
            Divider()
            #endif
            PDFPageActionsMenuContent(commands: commands, pageIndices: [session.currentPageIndex], isBookmarked: session.bookmarkedPageIndices.contains(session.currentPageIndex))
        }
        if !isCompactWidthOnAnyPlatform {
            Section { goToPageButton }
        }
        WorkspaceMoreMenuItems()
    }

    /// The page shown is the menu item's subtitle, as it is the title's in a regular width.
    private var goToPageButton: some View {
        Button {
            showsPageJump = true
        } label: {
            Label {
                Text("Go to Page…")
                Text("Page \(session.currentPageIndex + 1) of \(session.pageCount)")
            } icon: {
                Image(systemName: "number")
            }
        }
    }

    private var pageJumpField: some View {
        PDFPageJumpField(pageCount: session.pageCount, currentPageNumber: session.currentPageIndex + 1) { pageNumber in
            session.go(to: pageNumber - 1)
            showsPageJump = false
        }
    }

    /// Whether the width is compact; never on macOS, which has no size classes to speak of.
    private var isCompactWidthOnAnyPlatform: Bool {
        #if canImport(UIKit)
        isCompactWidth
        #else
        false
        #endif
    }

    #if canImport(UIKit)
    private func presentFindNavigator() {
        session.pdfView?.findInteraction.presentFindNavigator(showingReplace: false)
    }
    #endif
}

/// A number field that moves to a page, as in Preview's "Go to Page".
struct PDFPageJumpField: View {
    let pageCount: Int
    let currentPageNumber: Int
    let goToPage: (Int) -> Void
    @State private var pageText = ""
    @FocusState private var isFocused: Bool

    /// Longer numbers are no page, and refusing them keeps the arithmetic from overflowing.
    private static let maximumPageNumberDigits = 9

    private var requestedPageNumber: Int? { Self.pageNumber(from: pageText, pageCount: pageCount) }

    /// The page number typed, in any script's decimal digits: the number pad of an Arabic,
    /// Persian, or Devanagari keyboard types its own digits, and CJK input can type
    /// full-width ones. Nil when the text is not a page of this PDF.
    static func pageNumber(from text: String, pageCount: Int) -> Int? {
        let trimmedText = text.trimmingCharacters(in: .whitespaces)
        guard !trimmedText.isEmpty, trimmedText.count <= maximumPageNumberDigits else { return nil }
        var pageNumber = 0
        for character in trimmedText {
            guard character.unicodeScalars.count == 1, character.unicodeScalars.first?.properties.numericType == .decimal,
                  let digit = character.wholeNumberValue else { return nil }
            pageNumber = pageNumber * 10 + digit
        }
        return (1...max(1, pageCount)).contains(pageNumber) ? pageNumber : nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Go to Page").font(.headline)
            HStack {
                TextField("Page", text: $pageText, prompt: Text("\(currentPageNumber)"))
                    .focused($isFocused)
                    #if canImport(UIKit)
                    .keyboardType(.numberPad)
                    #endif
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 90)
                    .onSubmit(submit)
                Text("of \(pageCount)").foregroundStyle(.secondary).monospacedDigit().fixedSize()
                Button("Go", action: submit).buttonStyle(.borderedProminent).fixedSize().disabled(requestedPageNumber == nil)
            }
        }
        .onAppear { isFocused = true }
    }

    private func submit() {
        guard let requestedPageNumber else { return }
        goToPage(requestedPageNumber)
    }
}

/// Page operations shared by the toolbar and the pages sidebar, with the confirmations
/// they need before changing the file.
@MainActor @Observable
final class PDFPageCommands {
    let session: PDFSession
    var pagesPendingDeletion: [Int] = []
    var isConfirmingDeletion = false
    var isConfirmingStructureRewrite = false
    private var structureChangeAwaitingConfirmation: (() -> Void)?
    var isImporting = false
    var importInsertionIndex = 0
    var exportDocument: PDFExportDocument?
    var isExporting = false
    var exportFilename = "Pages"

    init(session: PDFSession) { self.session = session }

    var structureRewriteMessage: String {
        let entries = session.structureEntriesLostByPageChanges
        let listedEntries = ListFormatter.localizedString(byJoining: entries)
        return "Changing the pages or bookmarks of this PDF removes its \(listedEntries). Other apps will still show every page and annotation."
    }

    func insertPaper(_ template: PaperTemplate, at insertionIndex: Int) {
        changingPageStructure { [session] in
            Task {
                do { try await session.insertPaper(GraphitePreferences.storedNotebookPaper(template: template), at: insertionIndex) }
                catch { session.errorMessage = error.localizedDescription }
            }
        }
    }

    func requestImport(at insertionIndex: Int) {
        importInsertionIndex = insertionIndex
        changingPageStructure { [weak self] in self?.isImporting = true }
    }

    func importPages(from sourceLocation: URL) {
        let insertionIndex = importInsertionIndex
        Task {
            do { try await session.importPages(from: sourceLocation, at: insertionIndex) }
            catch { session.errorMessage = error.localizedDescription }
        }
    }

    func duplicate(pages pageIndices: [Int]) {
        changingPageStructure { [session] in
            perform(session) { try session.duplicatePages(pageIndices) }
        }
    }

    func rotate(pages pageIndices: [Int], clockwise: Bool) {
        perform(session) { try session.rotatePages(pageIndices, clockwise: clockwise) }
    }

    func move(page pageIndex: Int, to destinationIndex: Int) {
        guard destinationIndex >= 0, destinationIndex < session.pageCount, destinationIndex != pageIndex else { return }
        changingPageStructure { [session] in
            perform(session) {
                try session.movePage(from: pageIndex, to: destinationIndex)
                session.go(to: destinationIndex)
            }
        }
    }

    func requestDeletion(of pageIndices: [Int]) {
        guard !pageIndices.isEmpty else { return }
        guard pageIndices.count < session.pageCount else {
            session.errorMessage = "A PDF must keep at least one page."
            return
        }
        pagesPendingDeletion = pageIndices.sorted()
        isConfirmingDeletion = true
    }

    func confirmDeletion() {
        let pageIndices = pagesPendingDeletion
        pagesPendingDeletion = []
        changingPageStructure { [session] in
            Task {
                do { try await session.deletePages(at: pageIndices) }
                catch { session.errorMessage = error.localizedDescription }
            }
        }
    }

    func toggleBookmark(page pageIndex: Int) {
        if let bookmark = session.outlineEntries.last(where: { entry in entry.isBookmark && entry.pageIndex == pageIndex }) {
            removeOutlineEntry(bookmark)
        } else {
            changingPageStructure { [session] in perform(session) { try session.addBookmark(pageIndex: pageIndex) } }
        }
    }

    func removeOutlineEntry(_ entry: PDFOutlineEntry) {
        changingPageStructure { [session] in perform(session) { try session.apply(.removeOutlineItem(path: entry.path)) } }
    }

    func export(pages pageIndices: [Int]) {
        let sortedPages = Array(Set(pageIndices)).sorted()
        guard !sortedPages.isEmpty else { return }
        exportFilename = Self.exportFilename(stem: session.location.deletingPathExtension().lastPathComponent, pageIndices: sortedPages)
        Task {
            do {
                exportDocument = PDFExportDocument(data: try await session.export(pages: sortedPages))
                isExporting = true
            } catch {
                session.errorMessage = error.localizedDescription
            }
        }
    }

    /// Longer lists of page ranges name the file by its page count instead.
    private static let maximumPageRangesDescriptionLength = 40

    /// "Notes page 3", "Notes pages 1-10", or for a selection with gaps "Notes pages 1-3, 7"
    /// (page numbers start at 1). `pageIndices` are sorted and unique.
    static func exportFilename(stem: String, pageIndices: [Int]) -> String {
        guard pageIndices.count > 1 else { return "\(stem) page \((pageIndices.first ?? 0) + 1)" }
        var ranges: [ClosedRange<Int>] = []
        for pageIndex in pageIndices {
            if let lastRange = ranges.last, lastRange.upperBound + 1 == pageIndex {
                ranges[ranges.count - 1] = lastRange.lowerBound...pageIndex
            } else {
                ranges.append(pageIndex...pageIndex)
            }
        }
        let rangesDescription = ranges.map { range in
            range.count == 1 ? "\(range.lowerBound + 1)" : "\(range.lowerBound + 1)-\(range.upperBound + 1)"
        }.joined(separator: ", ")
        guard rangesDescription.count <= maximumPageRangesDescriptionLength else { return "\(stem) \(pageIndices.count) pages" }
        return "\(stem) pages \(rangesDescription)"
    }

    func confirmStructureRewrite() {
        session.acceptsStructureRewrite = true
        let action = structureChangeAwaitingConfirmation
        structureChangeAwaitingConfirmation = nil
        action?()
    }

    func cancelStructureRewrite() {
        structureChangeAwaitingConfirmation = nil
    }

    /// Runs an action that rewrites the page tree, asking first when that would remove
    /// document settings from the file.
    private func changingPageStructure(_ action: @escaping () -> Void) {
        guard !session.structureEntriesLostByPageChanges.isEmpty, !session.acceptsStructureRewrite else {
            action()
            return
        }
        structureChangeAwaitingConfirmation = action
        isConfirmingStructureRewrite = true
    }
}

@MainActor
private func perform(_ session: PDFSession, _ operation: () throws -> Void) {
    do { try operation() } catch { session.errorMessage = error.localizedDescription }
}

/// Confirmations, file import and export for page operations.
struct PDFPageCommandDialogs: ViewModifier {
    @Bindable var commands: PDFPageCommands

    func body(content: Content) -> some View {
        content
            .confirmationDialog(commands.pagesPendingDeletion.count == 1 ? "Delete this page?" : "Delete \(commands.pagesPendingDeletion.count) pages?",
                                isPresented: $commands.isConfirmingDeletion, titleVisibility: .visible) {
                Button(commands.pagesPendingDeletion.count == 1 ? "Delete Page" : "Delete Pages", role: .destructive) { commands.confirmDeletion() }
            } message: {
                Text("The page and its annotations are removed from the PDF. Undo puts them back while the PDF stays open.")
            }
            .confirmationDialog("Change the pages of this PDF?", isPresented: $commands.isConfirmingStructureRewrite, titleVisibility: .visible) {
                Button("Continue") { commands.confirmStructureRewrite() }
                Button("Cancel", role: .cancel) { commands.cancelStructureRewrite() }
            } message: {
                Text(commands.structureRewriteMessage)
            }
            .fileImporter(isPresented: $commands.isImporting, allowedContentTypes: [.pdf]) { result in
                switch result {
                case .success(let location): commands.importPages(from: location)
                case .failure(let error): commands.session.errorMessage = error.localizedDescription
                }
            }
            .fileExporter(isPresented: $commands.isExporting, document: commands.exportDocument, contentType: .pdf, defaultFilename: commands.exportFilename) { result in
                if case .failure(let error) = result { commands.session.errorMessage = error.localizedDescription }
                commands.exportDocument = nil
            }
    }
}

/// Paper templates to insert before or after a page, and importing pages from a PDF.
struct PDFAddPageMenu: View {
    let commands: PDFPageCommands
    let insertionIndexAfter: Int
    let insertionIndexBefore: Int

    var body: some View {
        Menu("Add Page", systemImage: "plus.rectangle.on.rectangle") {
            Section("After This Page") {
                ForEach(PaperTemplate.allCases) { template in
                    Button(template.title, systemImage: template.symbolName) { commands.insertPaper(template, at: insertionIndexAfter) }
                }
            }
            Menu("Before This Page", systemImage: "arrow.up.doc") {
                ForEach(PaperTemplate.allCases) { template in
                    Button(template.title, systemImage: template.symbolName) { commands.insertPaper(template, at: insertionIndexBefore) }
                }
            }
            Button("Import Pages from PDF…", systemImage: "square.and.arrow.down") { commands.requestImport(at: insertionIndexAfter) }
        }
    }
}

/// Actions for one or more pages, used by the toolbar and the pages sidebar.
struct PDFPageActionsMenuContent: View {
    let commands: PDFPageCommands
    let pageIndices: [Int]
    let isBookmarked: Bool

    var body: some View {
        if pageIndices.count == 1, let pageIndex = pageIndices.first {
            Button(isBookmarked ? "Remove Bookmark" : "Add Bookmark", systemImage: isBookmarked ? "bookmark.slash" : "bookmark") {
                commands.toggleBookmark(page: pageIndex)
            }
        }
        Button("Rotate Left", systemImage: "rotate.left") { commands.rotate(pages: pageIndices, clockwise: false) }
        Button("Rotate Right", systemImage: "rotate.right") { commands.rotate(pages: pageIndices, clockwise: true) }
        Button(pageIndices.count == 1 ? "Duplicate Page" : "Duplicate Pages", systemImage: "plus.square.on.square") { commands.duplicate(pages: pageIndices) }
        Button(pageIndices.count == 1 ? "Export Page…" : "Export Pages…", systemImage: "square.and.arrow.up") { commands.export(pages: pageIndices) }
        Divider()
        Button(pageIndices.count == 1 ? "Delete Page…" : "Delete Pages…", systemImage: "trash", role: .destructive) { commands.requestDeletion(of: pageIndices) }
    }
}

extension PaperTemplate {
    var symbolName: String {
        switch self {
        case .blank: "doc"
        case .dotted: "circle.grid.3x3"
        case .grid: "squareshape.split.3x3"
        case .ruled: "line.3.horizontal"
        case .cornell: "rectangle.split.2x1"
        case .engineering: "ruler"
        case .isometric: "triangle"
        case .music: "music.note"
        }
    }
}

struct PDFExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.pdf] }
    let data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw GraphiteError.invalidFile("Invalid PDF export.") }
        self.data = data
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

/// A line under the window's title, where the system shows one (iPadOS 26 and macOS). Nil
/// shows an empty subtitle rather than none, so the PDF's view stays the same view when the
/// pane gains or loses focus; SwiftUI would otherwise build the PDF view again.
private struct NavigationSubtitle: ViewModifier {
    let text: String?

    func body(content: Content) -> some View {
        if #available(iOS 26, macOS 11, *) {
            content.navigationSubtitle(Text(text ?? ""))
        } else {
            content
        }
    }
}

extension ReadAloudNavigator.PenMark {
    /// This mark in the document as it is now: where it was while its page still holds the
    /// same words there (ink and saves change nothing), otherwise found again by its text on
    /// the pages, when pages were inserted, removed or moved. Nil when its text is gone.
    func located(in document: PDFDocument) -> Self? {
        guard !context.isEmpty else { return self }
        let contextLength = (context as NSString).length
        if let pageText = document.page(at: pageIndex)?.string as NSString? {
            let contextStart = range.location - wordOffsetInContext
            if contextStart >= 0, contextStart + contextLength <= pageText.length,
               pageText.substring(with: NSRange(location: contextStart, length: contextLength)) == context { return self }
        }
        for candidateIndex in 0..<document.pageCount {
            guard let page = document.page(at: candidateIndex), let pageText = page.string as NSString? else { continue }
            let found = pageText.range(of: context, options: .literal)
            guard found.location != NSNotFound else { continue }
            let wordRange = NSRange(location: found.location + wordOffsetInContext, length: range.length)
            return ReadAloudNavigator.PenMark(sourceIdentifier: sourceIdentifier, pageIndex: candidateIndex, range: wordRange,
                                              bounds: page.selection(for: wordRange)?.bounds(for: page) ?? bounds,
                                              context: context, wordOffsetInContext: wordOffsetInContext)
        }
        return nil
    }
}

import SwiftUI
import PDFKit
import UniformTypeIdentifiers
import GraphiteCore
import GraphiteApple

/// Device preference keys for PDF annotation.
enum PDFAnnotationPreferenceKey {
    static let drawsWithFinger = "GraphitePDFDrawsWithFinger"
    static let showsToolPicker = "GraphitePDFShowsToolPicker"
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
    let resolveConflict: (URL) -> Void

    var body: some View {
        // The workspace replaces the session when the file is reloaded. The PDF view, its
        // canvases, and the page commands belong to one session, so they are rebuilt.
        PDFPaneContent(session: session, isFocused: isFocused, focus: focus, linkActions: linkActions, resolveConflict: resolveConflict)
            .id(ObjectIdentifier(session))
    }
}

private struct PDFPaneContent: View {
    @Bindable var session: PDFSession
    let isFocused: Bool
    let focus: () -> Void
    let linkActions: PDFLinkActions?
    let resolveConflict: (URL) -> Void
    @State private var commands: PDFPageCommands
    @State private var thumbnailRenderer = PDFThumbnailRenderer()
    @State private var showsPages = false
    @State private var showsPageJump = false
    @State private var showsReloadConfirmation = false
    @State private var showsSignatureConfirmation = false
    @AppStorage(PDFAnnotationPreferenceKey.drawsWithFinger) private var drawsWithFinger = false
    @AppStorage(PDFAnnotationPreferenceKey.showsToolPicker) private var showsToolPicker = true

    init(session: PDFSession, isFocused: Bool, focus: @escaping () -> Void, linkActions: PDFLinkActions?, resolveConflict: @escaping (URL) -> Void) {
        self.session = session
        self.isFocused = isFocused
        self.focus = focus
        self.linkActions = linkActions
        self.resolveConflict = resolveConflict
        _commands = State(initialValue: PDFPageCommands(session: session))
    }

    var body: some View {
        VStack(spacing: 0) {
            statusBanner
            HStack(spacing: 0) {
                if showsPages {
                    PDFPagesSidebar(session: session, commands: commands, renderer: thumbnailRenderer)
                        .frame(width: 210)
                        .transition(.move(edge: .leading))
                    Divider()
                }
                // The tool picker belongs to the focused side; it would cover the other one.
                // A protected PDF is not annotated, so PDFKit's own text selection applies.
                GraphitePDFView(session: session,
                                input: PDFAnnotationInput(isEnabled: !session.isProtected, drawsWithFinger: drawsWithFinger,
                                                          showsToolPicker: showsToolPicker && isFocused && !session.isProtected),
                                initialPageIndex: session.currentPageIndex > 0 ? session.currentPageIndex : nil, beginInteraction: focus,
                                linkActions: linkActions)
                    .ignoresSafeArea(edges: .bottom)
            }
        }
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
        // Neutral icons, as in Obsidian; the accent is kept for selection and toggles.
        ToolbarItemGroup(placement: .primaryAction) { Group {
            Button(showsPages ? "Hide Pages" : "Show Pages", systemImage: "square.grid.2x2") {
                withAnimation(.snappy) { showsPages.toggle() }
            }
            #if canImport(UIKit)
            Button("Find in PDF", systemImage: "magnifyingglass") {
                session.pdfView?.findInteraction.presentFindNavigator(showingReplace: false)
            }
            #endif
            Button {
                showsPageJump = true
            } label: {
                Text("\(session.currentPageIndex + 1) of \(session.pageCount)").monospacedDigit()
            }
            .accessibilityLabel("Page \(session.currentPageIndex + 1) of \(session.pageCount). Go to page")
            .popover(isPresented: $showsPageJump) {
                PDFPageJumpField(pageCount: session.pageCount, currentPageNumber: session.currentPageIndex + 1) { pageNumber in
                    session.go(to: pageNumber - 1)
                    showsPageJump = false
                }
                .padding()
                .presentationCompactAdaptation(.popover)
            }
            if !session.isProtected {
                #if canImport(UIKit)
                Button(showsToolPicker ? "Hide Tools" : "Show Tools", systemImage: showsToolPicker ? "pencil.tip.crop.circle.fill" : "pencil.tip.crop.circle") {
                    showsToolPicker.toggle()
                }
                #endif
                PDFAddPageMenu(commands: commands, insertionIndexAfter: session.currentPageIndex + 1, insertionIndexBefore: session.currentPageIndex)
            }
            Menu("More", systemImage: "ellipsis.circle") {
                if let linkActions {
                    Button("Copy Link to This Page", systemImage: "link") { linkActions.copyLink(session.currentPageIndex) }
                    Divider()
                }
                if !session.isProtected {
                    #if canImport(UIKit)
                    Toggle("Draw with Finger", systemImage: "hand.draw", isOn: $drawsWithFinger)
                    Divider()
                    #endif
                    PDFPageActionsMenuContent(commands: commands, pageIndices: [session.currentPageIndex], isBookmarked: session.bookmarkedPageIndices.contains(session.currentPageIndex))
                }
            }
        }.tint(.primary) }
    }
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
                do { try await session.insertPaper(template, at: insertionIndex) }
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
            // From the last page back, so earlier duplicates do not shift later indices.
            perform(session) { for pageIndex in pageIndices.sorted(by: >) { try session.apply(.duplicate(page: pageIndex)) } }
        }
    }

    func rotate(pages pageIndices: [Int], clockwise: Bool) {
        perform(session) { for pageIndex in pageIndices { try session.apply(.rotate(page: pageIndex, clockwise: clockwise)) } }
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
        changingPageStructure { [session] in perform(session) { try session.apply(.delete(pages: pageIndices)) } }
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
                Text("The page and its annotations are removed from the PDF.")
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

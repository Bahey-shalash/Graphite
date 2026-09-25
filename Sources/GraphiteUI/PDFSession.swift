import Foundation
import Observation
import PDFKit
import GraphiteCore
import GraphiteApple

/// A private copy of the PDF as it was last read or saved. Edits are replayed on it when
/// saving, so a live `PDFDocument` never crosses actors. Its file is deleted when the
/// last owner releases it, which includes a save or export still reading it.
final class PDFBaselineSnapshot: Sendable {
    static let filenamePrefix = "Graphite-OpenPDF-"
    let location: URL

    init(location: URL) { self.location = location }

    /// The name carries the process that made the copy. iOS ends suspended apps without
    /// running deinitializers, so copies of whole textbooks would otherwise pile up; the
    /// process identifier tells a copy left by an ended process from one still in use.
    static func makeLocation() -> URL {
        _ = staleBaselinesRemoved
        let filename = "\(filenamePrefix)\(ProcessInfo.processInfo.processIdentifier)-\(UUID().uuidString).pdf"
        return FileManager.default.temporaryDirectory.appendingPathComponent(filename)
    }

    /// Runs once, before this process makes its first copy, so it never races one.
    private static let staleBaselinesRemoved: Void = removeStaleBaselines(in: FileManager.default.temporaryDirectory)

    /// Removes copies whose process has ended, including ones named before copies
    /// carried a process identifier.
    static func removeStaleBaselines(in directory: URL) {
        guard let filenames = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return }
        for filename in filenames where filename.hasPrefix(filenamePrefix) && filename.hasSuffix(".pdf") && !isOwnedByRunningProcess(filename) {
            // Best effort: a copy that cannot be removed now is tried again at the next launch.
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(filename))
        }
    }

    private static func isOwnedByRunningProcess(_ filename: String) -> Bool {
        let processText = filename.dropFirst(filenamePrefix.count).prefix { character in character != "-" }
        guard let processIdentifier = pid_t(processText), processIdentifier > 0 else { return false }
        // Signal 0 only checks that the process exists; EPERM means it exists but is not ours.
        return kill(processIdentifier, 0) == 0 || errno == EPERM
    }

    deinit { try? FileManager.default.removeItem(at: location) }
}

/// A newly loaded PDF has no references outside this transfer. The worker never
/// touches it again after returning. Its sole consumer is the main-actor session.
private struct LoadedPDF: @unchecked Sendable {
    let document: PDFDocument
    let revision: FileRevision
    let baseline: PDFBaselineSnapshot
    let structureEntriesLostByPageChanges: [String]
    let hasDigitalSignatures: Bool
}

/// A PDF that opens only with its password.
struct PDFPasswordRequired: LocalizedError {
    /// True when a password was given and did not open it.
    let wasPasswordWrong: Bool
    var errorDescription: String? { wasPasswordWrong ? "That password does not open this PDF." : "This PDF is protected by a password." }
}

private actor PDFLoader {
    func load(_ location: URL, password: String?, writer: AtomicFileWriter) throws -> LoadedPDF {
        var coordinationError: NSError?
        var loaded: Result<LoadedPDF, Error>?
        writer.makeCoordinator().coordinate(readingItemAt: location, options: [], error: &coordinationError) { source in
            loaded = Result {
                let baseline = PDFBaselineSnapshot(location: PDFBaselineSnapshot.makeLocation())
                try FileManager.default.copyItem(at: source, to: baseline.location)
                guard let document = PDFDocument(url: baseline.location) else { throw GraphiteError.invalidFile("This PDF is unreadable.") }
                if document.isLocked {
                    guard let password else { throw PDFPasswordRequired(wasPasswordWrong: false) }
                    guard document.unlock(withPassword: password) else { throw PDFPasswordRequired(wasPasswordWrong: true) }
                }
                return LoadedPDF(document: document, revision: try FileRevision.read(baseline.location), baseline: baseline,
                                 structureEntriesLostByPageChanges: PDFStructureInspection.entriesLostByPageChanges(in: baseline.location),
                                 hasDigitalSignatures: PDFSignatureDetection.hasDigitalSignatures(at: baseline.location))
            }
        }
        if let coordinationError { throw coordinationError }
        guard let loaded else { throw GraphiteError.unavailable("The PDF is unavailable.") }
        return try loaded.get()
    }
}

/// Finds digital signatures. PDFKit always writes a whole new file, never an incremental
/// update after the signed bytes, so any save makes other readers report the signature
/// as broken.
enum PDFSignatureDetection {
    /// Bit 2 of the form's `/SigFlags`, AppendOnly: signing tools set it, because the
    /// signatures break unless changes are appended. Bit 1 only says a signature field
    /// exists, which blank forms waiting to be signed also have.
    private static let appendOnlyFlag: CGPDFInteger = 2
    /// Bounds the walk over form fields, whose `/Kids` a damaged file could make cyclic.
    private static let maximumInspectedFields = 10_000

    /// Reads only the document catalog and its form, which CoreGraphics loads lazily.
    static func hasDigitalSignatures(at fileLocation: URL) -> Bool {
        guard let pdfDocument = CGPDFDocument(fileLocation as CFURL) else { return false }
        // The catalog and its dictionaries belong to the document and are freed with it.
        return withExtendedLifetime(pdfDocument) {
            guard let catalog = pdfDocument.catalog else { return false }
            // Certification and usage-rights signatures are listed in the catalog's `/Perms`.
            var permissions: CGPDFDictionaryRef?
            if CGPDFDictionaryGetDictionary(catalog, "Perms", &permissions) { return true }
            var form: CGPDFDictionaryRef?
            guard CGPDFDictionaryGetDictionary(catalog, "AcroForm", &form), let form else { return false }
            var signatureFlags: CGPDFInteger = 0
            if CGPDFDictionaryGetInteger(form, "SigFlags", &signatureFlags), signatureFlags & appendOnlyFlag != 0 { return true }
            return hasSignedSignatureField(in: form)
        }
    }

    /// A signature field with a value (`/V`) has been signed. The field type is inherited
    /// from parent fields.
    private static func hasSignedSignatureField(in form: CGPDFDictionaryRef) -> Bool {
        var fields: CGPDFArrayRef?
        guard CGPDFDictionaryGetArray(form, "Fields", &fields), let fields else { return false }
        var pendingFields: [(field: CGPDFDictionaryRef, isSignatureField: Bool)] = dictionaries(in: fields).map { field in (field, false) }
        var inspectedFieldCount = 0
        while let (field, parentIsSignatureField) = pendingFields.popLast(), inspectedFieldCount < maximumInspectedFields {
            inspectedFieldCount += 1
            var fieldType: UnsafePointer<CChar>?
            let isSignatureField = CGPDFDictionaryGetName(field, "FT", &fieldType)
                ? fieldType.map { typeName in String(cString: typeName) == "Sig" } ?? false
                : parentIsSignatureField
            var signatureValue: CGPDFDictionaryRef?
            if isSignatureField && CGPDFDictionaryGetDictionary(field, "V", &signatureValue) { return true }
            var kids: CGPDFArrayRef?
            if CGPDFDictionaryGetArray(field, "Kids", &kids), let kids {
                pendingFields.append(contentsOf: dictionaries(in: kids).map { kid in (kid, isSignatureField) })
            }
        }
        return false
    }

    private static func dictionaries(in array: CGPDFArrayRef) -> [CGPDFDictionaryRef] {
        (0..<CGPDFArrayGetCount(array)).compactMap { elementIndex in
            var dictionary: CGPDFDictionaryRef?
            return CGPDFArrayGetDictionary(array, elementIndex, &dictionary) ? dictionary : nil
        }
    }
}

/// One page's appearance version. Each page has its own observable object, so a stroke
/// redraws only the thumbnail of the page it changed instead of every visible row.
@MainActor @Observable
private final class PDFPageAppearance {
    var version = 0
}

/// One entry of the PDF outline (its table of contents and bookmarks).
struct PDFOutlineEntry: Identifiable, Equatable {
    /// Child indices from the outline root; stable until the outline changes.
    let path: [Int]
    let label: String
    let pageIndex: Int?
    let hasChildren: Bool
    var id: [Int] { path }
    var depth: Int { path.count - 1 }
    /// The start of the label Graphite gives the bookmarks it adds, "Page 12".
    static let bookmarkLabelPrefix = "Page "
    /// A top-level entry without children, labeled the way Graphite labels bookmarks, is
    /// shown as a bookmark of its page. The label test keeps a flat table of contents
    /// written by the PDF's author ("Introduction", "Results") from being offered for
    /// removal as the user's bookmarks.
    var isBookmark: Bool { depth == 0 && !hasChildren && pageIndex != nil && label.hasPrefix(Self.bookmarkLabelPrefix) }
}

/// The open PDF shown by the PDF pane or an embedded viewer.
///
/// Edits apply immediately to `document` and are recorded as immutable `PDFEdit`s. A
/// save replays the recorded edits on the baseline snapshot in the background, replaces
/// the file only if it is unchanged since it was read, and then makes the written file
/// the new baseline, so the next save replays only newer edits.
@MainActor @Observable
final class PDFSession {
    static let autosaveDelay = Duration.seconds(2)
    /// Autosave waits this many times as long as the last save took, so a PDF whose full
    /// rewrite is slow (a heavily annotated textbook) is not rewritten after every pause.
    private static let autosaveDelayPerSaveDuration = 10
    private static let maximumAutosaveDelay = Duration.seconds(30)
    /// A failed autosave is tried again after 4, 8, 16, 32, then 60 seconds.
    private static let maximumAutosaveRetryDoublings = 5
    private static let maximumAutosaveRetryDelay = Duration.seconds(60)
    /// Imported pages stay in memory, in the document and in the edit list, until the
    /// next save, so an import is bounded.
    nonisolated static let maximumImportedPDFBytes = 512 * 1_048_576
    /// Bounds the outline read into memory for the sidebar.
    private static let maximumOutlineEntries = 2_000

    let location: URL
    let document: PDFDocument
    private var revision: FileRevision
    private var edits: [PDFEdit] = []
    private var baseline: PDFBaselineSnapshot
    /// Edits before this index are being written by a running save; merging a new edit
    /// into one of them would lose it when the saved edits are dropped.
    private var firstMergeableEditIndex = 0
    private var savedVersion = 0
    private var runningSave: Task<Void, Error>?
    private var autosaveTask: Task<Void, Never>?
    @ObservationIgnored private var pageAppearances: [ObjectIdentifier: PDFPageAppearance] = [:]
    @ObservationIgnored private var lastSaveDuration = Duration.zero
    @ObservationIgnored private var consecutiveAutosaveFailures = 0
    /// Coordinates with Graphite's vault presenter, so the session's own saves are not
    /// reported back as external changes (each one would hash the whole PDF again).
    private let writer: AtomicFileWriter
    private let fileService: PDFFileService
    /// Called with the file each save wrote: the PDF itself, or a separate copy beside it.
    /// The session's own writes are not reported as external changes, so this is how the
    /// workspace learns of them.
    @ObservationIgnored var didSave: (@MainActor (URL) -> Void)?
    /// Write the re-editing records that Pencil canvases defer while drawing (see
    /// `PDFPageInkTracker`), keyed by the view owning the canvases. Until one runs, the
    /// page's ink reads back as not editable, so every save, export and page-structure
    /// change runs them first.
    @ObservationIgnored private var pendingInkRecordWriters: [ObjectIdentifier: () -> Void] = [:]
    /// Identifies this session's page drags, so a page dragged from another PDF is refused.
    let identifier = UUID()

    var currentPageIndex = 0
    private(set) var pageCount: Int
    /// Document settings the next page change would remove from the file (see
    /// `PDFStructureInspection`). Empty when page changes lose nothing.
    private(set) var structureEntriesLostByPageChanges: [String]
    /// The user accepted losing those settings for this session.
    var acceptsStructureRewrite = false
    var hasExternalConflict = false
    /// The last save failed for a reason other than a conflict; the edits are still here.
    private(set) var hasFailedSave = false
    private(set) var changeVersion = 0
    /// Changes when pages are inserted, deleted, or reordered; page lists redraw on it.
    private(set) var pageListVersion = 0
    /// Changes when bookmarks or the outline change.
    private(set) var outlineVersion = 0
    @ObservationIgnored private var cachedOutlineEntries: (version: Int, entries: [PDFOutlineEntry])?
    var errorMessage: String?
    weak var pdfView: PDFView?

    var isSaving: Bool { runningSave != nil }
    var hasUnsavedChanges: Bool { changeVersion != savedVersion }
    /// A password-protected (encrypted) PDF is shown without being changed: PDFKit would
    /// write it back without its encryption, and Graphite does not know its owner password.
    /// Its permissions are checked too, because PDFKit silently drops the ink, markup and
    /// page changes they forbid.
    let isPasswordProtected: Bool
    /// Any save rewrites the whole file and breaks the signatures, so a signed PDF is shown
    /// without changes until the user accepts that.
    let hasDigitalSignatures: Bool
    var acceptsSignatureInvalidation = false
    /// The PDF is shown without being changed: every edit is refused.
    var isProtected: Bool { isPasswordProtected || (hasDigitalSignatures && !acceptsSignatureInvalidation) }

    private init(location: URL, loaded: LoadedPDF, writer: AtomicFileWriter) {
        self.location = location
        self.writer = writer
        fileService = PDFFileService(writer: writer)
        document = loaded.document
        isPasswordProtected = loaded.document.isEncrypted || !loaded.document.allowsCommenting || !loaded.document.allowsDocumentChanges
        hasDigitalSignatures = loaded.hasDigitalSignatures
        revision = loaded.revision
        baseline = loaded.baseline
        pageCount = loaded.document.pageCount
        structureEntriesLostByPageChanges = loaded.structureEntriesLostByPageChanges
    }

    /// - Parameters:
    ///   - password: Unlocks a PDF that opens only with a password.
    ///   - writer: The vault's writer, so saves coordinate with Graphite's file presenter.
    static func open(_ location: URL, password: String? = nil, writer: AtomicFileWriter = AtomicFileWriter()) async throws -> PDFSession {
        let loaded = try await PDFLoader().load(location, password: password, writer: writer)
        return PDFSession(location: location, loaded: loaded, writer: writer)
    }

    // MARK: Edits

    func apply(_ edit: PDFEdit) throws {
        if isPasswordProtected { throw GraphiteError.unavailable("This PDF is protected by a password, so Graphite shows it without changing it.") }
        if isProtected { throw GraphiteError.unavailable("This PDF is digitally signed, so Graphite shows it without changing it.") }
        // Deferred records name pages by index, which a page-structure change would move.
        if edit.changesPageTree { writePendingInkRecords() }
        let changedPage = edit.changedPageIndex.flatMap(document.page(at:))
        try PDFPageManager.apply(edit, to: document)
        record(edit)
        if let changedPage { appearance(of: changedPage).version += 1 }
        // Page changes can move or remove the pages outline entries point to.
        if edit.changesPageTree { pageListVersion += 1 }
        if edit.changesPageTree || edit.changesOutline { outlineVersion += 1 }
        // Assigned only when they change: every view showing the page count or the current
        // page would otherwise be redrawn after each stroke.
        if pageCount != document.pageCount { pageCount = document.pageCount }
        let currentPageIndexInRange = min(currentPageIndex, max(0, pageCount - 1))
        if currentPageIndex != currentPageIndexInRange { currentPageIndex = currentPageIndexInRange }
        changeVersion += 1
        scheduleAutosave()
    }

    /// Registers the view that owns Pencil canvases; `write` applies their deferred records.
    func registerPendingInkRecordWriter(for owner: AnyObject, _ write: @escaping () -> Void) {
        pendingInkRecordWriters[ObjectIdentifier(owner)] = write
    }

    func unregisterPendingInkRecordWriter(for owner: AnyObject) {
        pendingInkRecordWriters[ObjectIdentifier(owner)] = nil
    }

    func writePendingInkRecords() {
        for write in pendingInkRecordWriters.values { write() }
    }

    private func record(_ edit: PDFEdit) {
        // Successive strokes on one page merge into one update, so the list grows with
        // the pages touched rather than with every stroke.
        if case .updateInk(let update) = edit, edits.count > firstMergeableEditIndex,
           case .updateInk(let previousUpdate) = edits.last, let mergedUpdate = previousUpdate.merged(with: update) {
            edits[edits.count - 1] = .updateInk(mergedUpdate)
        } else {
            edits.append(edit)
        }
    }

    /// Increases whenever the page's visible content changes; thumbnails redraw on it.
    func appearanceVersion(of page: PDFPage) -> Int {
        appearance(of: page).version
    }

    private func appearance(of page: PDFPage) -> PDFPageAppearance {
        if let existingAppearance = pageAppearances[ObjectIdentifier(page)] { return existingAppearance }
        let newAppearance = PDFPageAppearance()
        pageAppearances[ObjectIdentifier(page)] = newAppearance
        return newAppearance
    }

    // MARK: Saving

    /// Saves pending edits. A save already running is awaited first, so navigation,
    /// autosave, and explicit saves never reject each other.
    func save() async throws {
        while let previousSave = runningSave {
            _ = try? await previousSave.value
            // Whichever waiter resumes first clears the finished save, so no waiter spins on it.
            if runningSave == previousSave { runningSave = nil }
        }
        guard hasUnsavedChanges else { return }
        guard !hasExternalConflict else { throw GraphiteError.conflict }
        writePendingInkRecords()
        let saveTask = Task { try await self.writePendingEdits() }
        runningSave = saveTask
        defer { if runningSave == saveTask { runningSave = nil } }
        try await saveTask.value
    }

    private func writePendingEdits() async throws {
        let editsToSave = edits
        let versionToSave = changeVersion
        let currentBaseline = baseline
        let nextBaselineLocation = PDFBaselineSnapshot.makeLocation()
        firstMergeableEditIndex = editsToSave.count
        defer { firstMergeableEditIndex = 0 }
        let saveStart = ContinuousClock.now
        do {
            let savedRevision = try await fileService.save(url: location, revision: revision, edits: editsToSave,
                                                           baselineURL: currentBaseline.location, savedSnapshotDestination: nextBaselineLocation)
            lastSaveDuration = saveStart.duration(to: .now)
            revision = savedRevision
            baseline = PDFBaselineSnapshot(location: nextBaselineLocation)
            edits.removeFirst(editsToSave.count)
            if editsToSave.contains(where: { edit in edit.changesPageTree || edit.changesOutline }) {
                // The rewrite has already removed them from the file.
                structureEntriesLostByPageChanges = []
            }
            savedVersion = versionToSave
            errorMessage = nil
            hasFailedSave = false
            consecutiveAutosaveFailures = 0
            didSave?(location)
        } catch {
            if error as? GraphiteError == .conflict { hasExternalConflict = true } else { hasFailedSave = true }
            errorMessage = error.localizedDescription
            throw error
        }
    }

    /// How long autosave waits after an edit: longer after slow saves, and longer again
    /// after each failed autosave in a row, so a save that keeps failing is retried
    /// without rewriting a large file continuously.
    static func autosaveDelay(afterSaveTaking saveDuration: Duration, consecutiveFailures: Int) -> Duration {
        let proportionalDelay = min(max(autosaveDelay, saveDuration * autosaveDelayPerSaveDuration), maximumAutosaveDelay)
        guard consecutiveFailures > 0 else { return proportionalDelay }
        let retryDelay = autosaveDelay * (1 << min(consecutiveFailures, maximumAutosaveRetryDoublings))
        return min(max(proportionalDelay, retryDelay), maximumAutosaveRetryDelay)
    }

    private func scheduleAutosave() {
        autosaveTask?.cancel()
        let delay = Self.autosaveDelay(afterSaveTaking: lastSaveDuration, consecutiveFailures: consecutiveAutosaveFailures)
        autosaveTask = Task { [weak self] in
            do { try await Task.sleep(for: delay) } catch { return }
            guard let self, !self.hasExternalConflict else { return }
            do {
                try await self.save()
            } catch {
                self.errorMessage = error.localizedDescription
                // A conflict waits for the user's choice; any other failure is retried, so
                // the edits reach the file without waiting for another edit.
                guard !self.hasExternalConflict, self.hasUnsavedChanges else { return }
                self.consecutiveAutosaveFailures += 1
                self.scheduleAutosave()
            }
        }
    }

    /// Saves before the viewer releases the session. Errors leave the edits in memory.
    func saveBeforeClosing() async throws {
        autosaveTask?.cancel()
        try await save()
    }

    func saveSeparateCopy() async throws -> URL {
        let directory = location.deletingLastPathComponent()
        let filename = location.deletingPathExtension().lastPathComponent + " Graphite edits " + UUID().uuidString.prefix(8) + ".pdf"
        let destination = directory.appendingPathComponent(filename)
        writePendingInkRecords()
        let currentBaseline = baseline
        _ = try await fileService.saveCopy(baselineURL: currentBaseline.location, edits: edits, destination: destination)
        withExtendedLifetime(currentBaseline) {}
        didSave?(destination)
        return destination
    }

    func export(pages: [Int]) async throws -> Data {
        writePendingInkRecords()
        let currentBaseline = baseline
        let exported = try await fileService.export(baselineURL: currentBaseline.location, edits: edits, pages: pages)
        withExtendedLifetime(currentBaseline) {}
        return exported
    }

    func hasChangedExternally() async throws -> Bool {
        guard !isSaving else { return false }
        let location = location
        let writer = writer
        let revisionBeforeRead = revision
        let currentRevision = try await Task.detached { try Self.readRevision(of: location, writer: writer) }.value
        // A save that ran during the read replaced the file, so the hash may be of the
        // file before it. The next check compares with the revision that save wrote.
        guard !isSaving, revision == revisionBeforeRead else { return false }
        let changed = currentRevision != revision
        if changed && hasUnsavedChanges { hasExternalConflict = true; errorMessage = GraphiteError.conflict.localizedDescription }
        return changed
    }

    /// Hashes the file inside a coordinated read, so a sync provider that is writing it
    /// finishes first and the hash is never of a partly written file.
    nonisolated private static func readRevision(of location: URL, writer: AtomicFileWriter) throws -> FileRevision {
        var coordinationError: NSError?
        var readResult: Result<FileRevision, Error>?
        writer.makeCoordinator().coordinate(readingItemAt: location, options: [], error: &coordinationError) { coordinatedLocation in
            readResult = Result { try FileRevision.read(coordinatedLocation) }
        }
        if let coordinationError { throw coordinationError }
        guard let readResult else { throw GraphiteError.unavailable("The PDF is unavailable.") }
        return try readResult.get()
    }

    // MARK: Navigation

    func go(to pageIndex: Int) {
        guard let page = document.page(at: pageIndex) else { return }
        pdfView?.go(to: page)
        currentPageIndex = pageIndex
    }

    // MARK: Pages

    func insertPaper(_ template: PaperTemplate, at insertionIndex: Int) async throws {
        let referenceBounds = document.page(at: min(currentPageIndex, max(0, pageCount - 1)))?.bounds(for: .cropBox) ?? CGRect(x: 0, y: 0, width: 595.28, height: 841.89)
        let pageSize = referenceBounds.size
        let paperData = try await Task.detached { try PDFTemplateGenerator.pageData(template: template, matching: pageSize) }.value
        try apply(.insert(data: paperData, at: min(max(0, insertionIndex), pageCount)))
        go(to: insertionIndex)
    }

    /// The file is read in the background. Copying its pages into the displayed document
    /// stays on the main actor, which owns that `PDFDocument`.
    func importPages(from sourceLocation: URL, at insertionIndex: Int) async throws {
        let snapshot = try await Task.detached {
            let hasAccess = sourceLocation.startAccessingSecurityScopedResource()
            defer { if hasAccess { sourceLocation.stopAccessingSecurityScopedResource() } }
            return try AtomicFileWriter().read(sourceLocation, maximumBytes: Self.maximumImportedPDFBytes)
        }.value
        try apply(.insert(data: snapshot.data, at: min(max(0, insertionIndex), pageCount)))
        go(to: insertionIndex)
    }

    /// Moves one page so that it ends up at `destinationIndex`.
    func movePage(from sourceIndex: Int, to destinationIndex: Int) throws {
        guard sourceIndex != destinationIndex else { return }
        try apply(.move(from: sourceIndex, to: destinationIndex))
    }

    // MARK: Bookmarks and outline

    /// The outline, read again only after it or the pages change.
    var outlineEntries: [PDFOutlineEntry] {
        let version = outlineVersion
        if let cachedOutlineEntries, cachedOutlineEntries.version == version { return cachedOutlineEntries.entries }
        let entries = readOutlineEntries()
        cachedOutlineEntries = (version, entries)
        return entries
    }

    private func readOutlineEntries() -> [PDFOutlineEntry] {
        guard let root = document.outlineRoot else { return [] }
        var entries: [PDFOutlineEntry] = []
        var pending: [(item: PDFOutline, path: [Int])] = (0..<root.numberOfChildren).reversed().compactMap { childIndex in
            root.child(at: childIndex).map { child in (child, [childIndex]) }
        }
        while let (item, path) = pending.popLast(), entries.count < Self.maximumOutlineEntries {
            let pageIndex = item.destination?.page.map(document.index(for:)).flatMap { index in index == NSNotFound ? nil : index }
            entries.append(PDFOutlineEntry(path: path, label: item.label ?? "Untitled", pageIndex: pageIndex, hasChildren: item.numberOfChildren > 0))
            for childIndex in (0..<item.numberOfChildren).reversed() {
                if let child = item.child(at: childIndex) { pending.append((child, path + [childIndex])) }
            }
        }
        return entries
    }

    /// Pages with a bookmark: a top-level outline entry without children pointing to them.
    var bookmarkedPageIndices: Set<Int> {
        Set(outlineEntries.filter(\.isBookmark).compactMap(\.pageIndex))
    }

    func addBookmark(pageIndex: Int) throws {
        guard let page = document.page(at: pageIndex) else { return }
        let pageLabel = page.label.flatMap { label in label.isEmpty ? nil : label } ?? "\(pageIndex + 1)"
        try apply(.bookmark(page: pageIndex, label: PDFOutlineEntry.bookmarkLabelPrefix + pageLabel))
    }

    // MARK: Text markup

    // Undo and redo keep the page object, not its index, and look the index up when they
    // run: pages inserted, deleted, or moved in between would otherwise put the markup on
    // another page.

    func addMarkup(_ kind: PDFMarkupKind, color: PDFMarkupColor, for selection: PDFSelection) throws {
        let linesByPage = selection.markupLinesByPage(in: document)
        guard !linesByPage.isEmpty else { throw GraphiteError.unavailable("Select some PDF text first.") }
        var added: [(page: PDFPage, markup: PDFMarkup)] = []
        for (pageIndex, lineBounds) in linesByPage {
            guard let page = document.page(at: pageIndex) else { throw GraphiteError.invalidFile("Page no longer exists.") }
            let markup = PDFMarkup(kind: kind, color: color, lineBounds: lineBounds)
            try apply(.addMarkup(page: pageIndex, markup: markup))
            added.append((page, markup))
        }
        registerUndo(actionName: kind.title) { session in
            for (page, markup) in added.reversed() { try session.removeMarkup(markup, on: page) }
        } redo: { session in
            for (page, markup) in added { try session.apply(.addMarkup(page: session.currentIndex(of: page), markup: markup)) }
        }
    }

    func removeMarkup(_ annotation: PDFAnnotation, on page: PDFPage) throws {
        let pageIndex = document.index(for: page)
        guard pageIndex != NSNotFound, let markup = PDFMarkup(annotation: annotation) else { return }
        try apply(.removeAnnotation(PDFAnnotationReference(annotation: annotation, pageIndex: pageIndex)))
        registerUndo(actionName: "Remove \(markup.kind.title)") { session in
            try session.apply(.addMarkup(page: session.currentIndex(of: page), markup: markup))
        } redo: { session in
            try session.removeMarkup(markup, on: page)
        }
    }

    func recolorMarkup(_ annotation: PDFAnnotation, on page: PDFPage, to color: PDFMarkupColor) throws {
        let pageIndex = document.index(for: page)
        guard pageIndex != NSNotFound, let previousMarkup = PDFMarkup(annotation: annotation) else { return }
        let reference = PDFAnnotationReference(annotation: annotation, pageIndex: pageIndex)
        try apply(.recolorMarkup(reference, color: color))
        func currentReference(in session: PDFSession) throws -> PDFAnnotationReference {
            PDFAnnotationReference(pageIndex: try session.currentIndex(of: page), name: reference.name,
                                   annotationType: reference.annotationType, bounds: reference.bounds)
        }
        registerUndo(actionName: "Change Color") { session in
            // The exact original color: `previousMarkup.color` is only the nearest palette color.
            try session.apply(.restoreMarkupColor(currentReference(in: session), from: previousMarkup))
        } redo: { session in
            try session.apply(.recolorMarkup(currentReference(in: session), color: color))
        }
    }

    /// The reference carries the bounds, so the markup is still found after an older
    /// build's page change dropped its name from the file.
    private func removeMarkup(_ markup: PDFMarkup, on page: PDFPage) throws {
        let reference = PDFAnnotationReference(pageIndex: try currentIndex(of: page), name: markup.name,
                                               annotationType: markup.kind.annotationTypeName, bounds: markup.bounds)
        try apply(.removeAnnotation(reference))
    }

    /// Where the page is now; it throws when the page was deleted.
    private func currentIndex(of page: PDFPage) throws -> Int {
        let pageIndex = document.index(for: page)
        guard pageIndex != NSNotFound else { throw GraphiteError.invalidFile("Page no longer exists.") }
        return pageIndex
    }

    /// Registers an undoable markup change with the undo manager of the view showing the
    /// PDF, the same history PencilKit records strokes in. Undo and redo register each
    /// other again, so the change can be undone and redone repeatedly.
    private func registerUndo(actionName: String, undo: @escaping (PDFSession) throws -> Void, redo: @escaping (PDFSession) throws -> Void) {
        guard let undoManager = pdfView?.undoManager else { return }
        undoManager.registerUndo(withTarget: self) { session in
            do {
                try undo(session)
                session.registerUndo(actionName: actionName, undo: redo, redo: undo)
            } catch { session.errorMessage = error.localizedDescription }
        }
        undoManager.setActionName(actionName)
    }
}

import Foundation
import Observation
import GraphiteCore

@MainActor @Observable
final class MarkdownSession {
    static let maximumEditableBytes = 8 * 1_048_576
    let path: VaultPath
    private let store: VaultStore
    private let didSave: @MainActor (VaultPath) -> Void
    var text: String
    var selection = NSRange(location: 0, length: 0)
    /// Reading view, Live Preview, or source mode, as for an Obsidian tab.
    var viewMode: NoteViewMode = .livePreview
    /// Link and tag suggestions at the cursor.
    let completion = CompletionModel()
    var errorMessage: String?
    var hasExternalConflict = false
    /// The character at the top of the editor when it last closed, so a tab shows the
    /// note where it was left; nil at the top.
    @ObservationIgnored var savedScrollLocation: Int?
    /// Whether the person has put the cursor somewhere in this note since it opened; until
    /// then, quotes from a PDF go to the end of the note rather than its top.
    @ObservationIgnored var hasPlacedCursor = false
    /// Whether the editor should start editing as soon as it shows, as for a note just
    /// created. Observed, so an editor already on screen notices it.
    var startsEditingWhenShown = false
    /// The find bar to open once the editor shows, with replace or without, for Obsidian's
    /// "Search current file" from the command palette.
    var findRequest: FindRequest?

    enum FindRequest { case find, findAndReplace }

    /// The last heading or match request an editor or reading view of this note showed,
    /// so switching tabs or views does not jump to it again.
    @ObservationIgnored var handledHeadingScrollToken: UUID?
    /// The last reading-view build of this note, so switching from editing back to reading shows it at once.
    @ObservationIgnored let readingBlocksCache = ReadingBlocksCache()
    /// Insertions waiting for the editor view, which applies them one at a time so native
    /// undo stays intact. Each range is in the text as it will be once every earlier
    /// insertion in the queue is applied, so requests made before the editor catches up,
    /// such as several images dropped together, all land where they were aimed.
    private var pendingInsertions: [EditorInsertion] = []
    /// The next insertion for the editor to apply.
    var pendingInsertion: EditorInsertion? { pendingInsertions.first }
    private var savedText: String
    /// Foundation's UTF-8 decoding drops a leading byte-order mark, so it is remembered and
    /// written back: saving must not change bytes the person did not edit.
    private var hasByteOrderMark: Bool
    private var revision: FileRevision
    private var activeSave: Task<Void, Error>?
    var isSaving: Bool { activeSave != nil }
    var hasUnsavedChanges: Bool { text != savedText }

    init(path: VaultPath, snapshot: FileSnapshot, store: VaultStore, didSave: @escaping @MainActor (VaultPath) -> Void) throws {
        guard let decoded = NoteTextEncoding.decode(snapshot.data) else { throw GraphiteError.invalidFile("This note is not UTF-8 encoded.") }
        self.path = path; self.store = store; self.didSave = didSave
        text = decoded.text; savedText = decoded.text; hasByteOrderMark = decoded.hasByteOrderMark; revision = snapshot.revision
    }

    /// Saves the current text. A save already in flight is awaited first, so autosave,
    /// navigation, and the keyboard shortcut never race or report a spurious error.
    func save() async throws {
        while let previousSave = activeSave {
            _ = try? await previousSave.value
            // Whichever waiter resumes first clears the finished save. Awaiting a finished
            // task does not suspend, so a waiter that left it in place would spin on the
            // main actor and the saver that owns it would never run again.
            if activeSave == previousSave { activeSave = nil }
        }
        guard hasUnsavedChanges else { return }
        guard !hasExternalConflict else { throw GraphiteError.conflict }
        let textToSave = text
        let expectedRevision = revision
        willReplaceSavedText?(savedText)
        let dataToSave = NoteTextEncoding.encode(textToSave, hasByteOrderMark: hasByteOrderMark)
        let saveTask = Task { [store, path] in
            let newRevision = try await store.save(dataToSave, at: path, expecting: .revision(expectedRevision))
            self.revision = newRevision
            self.savedText = textToSave
        }
        activeSave = saveTask
        defer { if activeSave == saveTask { activeSave = nil } }
        do {
            try await saveTask.value
            errorMessage = nil
            didSave(path)
        } catch {
            if error as? GraphiteError == .conflict { hasExternalConflict = true }
            errorMessage = error.localizedDescription
            throw error
        }
    }

    func checkExternalChange() async {
        guard !isSaving else { return }
        do {
            let snapshot = try await store.read(path, maximumBytes: Self.maximumEditableBytes)
            guard snapshot.revision != revision else { return }
            if hasUnsavedChanges { hasExternalConflict = true; errorMessage = GraphiteError.conflict.localizedDescription }
            else { try adopt(snapshot) }
        } catch { errorMessage = error.localizedDescription }
    }

    func reload() async throws {
        guard try await store.fileExists(path) else { throw Self.removedExternallyError }
        try adopt(await store.read(path, maximumBytes: Self.maximumEditableBytes))
    }

    private static let removedExternallyError = GraphiteError.unavailable(
        "Another app deleted or moved this note, so there is no other version to use. Save a Copy keeps your edits.")

    private func adopt(_ snapshot: FileSnapshot) throws {
        guard let decoded = NoteTextEncoding.decode(snapshot.data) else { throw GraphiteError.invalidFile("External note is not UTF-8.") }
        // The version another app replaced is kept, in case its change was unwanted.
        if decoded.text != savedText { willReplaceSavedText?(savedText) }
        text = decoded.text; savedText = decoded.text; hasByteOrderMark = decoded.hasByteOrderMark; revision = snapshot.revision
        hasExternalConflict = false; errorMessage = nil
    }

    /// Writes the edits to a new note beside this one and ends the conflict: this note
    /// shows the other app's version again, or, when the other app deleted or moved it,
    /// lets the edits go from here, since they are now in the copy. Either way nothing
    /// unsaved is left, so the person can move on to the copy or any other note. Once the
    /// copy is written this does not throw, so the copy is never reported as failed.
    func saveSeparateCopy() async throws -> VaultPath {
        let separatePath = try await store.uniquePath(directory: path.parent, stem: path.stem + " Graphite edits", extension: "md")
        _ = try await store.save(NoteTextEncoding.encode(text, hasByteOrderMark: hasByteOrderMark), at: separatePath, expecting: .absent)
        do {
            try await reload()
        } catch {
            let isRemoved = (try? await store.fileExists(path)) == false
            text = savedText
            hasExternalConflict = false
            // The other version exists but cannot be shown, such as a file too large or
            // no longer UTF-8; the note says so when the person comes back to it.
            errorMessage = isRemoved ? nil : error.localizedDescription
        }
        return separatePath
    }

    /// Property types assigned in `.obsidian/types.json`, which the Properties view parses
    /// this note's frontmatter with.
    private(set) var declaredPropertyTypes: [String: PropertyType] = [:]

    /// Reads the vault's assigned property types again.
    func loadDeclaredPropertyTypes() async {
        let loadedTypes = await store.propertyTypes()
        if loadedTypes != declaredPropertyTypes { declaredPropertyTypes = loadedTypes }
    }

    /// Rewrites only the frontmatter, in Obsidian's property format, and saves through
    /// the normal autosave path. The properties were parsed with `declaredPropertyTypes`,
    /// so unchanged values keep their exact YAML.
    func replaceProperties(_ properties: [NoteProperty]) {
        text = NoteProperties.replacingFrontmatter(in: text, with: properties, declaredTypes: declaredPropertyTypes)
    }

    /// Folded headings and list items (`NoteFolding` keys). As in Obsidian, folds are kept
    /// on the device, not written into the note.
    var foldedKeys: Set<String> = [] {
        didSet { if foldedKeys != oldValue { didChangeFolds?(foldedKeys) } }
    }
    @ObservationIgnored var didChangeFolds: ((Set<String>) -> Void)?

    /// Folds or unfolds the heading or list item on the line at `location`; false when
    /// nothing there folds.
    @discardableResult
    func toggleFold(atLine location: Int) -> Bool {
        let regions = NoteFolding.regions(in: text)
        guard let region = NoteFolding.region(atLine: location, in: regions, text: text as NSString) else { return false }
        if foldedKeys.contains(region.key) { foldedKeys.remove(region.key) } else { foldedKeys.insert(region.key) }
        return true
    }

    /// Unfolds what hides a heading or text a jump is about to show.
    func unfold(toShow request: HeadingScrollRequest) {
        guard !foldedKeys.isEmpty else { return }
        let source = text as NSString
        var location = request.textRange?.location
        if location == nil, !request.anchor.isEmpty {
            // The heading's line: the first heading line whose anchor matches, outside code.
            var tracker = CodeFenceTracker()
            var lineStart = FrontmatterLocator.length(in: source)
            while lineStart < source.length, location == nil {
                let lineRange = source.lineRange(for: NSRange(location: lineStart, length: 0))
                let line = source.substring(with: lineRange)
                if !tracker.isCodeLine(line.trimmingCharacters(in: .whitespacesAndNewlines)),
                   NotePreviewDocument.outline(of: line).first?.anchor == request.anchor { location = lineRange.location }
                lineStart = NSMaxRange(lineRange)
            }
        }
        guard let location else { return }
        let folded = NoteFolding.foldedRegions(in: NoteFolding.regions(in: text), foldedKeys: foldedKeys)
        let hiding = NoteFolding.regions(hiding: location, in: folded)
        if !hiding.isEmpty { foldedKeys.subtract(hiding.map(\.key)) }
    }

    func foldAll() {
        foldedKeys = Set(NoteFolding.regions(in: text).map(\.key))
    }

    func unfoldAll() {
        foldedKeys = []
    }

    /// Called with the note's saved text just before a save or a reload replaces it, so File
    /// recovery can keep a copy.
    @ObservationIgnored var willReplaceSavedText: ((String) -> Void)?

    /// Whether an editor shows this note, which applies insertions so they can be undone.
    /// An editor that goes away before applying them leaves them in the text directly, so
    /// nothing requested is lost.
    @ObservationIgnored var isEditorAttached = false {
        didSet {
            guard !isEditorAttached, !pendingInsertions.isEmpty else { return }
            let waitingInsertions = pendingInsertions
            pendingInsertions = []
            waitingInsertions.forEach(applyWithoutEditor)
        }
    }

    /// Inserts `content` at `range` of the current text, or at the cursor.
    func insert(_ content: String, at range: NSRange? = nil) {
        let target = insertionTarget(for: range)
        request(EditorInsertion(text: content, range: target.range))
    }

    /// Inserts a block such as an embed on its own line. Blank lines around the cursor
    /// are kept, so paragraphs never merge and a following `---` never turns the
    /// block into a heading.
    /// - Parameter separatedByBlankLines: Keeps an empty line around the block (quotes).
    func insertBlock(_ block: String, at range: NSRange? = nil, separatedByBlankLines: Bool = false) {
        let target = insertionTarget(for: range)
        let insertionRange = target.range
        let source = target.text
        // Never split the frontmatter: Obsidian would stop reading the note's properties.
        let frontmatterLength = FrontmatterLocator.length(in: source)
        let location = max(min(insertionRange.location, source.length), frontmatterLength)
        let endLocation = max(min(insertionRange.location + insertionRange.length, source.length), location)
        let insertion = MarkdownBlockInsertion.text(inserting: block, into: source, replacing: NSRange(location: location, length: endLocation - location),
                                                    separatedByBlankLines: separatedByBlankLines)
        request(EditorInsertion(text: insertion, range: NSRange(location: location, length: endLocation - location)))
    }

    /// Applies an editing command's result, computed on the current text, through the
    /// editor, so it can be undone.
    func apply(_ edit: MarkdownTextEdit) {
        let target = insertionTarget(for: edit.range)
        let selectionAfter = insertionTarget(for: edit.selectionAfter).range
        request(EditorInsertion(text: edit.replacement, range: target.range, selectionAfter: selectionAfter))
    }

    private func request(_ insertion: EditorInsertion) {
        if isEditorAttached { pendingInsertions.append(insertion) } else { applyWithoutEditor(insertion) }
    }

    /// The text a new insertion goes into, which already includes the insertions still
    /// waiting for the editor, and `range` of the current text moved past them; without a
    /// range, the cursor as it will be once they are applied.
    private func insertionTarget(for range: NSRange?) -> (text: NSString, range: NSRange) {
        var source = text as NSString
        guard !pendingInsertions.isEmpty else { return (source, range ?? selection) }
        var movedRange = range ?? selection
        var cursorAfterInsertions = selection
        for insertion in pendingInsertions {
            let replacedRange = Self.clamped(insertion.range, toLength: source.length)
            let insertedLength = (insertion.text as NSString).length
            source = source.replacingCharacters(in: replacedRange, with: insertion.text) as NSString
            let movedStart = Self.moved(movedRange.location, pastReplacing: replacedRange, insertedLength: insertedLength)
            let movedEnd = Self.moved(NSMaxRange(movedRange), pastReplacing: replacedRange, insertedLength: insertedLength)
            movedRange = NSRange(location: movedStart, length: max(movedEnd - movedStart, 0))
            cursorAfterInsertions = insertion.selectionAfter ?? NSRange(location: replacedRange.location + insertedLength, length: 0)
        }
        return (source, range == nil ? cursorAfterInsertions : movedRange)
    }

    /// Where `location` ends up after `replacedRange` becomes `insertedLength` characters:
    /// unchanged before it, shifted after it, and at the end of the new text inside it. A
    /// location right where an insertion goes lands after it, so requests keep their order.
    private static func moved(_ location: Int, pastReplacing replacedRange: NSRange, insertedLength: Int) -> Int {
        if location < replacedRange.location { return location }
        if location >= NSMaxRange(replacedRange) { return location + insertedLength - replacedRange.length }
        return replacedRange.location + insertedLength
    }

    private static func clamped(_ range: NSRange, toLength length: Int) -> NSRange {
        let location = min(max(range.location, 0), length)
        return NSRange(location: location, length: min(max(range.length, 0), length - location))
    }

    /// Changes the text directly when no editor shows the note, as in reading view: an
    /// insertion waiting for an editor would not be saved until one appeared.
    private func applyWithoutEditor(_ insertion: EditorInsertion) {
        let source = text as NSString
        let replacedRange = Self.clamped(insertion.range, toLength: source.length)
        text = source.replacingCharacters(in: replacedRange, with: insertion.text)
        selection = insertion.selectionAfter ?? NSRange(location: replacedRange.location + (insertion.text as NSString).length, length: 0)
    }

    /// Opens the find bar in the editor, leaving reading view first: it searches the text.
    func requestFind(_ request: FindRequest, editingMode: EditingMode) {
        if viewMode == .reading { viewMode = editingMode == .source ? .source : .livePreview }
        findRequest = request
    }

    /// Obsidian's "Toggle reading view": reading, or back to the editing mode.
    func toggleReadingView(editingMode: EditingMode) {
        viewMode = viewMode != .reading ? .reading : (editingMode == .source ? .source : .livePreview)
    }

    func markInsertionApplied(_ insertion: EditorInsertion) {
        if pendingInsertions.first?.id == insertion.id { pendingInsertions.removeFirst() }
    }
}

/// A note's text as stored in UTF-8. A leading byte-order mark is kept apart from the
/// text, as Foundation's decoder would drop it, so that it can be written back unchanged.
enum NoteTextEncoding {
    private static let byteOrderMark: [UInt8] = [0xEF, 0xBB, 0xBF]

    /// The text, or nil when the bytes are not valid UTF-8.
    static func decode(_ data: Data) -> (text: String, hasByteOrderMark: Bool)? {
        let hasByteOrderMark = data.starts(with: byteOrderMark)
        guard let text = String(validating: data.dropFirst(hasByteOrderMark ? byteOrderMark.count : 0), as: UTF8.self) else { return nil }
        return (text, hasByteOrderMark)
    }

    static func encode(_ text: String, hasByteOrderMark: Bool) -> Data {
        hasByteOrderMark ? Data(byteOrderMark) + Data(text.utf8) : Data(text.utf8)
    }
}

struct EditorInsertion: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let range: NSRange
    /// Where the selection goes afterwards; after the inserted text when nil.
    var selectionAfter: NSRange?
}

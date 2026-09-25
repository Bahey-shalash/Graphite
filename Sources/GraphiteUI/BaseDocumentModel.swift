import Foundation
import Observation
import GraphiteCore
import GraphiteIndex

/// Where a base's definition comes from.
public enum BaseSource: Hashable, Sendable {
    /// A `.base` file in the vault.
    case file(VaultPath)
    /// The YAML of a ```` ```base ```` code block.
    case inline(String)
}

/// State of one open or embedded base. Reading, pre-filtering, evaluation and
/// sorting run off the main actor; only finished results are published here.
@MainActor @Observable
final class BaseDocumentModel {
    /// Notes larger than the editor's budget are not rewritten from a base.
    private static let maximumEditableNoteBytes = 8 * 1_048_576

    let source: BaseSource
    /// The file `this` refers to: the base itself, or the note embedding it.
    let contextPath: VaultPath
    private let store: VaultStore
    private let index: VaultIndex
    /// Tells the app which vault file the base just saved.
    private let didSaveFile: (VaultPath) -> Void

    private(set) var definition: BaseDefinition?
    private(set) var loadErrorMessage: String?
    private(set) var result: BaseQueryResult?
    private(set) var candidateCount = 0
    private(set) var loadedRecordCount = 0
    private(set) var isLoading = false
    var actionErrorMessage: String?
    private(set) var selectedViewIndex = 0
    /// A sort chosen from the column headers; nil uses the view's own sort.
    private(set) var sortOverride: [BaseSortKey]?
    private(set) var declaredTypes: [String: PropertyType] = [:]
    /// `declaredTypes` by case-folded name, since every editable cell looks its type up.
    @ObservationIgnored private var declaredTypesByFoldedName: [String: PropertyType] = [:]
    /// Checkbox values asked for that the base does not show yet, by edit request, so a
    /// quick second tap toggles from the value the first tap asked for.
    private(set) var requestedCheckboxValues: [String: Bool] = [:]
    /// Property writes run one after another, so each reads the note the previous one saved.
    @ObservationIgnored private var propertyWrites: Task<Void, Never>?
    /// Note property names seen in the loaded records, for choosing columns.
    private(set) var availablePropertyKeys: [String] = []
    /// The revision `definition` was parsed from. Set together with `definition`, so an
    /// edit whose revision check passes also acts on the views the person saw.
    private var sourceRevision: FileRevision?
    /// The text `definition` was parsed from, so a reload after an unrelated index change
    /// does not parse an unchanged base again.
    private var parsedSourceText: String?
    private var preferredViewName: String?
    /// Reloads overlap when index changes arrive quickly; only the newest one publishes.
    private var reloadGeneration = 0
    private var queryGeneration = 0
    /// The query now running, cancelled when a newer run supersedes it.
    private var runningQuery: Task<QueryOutcome, any Error>?
    /// The records the last published run loaded. The next run reads again only the files
    /// whose index rows changed, so a save elsewhere or a header tap does not reload them all.
    private var loadedRecords = LoadedBaseRecords()
    /// The vault content version the last completed reload read, set by the view that owns
    /// this model, so a view appearing again does not reload unchanged content.
    @ObservationIgnored var loadedContentVersion: Int?
    /// Keeps the property list for the view editor small on vaults with many keys.
    private nonisolated static let maximumAvailablePropertyKeys = 300

    init(source: BaseSource, contextPath: VaultPath, store: VaultStore, index: VaultIndex, preferredViewName: String? = nil,
         didSaveFile: @escaping (VaultPath) -> Void = { _ in }) {
        self.source = source
        self.didSaveFile = didSaveFile
        self.contextPath = contextPath
        self.store = store
        self.index = index
        self.preferredViewName = preferredViewName
    }

    var views: [BaseView] { definition?.views ?? [] }
    var selectedView: BaseView? { views.indices.contains(selectedViewIndex) ? views[selectedViewIndex] : nil }
    var isTruncated: Bool { candidateCount > loadedRecordCount }
    var effectiveSort: [BaseSortKey] { sortOverride ?? selectedView?.sort ?? [] }
    var vaultRoot: URL { store.root }

    // MARK: Loading

    /// Re-reads the definition and runs the selected view again. The selected view is
    /// kept by name, so a view another app inserts or removes does not move the
    /// selection, a header sort or an edit onto a different view.
    func reload() async {
        reloadGeneration += 1
        let generation = reloadGeneration
        isLoading = true
        do {
            let sourceText: String
            var loadedRevision: FileRevision?
            switch source {
            case .inline(let yaml):
                sourceText = yaml
            case .file(let path):
                let snapshot = try await store.read(path, maximumBytes: BaseDefinition.maximumSourceBytes)
                guard let fileText = UTF8FileText(snapshot.data) else { throw GraphiteError.invalidFile("This base is not UTF-8 text.") }
                sourceText = fileText.text
                loadedRevision = snapshot.revision
            }
            let parsedDefinition: BaseDefinition
            if let definition, sourceText == parsedSourceText {
                parsedDefinition = definition
            } else {
                parsedDefinition = try await Task.detached(priority: .userInitiated) { try BaseDefinition.parse(sourceText) }.value
            }
            let loadedDeclaredTypes = await store.propertyTypes()
            // A newer reload started while this one read or parsed; its definition wins.
            guard generation == reloadGeneration else { return }
            let previouslySelectedView = selectedView
            sourceRevision = loadedRevision
            parsedSourceText = sourceText
            declaredTypes = loadedDeclaredTypes
            declaredTypesByFoldedName = Dictionary(loadedDeclaredTypes.map { name, type in (Self.foldedPropertyName(name), type) },
                                                   uniquingKeysWith: { firstType, _ in firstType })
            definition = parsedDefinition
            loadErrorMessage = nil
            restoreSelection(in: parsedDefinition, previouslySelectedView: previouslySelectedView)
        } catch {
            guard generation == reloadGeneration else { return }
            if error is CancellationError {
                isLoading = false
                return
            }
            // A query still running for the old definition must not publish after this.
            runningQuery?.cancel()
            queryGeneration += 1
            definition = nil
            parsedSourceText = nil
            sourceRevision = nil
            result = nil
            loadErrorMessage = error.localizedDescription
            isLoading = false
            return
        }
        await runQuery()
    }

    private func restoreSelection(in parsedDefinition: BaseDefinition, previouslySelectedView: BaseView?) {
        let views = parsedDefinition.views
        if let preferredViewName, let namedIndex = views.firstIndex(where: { view in view.name == preferredViewName }) {
            selectedViewIndex = namedIndex
            self.preferredViewName = nil
            return
        }
        guard let previouslySelectedView else {
            selectedViewIndex = max(0, min(selectedViewIndex, views.count - 1))
            return
        }
        if views.indices.contains(selectedViewIndex), views[selectedViewIndex].name == previouslySelectedView.name { return }
        if let movedIndex = views.firstIndex(where: { view in view.name == previouslySelectedView.name }) {
            selectedViewIndex = movedIndex
            return
        }
        // The selected view is gone: its header sort belongs to no remaining view.
        selectedViewIndex = max(0, min(selectedViewIndex, views.count - 1))
        sortOverride = nil
        result = nil
    }

    /// Runs the selected view over the index. A newer run supersedes an older one and
    /// cancels it, as does cancelling the task that awaits this run.
    func runQuery() async {
        guard let definition, !definition.views.isEmpty else { return }
        runningQuery?.cancel()
        queryGeneration += 1
        let generation = queryGeneration
        isLoading = true
        let viewIndex = selectedViewIndex
        let sortOverride = sortOverride
        let environment = BaseEvaluationEnvironment(now: .now, calendar: BaseDateFormatting.displayCalendar, declaredTypes: declaredTypes)
        let contextPath = contextPath
        let index = index
        let provider = index.baseRecordProvider
        let previouslyLoadedRecords = loadedRecords
        // Detached: record lookups through the provider read SQLite synchronously. A
        // detached task does not inherit cancellation, so it is cancelled explicitly.
        let queryTask = Task.detached(priority: .userInitiated) { () throws -> QueryOutcome in
            let indexedContext = try await index.baseRecord(at: contextPath)
            try Task.checkCancellation()
            let thisRecord = indexedContext ?? BaseFileRecord(path: contextPath, size: 0, createdDate: .now, modifiedDate: .now)
            let view = definition.views[viewIndex]
            let filters = [definition.filters, view.filters].compactMap { filter in filter }
            let prefilter = BaseRecordPrefilter.extract(from: filters, definition: definition, environment: environment, thisRecord: thisRecord, provider: provider)
            let (batch, loadedRecords) = try await index.baseRecords(matching: prefilter, reusing: previouslyLoadedRecords)
            try Task.checkCancellation()
            let engine = BaseQueryEngine(definition: definition, environment: environment, thisRecord: thisRecord, provider: provider)
            var propertyKeys: Set<String> = []
            for record in batch.records where propertyKeys.count < Self.maximumAvailablePropertyKeys {
                propertyKeys.formUnion(record.properties.map(\.key))
            }
            let sortedKeys = propertyKeys.sorted { leftKey, rightKey in leftKey.localizedStandardCompare(rightKey) == .orderedAscending }
            let queryResult = engine.run(viewIndex: viewIndex, records: batch.records, sortOverride: sortOverride)
            // The evaluator cannot throw, so a lookup the database failed read as a missing
            // record or link; the rows computed from it are not shown.
            try provider.throwIfLookupFailed()
            return QueryOutcome(result: queryResult, candidateCount: batch.candidateCount,
                                loadedRecordCount: batch.records.count, availablePropertyKeys: sortedKeys, loadedRecords: loadedRecords)
        }
        runningQuery = queryTask
        do {
            let outcome = try await withTaskCancellationHandler {
                try await queryTask.value
            } onCancel: {
                queryTask.cancel()
            }
            guard generation == queryGeneration else { return }
            loadedRecords = outcome.loadedRecords
            // Publishing an identical result would lay out every visible row again.
            if !(result.map { shownResult in Self.hasSameContent(shownResult, outcome.result) } ?? false) { result = outcome.result }
            candidateCount = outcome.candidateCount
            loadedRecordCount = outcome.loadedRecordCount
            availablePropertyKeys = outcome.availablePropertyKeys
            actionErrorMessage = nil
        } catch is CancellationError {
        } catch {
            guard generation == queryGeneration else { return }
            actionErrorMessage = error.localizedDescription
        }
        if generation == queryGeneration {
            isLoading = false
            runningQuery = nil
        }
    }

    private struct QueryOutcome: Sendable {
        let result: BaseQueryResult
        let candidateCount: Int
        let loadedRecordCount: Int
        let availablePropertyKeys: [String]
        let loadedRecords: LoadedBaseRecords
    }

    nonisolated static func hasSameContent(_ leftResult: BaseQueryResult, _ rightResult: BaseQueryResult) -> Bool {
        leftResult.matchingCount == rightResult.matchingCount && leftResult.view == rightResult.view && leftResult.columns == rightResult.columns
            && leftResult.problems == rightResult.problems && leftResult.mapCenter == rightResult.mapCenter
            && leftResult.summaries == rightResult.summaries && leftResult.groups == rightResult.groups
    }

    /// Shows the view with this name, as a `[[Books.base#Gallery]]` link asks; before the
    /// definition loads, the name is kept for the first load.
    func selectView(named viewName: String) async {
        guard definition != nil else {
            preferredViewName = viewName
            return
        }
        guard let viewIndex = views.firstIndex(where: { view in view.name == viewName }) else { return }
        await selectView(viewIndex)
    }

    func selectView(_ viewIndex: Int) async {
        guard views.indices.contains(viewIndex), viewIndex != selectedViewIndex else { return }
        selectedViewIndex = viewIndex
        sortOverride = nil
        result = nil
        await runQuery()
    }

    /// Header taps cycle ascending → descending → the view's own sort. When the view's own
    /// sort already puts this column first in descending order, returning to it would change
    /// nothing, so the tap sorts ascending instead and every tap changes the order.
    func toggleSort(on property: BasePropertyIdentifier) async {
        sortOverride = Self.sortOverride(afterTappingHeaderOf: property, effectiveSort: effectiveSort, viewSort: selectedView?.sort ?? [])
        await runQuery()
    }

    nonisolated static func sortOverride(afterTappingHeaderOf property: BasePropertyIdentifier, effectiveSort: [BaseSortKey],
                                         viewSort: [BaseSortKey]) -> [BaseSortKey]? {
        let ascending = [BaseSortKey(property: property, direction: .ascending)]
        let descending = [BaseSortKey(property: property, direction: .descending)]
        guard let current = effectiveSort.first, current.property == property else { return ascending }
        if current.direction == .ascending { return descending }
        return viewSort.first == descending.first ? ascending : nil
    }

    func setSort(on property: BasePropertyIdentifier, direction: BaseSortDirection) async {
        sortOverride = [BaseSortKey(property: property, direction: direction)]
        await runQuery()
    }

    func resetSort() async {
        sortOverride = nil
        await runQuery()
    }

    // MARK: Editing the base

    /// Only `.base` files are edited from here; a code block belongs to its note's editor.
    var canEditDefinition: Bool {
        if case .file = source, definition != nil { return true }
        return false
    }

    /// Applies an edit to the `.base` file with a revision-checked save, then reloads.
    /// Refuses when the file changed since it was loaded, so another app's edit is
    /// never overwritten, and when `target` no longer names the same view, so an edit
    /// prepared on one view (such as in the view editor) never lands on another.
    /// - Returns: The edit's result, or nil when nothing was saved.
    /// - Parameter selectingViewNamed: The view to keep selected afterwards, such as the
    ///   new name of a renamed view.
    func editDefinition<EditResult: Sendable>(target: BaseViewTarget? = nil, selectingViewNamed viewNameAfterEdit: String? = nil,
                                              _ change: @escaping @Sendable (inout BaseDefinitionEditor) throws -> EditResult) async -> EditResult? {
        guard case .file(let path) = source else { return nil }
        do {
            let snapshot = try await store.read(path, maximumBytes: BaseDefinition.maximumSourceBytes)
            guard let sourceRevision, snapshot.revision == sourceRevision else {
                await reload()
                throw GraphiteError.invalidFile("This base changed in another app, so Graphite reloaded it. Make the change again.")
            }
            if let target, !(definition?.views.contains(where: target.matches) ?? false) {
                throw GraphiteError.invalidFile("The view “\(target.name)” changed in another app. Make the change again.")
            }
            guard let fileText = UTF8FileText(snapshot.data) else { throw GraphiteError.invalidFile("This base is not UTF-8 text.") }
            let text = fileText.text
            let (updatedText, editResult) = try await Task.detached(priority: .userInitiated) {
                var editor = try BaseDefinitionEditor(yaml: text)
                let editResult = try change(&editor)
                return (try editor.yaml(), editResult)
            }.value
            // `sourceRevision` keeps naming the text `definition` was parsed from until the
            // reload below parses the saved text, so an edit started meanwhile is refused
            // rather than checked against views this edit replaced.
            _ = try await store.save(fileText.encoded(updatedText), at: path, expecting: .revision(snapshot.revision))
            didSaveFile(path)
            if let viewNameAfterEdit, !viewNameAfterEdit.isEmpty { preferredViewName = viewNameAfterEdit }
            await reload()
            return editResult
        } catch {
            actionErrorMessage = error.localizedDescription
            return nil
        }
    }

    // `selectedViewIndex` counts the views shown in the menu. The file's editor counts
    // entries of the `views` list, which can include entries that are not views, so it
    // is given `BaseView.id`, the view's position in that list.

    /// Selects the view at `position` in the file's `views` list, after an edit added it.
    private func selectView(atPosition position: Int) async {
        guard let viewIndex = views.firstIndex(where: { view in view.id == position }) else { return }
        await selectView(viewIndex)
    }

    /// Writes the header sort into the view, as Obsidian saves sort changes.
    func saveSortToView() async {
        guard let sortOverride, let view = selectedView else { return }
        let viewPosition = view.id
        if await editDefinition(target: BaseViewTarget(view), { editor in try editor.setSort(sortOverride, forViewAt: viewPosition) }) != nil {
            self.sortOverride = nil
            await runQuery()
        }
    }

    func addView(type: BaseViewType) async {
        let name = uniqueViewName(type.defaultViewName)
        if let newPosition = await editDefinition({ editor in editor.addView(type: type, name: name) }) {
            await selectView(atPosition: newPosition)
        }
    }

    func duplicateSelectedView() async {
        guard let view = selectedView else { return }
        let viewPosition = view.id
        let name = uniqueViewName(view.name + " copy")
        if let newPosition = await editDefinition(target: BaseViewTarget(view), { editor in try editor.duplicateView(at: viewPosition, name: name) }) {
            await selectView(atPosition: newPosition)
        }
    }

    /// Deletes the view the person confirmed, even if the selection moved since.
    func deleteView(_ target: BaseViewTarget) async {
        guard views.count > 1 else { return }
        let viewPosition = target.position
        let viewIndex = selectedViewIndex
        let wasSelected = selectedView.map(target.matches) ?? false
        if await editDefinition(target: target, { editor in try editor.removeView(at: viewPosition) }) != nil {
            guard wasSelected else { return }
            selectedViewIndex = max(0, min(viewIndex, views.count - 1))
            sortOverride = nil
            result = nil
            await runQuery()
        }
    }

    private func uniqueViewName(_ baseName: String) -> String {
        let existingNames = Set(views.map(\.name))
        guard existingNames.contains(baseName) else { return baseName }
        for suffixNumber in 2...1_000 where !existingNames.contains("\(baseName) \(suffixNumber)") { return "\(baseName) \(suffixNumber)" }
        return baseName
    }

    // MARK: Links

    /// The file a link cell points to, if exactly one. A folder is never a link's
    /// destination, so `[[Books]]` reaches `Books.md` even beside a `Books` folder.
    /// - Throws: When the vault or the index cannot be read, so that is not reported
    ///   as a link with no match.
    func resolve(_ link: BaseLink) async throws -> VaultPath? {
        guard !link.isExternal else { return nil }
        let source = link.source ?? contextPath
        if let rootedPath = try? VaultPath(link.pathPart), !rootedPath.rawValue.isEmpty, try isRegularFile(rootedPath) { return rootedPath }
        let matches = try await index.resolve(link.target, from: source)
        return matches.count == 1 ? matches.first : nil
    }

    private func isRegularFile(_ path: VaultPath) throws -> Bool {
        let location = try path.url(in: store.root)
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: location.path, isDirectory: &isDirectory) && !isDirectory.boolValue
    }

    // MARK: Editing

    /// Whether a cell's property can be edited from the base: note properties only,
    /// never the note that embeds this base (its open editor owns that text). For a
    /// base opened on its own, `contextPath` is the `.base` file, which is never a row
    /// that can be edited.
    func canEdit(_ property: BasePropertyIdentifier, of path: VaultPath) -> Bool {
        guard case .note = property, DocumentKind(path: path) == .markdown else { return false }
        return path != contextPath
    }

    /// Whether a value can round-trip through the property editor. A mapping, or a list
    /// holding mappings or lists, would be rewritten as its display text and lose its
    /// nested structure, so it is edited in the note instead.
    nonisolated static func canEditValue(_ value: BaseValue?) -> Bool {
        switch value {
        case .object: false
        case .list(let elements): !elements.contains { element in
            switch element {
            case .object, .list: true
            default: false
            }
        }
        default: true
        }
    }

    func editorKind(for property: BasePropertyIdentifier, currentValue: BaseValue?) -> BasePropertyEditorKind {
        let declaredType = declaredTypes[property.name] ?? declaredTypesByFoldedName[Self.foldedPropertyName(property.name)]
        switch declaredType {
        case .number: return .number
        case .checkbox: return .checkbox
        case .date: return .date
        case .datetime: return .dateTime
        case .multitext, .tags, .aliases: return .list
        case .text: return .text
        case nil: break
        }
        switch currentValue {
        case .boolean: return .checkbox
        case .number: return .number
        case .date(let date): return date.hasTime ? .dateTime : .date
        case .list: return .list
        default: return .text
        }
    }

    private nonisolated static func foldedPropertyName(_ name: String) -> String {
        name.folding(options: .caseInsensitive, locale: nil)
    }

    /// Checks or unchecks a checkbox cell, starting from the value the person sees: the
    /// value an earlier tap asked for while its save is running, otherwise `shownValue`.
    func toggleCheckbox(_ request: BaseEditRequest, shownValue: Bool) async {
        let isChecked = !(requestedCheckboxValues[request.id] ?? shownValue)
        requestedCheckboxValues[request.id] = isChecked
        let previousWrite = propertyWrites
        let write = Task {
            await previousWrite?.value
            await self.setProperty(request.property, of: request.path, to: .checkbox(isChecked))
        }
        propertyWrites = write
        await write.value
        if requestedCheckboxValues[request.id] == isChecked { requestedCheckboxValues[request.id] = nil }
    }

    /// Writes one property into the note's frontmatter with a revision-checked save,
    /// refreshes that note's index rows, and runs the view again.
    /// - Returns: Whether the note was saved (or already had this value).
    @discardableResult
    func setProperty(_ property: BasePropertyIdentifier, of path: VaultPath, to value: PropertyValue?) async -> Bool {
        guard canEdit(property, of: path) else { return false }
        let store = store
        let declaredTypes = declaredTypes
        do {
            let snapshot = try await store.read(path, maximumBytes: Self.maximumEditableNoteBytes)
            guard let noteFileText = UTF8FileText(snapshot.data) else { throw GraphiteError.invalidFile("This note is not UTF-8 text.") }
            let noteText = noteFileText.text
            let updatedText = try await Task.detached(priority: .userInitiated) {
                try BasePropertyEditing.settingProperty(property.name, to: value, in: noteText, declaredTypes: declaredTypes)
            }.value
            guard updatedText != noteText else { return true }
            _ = try await store.save(noteFileText.encoded(updatedText), at: path, expecting: .revision(snapshot.revision))
        } catch {
            actionErrorMessage = error.localizedDescription
            return false
        }
        // The note is saved from here on, so a failure to refresh the index is reported as
        // that, never as a failed edit that the person might repeat.
        didSaveFile(path)
        var indexErrorMessage: String?
        do {
            try await index.refresh(paths: [path], root: store.root)
        } catch {
            indexErrorMessage = "The change was saved to “\(path.name)”, but the base can't show it until the vault index updates. \(error.localizedDescription)"
        }
        await runQuery()
        if let indexErrorMessage { actionErrorMessage = indexErrorMessage }
        return true
    }

    /// The property as written in the note's frontmatter. A base value cannot tell an
    /// embed or a Markdown link from a Wikilink, or show a date's written separator, so
    /// the cell editor starts from this text to keep them. Nil when the note or its
    /// frontmatter cannot be read, or the note has no such property.
    func writtenPropertyNode(_ property: BasePropertyIdentifier, of path: VaultPath) async -> BaseFrontmatterNode? {
        guard let snapshot = try? await store.read(path, maximumBytes: Self.maximumEditableNoteBytes),
              let noteText = UTF8FileText(snapshot.data)?.text else { return nil }
        let propertyName = property.name.trimmingCharacters(in: .whitespaces)
        return await Task.detached(priority: .userInitiated) {
            guard let yaml = BasePropertyEditing.frontmatterYAML(in: noteText),
                  let entries = BaseFrontmatter.entries(fromYAML: yaml) else { return nil }
            // The same entry `BasePropertyEditing.settingProperty` changes on saving.
            let entry = entries.first { entry in entry.key == propertyName }
                ?? entries.first { entry in entry.key.caseInsensitiveCompare(propertyName) == .orderedSame }
            return entry?.node
        }.value
    }
}

/// One view of a base as the person saw it: its position in the file's `views` list and
/// its name. An edit prepared on a view checks both, so it never lands on another view.
struct BaseViewTarget: Hashable {
    let position: Int
    let name: String

    init(_ view: BaseView) {
        self.init(position: view.id, name: view.name)
    }

    init(position: Int, name: String) {
        self.position = position
        self.name = name
    }

    func matches(_ view: BaseView) -> Bool { view.id == position && view.name == name }
}

/// The text of a UTF-8 file and whether it began with a byte order mark. Decoding drops a
/// leading mark, so saving only `Data(text.utf8)` would remove one the person never
/// edited; `encoded(_:)` puts it back.
private struct UTF8FileText {
    private static let byteOrderMark: [UInt8] = [0xEF, 0xBB, 0xBF]
    let text: String
    let hasByteOrderMark: Bool

    init?(_ data: Data) {
        hasByteOrderMark = data.starts(with: Self.byteOrderMark)
        guard let decodedText = String(data: hasByteOrderMark ? Data(data.dropFirst(Self.byteOrderMark.count)) : data, encoding: .utf8) else { return nil }
        text = decodedText
    }

    func encoded(_ updatedText: String) -> Data {
        (hasByteOrderMark ? Data(Self.byteOrderMark) : Data()) + Data(updatedText.utf8)
    }
}

enum BasePropertyEditorKind {
    case text, number, checkbox, date, dateTime, list
}

extension BaseViewType {
    /// The name Obsidian gives a new view of this type.
    var defaultViewName: String {
        switch self {
        case .table: "Table"
        case .cards: "Cards"
        case .list: "List"
        case .map: "Map"
        case .unsupported(let name): name.capitalized
        }
    }
}

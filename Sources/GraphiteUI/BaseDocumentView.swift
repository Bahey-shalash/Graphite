import SwiftUI
import GraphiteCore
import GraphiteIndex

/// Opens a `.base` file: a view switcher, the result count, and the selected view.
/// `this` is the base file itself.
///
/// - Parameters:
///   - viewName: The view to show, as in a `[[Books.base#Gallery]]` link. A new name
///     selects that view in the base already shown.
///   - contentVersion: Change it after vault files or the index change; the base
///     re-reads its definition and runs the view again.
///   - isIndexComplete: False while the first index scan runs, to say results may be partial.
///   - open: Opens a vault file (a row, card, marker or link).
///   - filesChanged: Called after the base saved a note (inline property edits).
public struct BaseDocumentView: View {
    private let path: VaultPath
    private let viewName: String?
    private let store: VaultStore
    private let index: VaultIndex
    private let contentVersion: Int
    private let isIndexComplete: Bool
    private let open: (VaultPath) -> Void
    private let filesChanged: ([VaultPath]) -> Void

    public init(path: VaultPath, viewName: String? = nil, store: VaultStore, index: VaultIndex, contentVersion: Int = 0, isIndexComplete: Bool = true,
                open: @escaping (VaultPath) -> Void, filesChanged: @escaping ([VaultPath]) -> Void = { _ in }) {
        self.path = path
        self.viewName = viewName
        self.store = store
        self.index = index
        self.contentVersion = contentVersion
        self.isIndexComplete = isIndexComplete
        self.open = open
        self.filesChanged = filesChanged
    }

    public var body: some View {
        let open = open
        BaseContainerView(source: .file(path), contextPath: path, preferredViewName: viewName, store: store, index: index, contentVersion: contentVersion,
                          isIndexComplete: isIndexComplete, presentation: .document, open: open, openBase: { basePath, _ in open(basePath) },
                          filesChanged: filesChanged)
            .id(path)
    }
}

/// A base inside a Markdown note: a ```` ```base ```` block, or an embed such as
/// `![[Books.base#Reading]]`. `this` is the embedding note. It has a fixed height and
/// scrolls on its own.
public struct EmbeddedBaseView: View {
    public static let defaultHeight: CGFloat = 420
    private let source: BaseSource
    private let embeddingNote: VaultPath
    private let preferredViewName: String?
    private let store: VaultStore
    private let index: VaultIndex
    private let contentVersion: Int
    private let isIndexComplete: Bool
    private let height: CGFloat
    private let open: (VaultPath) -> Void
    private let openBase: ((VaultPath, String?) -> Void)?
    private let filesChanged: ([VaultPath]) -> Void
    private let modelCache: EmbeddedBaseModelCache?

    /// A ```` ```base ```` code block.
    /// - Parameter modelCache: Keeps the base's results while it is off screen; see `EmbeddedBaseModelCache`.
    public init(yaml: String, embeddingNote: VaultPath, store: VaultStore, index: VaultIndex, contentVersion: Int = 0, isIndexComplete: Bool = true,
                height: CGFloat = EmbeddedBaseView.defaultHeight, open: @escaping (VaultPath) -> Void, filesChanged: @escaping ([VaultPath]) -> Void = { _ in },
                modelCache: EmbeddedBaseModelCache? = nil) {
        self.init(source: .inline(yaml), embeddingNote: embeddingNote, viewName: nil, store: store, index: index, contentVersion: contentVersion,
                  isIndexComplete: isIndexComplete, height: height, open: open, openBase: nil, filesChanged: filesChanged, modelCache: modelCache)
    }

    /// An embedded `.base` file, optionally starting on the view named after `#`.
    /// - Parameter openBase: Opens the base on its own at the named view, for the Open Base
    ///   button. Without it, the button opens the base at its first view through `open`.
    /// - Parameter modelCache: Keeps the base's results while it is off screen; see `EmbeddedBaseModelCache`.
    public init(basePath: VaultPath, viewName: String? = nil, embeddingNote: VaultPath, store: VaultStore, index: VaultIndex, contentVersion: Int = 0,
                isIndexComplete: Bool = true, height: CGFloat = EmbeddedBaseView.defaultHeight,
                open: @escaping (VaultPath) -> Void, openBase: ((VaultPath, String?) -> Void)? = nil, filesChanged: @escaping ([VaultPath]) -> Void = { _ in },
                modelCache: EmbeddedBaseModelCache? = nil) {
        self.init(source: .file(basePath), embeddingNote: embeddingNote, viewName: viewName, store: store, index: index, contentVersion: contentVersion,
                  isIndexComplete: isIndexComplete, height: height, open: open, openBase: openBase, filesChanged: filesChanged, modelCache: modelCache)
    }

    private init(source: BaseSource, embeddingNote: VaultPath, viewName: String?, store: VaultStore, index: VaultIndex, contentVersion: Int,
                 isIndexComplete: Bool, height: CGFloat, open: @escaping (VaultPath) -> Void, openBase: ((VaultPath, String?) -> Void)?,
                 filesChanged: @escaping ([VaultPath]) -> Void, modelCache: EmbeddedBaseModelCache?) {
        self.source = source
        self.embeddingNote = embeddingNote
        self.preferredViewName = viewName
        self.store = store
        self.index = index
        self.contentVersion = contentVersion
        self.isIndexComplete = isIndexComplete
        self.height = height
        self.open = open
        self.openBase = openBase
        self.filesChanged = filesChanged
        self.modelCache = modelCache
    }

    public var body: some View {
        let open = open
        BaseContainerView(source: source, contextPath: embeddingNote, preferredViewName: preferredViewName, store: store, index: index,
                          contentVersion: contentVersion, isIndexComplete: isIndexComplete, presentation: .embedded(height: height),
                          open: open, openBase: openBase ?? { basePath, _ in open(basePath) }, filesChanged: filesChanged, modelCache: modelCache)
            .id(EmbedIdentity(source: source, embeddingNote: embeddingNote, viewName: preferredViewName))
    }

    struct EmbedIdentity: Hashable {
        let source: BaseSource
        let embeddingNote: VaultPath
        let viewName: String?
    }
}

/// The state of recently shown embedded bases. A note's editor drops the views of bases
/// scrolled out of sight; with this cache a base scrolled back shows its last results at
/// once and runs again only if the vault changed meanwhile. Keep one per open vault and
/// note editor, and drop it when the vault closes.
@MainActor
public final class EmbeddedBaseModelCache {
    /// Each kept model holds its loaded records and result, so only a few are kept.
    private static let capacity = 8
    /// Most recently used last.
    private var entries: [(identity: EmbeddedBaseView.EmbedIdentity, model: BaseDocumentModel)] = []

    public init() {}

    func model(for identity: EmbeddedBaseView.EmbedIdentity, makeModel: () -> BaseDocumentModel) -> BaseDocumentModel {
        if let position = entries.firstIndex(where: { entry in entry.identity == identity }) {
            let entry = entries.remove(at: position)
            entries.append(entry)
            return entry.model
        }
        let model = makeModel()
        entries.append((identity, model))
        if entries.count > Self.capacity { entries.removeFirst(entries.count - Self.capacity) }
        return model
    }
}

enum BasePresentation: Equatable {
    case document
    case embedded(height: CGFloat)
}

extension EnvironmentValues {
    /// False for a base inside a note: its rows lengthen the note instead of scrolling
    /// inside a box, which would trap the finger that scrolls the note.
    @Entry var basesScrollVertically = true
    /// The most rows a view shows; nil shows every row.
    @Entry var baseRowLimit: Int? = nil
}

/// A result group with only the rows that fit within a row limit.
struct BaseVisibleGroup: Identifiable {
    let group: BaseResultGroup
    let rows: [BaseResultRow]
    var id: Int { group.id }
}

extension BaseQueryResult {
    func visibleGroups(rowLimit: Int?) -> [BaseVisibleGroup] {
        guard let rowLimit else { return groups.map { group in BaseVisibleGroup(group: group, rows: group.rows) } }
        var remainingRowCount = rowLimit
        var visibleGroups: [BaseVisibleGroup] = []
        for group in groups where remainingRowCount > 0 {
            let rows = Array(group.rows.prefix(remainingRowCount))
            remainingRowCount -= rows.count
            visibleGroups.append(BaseVisibleGroup(group: group, rows: rows))
        }
        return visibleGroups
    }
}

/// Shared body of the document and embedded bases. Owns the model for one source.
struct BaseContainerView: View {
    let presentation: BasePresentation
    @Environment(\.accent) private var accent
    let contentVersion: Int
    let isIndexComplete: Bool
    let preferredViewName: String?
    let open: (VaultPath) -> Void
    /// Opens a `.base` file on its own, at the named view.
    let openBase: (VaultPath, String?) -> Void
    let filesChanged: ([VaultPath]) -> Void
    @State private var model: BaseDocumentModel
    /// Kept across reloads: each cached thumbnail is checked against its file, so an index
    /// change after every autosave does not decode every cover again.
    @State private var thumbnails = BaseThumbnailStore()
    @State private var editRequest: BaseEditRequest?
    /// The edited property as written in its note, read before the property sheet opens.
    @State private var editedWrittenNode: BaseFrontmatterNode?
    @State private var editedView: EditedView?
    @State private var viewPendingDeletion: BaseViewTarget?
    /// Rows a base inside a note shows; "Show More" raises it.
    @State private var embeddedRowLimit = Self.embeddedRowLimitStep

    init(source: BaseSource, contextPath: VaultPath, preferredViewName: String?, store: VaultStore, index: VaultIndex, contentVersion: Int,
         isIndexComplete: Bool, presentation: BasePresentation, open: @escaping (VaultPath) -> Void, openBase: @escaping (VaultPath, String?) -> Void,
         filesChanged: @escaping ([VaultPath]) -> Void, modelCache: EmbeddedBaseModelCache? = nil) {
        self.presentation = presentation
        self.contentVersion = contentVersion
        self.isIndexComplete = isIndexComplete
        self.preferredViewName = preferredViewName
        self.open = open
        self.openBase = openBase
        self.filesChanged = filesChanged
        let makeModel = {
            BaseDocumentModel(source: source, contextPath: contextPath, store: store, index: index, preferredViewName: preferredViewName,
                              didSaveFile: { path in filesChanged([path]) })
        }
        let identity = EmbeddedBaseView.EmbedIdentity(source: source, embeddingNote: contextPath, viewName: preferredViewName)
        _model = State(initialValue: modelCache?.model(for: identity, makeModel: makeModel) ?? makeModel())
    }

    private var isEmbedded: Bool { presentation != .document }
    /// Rows a base inside a note shows at first, and how many more each "Show More" adds.
    /// Its rows lengthen the note, so they are all laid out; the limit keeps that bounded.
    private static let embeddedRowLimitStep = 100
    /// A base inside a note grows with its rows, except a map, which keeps its height.
    private var growsWithContent: Bool { isEmbedded && model.selectedView?.type != .map }

    var body: some View {
        Group {
            switch presentation {
            case .document:
                content
            case .embedded(let height):
                content
                    .frame(height: growsWithContent ? nil : embeddedHeight(defaultHeight: height))
                    .environment(\.basesScrollVertically, !growsWithContent)
                    .environment(\.baseRowLimit, growsWithContent ? embeddedRowLimit : nil)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(Color.secondary.opacity(0.25)) }
            }
        }
        .task(id: contentVersion) {
            // A kept model, or this view appearing again, may already show this version.
            guard model.loadedContentVersion != contentVersion else { return }
            await model.reload()
            if !Task.isCancelled, model.loadErrorMessage == nil { model.loadedContentVersion = contentVersion }
        }
        .onChange(of: preferredViewName) { _, viewName in
            guard let viewName else { return }
            Task { await model.selectView(named: viewName) }
        }
        // Both sheets wait for the save and stay open with the edit when it fails.
        .sheet(item: $editRequest) { request in
            BasePropertyEditorSheet(request: request, writtenNode: editedWrittenNode) { newValue in
                guard await model.setProperty(request.property, of: request.path, to: newValue) else {
                    return takeActionErrorMessage(otherwise: "The note was not saved.")
                }
                return nil
            }
            .tint(accent)
        }
        .sheet(item: $editedView) { editedView in
            // The sheet follows the base as it reloads: it shows when its view changed or was
            // removed, and always keeps Cancel.
            let definition = model.definition ?? editedView.definition
            BaseViewEditorSheet(definition: definition, viewIndex: editedView.viewIndex(in: definition),
                                availablePropertyKeys: model.availablePropertyKeys) { draft, original, viewPosition in
                // The view the draft was made from; saving is refused if the file no longer
                // has it there, so the draft never lands on another view.
                let target = BaseViewTarget(position: viewPosition, name: original.name)
                let newViewName = draft.name.trimmingCharacters(in: .whitespaces)
                let isSaved = await model.editDefinition(target: target, selectingViewNamed: newViewName) { editor in
                    try draft.apply(to: &editor, original: original, viewPosition: viewPosition)
                } != nil
                return isSaved ? nil : takeActionErrorMessage(otherwise: "The base was not saved.")
            }
            .tint(accent)
        }
        .confirmationDialog("Delete the view “\(viewPendingDeletion?.name ?? "")” from this base?",
                            isPresented: Binding(get: { viewPendingDeletion != nil }, set: { isPresented in if !isPresented { viewPendingDeletion = nil } }),
                            titleVisibility: .visible, presenting: viewPendingDeletion) { target in
            Button("Delete View", role: .destructive) { Task { await model.deleteView(target) } }
        } message: { _ in
            Text("The notes it shows are not changed.")
        }
    }

    /// Says how many rows are hidden and offers to show more. A `.base` file can also be
    /// opened on its own; a ```` ```base ```` block has no file to open.
    private func rowLimitFooter(displayedCount: Int) -> some View {
        HStack(spacing: 12) {
            Text("Showing the first \(embeddedRowLimit.formatted()) of \(displayedCount.formatted()) results.")
                .font(.caption).foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Button("Show More") { embeddedRowLimit += Self.embeddedRowLimitStep }
                .font(.caption)
            if case .file(let basePath) = model.source {
                Button("Open Base") { openBase(basePath, model.selectedView?.name) }
                    .font(.caption)
            }
        }
        .buttonStyle(.borderless)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16).padding(.vertical, 8)
    }

    private func beginEditingSelectedView() {
        guard let definition = model.definition, let view = model.selectedView else { return }
        editedView = EditedView(definition: definition, target: BaseViewTarget(view))
    }

    /// The model's message for a failed save, moved into the open sheet so it is not also
    /// shown behind it.
    private func takeActionErrorMessage(otherwise fallbackMessage: String) -> String {
        let message = model.actionErrorMessage ?? fallbackMessage
        model.actionErrorMessage = nil
        return message
    }

    /// Embedded maps use the plugin's `mapHeight`, plus room for the toolbar.
    private func embeddedHeight(defaultHeight: CGFloat) -> CGFloat {
        guard let view = model.selectedView, view.type == .map else { return defaultHeight }
        return CGFloat(view.map.embeddedHeight) + 48
    }

    @ViewBuilder private var content: some View {
        VStack(spacing: 0) {
            BaseToolbar(model: model, isEmbedded: isEmbedded, openBase: openBase, editView: beginEditingSelectedView,
                        deleteView: { viewPendingDeletion = model.selectedView.map(BaseViewTarget.init) })
            Divider()
            banners
            viewContent
                .frame(maxWidth: .infinity, maxHeight: growsWithContent ? nil : .infinity)
            if growsWithContent, let result = model.result, result.displayedCount > embeddedRowLimit {
                Divider()
                rowLimitFooter(displayedCount: result.displayedCount)
            }
        }
        .background(.background)
    }

    @ViewBuilder private var banners: some View {
        let messages = bannerMessages
        if !messages.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(messages.enumerated()), id: \.offset) { _, message in
                    Label(message.text, systemImage: message.systemImage)
                        .font(.callout)
                        .foregroundStyle(message.isError ? Color.red : Color.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.orange.opacity(0.1))
            Divider()
        }
    }

    private struct BannerMessage {
        let text: String
        let systemImage: String
        let isError: Bool
    }

    private var bannerMessages: [BannerMessage] {
        var messages: [BannerMessage] = []
        if let actionErrorMessage = model.actionErrorMessage {
            messages.append(BannerMessage(text: actionErrorMessage, systemImage: "exclamationmark.circle", isError: true))
        }
        if !isIndexComplete {
            messages.append(BannerMessage(text: "The vault is still being indexed, so results may be incomplete.", systemImage: "hourglass", isError: false))
        }
        if model.isTruncated {
            messages.append(BannerMessage(text: "Only the first \(model.loadedRecordCount.formatted()) of \(model.candidateCount.formatted()) files that could match were checked. Add a folder, tag or property filter to narrow this base.",
                                          systemImage: "exclamationmark.triangle", isError: false))
        }
        for issue in model.definition?.issues ?? [] {
            messages.append(BannerMessage(text: issue, systemImage: "exclamationmark.triangle", isError: false))
        }
        for problem in model.result?.problems ?? [] {
            messages.append(BannerMessage(text: problem, systemImage: "exclamationmark.triangle", isError: true))
        }
        return messages
    }

    @ViewBuilder private var viewContent: some View {
        if let loadErrorMessage = model.loadErrorMessage {
            ContentUnavailableView {
                Label("Can't Show This Base", systemImage: "exclamationmark.triangle")
            } description: {
                Text(loadErrorMessage)
            } actions: {
                Button("Try Again") { Task { await model.reload() } }
            }
        } else if let view = model.selectedView, case .unsupported(let typeName) = view.type {
            ContentUnavailableView {
                Label("“\(typeName)” Views Aren't Supported", systemImage: "questionmark.square.dashed")
            } description: {
                Text("Graphite shows table, cards, list and map views. Choose another view from the menu above.")
            }
        } else if let result = model.result, result.view.id == model.selectedView?.id {
            if result.rows.isEmpty && result.view.type != .map {
                ContentUnavailableView {
                    Label("No Results", systemImage: result.view.type.systemImage)
                } description: {
                    Text(result.problems.isEmpty ? "No files match this view's filters." : "Fix the problem shown above to see results.")
                }
            } else {
                resultView(result)
            }
        } else if model.isLoading || model.definition == nil {
            ProgressView().controlSize(.large)
        }
    }

    @ViewBuilder private func resultView(_ result: BaseQueryResult) -> some View {
        let actions = viewActions
        switch result.view.type {
        case .table:
            BaseTableView(result: result, sortKeys: model.effectiveSort, actions: actions) { property, direction in
                Task {
                    if let direction { await model.setSort(on: property, direction: direction) } else { await model.toggleSort(on: property) }
                }
            }
        case .cards:
            BaseCardsView(result: result, actions: actions)
        case .list:
            BaseListView(result: result, actions: actions)
        case .map:
            BaseMapView(result: result, actions: actions)
        case .unsupported:
            EmptyView()
        }
    }

    private var viewActions: BaseViewActions {
        let model = model
        return BaseViewActions(
            openPath: open,
            openLink: { link in
                Task {
                    do {
                        if let path = try await model.resolve(link) { open(path) }
                        else { model.actionErrorMessage = "No single file matches “\(link.displayText)”." }
                    } catch {
                        model.actionErrorMessage = "Graphite couldn't follow “\(link.displayText)”. \(error.localizedDescription)"
                    }
                }
            },
            editRequest: { path, property, cell in
                let value = cell.value
                guard model.canEdit(property, of: path), BaseDocumentModel.canEditValue(value) else { return nil }
                return BaseEditRequest(path: path, property: property, displayName: model.definition?.displayName(for: property) ?? property.name,
                                       kind: model.editorKind(for: property, currentValue: value), currentValue: value)
            },
            beginEditing: { request in
                Task {
                    editedWrittenNode = await model.writtenPropertyNode(request.property, of: request.path)
                    editRequest = request
                }
            },
            toggleCheckbox: { request, shownValue in Task { await model.toggleCheckbox(request, shownValue: shownValue) } },
            requestedCheckboxValue: { request in model.requestedCheckboxValues[request.id] },
            thumbnails: thumbnails,
            vaultRoot: model.vaultRoot,
            contentVersion: contentVersion)
    }

    /// The view the view editor was opened on, with the definition it was read from.
    private struct EditedView: Identifiable {
        let definition: BaseDefinition
        let target: BaseViewTarget
        var id: BaseViewTarget { target }

        /// Where the edited view is in `definition.views`: where it was, or by its name after
        /// views were added or removed before it. Past the end when it was removed, which the
        /// sheet shows.
        func viewIndex(in definition: BaseDefinition) -> Int {
            definition.views.firstIndex(where: target.matches)
                ?? definition.views.firstIndex { view in view.name == target.name }
                ?? definition.views.endIndex
        }
    }
}

/// The row above the view: a view switcher (a menu, like Obsidian's), the result
/// count, and sorting.
struct BaseToolbar: View {
    @Bindable var model: BaseDocumentModel
    let isEmbedded: Bool
    let openBase: (VaultPath, String?) -> Void
    let editView: () -> Void
    let deleteView: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            if model.views.count > 1 {
                Menu {
                    ForEach(Array(model.views.enumerated()), id: \.element.id) { viewIndex, view in
                        Button {
                            Task { await model.selectView(viewIndex) }
                        } label: {
                            Label(view.name, systemImage: view.type.systemImage)
                        }
                    }
                } label: {
                    viewTitle(showsChevron: true)
                }
                .menuIndicator(.hidden)
                .fixedSize()
                .accessibilityLabel("View: \(model.selectedView?.name ?? "")")
            } else {
                viewTitle(showsChevron: false).foregroundStyle(.tint)
            }

            Text(countText).font(.subheadline).foregroundStyle(.secondary).monospacedDigit().lineLimit(1)
            if model.isLoading { ProgressView().controlSize(.small) }
            Spacer(minLength: 8)
            if model.sortOverride != nil {
                Button("Reset Sort", systemImage: "arrow.uturn.backward") { Task { await model.resetSort() } }
                    .labelStyle(.titleAndIcon)
                    .font(.subheadline)
                    .help("Return to the sort saved in the base")
            }
            if model.canEditDefinition { viewOptions }
            if isEmbedded, case .file(let basePath) = model.source {
                Button("Open Base", systemImage: "arrow.up.forward.square") { openBase(basePath, model.selectedView?.name) }
                    .labelStyle(.iconOnly)
                    .help("Open \(basePath.name)")
            }
            Button("Reload", systemImage: "arrow.clockwise") { Task { await model.reload() } }
                .labelStyle(.iconOnly)
                .disabled(model.isLoading)
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 16)
        .padding(.vertical, isEmbedded ? 8 : 10)
    }

    /// Obsidian's view menu: edit, create, duplicate and delete views, and keep a sort.
    private var viewOptions: some View {
        Menu {
            Button("Edit View…", systemImage: "slider.horizontal.3", action: editView)
            if model.sortOverride != nil {
                Button("Save Sort to View", systemImage: "arrow.up.arrow.down") { Task { await model.saveSortToView() } }
            }
            Menu("New View", systemImage: "plus") {
                ForEach([BaseViewType.table, .cards, .list, .map], id: \.rawValue) { type in
                    Button(type.defaultViewName, systemImage: type.systemImage) { Task { await model.addView(type: type) } }
                }
            }
            Button("Duplicate View", systemImage: "plus.square.on.square") { Task { await model.duplicateSelectedView() } }
            Button("Delete View…", systemImage: "trash", role: .destructive, action: deleteView)
                .disabled(model.views.count < 2)
        } label: {
            Label("View Options", systemImage: "slider.horizontal.3")
        }
        .labelStyle(.iconOnly)
        .menuIndicator(.hidden)
        .disabled(model.isLoading)
    }

    private func viewTitle(showsChevron: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: model.selectedView?.type.systemImage ?? "tablecells")
            Text(model.selectedView?.name ?? "Base").fontWeight(.semibold).lineLimit(1)
            if showsChevron { Image(systemName: "chevron.down").font(.caption2.weight(.bold)).foregroundStyle(.secondary) }
        }
    }

    private var countText: String {
        guard let result = model.result else { return "" }
        let matchingCount = result.matchingCount
        let noun = matchingCount == 1 ? "result" : "results"
        if result.displayedCount < matchingCount { return "\(result.displayedCount.formatted()) of \(matchingCount.formatted()) \(noun)" }
        return "\(matchingCount.formatted()) \(noun)"
    }
}

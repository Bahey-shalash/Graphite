import SwiftUI
import GraphiteCore

/// The settings of one view, as Obsidian's view, property, sort and filter menus edit
/// them. Saving writes only the changed keys back into the `.base` file.
struct BaseViewDraft: Equatable, Sendable {
    var name: String
    var type: BaseViewType
    var hasLimit: Bool
    var limit: Int
    var order: [BasePropertyIdentifier]
    var sort: [BaseSortKey]
    var groupProperty: BasePropertyIdentifier?
    var groupDirection: BaseSortDirection
    /// Nil when the view's filters use nested groups that only the file can express, or
    /// were not fully read: offering the readable part would drop the rest on saving.
    var filterExpressions: [String]?
    var imageProperty: BasePropertyIdentifier?
    var imageFit: BaseImageFit
    var cardSize: Double?
    var coordinatesProperty: BasePropertyIdentifier?
    var markerIconProperty: BasePropertyIdentifier?
    var markerColorProperty: BasePropertyIdentifier?
    var defaultZoom: Double?

    init(view: BaseView) {
        name = view.name
        type = view.type
        hasLimit = view.limit != nil
        limit = view.limit ?? 50
        order = view.order.isEmpty ? [.file("name")] : view.order
        sort = view.sort
        groupProperty = view.groupBy?.property
        groupDirection = view.groupBy?.direction ?? .ascending
        filterExpressions = view.hasUnreadableFilters ? nil : BaseFilter.flatExpressions(of: view.filters)
        imageProperty = view.cards.imageProperty
        imageFit = view.cards.imageFit
        // A `.base` file can hold `nan` or `.inf`, which the steppers cannot show and which
        // never compare equal, so they read as unset and are written only when changed.
        cardSize = view.cards.cardSize.flatMap { size in size.isFinite ? size : nil }
        coordinatesProperty = view.map.coordinatesProperty
        markerIconProperty = view.map.markerIconProperty
        markerColorProperty = view.map.markerColorProperty
        defaultZoom = view.map.defaultZoom.flatMap { zoom in zoom.isFinite ? zoom : nil }
    }

    /// Applies the fields that differ from `original`, leaving everything else as written.
    /// - Parameter viewPosition: The view's position in the file's `views` list
    ///   (`BaseView.id`), which can differ from its place in the view menu.
    func apply(to editor: inout BaseDefinitionEditor, original: BaseViewDraft, viewPosition: Int) throws {
        // Compared untrimmed, so a name written with spaces is left alone unless edited.
        if name != original.name { try editor.setName(name.trimmingCharacters(in: .whitespaces), forViewAt: viewPosition) }
        if type != original.type { try editor.setType(type, forViewAt: viewPosition) }
        if hasLimit != original.hasLimit || (hasLimit && limit != original.limit) { try editor.setLimit(hasLimit ? limit : nil, forViewAt: viewPosition) }
        if order != original.order { try editor.setOrder(order, forViewAt: viewPosition) }
        if sort != original.sort { try editor.setSort(sort, forViewAt: viewPosition) }
        if groupProperty != original.groupProperty || groupDirection != original.groupDirection {
            try editor.setGroupBy(groupProperty.map { property in BaseSortKey(property: property, direction: groupDirection) }, forViewAt: viewPosition)
        }
        if let filterExpressions, filterExpressions != original.filterExpressions { try editor.setFilterExpressions(filterExpressions, forViewAt: viewPosition) }
        if imageProperty != original.imageProperty { try editor.setOption("image", text: imageProperty?.rawValue, forViewAt: viewPosition) }
        if imageFit != original.imageFit { try editor.setOption("imageFit", text: imageFit.rawValue, forViewAt: viewPosition) }
        if cardSize != original.cardSize { try editor.setOption("cardSize", number: cardSize, forViewAt: viewPosition) }
        if coordinatesProperty != original.coordinatesProperty { try editor.setOption("coordinates", text: coordinatesProperty?.rawValue, forViewAt: viewPosition) }
        if markerIconProperty != original.markerIconProperty { try editor.setOption("markerIcon", text: markerIconProperty?.rawValue, forViewAt: viewPosition) }
        if markerColorProperty != original.markerColorProperty { try editor.setOption("markerColor", text: markerColorProperty?.rawValue, forViewAt: viewPosition) }
        if defaultZoom != original.defaultZoom { try editor.setOption("defaultZoom", number: defaultZoom, forViewAt: viewPosition) }
    }

    static let limitRange = 1...100_000
    /// Up to this many files the limit changes one at a time, and by tens above it.
    private static let limitSingleStepMaximum = 20

    /// The limit after pressing plus: 19 → 20, 20 → 30.
    static func increasedLimit(_ limit: Int) -> Int {
        min(limit + (limit < limitSingleStepMaximum ? 1 : 10), limitRange.upperBound)
    }

    /// The limit after pressing minus: 30 → 20, 25 → 20, 20 → 19, so every limit up to 20
    /// is reachable from above.
    static func decreasedLimit(_ limit: Int) -> Int {
        guard limit > limitSingleStepMaximum else { return max(limit - 1, limitRange.lowerBound) }
        return max(limit - 10, limitSingleStepMaximum)
    }

    // Rows are identified by position, and SwiftUI can still call a removed row's binding
    // while the list updates, so these accessors ignore a position past the end.

    func filterExpression(at position: Int) -> String {
        guard let filterExpressions, filterExpressions.indices.contains(position) else { return "" }
        return filterExpressions[position]
    }

    mutating func setFilterExpression(_ expression: String, at position: Int) {
        guard filterExpressions?.indices.contains(position) == true else { return }
        filterExpressions?[position] = expression
    }

    func sortDirection(at position: Int) -> BaseSortDirection {
        sort.indices.contains(position) ? sort[position].direction : .ascending
    }

    mutating func setSortDirection(_ direction: BaseSortDirection, at position: Int) {
        guard sort.indices.contains(position) else { return }
        sort[position].direction = direction
    }
}

/// The view editor's draft and the view it was made from. The base can be loaded again
/// while the sheet is open, after an edit in another app. Saving writes the fields that
/// differ from `original`, so a draft kept across such a change would revert it, or be
/// written over another view that moved into its place.
struct BaseViewEditing: Equatable {
    enum FileChange: Equatable {
        case viewChanged, viewRemoved
    }

    var draft: BaseViewDraft
    private(set) var original: BaseViewDraft
    /// The view's position in the file's `views` list (`BaseView.id`) when the draft was made.
    private(set) var viewPosition: Int
    /// Set when the file changed under an edited draft, which can then not be saved.
    private(set) var fileChange: FileChange?

    init(view: BaseView) {
        let viewDraft = BaseViewDraft(view: view)
        draft = viewDraft
        original = viewDraft
        viewPosition = view.id
    }

    /// Marked as removed when the definition has no view at `viewIndex`, which can
    /// happen when the base was loaded again just before the sheet opened.
    init(viewAt viewIndex: Int, in definition: BaseDefinition) {
        guard definition.views.indices.contains(viewIndex) else {
            self.init(view: BaseView(id: viewIndex, type: .table, name: ""))
            fileChange = .viewRemoved
            return
        }
        self.init(view: definition.views[viewIndex])
    }

    var hasChanges: Bool { draft != original }

    /// Follows the file after it was loaded again. A draft without changes starts over
    /// from the view as it is now; an edited one is kept but marked as out of date.
    mutating func fileLoaded(_ view: BaseView?) {
        guard let view else {
            fileChange = .viewRemoved
            return
        }
        if view.id == viewPosition && BaseViewDraft(view: view) == original {
            fileChange = nil
        } else if hasChanges {
            fileChange = .viewChanged
        } else {
            self = BaseViewEditing(view: view)
        }
    }

    /// Drops the changes and edits the view as the file has it now.
    mutating func discardChanges(reloading view: BaseView) {
        self = BaseViewEditing(view: view)
    }
}

struct BaseViewEditorSheet: View {
    private static let editableTypes: [BaseViewType] = [.table, .cards, .list, .map]
    private static let fileProperties: [BasePropertyIdentifier] = ["name", "basename", "path", "folder", "ext", "size", "ctime", "mtime", "tags", "links", "embeds", "backlinks"].map(BasePropertyIdentifier.file)

    let definition: BaseDefinition
    let viewIndex: Int
    let availablePropertyKeys: [String]
    /// Saves the draft into the view at the given position of the file's `views` list and
    /// returns nil, or returns why the base was not saved. The sheet stays open with the
    /// draft until the save succeeds.
    let saveEdit: (_ draft: BaseViewDraft, _ original: BaseViewDraft, _ viewPosition: Int) async -> String?
    @Environment(\.dismiss) private var dismiss
    @State private var editing: BaseViewEditing
    @State private var isSaving = false
    @State private var failureMessage: String?

    init(definition: BaseDefinition, viewIndex: Int, availablePropertyKeys: [String],
         saveEdit: @escaping (_ draft: BaseViewDraft, _ original: BaseViewDraft, _ viewPosition: Int) async -> String?) {
        self.definition = definition
        self.viewIndex = viewIndex
        self.availablePropertyKeys = availablePropertyKeys
        self.saveEdit = saveEdit
        _editing = State(initialValue: BaseViewEditing(viewAt: viewIndex, in: definition))
    }

    private var draft: BaseViewDraft {
        get { editing.draft }
        nonmutating set { editing.draft = newValue }
    }

    private var original: BaseViewDraft { editing.original }

    /// The edited view as the file has it now, or nil when it was removed.
    private var currentView: BaseView? {
        definition.views.indices.contains(viewIndex) ? definition.views[viewIndex] : nil
    }

    /// The part of the current view the draft depends on. Compared through the draft, so
    /// a value that never equals itself (`nan`) does not read as a change on every update.
    private struct CurrentViewState: Equatable {
        let viewPosition: Int
        let draft: BaseViewDraft
    }

    private var currentViewState: CurrentViewState? {
        currentView.map { view in CurrentViewState(viewPosition: view.id, draft: BaseViewDraft(view: view)) }
    }

    /// Every property a view can show: note properties seen in the results, those the
    /// base already names, file properties and formulas.
    private var choices: [BasePropertyIdentifier] {
        var properties: [BasePropertyIdentifier] = []
        func add(_ property: BasePropertyIdentifier) { if !properties.contains(property) { properties.append(property) } }
        availablePropertyKeys.map(BasePropertyIdentifier.note).forEach(add)
        definition.views.flatMap(\.order).forEach(add)
        definition.formulas.map { formula in BasePropertyIdentifier.formula(formula.name) }.forEach(add)
        Self.fileProperties.forEach(add)
        return properties
    }

    private var noteAndFormulaChoices: [BasePropertyIdentifier] {
        choices.filter { property in if case .file = property { return false } else { return true } }
    }

    private var filterProblems: [Int: String] {
        var problems: [Int: String] = [:]
        for (position, expression) in (draft.filterExpressions ?? []).enumerated() where !expression.trimmingCharacters(in: .whitespaces).isEmpty {
            do { _ = try BaseExpression.parse(expression) } catch { problems[position] = error.localizedDescription }
        }
        return problems
    }

    private var canSave: Bool {
        !draft.name.trimmingCharacters(in: .whitespaces).isEmpty && filterProblems.isEmpty && editing.hasChanges && editing.fileChange == nil && !isSaving
    }

    var body: some View {
        NavigationStack {
            Form {
                fileChangeSection
                Section("View") {
                    TextField("Name", text: $editing.draft.name)
                    Picker("Layout", selection: $editing.draft.type) {
                        ForEach(Self.editableTypes, id: \.rawValue) { type in Label(type.defaultViewName, systemImage: type.systemImage).tag(type) }
                        if case .unsupported(let name) = original.type { Text(name).tag(original.type) }
                    }
                    Toggle("Limit results", isOn: $editing.draft.hasLimit)
                    if draft.hasLimit {
                        Stepper {
                            Text("\(draft.limit) files")
                        } onIncrement: {
                            draft.limit = BaseViewDraft.increasedLimit(draft.limit)
                        } onDecrement: {
                            draft.limit = BaseViewDraft.decreasedLimit(draft.limit)
                        }
                    }
                }
                propertiesSection
                sortSection
                groupSection
                filtersSection
                if draft.type == .cards { cardsSection }
                if draft.type == .map { mapSection }
            }
            .formStyle(.grouped)
            .navigationTitle("Edit View")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: saveDraft)
                        .disabled(!canSave)
                }
            }
        }
        // An iOS sheet takes the width it is given, which can be narrower than this in Slide
        // Over or a narrow split, so only the Mac, where a sheet fits its content, sets one.
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 560)
        #endif
        .interactiveDismissDisabled(isSaving)
        // A save reloads the base, so the file is compared again once the save has ended:
        // after a failure, with whatever the reload found.
        .onChange(of: currentViewState) { if !isSaving { editing.fileLoaded(currentView) } }
        .onChange(of: isSaving) { _, isStillSaving in if !isStillSaving { editing.fileLoaded(currentView) } }
    }

    @ViewBuilder private var fileChangeSection: some View {
        if let fileChange = editing.fileChange {
            Section {
                switch fileChange {
                case .viewChanged:
                    Text("This view changed in another app. Saving would undo that change, so discard your changes to edit the view as it is now.")
                    if let currentView {
                        Button("Discard My Changes", role: .destructive) { editing.discardChanges(reloading: currentView) }
                    }
                case .viewRemoved:
                    Text("This view was removed in another app, so your changes cannot be saved.")
                }
            }
            .foregroundStyle(.red)
        }
        if let failureMessage {
            Section { Label(failureMessage, systemImage: "exclamationmark.triangle").foregroundStyle(.red) }
        }
    }

    private func saveDraft() {
        failureMessage = nil
        isSaving = true
        let savedEditing = editing
        Task {
            if let message = await saveEdit(savedEditing.draft, savedEditing.original, savedEditing.viewPosition) {
                failureMessage = message
                isSaving = false
            } else {
                dismiss()
            }
        }
    }

    private func displayName(_ property: BasePropertyIdentifier) -> String {
        let name = definition.displayName(for: property)
        return name.isEmpty ? property.rawValue : name
    }

    private func propertyMenu(title: String, systemImage: String, excluding excluded: [BasePropertyIdentifier], select: @escaping (BasePropertyIdentifier) -> Void) -> some View {
        Menu {
            ForEach(choices.filter { property in !excluded.contains(property) }, id: \.self) { property in
                Button(displayName(property) + (displayName(property) == property.rawValue ? "" : "  (\(property.rawValue))")) { select(property) }
            }
        } label: {
            Label(title, systemImage: systemImage)
        }
    }

    private var propertiesSection: some View {
        Section {
            ForEach(Array(draft.order.enumerated()), id: \.element) { position, property in
                HStack {
                    Text(displayName(property))
                    Spacer()
                    Button("Move Up", systemImage: "chevron.up") { draft.order.swapAt(position, position - 1) }
                        .disabled(position == 0)
                    Button("Move Down", systemImage: "chevron.down") { draft.order.swapAt(position, position + 1) }
                        .disabled(position == draft.order.count - 1)
                    Button("Hide", systemImage: "eye.slash", role: .destructive) { draft.order.remove(at: position) }
                        .disabled(draft.order.count == 1)
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
            }
            propertyMenu(title: "Show Property", systemImage: "plus", excluding: draft.order) { property in draft.order.append(property) }
        } header: {
            Text("Properties")
        } footer: {
            Text("Shown in this order: table columns, card fields, list items.")
        }
    }

    private var sortSection: some View {
        Section("Sort") {
            ForEach(Array(draft.sort.enumerated()), id: \.offset) { position, sortKey in
                HStack {
                    Text(displayName(sortKey.property))
                    Spacer()
                    Picker("Direction", selection: Binding(get: { draft.sortDirection(at: position) }, set: { direction in draft.setSortDirection(direction, at: position) })) {
                        Text("Ascending").tag(BaseSortDirection.ascending)
                        Text("Descending").tag(BaseSortDirection.descending)
                    }
                    .labelsHidden()
                    .fixedSize()
                    Button("Remove Sort", systemImage: "minus.circle", role: .destructive) { draft.sort.remove(at: position) }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                }
            }
            propertyMenu(title: "Add Sort", systemImage: "arrow.up.arrow.down", excluding: draft.sort.map(\.property)) { property in
                draft.sort.append(BaseSortKey(property: property, direction: .ascending))
            }
        }
    }

    private var groupSection: some View {
        Section("Group By") {
            Picker("Property", selection: $editing.draft.groupProperty) {
                Text("None").tag(BasePropertyIdentifier?.none)
                ForEach(choices, id: \.self) { property in Text(displayName(property)).tag(BasePropertyIdentifier?.some(property)) }
            }
            if draft.groupProperty != nil {
                Picker("Order", selection: $editing.draft.groupDirection) {
                    Text("Ascending").tag(BaseSortDirection.ascending)
                    Text("Descending").tag(BaseSortDirection.descending)
                }
            }
        }
    }

    @ViewBuilder private var filtersSection: some View {
        Section {
            if let expressions = draft.filterExpressions {
                ForEach(Array(expressions.enumerated()), id: \.offset) { position, _ in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            TextField("status == \"done\"", text: Binding(get: { draft.filterExpression(at: position) },
                                                                         set: { text in draft.setFilterExpression(text, at: position) }))
                                .font(.body.monospaced())
                                .autocorrectionDisabled()
                            #if canImport(UIKit)
                                .textInputAutocapitalization(.never)
                            #endif
                            Button("Remove Filter", systemImage: "minus.circle", role: .destructive) { draft.filterExpressions?.remove(at: position) }
                                .labelStyle(.iconOnly)
                                .buttonStyle(.borderless)
                        }
                        if let problem = filterProblems[position] { Text(problem).font(.caption).foregroundStyle(.red) }
                    }
                }
                Button("Add Filter", systemImage: "line.3.horizontal.decrease") { draft.filterExpressions?.append("") }
            } else {
                Text("This view's filters use groups that can only be edited in the base file.").foregroundStyle(.secondary)
            }
        } header: {
            Text("Filters for This View")
        } footer: {
            Text("A file is shown when all of these are true, together with the filters that apply to every view.")
        }
    }

    private var cardsSection: some View {
        Section("Cards") {
            Picker("Cover image", selection: $editing.draft.imageProperty) {
                Text("None").tag(BasePropertyIdentifier?.none)
                ForEach(noteAndFormulaChoices, id: \.self) { property in Text(displayName(property)).tag(BasePropertyIdentifier?.some(property)) }
            }
            Picker("Image fit", selection: $editing.draft.imageFit) {
                Text("Cover").tag(BaseImageFit.cover)
                Text("Contain").tag(BaseImageFit.contain)
            }
            Stepper(value: Binding(get: { draft.cardSize ?? 220 }, set: { size in draft.cardSize = size }), in: 120...600, step: 20) {
                Text("Card width \(Int(draft.cardSize ?? 220)) pt")
            }
        }
    }

    private var mapSection: some View {
        Section {
            Picker("Coordinates", selection: $editing.draft.coordinatesProperty) {
                Text("None").tag(BasePropertyIdentifier?.none)
                ForEach(noteAndFormulaChoices, id: \.self) { property in Text(displayName(property)).tag(BasePropertyIdentifier?.some(property)) }
            }
            Picker("Marker icon", selection: $editing.draft.markerIconProperty) {
                Text("None").tag(BasePropertyIdentifier?.none)
                ForEach(noteAndFormulaChoices, id: \.self) { property in Text(displayName(property)).tag(BasePropertyIdentifier?.some(property)) }
            }
            Picker("Marker color", selection: $editing.draft.markerColorProperty) {
                Text("None").tag(BasePropertyIdentifier?.none)
                ForEach(noteAndFormulaChoices, id: \.self) { property in Text(displayName(property)).tag(BasePropertyIdentifier?.some(property)) }
            }
            Toggle("Default zoom", isOn: Binding(get: { draft.defaultZoom != nil }, set: { isOn in draft.defaultZoom = isOn ? BaseMapOptions.defaultZoom : nil }))
            if let zoom = draft.defaultZoom {
                Stepper(value: Binding(get: { zoom }, set: { newZoom in draft.defaultZoom = newZoom }), in: 1...18, step: 1) {
                    Text("Zoom level \(Int(zoom))")
                }
            }
        } header: {
            Text("Map")
        } footer: {
            Text("Coordinates are a property holding “latitude, longitude” or a two-item list. Icons use Lucide names, colors CSS colors.")
        }
    }
}

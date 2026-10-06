import SwiftUI
import GraphiteCore

/// Obsidian's table view: columns from `order`, sortable headers whose trailing edge
/// resizes the column, group sections with their summaries, and a pinned header and
/// summary row. Wide tables scroll sideways.
struct BaseTableView: View {
    private static let fileNameColumnWidth: CGFloat = 240
    private static let defaultColumnWidth: CGFloat = 170
    private static let horizontalCellPadding: CGFloat = 10
    /// The strip at a header's trailing edge that resizes its column: wide enough for a
    /// finger, narrow enough to leave the header its tap.
    private static let resizeHandleWidth: CGFloat = 22
    /// How far one step of the accessibility adjustment moves a column's edge.
    private static let accessibilityResizeStep: CGFloat = 20

    let result: BaseQueryResult
    let sortKeys: [BaseSortKey]
    let actions: BaseViewActions
    let sort: (BasePropertyIdentifier, BaseSortDirection?) -> Void
    /// Saves a column's width into the view, or removes it with nil, and returns whether
    /// the base was saved. Nil when the base cannot be edited here, which leaves the
    /// columns without resize handles.
    let resizeColumn: ((BasePropertyIdentifier, Double?) async -> Bool)?
    @Environment(\.basesScrollVertically) private var scrollsVertically
    @Environment(\.baseRowLimit) private var rowLimit
    @Environment(\.layoutDirection) private var layoutDirection
    /// The column whose edge is being dragged, or whose new width is being saved.
    @State private var columnResize: BaseColumnResize?
    /// The width the dragged column had when the drag began; nil when no edge is dragged.
    /// Gesture state, so a drag the system cancels ends it too.
    @GestureState private var dragStartWidth: CGFloat?
    // Worked out once per result rather than in every cell of every row.
    private let configuredColumnWidths: [CGFloat]
    private let rowLayout: (height: CGFloat, lineLimit: Int)

    init(result: BaseQueryResult, sortKeys: [BaseSortKey], actions: BaseViewActions, sort: @escaping (BasePropertyIdentifier, BaseSortDirection?) -> Void,
         resizeColumn: ((BasePropertyIdentifier, Double?) async -> Bool)? = nil) {
        self.result = result
        self.sortKeys = sortKeys
        self.actions = actions
        self.sort = sort
        self.resizeColumn = resizeColumn
        configuredColumnWidths = Self.columnWidths(for: result)
        rowLayout = Self.rowLayout(forRowHeight: result.view.rowHeight)
    }

    /// Each column's width: the one the view's `columnSize` gives it, else its default.
    static func columnWidths(for result: BaseQueryResult) -> [CGFloat] {
        result.columns.map { column in
            result.view.columnWidths[column.property].map { width in CGFloat(width) }
                ?? (column.property == .file("name") ? fileNameColumnWidth : defaultColumnWidth)
        }
    }

    /// The configured widths, with the column being resized at the width under the finger.
    private var columnWidths: [CGFloat] {
        guard let columnResize, let position = result.columns.firstIndex(where: { column in column.property == columnResize.property }) else { return configuredColumnWidths }
        var widths = configuredColumnWidths
        widths[position] = columnResize.width
        return widths
    }

    private var isGrouped: Bool { result.view.groupBy != nil }

    /// Obsidian's row heights: short, medium, tall and extra tall, which it writes as
    /// `extra`.
    static func rowLayout(forRowHeight rowHeight: String?) -> (height: CGFloat, lineLimit: Int) {
        switch rowHeight?.lowercased() {
        case "medium": (58, 2)
        case "tall": (82, 3)
        case "extra", "extra-tall", "extratall", "extra tall", "extra_tall": (120, 5)
        default: (38, 1)
        }
    }

    var body: some View {
        let columnWidths = columnWidths
        let totalWidth = columnWidths.reduce(0, +)
        return ScrollView(scrollsVertically ? [.horizontal, .vertical] : .horizontal) {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders, .sectionFooters]) {
                Section {
                    ForEach(result.visibleGroups(rowLimit: rowLimit)) { visibleGroup in
                        if isGrouped {
                            groupHeader(visibleGroup.group, totalWidth: totalWidth)
                            if !visibleGroup.group.summaries.isEmpty { summaryRow(visibleGroup.group.summaries, isPinned: false, columnWidths: columnWidths) }
                        }
                        ForEach(visibleGroup.rows) { row in rowView(row, columnWidths: columnWidths) }
                    }
                } header: {
                    headerRow(columnWidths: columnWidths)
                } footer: {
                    if !isGrouped && !result.summaries.isEmpty { summaryRow(result.summaries, isPinned: true, columnWidths: columnWidths) }
                }
            }
            .frame(width: totalWidth, alignment: .leading)
            .padding(.bottom, 12)
        }
        // Rows must not show below the pinned summary row, in the safe area under it.
        .clipped()
        // The saved width has arrived with a new result, or the view changed under the drag.
        .onChange(of: result.view.columnWidths) { columnResize = nil }
        // A drag that was cancelled saves nothing, so the column returns to its width.
        .onChange(of: dragStartWidth == nil) { _, dragEnded in
            if dragEnded, columnResize?.isBeingSaved == false { columnResize = nil }
        }
    }

    private func headerRow(columnWidths: [CGFloat]) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(result.columns.enumerated()), id: \.element.id) { position, column in
                let sortPosition = sortKeys.firstIndex { sortKey in sortKey.property == column.property }
                Button {
                    sort(column.property, nil)
                } label: {
                    HStack(spacing: 4) {
                        Text(column.displayName.isEmpty ? " " : column.displayName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        if let sortPosition {
                            Image(systemName: sortKeys[sortPosition].direction == .ascending ? "arrow.up" : "arrow.down")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.tint)
                            if sortKeys.count > 1 {
                                // With several sort keys, the number shows each key's priority.
                                Text("\(sortPosition + 1)").font(.caption2.weight(.bold)).foregroundStyle(.tint)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, Self.horizontalCellPadding)
                    .frame(width: columnWidths[position], height: 36, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .overlay(alignment: .trailing) { Divider() }
                .contextMenu {
                    Button("Sort Ascending", systemImage: "arrow.up") { sort(column.property, .ascending) }
                    Button("Sort Descending", systemImage: "arrow.down") { sort(column.property, .descending) }
                    if resizeColumn != nil, result.view.columnWidths[column.property] != nil {
                        Button("Reset Column Width", systemImage: "arrow.left.and.right") { saveColumnWidth(nil, of: column.property, shownWidth: columnWidths[position]) }
                    }
                }
                .accessibilityLabel("Sort by \(column.displayName)")
                .overlay(alignment: .trailing) {
                    if resizeColumn != nil { resizeHandle(for: column, width: columnWidths[position]) }
                }
            }
        }
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }

    // MARK: Resizing columns

    /// The trailing edge of a header. Dragging it changes the column's width, which is
    /// saved into the view when the finger lifts, as in Obsidian.
    private func resizeHandle(for column: BaseColumn, width: CGFloat) -> some View {
        let isResizing = columnResize?.property == column.property
        return Color.clear
            .frame(width: Self.resizeHandleWidth)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .overlay(alignment: .trailing) {
                if isResizing { Rectangle().fill(.tint).frame(width: 2) }
            }
            #if os(macOS)
            .pointerStyle(.columnResize)
            #endif
            // No minimum distance: the touch is the handle's from the start, so it never
            // scrolls the table sideways instead.
            .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .global)
                .updating($dragStartWidth) { _, startWidth, _ in
                    if startWidth == nil { startWidth = width }
                }
                .onChanged { drag in
                    columnResize = BaseColumnResize(property: column.property, startWidth: dragStartWidth ?? width,
                                                    translation: drag.translation.width, layoutDirection: layoutDirection)
                }
                .onEnded { _ in
                    guard let columnResize, columnResize.property == column.property else { return }
                    // A touch that did not move the edge is not a resize.
                    guard columnResize.width != columnResize.startWidth else { self.columnResize = nil; return }
                    saveColumnWidth(Double(columnResize.width), of: column.property, shownWidth: columnResize.startWidth)
                })
            .accessibilityElement()
            .accessibilityLabel("Width of \(column.displayName)")
            .accessibilityValue("\(Int(width)) points")
            .accessibilityAdjustableAction { direction in
                let step = direction == .increment ? Self.accessibilityResizeStep : -Self.accessibilityResizeStep
                saveColumnWidth(Double(BaseColumnResize.clampedWidth(width + step)), of: column.property, shownWidth: width)
            }
    }

    /// Shows the column at its new width while the base is saved. A save that fails puts
    /// the column back; the base says why.
    private func saveColumnWidth(_ width: Double?, of property: BasePropertyIdentifier, shownWidth: CGFloat) {
        guard let resizeColumn else { return }
        if let width { columnResize = BaseColumnResize(property: property, startWidth: shownWidth, width: CGFloat(width), isBeingSaved: true) }
        Task {
            let isSaved = await resizeColumn(property, width)
            if !isSaved, columnResize?.property == property { columnResize = nil }
        }
    }

    private func rowView(_ row: BaseResultRow, columnWidths: [CGFloat]) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(result.columns.enumerated()), id: \.element.id) { position, column in
                let cell = row.cells[position]
                let editRequest = actions.editRequest(row.path, column.property, cell)
                Group {
                    if column.property == .file("name") {
                        Text(BaseValue.file(row.path).displayText)
                            .fontWeight(.medium)
                            .foregroundStyle(.tint)
                            .lineLimit(rowLayout.lineLimit)
                    } else {
                        BaseCellView(cell: cell, lineLimit: rowLayout.lineLimit, actions: actions, editRequest: editRequest, holdsTags: column.property.holdsTags)
                    }
                }
                .padding(.horizontal, Self.horizontalCellPadding)
                .frame(width: columnWidths[position], height: rowLayout.height, alignment: .leading)
                .clipped()
                .overlay(alignment: .trailing) { Divider() }
                .contextMenu {
                    Button("Open", systemImage: "arrow.up.forward.square") { actions.openPath(row.path) }
                    if let editRequest {
                        Button("Edit “\(column.displayName)”…", systemImage: "pencil") { actions.beginEditing(editRequest) }
                    }
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { actions.openPath(row.path) }
        .overlay(alignment: .bottom) { Divider() }
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: "Open") { actions.openPath(row.path) }
    }

    private func groupHeader(_ group: BaseResultGroup, totalWidth: CGFloat) -> some View {
        HStack(spacing: 8) {
            if let groupBy = result.view.groupBy {
                Text(result.columns.first { column in column.property == groupBy.property }?.displayName ?? groupBy.property.defaultDisplayName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            groupKeyView(group.key)
            Text("\(group.rows.count)").font(.caption).foregroundStyle(.tertiary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Self.horizontalCellPadding)
        .padding(.top, 14)
        .padding(.bottom, 6)
        .frame(width: totalWidth, alignment: .leading)
        .overlay(alignment: .bottom) { Divider() }
    }

    @ViewBuilder private func groupKeyView(_ key: BaseCellValue?) -> some View {
        switch key {
        case .value(let value) where !value.isEmptyValue:
            BaseValueView(value: value, lineLimit: 1, actions: actions).font(.headline)
        case .error(let message):
            BaseCellView(cell: .error(message), lineLimit: 1, actions: actions)
        default:
            Text("No value").font(.headline).foregroundStyle(.secondary)
        }
    }

    private func summaryRow(_ summaries: [BasePropertyIdentifier: BaseSummaryCell], isPinned: Bool, columnWidths: [CGFloat]) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(result.columns.enumerated()), id: \.element.id) { position, column in
                Group {
                    if let summary = summaries[column.property] {
                        HStack(spacing: 6) {
                            Text(summary.name).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            switch summary.value {
                            case .value(let value): Text(BaseValueView.summaryText(value)).font(.callout.weight(.medium)).monospacedDigit().lineLimit(1)
                            case .error(let message): BaseCellView(cell: .error(message), lineLimit: 1, actions: actions)
                            }
                        }
                    } else {
                        Color.clear
                    }
                }
                .padding(.horizontal, Self.horizontalCellPadding)
                .frame(width: columnWidths[position], height: 34, alignment: .leading)
            }
        }
        .background(isPinned ? AnyShapeStyle(.bar) : AnyShapeStyle(Color.secondary.opacity(0.05)))
        .overlay(alignment: .top) { Divider() }
    }
}

/// A table column's width while its edge is dragged, and until the dragged width is saved.
struct BaseColumnResize: Equatable {
    let property: BasePropertyIdentifier
    /// The column's width when the drag began.
    let startWidth: CGFloat
    /// The width under the finger: whole points within Obsidian's column limits.
    let width: CGFloat
    /// Whether the drag ended and the width is on its way into the `.base` file.
    let isBeingSaved: Bool

    init(property: BasePropertyIdentifier, startWidth: CGFloat, width: CGFloat, isBeingSaved: Bool = false) {
        self.property = property
        self.startWidth = startWidth
        self.width = Self.clampedWidth(width)
        self.isBeingSaved = isBeingSaved
    }

    /// - Parameter translation: How far the finger moved sideways since the drag began.
    ///   In a right-to-left layout a column's trailing edge is its left one, so moving
    ///   left widens it.
    init(property: BasePropertyIdentifier, startWidth: CGFloat, translation: CGFloat, layoutDirection: LayoutDirection) {
        self.init(property: property, startWidth: startWidth, width: startWidth + (layoutDirection == .rightToLeft ? -translation : translation))
    }

    static func clampedWidth(_ width: CGFloat) -> CGFloat {
        guard width.isFinite else { return CGFloat(BaseView.minimumColumnWidth) }
        return min(max(width.rounded(), CGFloat(BaseView.minimumColumnWidth)), CGFloat(BaseView.maximumColumnWidth))
    }
}

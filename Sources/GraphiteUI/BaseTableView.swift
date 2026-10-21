import SwiftUI
import GraphiteCore

/// How a table fits the width of its view. On a phone, or in a note there, the file name
/// column's default width is a little over half the view, so another column shows beside
/// it, and a first column no wider than that stays at the leading edge while the table
/// scrolls sideways, so every row keeps its name.
struct BaseTableLayout {
    static let fileNameColumnWidth: CGFloat = 240
    static let defaultColumnWidth: CGFloat = 170
    /// Narrower views get the narrower file name column.
    static let compactWidthThreshold: CGFloat = 600
    /// The part of a narrow view the file name column takes by default, and the most of
    /// any view a pinned first column may cover: a little over half, which fits most
    /// place and book names on a phone.
    static let firstColumnShareOfWidth: CGFloat = 0.55

    /// The file name column's width when the view's `columnSize` does not set it.
    /// - Parameter viewWidth: The table's visible width; nil before it is laid out.
    static func defaultFileNameColumnWidth(viewWidth: CGFloat?) -> CGFloat {
        guard let viewWidth, viewWidth.isFinite, viewWidth > 0, viewWidth < compactWidthThreshold else { return fileNameColumnWidth }
        return max(CGFloat(BaseView.minimumColumnWidth), min(fileNameColumnWidth, (viewWidth * firstColumnShareOfWidth).rounded(.down)))
    }

    /// Whether the first column stays put while the others scroll under it. A wider one
    /// would leave the rest of the table too little room.
    static func pinsFirstColumn(firstColumnWidth: CGFloat, viewWidth: CGFloat?) -> Bool {
        guard let viewWidth, viewWidth.isFinite, viewWidth > 0 else { return false }
        return firstColumnWidth <= viewWidth * firstColumnShareOfWidth
    }
}

/// Obsidian's table view: columns from `order`, sortable headers whose trailing edge
/// resizes the column, group sections with their summaries, and a pinned header and
/// summary row. Wide tables scroll sideways under a pinned first column (see `BaseTableLayout`).
struct BaseTableView: View {
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
    /// On paper the table does not scroll: it is drawn whole, its columns narrowed to the page.
    @Environment(\.readingIsPrinted) private var isPrinted
    /// The column whose edge is being dragged, or whose new width is being saved.
    @State private var columnResize: BaseColumnResize?
    /// The width the dragged column had when the drag began; nil when no edge is dragged.
    /// Gesture state, so a drag the system cancels ends it too.
    @GestureState private var dragStartWidth: CGFloat?
    /// The table's visible width, nil until it is first laid out.
    @State private var viewWidth: CGFloat?
    // Worked out once per result rather than in every cell of every row.
    private let rowLayout: (height: CGFloat, lineLimit: Int)

    init(result: BaseQueryResult, sortKeys: [BaseSortKey], actions: BaseViewActions, sort: @escaping (BasePropertyIdentifier, BaseSortDirection?) -> Void,
         resizeColumn: ((BasePropertyIdentifier, Double?) async -> Bool)? = nil) {
        self.result = result
        self.sortKeys = sortKeys
        self.actions = actions
        self.sort = sort
        self.resizeColumn = resizeColumn
        rowLayout = Self.rowLayout(forRowHeight: result.view.rowHeight)
    }

    /// Each column's width: the one the view's `columnSize` gives it, else its default.
    /// - Parameter viewWidth: The table's visible width, which narrows the file name column on a phone.
    static func columnWidths(for result: BaseQueryResult, viewWidth: CGFloat? = nil) -> [CGFloat] {
        let fileNameColumnWidth = BaseTableLayout.defaultFileNameColumnWidth(viewWidth: viewWidth)
        return result.columns.map { column in
            result.view.columnWidths[column.property].map { width in CGFloat(width) }
                ?? (column.property == .file("name") ? fileNameColumnWidth : BaseTableLayout.defaultColumnWidth)
        }
    }

    /// The configured widths, with the column being resized at the width under the finger;
    /// on paper, narrowed together to fit the page.
    private var columnWidths: [CGFloat] {
        let configuredColumnWidths = Self.columnWidths(for: result, viewWidth: viewWidth)
        if isPrinted, let viewWidth, case let totalWidth = configuredColumnWidths.reduce(0, +), totalWidth > viewWidth {
            return configuredColumnWidths.map { width in width * viewWidth / totalWidth }
        }
        guard let columnResize, let position = result.columns.firstIndex(where: { column in column.property == columnResize.property }) else { return configuredColumnWidths }
        var widths = configuredColumnWidths
        widths[position] = columnResize.width
        return widths
    }

    private var isGrouped: Bool { result.view.groupBy != nil }

    /// The table in its scroll view; on paper, which does not scroll, the table alone.
    @ViewBuilder private func scrolled(@ViewBuilder _ table: () -> some View) -> some View {
        if isPrinted {
            table().frame(maxWidth: .infinity, alignment: .leading)
        } else {
            ScrollView(scrollsVertically ? [.horizontal, .vertical] : .horizontal) { table() }
        }
    }

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
        let pinsFirstColumn = columnWidths.first.map { width in BaseTableLayout.pinsFirstColumn(firstColumnWidth: width, viewWidth: viewWidth) } ?? false
        return scrolled {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders, .sectionFooters]) {
                Section {
                    ForEach(result.visibleGroups(rowLimit: rowLimit)) { visibleGroup in
                        if isGrouped {
                            groupHeader(visibleGroup.group, totalWidth: totalWidth)
                            if !visibleGroup.group.summaries.isEmpty {
                                summaryRow(visibleGroup.group.summaries, isPinned: false, columnWidths: columnWidths, pinsFirstColumn: pinsFirstColumn)
                            }
                        }
                        ForEach(visibleGroup.rows) { row in rowView(row, columnWidths: columnWidths, pinsFirstColumn: pinsFirstColumn) }
                    }
                } header: {
                    headerRow(columnWidths: columnWidths, pinsFirstColumn: pinsFirstColumn)
                } footer: {
                    if !isGrouped && !result.summaries.isEmpty { summaryRow(result.summaries, isPinned: true, columnWidths: columnWidths, pinsFirstColumn: pinsFirstColumn) }
                }
            }
            .frame(width: totalWidth, alignment: .leading)
            .padding(.bottom, 12)
        }
        // Rows must not show below the pinned summary row, in the safe area under it.
        .clipped()
        .onGeometryChange(for: CGFloat.self) { geometry in geometry.size.width } action: { width in viewWidth = width }
        // The saved width has arrived with a new result, or the view changed under the drag.
        .onChange(of: result.view.columnWidths) { columnResize = nil }
        // A drag that was cancelled saves nothing, so the column returns to its width.
        .onChange(of: dragStartWidth == nil) { _, dragEnded in
            if dragEnded, columnResize?.isBeingSaved == false { columnResize = nil }
        }
    }

    private func headerRow(columnWidths: [CGFloat], pinsFirstColumn: Bool) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(result.columns.enumerated()), id: \.element.id) { position, column in
                Button {
                    sort(column.property, nil)
                } label: {
                    headerLabel(for: column)
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
                .pinnedToLeadingEdge(position == 0 && pinsFirstColumn, rowBackground: headerBackground)
            }
        }
        .background(headerBackground)
        .overlay(alignment: .bottom) { Divider() }
    }

    /// The bar's material on screen; on paper a plain tint, as a material makes the
    /// table's drawing a picture instead of text.
    private var headerBackground: AnyShapeStyle {
        isPrinted ? AnyShapeStyle(Color.secondary.opacity(0.1)) : AnyShapeStyle(.bar)
    }

    /// A column's name, with its sort direction and, among several sort keys, its priority.
    private func headerLabel(for column: BaseColumn) -> some View {
        let sortPosition = sortKeys.firstIndex { sortKey in sortKey.property == column.property }
        return HStack(spacing: 4) {
            Text(column.displayName.isEmpty ? " " : column.displayName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if let sortPosition {
                Image(systemName: sortKeys[sortPosition].direction == .ascending ? "arrow.up" : "arrow.down")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.tint)
                if sortKeys.count > 1 {
                    Text("\(sortPosition + 1)").font(.caption2.weight(.bold)).foregroundStyle(.tint)
                }
            }
            Spacer(minLength: 0)
        }
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

    private func rowView(_ row: BaseResultRow, columnWidths: [CGFloat], pinsFirstColumn: Bool) -> some View {
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
                .pinnedToLeadingEdge(position == 0 && pinsFirstColumn, rowBackground: nil)
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
            // The property's name from the base, as the cards and list views show it.
            if let groupDisplayName = result.groupDisplayName {
                Text(groupDisplayName).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
            groupKeyView(group.key)
            Text("\(group.fullRowCount)").font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, Self.horizontalCellPadding)
        // The heading stays in sight while the table scrolls sideways.
        .pinnedToLeadingEdge(true, rowBackground: nil, drawsBackground: false)
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

    private func summaryRow(_ summaries: [BasePropertyIdentifier: BaseSummaryCell], isPinned: Bool, columnWidths: [CGFloat], pinsFirstColumn: Bool) -> some View {
        let rowBackground = isPinned ? AnyShapeStyle(.bar) : AnyShapeStyle(Color.secondary.opacity(0.05))
        return HStack(spacing: 0) {
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
                .pinnedToLeadingEdge(position == 0 && pinsFirstColumn, rowBackground: rowBackground)
            }
        }
        .background(rowBackground)
        .overlay(alignment: .top) { Divider() }
    }
}

extension View {
    /// Keeps a cell of the table's first column at the scroll view's leading edge while the
    /// table scrolls sideways, drawn above the cells that pass under it. The offset is a
    /// visual effect, so scrolling moves it without laying out the table again.
    /// - Parameters:
    ///   - rowBackground: What the cell's row draws behind its cells; the pinned cell draws
    ///     it over the page colour, so the cells under it do not show through.
    ///   - drawsBackground: False for content that has nothing beside it to cover.
    fileprivate func pinnedToLeadingEdge(_ isPinned: Bool, rowBackground: AnyShapeStyle?, drawsBackground: Bool = true) -> some View {
        modifier(PinnedToLeadingEdge(isPinned: isPinned, rowBackground: rowBackground, drawsBackground: drawsBackground))
    }
}

private struct PinnedToLeadingEdge: ViewModifier {
    let isPinned: Bool
    let rowBackground: AnyShapeStyle?
    let drawsBackground: Bool
    /// Paper does not scroll, and a visual effect would make the table's drawing a picture
    /// instead of text. It never changes while the table is shown, so the cell keeps its identity.
    @Environment(\.readingIsPrinted) private var isPrinted

    func body(content: Content) -> some View {
        let showsBackground = isPinned && drawsBackground
        let backed = content
            .background(showsBackground ? rowBackground ?? AnyShapeStyle(Color.clear) : AnyShapeStyle(Color.clear))
            .background(showsBackground ? AnyShapeStyle(.background) : AnyShapeStyle(Color.clear))
        if isPrinted {
            backed
        } else {
            backed
                .visualEffect { content, geometry in
                    content.offset(x: isPinned ? max(0, -geometry.frame(in: .scrollView(axis: .horizontal)).minX) : 0)
                }
                .zIndex(isPinned ? 1 : 0)
        }
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

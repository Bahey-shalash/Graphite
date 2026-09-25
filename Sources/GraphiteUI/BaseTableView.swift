import SwiftUI
import GraphiteCore

/// Obsidian's table view: columns from `order`, sortable headers, group sections with
/// their summaries, and a pinned header and summary row. Wide tables scroll sideways.
struct BaseTableView: View {
    private static let fileNameColumnWidth: CGFloat = 240
    private static let defaultColumnWidth: CGFloat = 170
    private static let horizontalCellPadding: CGFloat = 10

    let result: BaseQueryResult
    let sortKeys: [BaseSortKey]
    let actions: BaseViewActions
    let sort: (BasePropertyIdentifier, BaseSortDirection?) -> Void
    @Environment(\.basesScrollVertically) private var scrollsVertically
    @Environment(\.baseRowLimit) private var rowLimit
    // Worked out once per result rather than in every cell of every row.
    private let columnWidths: [CGFloat]
    private let totalWidth: CGFloat
    private let rowLayout: (height: CGFloat, lineLimit: Int)

    init(result: BaseQueryResult, sortKeys: [BaseSortKey], actions: BaseViewActions, sort: @escaping (BasePropertyIdentifier, BaseSortDirection?) -> Void) {
        self.result = result
        self.sortKeys = sortKeys
        self.actions = actions
        self.sort = sort
        columnWidths = result.columns.map { column in
            result.view.columnWidths[column.property].map { width in CGFloat(width) }
                ?? (column.property == .file("name") ? Self.fileNameColumnWidth : Self.defaultColumnWidth)
        }
        totalWidth = columnWidths.reduce(0, +)
        rowLayout = Self.rowLayout(forRowHeight: result.view.rowHeight)
    }

    private var isGrouped: Bool { result.view.groupBy != nil }

    /// Obsidian's row heights: short, medium, tall and extra tall.
    private static func rowLayout(forRowHeight rowHeight: String?) -> (height: CGFloat, lineLimit: Int) {
        switch rowHeight?.lowercased() {
        case "medium": (58, 2)
        case "tall": (82, 3)
        case "extra-tall", "extratall", "extra tall", "extra_tall": (120, 5)
        default: (38, 1)
        }
    }

    var body: some View {
        ScrollView(scrollsVertically ? [.horizontal, .vertical] : .horizontal) {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders, .sectionFooters]) {
                Section {
                    ForEach(result.visibleGroups(rowLimit: rowLimit)) { visibleGroup in
                        if isGrouped {
                            groupHeader(visibleGroup.group)
                            if !visibleGroup.group.summaries.isEmpty { summaryRow(visibleGroup.group.summaries, isPinned: false) }
                        }
                        ForEach(visibleGroup.rows) { row in rowView(row) }
                    }
                } header: {
                    headerRow
                } footer: {
                    if !isGrouped && !result.summaries.isEmpty { summaryRow(result.summaries, isPinned: true) }
                }
            }
            .frame(width: totalWidth, alignment: .leading)
            .padding(.bottom, 12)
        }
        // Rows must not show below the pinned summary row, in the safe area under it.
        .clipped()
    }

    private var headerRow: some View {
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
                }
                .accessibilityLabel("Sort by \(column.displayName)")
            }
        }
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }

    private func rowView(_ row: BaseResultRow) -> some View {
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

    private func groupHeader(_ group: BaseResultGroup) -> some View {
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

    private func summaryRow(_ summaries: [BasePropertyIdentifier: BaseSummaryCell], isPinned: Bool) -> some View {
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

import SwiftUI
import GraphiteCore

/// Moving cards between a board's columns, provided by the base's container.
struct BaseKanbanMoves {
    /// Whether the card of this file can be moved: the board groups by a note property,
    /// and the file is a Markdown note the base may write.
    let canMove: (VaultPath) -> Bool
    /// Writes the column's value into the note's grouped property.
    let move: (VaultPath, BaseCellValue) -> Void
}

/// Obsidian's Kanban layout: one column for each value of the view's `groupBy` property,
/// with a card for each file. Dragging a card to another column, or choosing the column
/// from the card's Move To menu, writes the column's value into the note's grouped
/// property, as Obsidian does. Only a note property can be written that way, so a board
/// grouped by a formula or a file property shows its cards without moving them.
struct BaseKanbanView: View {
    private static let columnWidth: CGFloat = 272
    /// Obsidian's title for the column of files without a value.
    static let emptyColumnTitle = "None"

    let result: BaseQueryResult
    let actions: BaseViewActions
    let moves: BaseKanbanMoves
    @Environment(\.basesScrollVertically) private var scrollsVertically
    @Environment(\.baseRowLimit) private var rowLimit
    @State private var targetedGroupID: Int?

    var body: some View {
        if result.view.groupBy == nil {
            ContentUnavailableView {
                Label("Choose the Board's Columns", systemImage: BaseViewType.kanban.systemImage)
            } description: {
                Text("A board has a column for each value of one property. Choose it under Group By in Edit View.")
            }
        } else {
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 12) {
                    ForEach(result.visibleGroups(rowLimit: rowLimit)) { visibleGroup in column(visibleGroup) }
                }
                .padding(16)
            }
        }
    }

    // MARK: Columns

    private func column(_ visibleGroup: BaseVisibleGroup) -> some View {
        let group = visibleGroup.group
        let isTargeted = targetedGroupID == group.id
        return VStack(alignment: .leading, spacing: 10) {
            columnHeader(group)
            if scrollsVertically {
                ScrollView(.vertical) { cardStack(visibleGroup) }
            } else {
                cardStack(visibleGroup)
            }
        }
        .padding(10)
        .frame(width: Self.columnWidth, alignment: .topLeading)
        .frame(maxHeight: scrollsVertically ? .infinity : nil, alignment: .top)
        .background(Color.secondary.opacity(isTargeted ? 0.2 : 0.08), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            if isTargeted { RoundedRectangle(cornerRadius: 12).strokeBorder(.tint, lineWidth: 2) }
        }
        .dropDestination(for: String.self) { droppedPaths, _ in
            drop(droppedPaths, on: group)
        } isTargeted: { isTargeted in
            if isTargeted { targetedGroupID = group.id } else if targetedGroupID == group.id { targetedGroupID = nil }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(Self.title(of: group)), \(group.rows.count) \(group.rows.count == 1 ? "card" : "cards")")
    }

    private func columnHeader(_ group: BaseResultGroup) -> some View {
        HStack(spacing: 8) {
            switch group.key {
            case .value(let value)? where !value.isEmptyValue:
                BaseValueView(value: value, lineLimit: 1, actions: actions).font(.headline)
            case .error(let message)?:
                BaseCellView(cell: .error(message), lineLimit: 1, actions: actions)
            default:
                Text(Self.emptyColumnTitle).font(.headline).foregroundStyle(.secondary)
            }
            Text("\(group.rows.count)").font(.caption).foregroundStyle(.tertiary).monospacedDigit()
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
    }

    private func cardStack(_ visibleGroup: BaseVisibleGroup) -> some View {
        LazyVStack(alignment: .leading, spacing: 8) {
            ForEach(visibleGroup.rows) { row in card(row, in: visibleGroup.group) }
        }
    }

    /// The title a column shows, and its name in a card's Move To menu.
    static func title(of group: BaseResultGroup) -> String {
        switch group.key {
        case .value(let value)? where !value.isEmptyValue: BaseValueView.summaryText(value)
        case .error(let message)?: message
        default: emptyColumnTitle
        }
    }

    // MARK: Cards

    private func card(_ row: BaseResultRow, in group: BaseResultGroup) -> some View {
        let isMovable = moves.canMove(row.path)
        let otherGroups = result.groups.filter { otherGroup in otherGroup.id != group.id && otherGroup.key.flatMap(BaseDocumentModel.propertyValue(forGroupKey:)) != nil }
        return VStack(alignment: .leading, spacing: 8) {
            cardTitle(row)
            ForEach(Array(result.columns.enumerated().dropFirst()), id: \.element.id) { position, column in
                if !(row.cells[position].value?.isEmptyValue ?? false) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(column.displayName).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        BaseCellView(cell: row.cells[position], lineLimit: 3, actions: actions, editRequest: actions.editRequest(row.path, column.property, row.cells[position]),
                                     holdsTags: column.property.holdsTags)
                            .font(.callout)
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 10))
        .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(Color.secondary.opacity(0.2)) }
        .shadow(color: .black.opacity(0.06), radius: 2, y: 1)
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .onTapGesture { actions.openPath(row.path) }
        .modifier(DraggableCard(path: row.path, isDraggable: isMovable))
        .contextMenu {
            Button("Open", systemImage: "arrow.up.forward.square") { actions.openPath(row.path) }
            if isMovable, !otherGroups.isEmpty {
                Menu("Move To", systemImage: "arrow.right.square") {
                    ForEach(otherGroups) { otherGroup in
                        Button(Self.title(of: otherGroup)) { if let key = otherGroup.key { moves.move(row.path, key) } }
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: "Open") { actions.openPath(row.path) }
        .accessibilityActions {
            if isMovable {
                ForEach(otherGroups) { otherGroup in
                    Button("Move to \(Self.title(of: otherGroup))") { if let key = otherGroup.key { moves.move(row.path, key) } }
                }
            }
        }
    }

    /// The first property of the view, as Obsidian titles a card; the file's name when it
    /// is that property or the view lists none.
    @ViewBuilder private func cardTitle(_ row: BaseResultRow) -> some View {
        if let firstColumn = result.columns.first, firstColumn.property != .file("name") {
            BaseCellView(cell: row.cells[0], lineLimit: 2, actions: actions, holdsTags: firstColumn.property.holdsTags)
                .font(.headline)
        } else {
            Text(BaseValue.file(row.path).displayText)
                .font(.headline)
                .lineLimit(2)
                .accessibilityAddTraits(.isButton)
        }
    }

    /// Moves the cards of this board dropped on a column. Anything else dropped there, such
    /// as text from another app, is not a card and moves nothing.
    private func drop(_ droppedPaths: [String], on group: BaseResultGroup) -> Bool {
        guard let groupKey = group.key, BaseDocumentModel.propertyValue(forGroupKey: groupKey) != nil else { return false }
        var isMoved = false
        for droppedPath in droppedPaths {
            guard let row = result.rows.first(where: { row in row.path.rawValue == droppedPath }), !group.rows.contains(where: { groupRow in groupRow.path == row.path }),
                  moves.canMove(row.path) else { continue }
            moves.move(row.path, groupKey)
            isMoved = true
        }
        return isMoved
    }
}

/// Lets a card be dragged to another column when it can be moved.
private struct DraggableCard: ViewModifier {
    let path: VaultPath
    let isDraggable: Bool

    func body(content: Content) -> some View {
        if isDraggable {
            content.draggable(path.rawValue) {
                Label(BaseValue.file(path).displayText, systemImage: "doc.text")
                    .padding(8)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            }
        } else {
            content
        }
    }
}

import SwiftUI
import GraphiteCore

/// Obsidian's cards view: a grid of cards with an optional cover image.
struct BaseCardsView: View {
    private static let defaultCardWidth: CGFloat = 220

    let result: BaseQueryResult
    let actions: BaseViewActions
    @Environment(\.basesScrollVertically) private var scrollsVertically
    @Environment(\.baseRowLimit) private var rowLimit

    private var options: BaseCardsOptions { result.view.cards }
    private var cardWidth: CGFloat { options.cardSize.map { size in CGFloat(size) } ?? Self.defaultCardWidth }

    var body: some View {
        if scrollsVertically { ScrollView { cards } } else { cards }
    }

    private var cards: some View {
        LazyVStack(alignment: .leading, spacing: 18) {
            ForEach(result.visibleGroups(rowLimit: rowLimit)) { visibleGroup in
                if result.view.groupBy != nil { BaseGroupHeader(group: visibleGroup.group, result: result, actions: actions) }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: cardWidth, maximum: cardWidth * 1.5), spacing: 16, alignment: .top)], alignment: .leading, spacing: 16) {
                    ForEach(visibleGroup.rows) { row in card(for: row) }
                }
            }
        }
        .padding(16)
    }

    private func card(for row: BaseResultRow) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if options.imageProperty != nil {
                Color.clear
                    .aspectRatio(1 / CGFloat(options.imageAspectRatio ?? 1), contentMode: .fit)
                    .overlay {
                        if let reference = row.presentation.coverImage {
                            BaseCoverImageView(reference: reference, fit: options.imageFit, thumbnails: actions.thumbnails, vaultRoot: actions.vaultRoot,
                                               contentVersion: actions.contentVersion)
                        } else {
                            Rectangle().fill(Color.secondary.opacity(0.08))
                        }
                    }
                    .clipped()
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(BaseValue.file(row.path).displayText)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { actions.openPath(row.path) }
                ForEach(Array(result.columns.enumerated()), id: \.element.id) { position, column in
                    if column.property != .file("name"), column.property != options.imageProperty, !(row.cells[position].value?.isEmptyValue ?? false) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(column.displayName).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                            BaseCellView(cell: row.cells[position], lineLimit: 3, actions: actions, editRequest: actions.editRequest(row.path, column.property, row.cells[position]),
                                         holdsTags: column.property.holdsTags)
                                .font(.callout)
                        }
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(Color.secondary.opacity(0.2)) }
        .shadow(color: .black.opacity(0.06), radius: 3, y: 1)
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onTapGesture { actions.openPath(row.path) }
        .contextMenu { Button("Open", systemImage: "arrow.up.forward.square") { actions.openPath(row.path) } }
        // The card's checkboxes and links stay separate elements, so VoiceOver and Switch
        // Control can reach them; the title opens the note, as a tap on the card does.
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: "Open") { actions.openPath(row.path) }
    }
}

/// Obsidian's list view: one item per file, with its other properties inline or indented.
struct BaseListView: View {
    let result: BaseQueryResult
    let actions: BaseViewActions

    @Environment(\.basesScrollVertically) private var scrollsVertically
    @Environment(\.baseRowLimit) private var rowLimit

    private var options: BaseListOptions { result.view.list }

    var body: some View {
        if scrollsVertically { ScrollView { items } } else { items }
    }

    private var items: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(result.visibleGroups(rowLimit: rowLimit)) { visibleGroup in
                if result.view.groupBy != nil { BaseGroupHeader(group: visibleGroup.group, result: result, actions: actions).padding(.top, 8) }
                ForEach(Array(visibleGroup.rows.enumerated()), id: \.element.id) { position, row in item(row, number: position + 1) }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .frame(maxWidth: 900, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func item(_ row: BaseResultRow, number: Int) -> some View {
        let primaryPosition = result.columns.indices.first
        let otherPositions = result.columns.indices.dropFirst().filter { position in !(row.cells[position].value?.isEmptyValue ?? false) }
        return HStack(alignment: .firstTextBaseline, spacing: 10) {
            switch options.marker {
            case .bullets: Text("•").foregroundStyle(.secondary)
            case .numbers: Text("\(number).").monospacedDigit().foregroundStyle(.secondary)
            case .none: EmptyView()
            }
            VStack(alignment: .leading, spacing: 4) {
                if options.indentsProperties {
                    primary(row, position: primaryPosition)
                    ForEach(otherPositions, id: \.self) { position in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(result.columns[position].displayName + ":").font(.callout).foregroundStyle(.secondary)
                            BaseCellView(cell: row.cells[position], lineLimit: 2, actions: actions,
                                         editRequest: actions.editRequest(row.path, result.columns[position].property, row.cells[position]),
                                         holdsTags: result.columns[position].property.holdsTags)
                        }
                        .padding(.leading, 12)
                    }
                } else {
                    // The separator follows each value, as Obsidian writes "Dune, Frank Herbert".
                    HStack(alignment: .firstTextBaseline, spacing: 0) {
                        primary(row, position: primaryPosition)
                        ForEach(otherPositions, id: \.self) { position in
                            Text(options.separator).foregroundStyle(.tertiary)
                            BaseCellView(cell: row.cells[position], lineLimit: 1, actions: actions,
                                         editRequest: actions.editRequest(row.path, result.columns[position].property, row.cells[position]),
                                         holdsTags: result.columns[position].property.holdsTags)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture { actions.openPath(row.path) }
        .contextMenu { Button("Open", systemImage: "arrow.up.forward.square") { actions.openPath(row.path) } }
    }

    @ViewBuilder private func primary(_ row: BaseResultRow, position: Int?) -> some View {
        if let position, result.columns[position].property != .file("name") {
            BaseCellView(cell: row.cells[position], lineLimit: 2, actions: actions, holdsTags: result.columns[position].property.holdsTags)
        } else {
            Text(BaseValue.file(row.path).displayText).fontWeight(.medium).foregroundStyle(.tint)
        }
    }
}

/// The heading above one group in cards and list views.
struct BaseGroupHeader: View {
    let group: BaseResultGroup
    let result: BaseQueryResult
    let actions: BaseViewActions

    var body: some View {
        HStack(spacing: 8) {
            switch group.key {
            case .value(let value) where !value.isEmptyValue:
                BaseValueView(value: value, lineLimit: 1, actions: actions).font(.headline)
            case .error(let message):
                BaseCellView(cell: .error(message), lineLimit: 1, actions: actions)
            default:
                Text("No value").font(.headline).foregroundStyle(.secondary)
            }
            Text("\(group.rows.count)").font(.caption).foregroundStyle(.tertiary)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }
}

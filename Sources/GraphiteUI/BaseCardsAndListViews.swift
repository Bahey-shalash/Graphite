import SwiftUI
import GraphiteCore

/// How a cards view fits its width. Obsidian's card size is the width of one card; a width
/// too narrow for two such cards (a phone, or a base inside a note there) shows two smaller
/// columns instead of one stretched card, with tighter margins.
struct BaseCardGridMetrics: Equatable {
    /// The narrowest card that still shows its cover and a two-line title.
    static let minimumCardWidth: CGFloat = 140
    /// Narrower views get the compact margins, gaps and type.
    static let compactWidthThreshold: CGFloat = 600
    /// Smaller card sizes are raised to this, which keeps the column count finite.
    private static let smallestPreferredCardWidth: CGFloat = 40

    let columnCount: Int
    let isCompact: Bool
    /// The gap between cards, across and down.
    let spacing: CGFloat
    /// The margin around the grid.
    let padding: CGFloat

    /// - Parameters:
    ///   - availableWidth: The view's whole width, margins included.
    ///   - preferredCardWidth: The view's card size.
    ///   - isPrinted: On paper the count is rounded to the nearest, cards a little narrower
    ///     than their size (never under `minimumCardWidth`) rather than a few stretched ones,
    ///     so a page holds more of them.
    init(availableWidth: CGFloat, preferredCardWidth: CGFloat, isPrinted: Bool = false) {
        isCompact = availableWidth < Self.compactWidthThreshold
        spacing = isCompact ? 12 : 16
        padding = isCompact ? 12 : 16
        let contentWidth = availableWidth.isFinite ? availableWidth - 2 * padding : 0
        let cardWidth = preferredCardWidth.isFinite ? max(preferredCardWidth, Self.smallestPreferredCardWidth) : Self.smallestPreferredCardWidth
        let exactCount = (contentWidth + spacing) / (cardWidth + spacing)
        let widestCount = max(1, Int(((contentWidth + spacing) / (Self.minimumCardWidth + spacing)).rounded(.down)))
        let fittingCount = isPrinted ? min(max(1, Int(exactCount.rounded())), widestCount)
                                     : max(1, Int(exactCount.rounded(.down)))
        columnCount = fittingCount < 2 && contentWidth >= 2 * Self.minimumCardWidth + spacing ? 2 : fittingCount
    }
}

/// Obsidian's cards view: a grid of cards with an optional cover image.
struct BaseCardsView: View {
    static let defaultCardWidth: CGFloat = 220

    let result: BaseQueryResult
    let actions: BaseViewActions
    @Environment(\.basesScrollVertically) private var scrollsVertically
    @Environment(\.baseRowLimit) private var rowLimit
    @Environment(\.readingIsPrinted) private var isPrinted
    /// The view's width, nil until it is first laid out.
    @State private var availableWidth: CGFloat?

    private var options: BaseCardsOptions { result.view.cards }
    private var cardWidth: CGFloat { options.cardSize.map { size in CGFloat(size) } ?? Self.defaultCardWidth }
    private var metrics: BaseCardGridMetrics? {
        availableWidth.map { width in BaseCardGridMetrics(availableWidth: width, preferredCardWidth: cardWidth, isPrinted: isPrinted) }
    }

    var body: some View {
        if scrollsVertically { ScrollView { cards } } else { cards }
    }

    private var cards: some View {
        let metrics = metrics
        return LazyVStack(alignment: .leading, spacing: metrics?.isCompact == true ? 14 : 18) {
            ForEach(result.visibleGroups(rowLimit: rowLimit)) { visibleGroup in
                if result.view.groupBy != nil { BaseGroupHeader(group: visibleGroup.group, result: result, actions: actions) }
                LazyVGrid(columns: gridColumns(metrics), alignment: .leading, spacing: metrics?.spacing ?? 16) {
                    ForEach(visibleGroup.rows) { row in card(for: row, isCompact: metrics?.isCompact ?? false) }
                }
            }
        }
        .padding(metrics?.padding ?? 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onGeometryChange(for: CGFloat.self) { geometry in geometry.size.width } action: { width in availableWidth = width }
    }

    /// Until the width is known, Obsidian's grid of cards at least the card size wide.
    private func gridColumns(_ metrics: BaseCardGridMetrics?) -> [GridItem] {
        guard let metrics else { return [GridItem(.adaptive(minimum: cardWidth, maximum: cardWidth * 1.5), spacing: 16, alignment: .top)] }
        return Array(repeating: GridItem(.flexible(), spacing: metrics.spacing, alignment: .top), count: metrics.columnCount)
    }

    /// The cover at the view's aspect ratio; a card without one keeps the space, marked
    /// as an empty photo, so the cards of a row line up.
    private func cover(for row: BaseResultRow) -> some View {
        Color.clear
            .aspectRatio(1 / CGFloat(options.imageAspectRatio ?? 1), contentMode: .fit)
            .overlay {
                if let reference = row.presentation.coverImage {
                    BaseCoverImageView(reference: reference, fit: options.imageFit, thumbnails: actions.thumbnails, vaultRoot: actions.vaultRoot,
                                       contentVersion: actions.contentVersion)
                } else {
                    ZStack {
                        Rectangle().fill(Color.secondary.opacity(0.08))
                        Image(systemName: "photo").font(.title2).foregroundStyle(.tertiary).accessibilityHidden(true)
                    }
                }
            }
            .clipped()
    }

    private func card(for row: BaseResultRow, isCompact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if options.imageProperty != nil { cover(for: row) }
            VStack(alignment: .leading, spacing: isCompact ? 6 : 8) {
                Text(BaseValue.file(row.path).displayText)
                    .font(isCompact ? .subheadline.weight(.semibold) : .headline)
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
                                .font(isCompact ? .subheadline : .callout)
                        }
                    }
                }
            }
            .padding(isCompact ? 10 : 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            // A grid row lays its cards out at a height measured before their text wraps;
            // without this the text of the taller card in a row is cut to fit it.
            .fixedSize(horizontal: false, vertical: true)
        }
        // Cards in one row share its height, so their edges line up.
        .frame(maxHeight: .infinity, alignment: .top)
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

/// How a list view's separator joins the values written inline. It follows each value but
/// the last, as Obsidian writes "Dune, Frank Herbert". A line may break between values; a
/// separator ending in a space keeps its other characters with the value before it, and
/// its space becomes the gap where the line breaks, so no line starts with ", ".
struct BaseListInlineSeparator {
    /// What follows a value on its line.
    let attachedText: String
    /// Whether a space follows the attached text.
    let isFollowedBySpace: Bool

    init(separator: String) {
        let attachedText = separator.replacing(/\s+$/, with: "")
        self.attachedText = attachedText
        isFollowedBySpace = attachedText.count < separator.count
    }
}

/// Obsidian's list view: one item per file, with its other properties inline or indented.
struct BaseListView: View {
    /// The gap a separator's trailing space leaves between inline values.
    private static let inlineSpaceWidth: CGFloat = 4
    /// The gap between lines of inline values that wrap.
    private static let inlineLineSpacing: CGFloat = 2

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
                ForEach(Array(visibleGroup.rows.enumerated()), id: \.element.id) { position, row in
                    item(row, number: visibleGroup.group.leftOutRows.before + position + 1)
                }
            }
        }
        // The toolbar's margin, so the list lines up under the view's name.
        .padding(.horizontal, 16)
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
                    inlineValues(row, primaryPosition: primaryPosition, otherPositions: otherPositions)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture { actions.openPath(row.path) }
        .contextMenu { Button("Open", systemImage: "arrow.up.forward.square") { actions.openPath(row.path) } }
    }

    /// The file and its values on one line, wrapping onto more lines between values when a
    /// narrow view (a phone) cannot fit them, instead of cutting each value short.
    private func inlineValues(_ row: BaseResultRow, primaryPosition: Int?, otherPositions: [Int]) -> some View {
        let separator = BaseListInlineSeparator(separator: options.separator)
        return WrappingRowLayout(horizontalSpacing: separator.isFollowedBySpace ? Self.inlineSpaceWidth : 0, verticalSpacing: Self.inlineLineSpacing) {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                primary(row, position: primaryPosition)
                if !otherPositions.isEmpty { Text(separator.attachedText).foregroundStyle(.tertiary) }
            }
            ForEach(otherPositions, id: \.self) { position in
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    BaseCellView(cell: row.cells[position], lineLimit: 1, actions: actions,
                                 editRequest: actions.editRequest(row.path, result.columns[position].property, row.cells[position]),
                                 holdsTags: result.columns[position].property.holdsTags)
                        .foregroundStyle(.secondary)
                    if position != otherPositions.last { Text(separator.attachedText).foregroundStyle(.tertiary) }
                }
            }
        }
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
            // Obsidian names the property before each group's value: "cuisine French".
            if let groupDisplayName = result.groupDisplayName {
                Text(groupDisplayName).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            }
            switch group.key {
            case .value(let value) where !value.isEmptyValue:
                BaseValueView(value: value, lineLimit: 1, actions: actions).font(.headline)
            case .error(let message):
                BaseCellView(cell: .error(message), lineLimit: 1, actions: actions)
            default:
                Text("No value").font(.headline).foregroundStyle(.secondary)
            }
            Text("\(group.fullRowCount)").font(.caption).foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }
}

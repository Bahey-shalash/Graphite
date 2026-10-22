import CoreGraphics

/// An entity's box measured: its size, and its name and attribute rows placed from the box's top left corner.
struct EntityRelationshipMeasuredBox {
    let size: CGSize
    let name: DiagramTextBlock
    let rows: [EntityRelationshipLayoutRow]
}

/// Sizes an entity's box around its text as Pele does: the name 18 points from each side and 12 above and below it,
/// the box at least 96 points wide; with attributes, the name in a header 9 points above and below it, then a row
/// for each attribute (`EntityRelationshipAttributeTable`), 12 points in from the box's sides.
enum EntityRelationshipBoxMeasurement {
    static let minimumWidth: CGFloat = 96
    static let nameHorizontalPadding: CGFloat = 18
    static let nameVerticalPadding: CGFloat = 12
    static let headerVerticalPadding: CGFloat = 9
    static let cellHorizontalPadding: CGFloat = 12
    /// The widest a name's line is before it wraps.
    static let nameWrappingWidth: CGFloat = 240
    /// The widest a comment's line is before it wraps; types, names and keys never wrap.
    static let commentWrappingWidth: CGFloat = 260

    /// - Parameter minimumSize: The least size the entity's loops need; its height counts for a box without
    ///   attributes only, which loops out of its right side.
    static func box<Measurer>(for entity: EntityRelationshipEntity, measurers: EntityRelationshipTextMeasurers<Measurer>,
                              minimumSize: CGSize) -> EntityRelationshipMeasuredBox {
        var name = DiagramTextBlock(label: entity.label, measurer: measurers.name, maximumWidth: nameWrappingWidth)
        let nameHeight = max(name.size.height, measurers.name.lineHeight)
        let narrowest = max(minimumWidth, minimumSize.width, name.size.width + 2 * nameHorizontalPadding)
        guard !entity.attributes.isEmpty else {
            let size = CGSize(width: narrowest, height: max(nameHeight + 2 * nameVerticalPadding, minimumSize.height))
            name.center = CGPoint(x: size.width / 2, y: size.height / 2)
            return EntityRelationshipMeasuredBox(size: size, name: name, rows: [])
        }
        let table = EntityRelationshipAttributeTable(cells: entity.attributes.map { attribute in cells(of: attribute, measurers: measurers) },
                                                     rowLineHeight: measurers.row.lineHeight)
        let width = max(narrowest, table.filledWidth + 2 * cellHorizontalPadding)
        let headerHeight = nameHeight + 2 * headerVerticalPadding
        name.center = CGPoint(x: width / 2, y: headerHeight / 2)
        let rows = table.rows(top: headerHeight, width: width, inset: cellHorizontalPadding, rowFontSize: measurers.row.fontSize)
        return EntityRelationshipMeasuredBox(size: CGSize(width: width, height: headerHeight + table.height), name: name, rows: rows)
    }

    /// An attribute's type, name, keys and comment, measured in that order; a cell with nothing to show has no lines.
    private static func cells<Measurer>(of attribute: EntityRelationshipAttribute,
                                        measurers: EntityRelationshipTextMeasurers<Measurer>) -> [DiagramTextBlock] {
        let unwrapped = CGFloat.greatestFiniteMagnitude
        let keys = DiagramLabel(attribute.keys.map(\.mermaidKeyword).joined(separator: ", "))
        return [
            DiagramTextBlock(label: lines(of: attribute.type), measurer: measurers.row, maximumWidth: unwrapped),
            DiagramTextBlock(label: lines(of: attribute.name), measurer: measurers.row, maximumWidth: unwrapped),
            DiagramTextBlock(label: keys, measurer: measurers.key, maximumWidth: unwrapped),
            DiagramTextBlock(label: attribute.comment ?? DiagramLabel(lines: []), measurer: measurers.row, maximumWidth: commentWrappingWidth),
        ]
    }

    /// A type or a name in backticks may hold line breaks; each starts a line.
    private static func lines(of text: String) -> DiagramLabel {
        DiagramLabel(lines: text.split(separator: "\n", omittingEmptySubsequences: false).map { line in
            String(line.hasSuffix("\r") ? line.dropLast() : line)
        })
    }
}

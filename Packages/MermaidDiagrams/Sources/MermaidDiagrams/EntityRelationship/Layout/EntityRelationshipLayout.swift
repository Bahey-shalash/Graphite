import CoreGraphics

/// An entity relationship diagram laid out on a page whose origin is the top left corner and whose y runs down, in
/// points. Drawing it needs only colors: every position, path and text measurement is here.
public struct EntityRelationshipLayout: Equatable, Sendable {
    public let size: CGSize
    /// The font the entities' names were measured in; attribute rows and labels are in the same font at their own
    /// `fontSize`.
    public let font: DiagramFont
    public let entities: [EntityRelationshipLayoutEntity]
    /// The relationships in the order they are written, those of an entity with itself included.
    public let relationships: [EntityRelationshipLayoutRelationship]
    /// The diagram's title above it, or nil.
    public let title: DiagramTextBlock?
}

/// An entity's box: its name in a header, and a row under it for each attribute.
public struct EntityRelationshipLayoutEntity: Equatable, Sendable {
    public let frame: CGRect
    /// The name or alias, centered in the header, or in the whole box when it has no attributes.
    public let name: DiagramTextBlock
    /// The attribute rows, top to bottom; the header ends where the first begins.
    public let rows: [EntityRelationshipLayoutRow]
}

/// One attribute's row across its entity's box.
public struct EntityRelationshipLayoutRow: Equatable, Sendable {
    /// The row's band, as wide as the box.
    public let frame: CGRect
    /// Each line of the row's cells, starting at its column's left edge.
    public let texts: [EntityRelationshipLayoutCellText]
}

/// One line of an attribute's cell, a block of its own placed so that it starts at its column's left edge.
public struct EntityRelationshipLayoutCellText: Equatable, Sendable {
    public let column: EntityRelationshipColumn
    public let text: DiagramTextBlock
}

/// The columns of an entity's attribute rows, left to right. A column no row fills takes no room.
public enum EntityRelationshipColumn: Equatable, Sendable, CaseIterable {
    case type
    case name
    case keys
    case comment
}

/// A relationship's line between two boxes, or looping out of one box and back, with a cardinality mark at each end.
public struct EntityRelationshipLayoutRelationship: Equatable, Sendable {
    public let identification: EntityRelationshipIdentification
    /// The line, from the first entity's box to the second's; the marks are drawn over its ends.
    public let path: DiagramPath
    public let firstEntityMark: EntityRelationshipCardinalityMark
    public let secondEntityMark: EntityRelationshipCardinalityMark
    /// The label, drawn on a patch of the background, or nil.
    public let label: DiagramTextBlock?
}

/// A cardinality drawn where a relationship's line meets a box.
public struct EntityRelationshipCardinalityMark: Equatable, Sendable {
    public let cardinality: EntityRelationshipCardinality
    /// Where the line meets the box.
    public let tip: CGPoint
    /// The unit direction from the line into the box.
    public let direction: CGVector

    /// How far a mark reaches back along its line from the box, in points: Pele's.
    public static let length: CGFloat = 18
}

extension EntityRelationshipLayoutEntity {
    func translated(by offset: CGVector) -> EntityRelationshipLayoutEntity {
        EntityRelationshipLayoutEntity(frame: frame.offsetBy(dx: offset.dx, dy: offset.dy), name: name.translated(by: offset),
                                       rows: rows.map { row in row.translated(by: offset) })
    }
}

extension EntityRelationshipLayoutRow {
    func translated(by offset: CGVector) -> EntityRelationshipLayoutRow {
        EntityRelationshipLayoutRow(frame: frame.offsetBy(dx: offset.dx, dy: offset.dy), texts: texts.map { cell in
            EntityRelationshipLayoutCellText(column: cell.column, text: cell.text.translated(by: offset))
        })
    }
}

extension EntityRelationshipLayoutRelationship {
    func translated(by offset: CGVector) -> EntityRelationshipLayoutRelationship {
        EntityRelationshipLayoutRelationship(identification: identification, path: path.translated(by: offset),
                                             firstEntityMark: firstEntityMark.translated(by: offset),
                                             secondEntityMark: secondEntityMark.translated(by: offset), label: label?.translated(by: offset))
    }
}

extension EntityRelationshipCardinalityMark {
    func translated(by offset: CGVector) -> EntityRelationshipCardinalityMark {
        EntityRelationshipCardinalityMark(cardinality: cardinality, tip: tip.translated(by: offset), direction: direction)
    }
}

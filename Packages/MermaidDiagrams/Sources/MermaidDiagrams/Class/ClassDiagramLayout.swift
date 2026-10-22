import CoreGraphics

/// A class diagram laid out on a page whose origin is the top left corner and whose y runs down, in points. Drawing
/// it needs only colors: every position, path and text measurement is here.
public struct ClassDiagramLayout: Equatable, Sendable {
    public let size: CGSize
    /// The font the text was measured in; each block carries its own size.
    public let font: DiagramFont
    /// The classes' boxes, in the order of `ClassDiagram.classes`.
    public let classes: [ClassDiagramLayoutClass]
    /// The notes, in the order of `ClassDiagram.notes`.
    public let notes: [ClassDiagramLayoutNote]
    /// The names of lollipop interfaces, drawn as text alone.
    public let interfaces: [DiagramTextBlock]
    /// The relations' lines, in the order of `ClassDiagram.relations`.
    public let relations: [ClassDiagramLayoutEdge]
    /// The dotted lines from notes to their classes, in the order of the notes that have one.
    public let noteLinks: [ClassDiagramLayoutEdge]
    /// The diagram's title above it, drawn bold, or nil.
    public let title: DiagramTextBlock?
}

/// A class's box: its outline, the lines between its compartments, and its text.
public struct ClassDiagramLayoutClass: Equatable, Sendable {
    public let frame: CGRect
    /// The y of each line drawn across the box: under the title, and under the attributes.
    public let dividerYs: [CGFloat]
    /// `«interface»` and the like, above the name, drawn small in the muted color.
    public let annotations: [DiagramTextBlock]
    /// The name, drawn bold.
    public let name: DiagramTextBlock
    /// The attributes then the methods, each a line of its own starting at the box's left padding.
    public let members: [ClassDiagramLayoutMember]
}

/// A line of a class's attributes or methods.
public struct ClassDiagramLayoutMember: Equatable, Sendable {
    public let text: DiagramTextBlock
    /// Static members are underlined, abstract ones in italics.
    public let classifier: ClassDiagramMemberClassifier
}

/// A note: a box with a folded corner around its text.
public struct ClassDiagramLayoutNote: Equatable, Sendable {
    public let frame: CGRect
    public let text: DiagramTextBlock
}

/// A relation's or a note's line, with its marks and texts.
public struct ClassDiagramLayoutEdge: Equatable, Sendable {
    public let line: ClassDiagramLineStyle
    /// The line, which stops where a mark begins.
    public let path: DiagramPath
    public let sourceMark: ClassDiagramRelationMark?
    public let targetMark: ClassDiagramRelationMark?
    /// The relation's text, drawn on a patch of the background, or nil.
    public let text: DiagramTextBlock?
    /// The cardinality beside the source end, drawn small in the muted color, or nil.
    public let sourceCardinality: DiagramTextBlock?
    /// The cardinality beside the target end, or nil.
    public let targetCardinality: DiagramTextBlock?
}

/// The mark at an end of a relation: its kind, the point it touches what it marks, and the unit direction it points
/// in, toward that point.
public struct ClassDiagramRelationMark: Equatable, Sendable {
    public let end: ClassDiagramRelationEnd
    public let tip: CGPoint
    public let direction: CGVector
}

extension ClassDiagramLayoutClass {
    func translated(by offset: CGVector) -> ClassDiagramLayoutClass {
        ClassDiagramLayoutClass(frame: frame.offsetBy(dx: offset.dx, dy: offset.dy), dividerYs: dividerYs.map { y in y + offset.dy },
                                annotations: annotations.map { block in block.translated(by: offset) }, name: name.translated(by: offset),
                                members: members.map { member in
                                    ClassDiagramLayoutMember(text: member.text.translated(by: offset), classifier: member.classifier)
                                })
    }
}

extension ClassDiagramLayoutNote {
    func translated(by offset: CGVector) -> ClassDiagramLayoutNote {
        ClassDiagramLayoutNote(frame: frame.offsetBy(dx: offset.dx, dy: offset.dy), text: text.translated(by: offset))
    }
}

extension ClassDiagramLayoutEdge {
    func translated(by offset: CGVector) -> ClassDiagramLayoutEdge {
        ClassDiagramLayoutEdge(line: line, path: path.translated(by: offset), sourceMark: sourceMark?.translated(by: offset),
                               targetMark: targetMark?.translated(by: offset), text: text?.translated(by: offset),
                               sourceCardinality: sourceCardinality?.translated(by: offset), targetCardinality: targetCardinality?.translated(by: offset))
    }
}

extension ClassDiagramRelationMark {
    func translated(by offset: CGVector) -> ClassDiagramRelationMark {
        ClassDiagramRelationMark(end: end, tip: tip.translated(by: offset), direction: direction)
    }
}

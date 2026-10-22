/// A node of a flowchart: the identifier edges name it by, the text drawn in it and its shape.
public struct FlowchartNode: Equatable, Sendable {
    public let identifier: String
    /// The node's text; its identifier when the diagram gives none.
    public internal(set) var label: DiagramLabel
    public internal(set) var shape: FlowchartNodeShape

    init(identifier: String, label: DiagramLabel, shape: FlowchartNodeShape = .rectangle) {
        self.identifier = identifier
        self.label = label
        self.shape = shape
    }
}

/// The shapes a flowchart node is drawn in: Mermaid's classic shapes, written with brackets around the text
/// (`A[text]`, `A{text}`) or by name (`A@{ shape: diam }`).
public enum FlowchartNodeShape: Equatable, Sendable, CaseIterable {
    /// `[text]`.
    case rectangle
    /// `(text)`.
    case roundedRectangle
    /// `([text])`.
    case stadium
    /// `[[text]]`, a rectangle with a line inside each end.
    case subroutine
    /// `[(text)]`, a database.
    case cylinder
    /// `((text))`.
    case circle
    /// `(((text)))`.
    case doubleCircle
    /// `>text]`, a flag notched on its left.
    case asymmetric
    /// `{text}`, a decision.
    case diamond
    /// `{{text}}`.
    case hexagon
    /// `[/text/]`, a parallelogram leaning right.
    case leanRight
    /// `[\text\]`, a parallelogram leaning left.
    case leanLeft
    /// `[/text\]`, wider at the bottom.
    case trapezoid
    /// `[\text/]`, wider at the top.
    case invertedTrapezoid
    /// `@{ shape: text }`: the text alone, without an outline.
    case text

    /// The shape a `shape:` attribute names, by Mermaid's documented short name or any of its aliases, or nil for
    /// a shape that is not drawn yet.
    public init?(shapeName: String) {
        guard let shape = Self.shapesByName[shapeName.lowercased()] else { return nil }
        self = shape
    }

    /// Mermaid's names for each shape (the short name first), as Mermaid 12.1.0 documents them.
    var mermaidNames: [String] {
        switch self {
        case .rectangle: ["rect", "proc", "process", "rectangle", "squarerect"]
        case .roundedRectangle: ["rounded", "event", "roundedrect"]
        case .stadium: ["stadium", "terminal", "pill"]
        case .subroutine: ["fr-rect", "subprocess", "subproc", "framed-rectangle", "subroutine"]
        case .cylinder: ["cyl", "db", "database", "cylinder"]
        case .circle: ["circle", "circ"]
        case .doubleCircle: ["dbl-circ", "double-circle", "doublecircle"]
        case .asymmetric: ["odd", "rect_left_inv_arrow"]
        case .diamond: ["diam", "decision", "diamond", "question"]
        case .hexagon: ["hex", "hexagon", "prepare"]
        case .leanRight: ["lean-r", "lean-right", "in-out", "lean_right"]
        case .leanLeft: ["lean-l", "lean-left", "out-in", "lean_left"]
        case .trapezoid: ["trap-b", "priority", "trapezoid-bottom", "trapezoid"]
        case .invertedTrapezoid: ["trap-t", "manual", "trapezoid-top", "inv-trapezoid", "inv_trapezoid"]
        case .text: ["text"]
        }
    }

    private static let shapesByName: [String: FlowchartNodeShape] = {
        var shapesByName: [String: FlowchartNodeShape] = [:]
        for shape in allCases {
            for name in shape.mermaidNames { shapesByName[name] = shape }
        }
        return shapesByName
    }()
}

/// The bounds every diagram is read and laid out within, so that a diagram written to exhaust memory or time fails
/// with a typed error instead. Each count is checked before anything of that count is made.
public struct MermaidDiagramLimits: Equatable, Sendable {
    /// The longest diagram text read, in UTF-8 bytes.
    public var maximumSourceBytes: Int
    /// The most nodes one diagram may declare.
    public var maximumNodeCount: Int
    /// The most edges one diagram may hold: `A & B --> C & D` makes four, so a short text can ask for many.
    public var maximumEdgeCount: Int
    /// The most points the layered layout may place: the nodes, plus one for each rank an edge crosses.
    public var maximumLayoutPointCount: Int

    public init(maximumSourceBytes: Int, maximumNodeCount: Int, maximumEdgeCount: Int, maximumLayoutPointCount: Int) {
        self.maximumSourceBytes = maximumSourceBytes
        self.maximumNodeCount = maximumNodeCount
        self.maximumEdgeCount = maximumEdgeCount
        self.maximumLayoutPointCount = maximumLayoutPointCount
    }

    /// Mermaid's default text size (50,000), Pele's edge limit (5,000), as many nodes, and 50,000 layout points:
    /// a diagram past them is far beyond what a note shows legibly.
    public static let standard = MermaidDiagramLimits(maximumSourceBytes: 50_000, maximumNodeCount: 5_000, maximumEdgeCount: 5_000,
                                                      maximumLayoutPointCount: 50_000)
}

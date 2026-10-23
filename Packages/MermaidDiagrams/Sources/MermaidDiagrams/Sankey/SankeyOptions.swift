/// A Sankey diagram's options from its front matter (`config:` then `sankey:`), as Pele applies them: the chart's
/// size, the nodes' width and the padding between them, whether values are shown with their prefix and suffix, and
/// how nodes are put in columns. A number below its least is left at Pele's default, and one above its most is cut
/// to it. Labels outlined in the page's color (`labelStyle: outlined`), a band color other than the gradient
/// (`linkColor`) and nodes' own colors (`nodeColors`) are not drawn yet: a diagram that sets them keeps its block as
/// code.
public struct SankeyOptions: Equatable, Sendable {
    public internal(set) var chartWidth: Double = 600
    public internal(set) var chartHeight: Double = 400
    public internal(set) var nodeWidth: Double = 10
    /// Between two nodes of a column, before the room values add.
    public internal(set) var nodePadding: Double = 12
    /// Whether each label shows its node's value after its name: unless `showValues: false`.
    public internal(set) var showsValues = true
    public internal(set) var valuePrefix = ""
    public internal(set) var valueSuffix = ""
    public internal(set) var alignment = SankeyNodeAlignment.justify
    /// Whether an option that is not drawn yet is set.
    public internal(set) var setsOptionsNotDrawn = false

    /// The most a chart's side, a node's width and the padding may be: Pele's.
    static let largestChartSide = 10_000.0
    static let largestNodeWidth = 200.0
    static let largestNodePadding = 200.0

    init() {}

    init(_ options: MermaidFrontMatterOptions) {
        chartWidth = Self.number(options.values["width"], least: 1, most: Self.largestChartSide) ?? chartWidth
        chartHeight = Self.number(options.values["height"], least: 1, most: Self.largestChartSide) ?? chartHeight
        nodeWidth = min(Self.number(options.values["nodeWidth"], least: 1, most: Self.largestNodeWidth) ?? nodeWidth, chartWidth)
        nodePadding = Self.number(options.values["nodePadding"], least: 0, most: Self.largestNodePadding) ?? nodePadding
        showsValues = options.values["showValues"] != .boolean(false)
        valuePrefix = Self.text(options.values["prefix"])
        valueSuffix = Self.text(options.values["suffix"])
        if case .text(let written) = options.values["nodeAlignment"], let alignment = SankeyNodeAlignment(rawValue: written) { self.alignment = alignment }
        let isOutlined = options.values["labelStyle"] == .text("outlined")
        let colorsLinks = options.values["linkColor"].map { value in value != .text("gradient") } ?? false
        setsOptionsNotDrawn = isOutlined || colorsLinks || options.values["nodeColors"] != nil
    }

    private static func number(_ value: MermaidFrontMatterOptions.Value?, least: Double, most: Double) -> Double? {
        guard case .number(let number) = value, number >= least else { return nil }
        return min(number, most)
    }

    /// Text, or a finite number written as JavaScript writes it; empty otherwise.
    private static func text(_ value: MermaidFrontMatterOptions.Value?) -> String {
        switch value {
        case .text(let written): written
        case .number(let number) where number.isFinite: JavaScriptNumberText.text(number)
        case .number, .boolean, .collection, nil: ""
        }
    }
}

/// How a Sankey diagram's nodes are put in columns (`nodeAlignment`).
public enum SankeyNodeAlignment: String, Equatable, Sendable {
    /// Each node in the column of its longest distance from a source, and nodes with no flow out in the last column.
    case justify
    /// Each node in the column of its longest distance from a source.
    case left
    /// Each node as many columns before the last as its longest distance to a node with no flow out.
    case right
    /// As `left`, but a source moves up to the column before its nearest target.
    case center
}

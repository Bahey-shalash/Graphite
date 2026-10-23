import CoreGraphics
import Foundation

/// Lays a Sankey diagram out as Pele does: a chart of 600 by 400 points, nodes 10 points wide in columns
/// (`SankeyPlacement`) with 27 points between nodes (12, and 15 for the value under each label), each node's label
/// beside its bar (`SankeyLabelPlacement`), its name and its value rounded to two decimals, at seven eighths of the
/// text size, smaller when a column holds so many nodes that each would have less than 1.8 lines (down to five
/// eighths), the bold title above, and the page around the chart and its labels.
public enum SankeyLayoutEngine {
    static let chartWidth = 600.0
    static let chartHeight = 400.0
    static let nodeWidth = 10.0
    /// Between two nodes of a column: Pele's padding, and the room it adds for values.
    static let nodePadding = 12.0 + 15.0
    /// Around the page.
    static let padding: CGFloat = 8
    /// Between the title and the chart.
    static let titleGap: CGFloat = 12
    /// The labels' size, as a share of the text size, and the least they shrink to.
    static let labelScale: CGFloat = 0.875
    static let smallestLabelScale: CGFloat = 0.625
    /// The lines of room each node of the fullest column keeps for its label before labels shrink.
    static let linesPerNode = 1.8
    /// A thin node keeps room for its label's height: the label's size times this.
    static let labelHeightRatio = 1.15
    /// Beyond this, a value is written as it is, not rounded to two decimals.
    static let largestRoundedValue = 1e15
    /// The widest the title is before it wraps: wide enough that it does not.
    static let unwrappedTitleWidth: CGFloat = 4_000

    public static func layout(_ diagram: SankeyDiagram, typography: DiagramTypography) throws(SankeyLayoutError) -> SankeyLayout {
        let labelSize = typography.edgeText.fontSize
        return try layout(diagram, titleText: typography.boldNodeText, font: typography.font) { size in
            size == labelSize ? typography.edgeText : CoreTextDiagramTextMeasurer(font: typography.font.resized(to: size))
        }
    }

    /// `labelText` gives the measurer of the labels at a size: seven eighths of the font's, or less when crowded.
    static func layout<Measurer: DiagramTextMeasuring>(_ diagram: SankeyDiagram, titleText: some DiagramTextMeasuring, font: DiagramFont,
                                                       labelText: (CGFloat) -> Measurer) throws(SankeyLayoutError) -> SankeyLayout {
        var labelSize = (font.size * labelScale).rounded()
        var placement = try place(diagram, labelSize: labelSize)
        let fullestColumn = max(1, placement.columns.map(\.count).max() ?? 1)
        let crowdedSize = max((font.size * smallestLabelScale).rounded(), (CGFloat(chartHeight) / CGFloat(fullestColumn) / CGFloat(linesPerNode)).rounded())
        if crowdedSize < labelSize {
            labelSize = crowdedSize
            placement = try place(diagram, labelSize: labelSize)
        }
        let measurer = labelText(labelSize)
        let texts = diagram.nodes.indices.map { index in labelTexts(name: diagram.nodes[index].name, value: placement.nodes[index].value) }
        let widths = texts.map { text in Double(measurer.width(of: text.name + " " + text.value)) }
        let labels = SankeyLabelPlacement(nodes: placement.nodes, widths: widths, fontSize: Double(labelSize), chartSize: (chartWidth, chartHeight),
                                          nodeWidth: nodeWidth)
        let title = diagram.title.map { title in
            DiagramTextBlock(label: DiagramLabelDecoder.label(from: title, form: .plain), measurer: titleText, maximumWidth: unwrappedTitleWidth)
        }.flatMap { block in block.lines.isEmpty ? nil : block }
        let page = SankeyPage(labels: labels, title: title)
        return SankeyLayout(size: page.size, font: font, title: page.placedTitle,
                            nodes: placement.nodes.enumerated().map { index, node in page.node(node, seriesIndex: index) },
                            links: placement.links.map { link in page.link(link, nodes: placement.nodes) },
                            labels: zip(texts, labels.labels).map { text, label in
                                page.label(name: text.name, value: text.value, label: label, measurer: measurer)
                            })
    }

    private static func place(_ diagram: SankeyDiagram, labelSize: CGFloat) throws(SankeyLayoutError) -> SankeyPlacement {
        try SankeyPlacement(diagram: diagram, options: SankeyPlacement.Options(width: chartWidth, height: chartHeight, nodeWidth: nodeWidth,
                                                                                  nodePadding: nodePadding,
                                                                                  labelHeight: Double(labelSize) * labelHeightRatio))
    }

    /// A node's name with its entity codes decoded and its whitespace runs as one space, as an SVG shows it, and its
    /// value rounded to two decimals, written as JavaScript writes it.
    private static func labelTexts(name: String, value: Double) -> (name: String, value: String) {
        let decoded = DiagramLabelDecoder.decodingEntities(name).split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let rounded = value.magnitude < largestRoundedValue ? ((value * 100) + 0.5).rounded(.down) / 100 : value
        return (decoded, JavaScriptNumberText.text(rounded))
    }
}

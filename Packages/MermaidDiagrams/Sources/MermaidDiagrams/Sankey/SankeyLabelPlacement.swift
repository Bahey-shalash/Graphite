/// Where each Sankey node's label goes, as Pele places them: beside its bar, after it in the chart's left half and
/// before it in the right half, its middle at the bar's. A label that would run into another tries the other side,
/// then a line up or down on either side, where it runs into no other label or bar, stays within the room the labels
/// first took, and stays nearer its own bar than any other bar of its column; else it stays. Only up to 300 nodes are
/// placed with that care.
struct SankeyLabelPlacement {
    struct Label {
        let width: Double
        /// Whether the label is after its bar, its left side against the bar's right; before it otherwise.
        var isAfter: Bool
        var left: Double
        /// The middle of the label's line.
        var middle: Double
    }

    private(set) var labels: [Label] = []
    /// The room the chart and its labels take, the chart's own included.
    private(set) var minimumX = 0.0
    private(set) var maximumX: Double
    private(set) var minimumY = 0.0
    private(set) var maximumY: Double

    /// Between a bar and its label, and the least room between two labels across.
    static let labelGap = 6.0
    /// Half a label's height, as a share of its font size; its line, as a share of its font size.
    static let halfHeightRatio = 0.75
    static let lineHeightRatio = 1.5
    /// The most nodes whose labels are moved apart.
    static let carefulNodeCount = 300

    private let nodes: [SankeyPlacement.Node]
    private let nodeWidth: Double
    private let halfHeight: Double
    private let lineHeight: Double
    /// The labels near each band of the chart's height, by band: a label is in the two bands on either side of its own.
    private var labelsByBand: [Int: [Int]] = [:]

    init(nodes: [SankeyPlacement.Node], widths: [Double], fontSize: Double, chartSize: (width: Double, height: Double), nodeWidth: Double) {
        self.nodes = nodes
        self.nodeWidth = nodeWidth
        halfHeight = fontSize * Self.halfHeightRatio
        lineHeight = fontSize * Self.lineHeightRatio
        maximumX = chartSize.width
        maximumY = chartSize.height
        for (node, width) in zip(nodes, widths) {
            let isAfter = node.x < chartSize.width / 2
            let left = isAfter ? node.x + nodeWidth + Self.labelGap : node.x - Self.labelGap - width
            let middle = node.y + node.height / 2
            minimumX = min(minimumX, left)
            maximumX = max(maximumX, left + width)
            minimumY = min(minimumY, middle - halfHeight)
            maximumY = max(maximumY, middle + halfHeight)
            labels.append(Label(width: width, isAfter: isAfter, left: left, middle: middle))
        }
        guard nodes.count <= Self.carefulNodeCount else { return }
        for (index, label) in labels.enumerated() {
            let band = band(of: label.middle)
            for key in (band - 2)...(band + 2) { labelsByBand[key, default: []].append(index) }
        }
        for index in labels.indices where overlapsLabel(index, left: labels[index].left, middle: labels[index].middle) { move(index) }
    }

    private func band(of middle: Double) -> Int {
        Int((middle / lineHeight).rounded(.down))
    }

    private func overlapsLabel(_ index: Int, left: Double, middle: Double) -> Bool {
        let width = labels[index].width
        return (labelsByBand[band(of: middle)] ?? []).contains { other in
            let label = labels[other]
            return other != index && abs(label.middle - middle) < lineHeight && left < label.left + label.width + Self.labelGap
                && left + width > label.left - Self.labelGap
        }
    }

    /// Tries the other side, then a line up and a line down on either side, and keeps the first place that is free.
    private mutating func move(_ index: Int) {
        let node = nodes[index]
        let label = labels[index]
        for shift in [0, -lineHeight, lineHeight] {
            for isAfter in [label.isAfter, !label.isAfter] {
                let left = isAfter ? node.x + nodeWidth + Self.labelGap : node.x - Self.labelGap - label.width
                let middle = label.middle + shift
                guard isFree(index, left: left, middle: middle) else { continue }
                labels[index].left = left
                labels[index].middle = middle
                labels[index].isAfter = isAfter
                return
            }
        }
    }

    private func isFree(_ index: Int, left: Double, middle: Double) -> Bool {
        let width = labels[index].width
        guard !overlapsLabel(index, left: left, middle: middle), left >= minimumX, left + width <= maximumX, middle - halfHeight >= minimumY,
              middle + halfHeight <= maximumY else { return false }
        let node = nodes[index]
        let ownDistance = max(0, node.y - middle, middle - node.y - node.height)
        return !nodes.indices.contains { other in
            guard other != index else { return false }
            let bar = nodes[other]
            let isUnderLabel = left < bar.x + nodeWidth + Self.labelGap && left + width > bar.x - Self.labelGap && middle - halfHeight < bar.y + bar.height
                && middle + halfHeight > bar.y
            let isNearerBarOfColumn = bar.x == node.x && max(0, bar.y - middle, middle - bar.y - bar.height) <= ownDistance
            return isUnderLabel || isNearerBarOfColumn
        }
    }
}

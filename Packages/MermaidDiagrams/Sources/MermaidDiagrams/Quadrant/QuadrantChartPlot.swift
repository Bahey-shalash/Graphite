import CoreGraphics

/// Where a quadrant chart's title, axes' texts and quadrants go on Pele's page of 500 by 500 points: the title at the
/// top, the y axis's texts turned at the left of the quadrants, the x axis's texts below them once the chart has points
/// (above them before), and the four quadrants filling the rest, 4 points apart.
struct QuadrantChartPlot {
    let title: DiagramTextBlock?
    /// The four quadrants and the gaps between them.
    let frame: CGRect
    let quadrantSize: CGSize
    let axisLabels: [QuadrantChartAxisLabel]

    /// The page's side: Pele's `chartWidth` and `chartHeight`, which the front matter's configuration would set.
    static let pageSide: CGFloat = 500
    /// Around the page's content: Pele's `quadrantPadding`.
    static let padding: CGFloat = 8
    /// Below the title, half of it above: Pele's `titlePadding`.
    static let titlePadding: CGFloat = 10
    /// Between an axis's texts and the quadrants: Pele's `xAxisLabelPadding` and `yAxisLabelPadding`.
    static let axisLabelPadding: CGFloat = 5
    /// Between two quadrants.
    static let quadrantGap: CGFloat = 4
    /// What an axis's text leaves of its half of the axis, and a quadrant's text of its quadrant's width.
    static let textInset: CGFloat = 16
    /// The narrowest a text wraps at.
    static let narrowestTextWidth: CGFloat = 40

    init(chart: QuadrantChart, axisText: some DiagramTextMeasuring, titleText: some DiagramTextMeasuring) {
        let side = Self.pageSide - 2 * Self.padding
        var title = Self.block(chart.title.map { title in DiagramLabelDecoder.label(from: title, form: .plain) }, measurer: titleText, maximumWidth: side)
        let titleSpace = title.map { title in title.size.height + Self.titlePadding } ?? 0
        let xLow = Self.block(chart.xAxisLowLabel, measurer: axisText, maximumWidth: chart.xAxisHighLabel == nil ? side : side / 2 - Self.textInset)
        let xHigh = Self.block(chart.xAxisHighLabel, measurer: axisText, maximumWidth: side / 2 - Self.textInset)
        let xHeight = max(xLow?.size.height ?? 0, xHigh?.size.height ?? 0)
        let xSpace = xLow == nil && xHigh == nil ? 0 : xHeight + Self.axisLabelPadding
        let tall = Self.pageSide - 2 * Self.padding - titleSpace - xSpace
        let yLow = Self.block(chart.yAxisLowLabel, measurer: axisText, maximumWidth: chart.yAxisHighLabel == nil ? tall : tall / 2 - Self.textInset)
        let yHigh = Self.block(chart.yAxisHighLabel, measurer: axisText, maximumWidth: tall / 2 - Self.textInset)
        let yHeight = max(yLow?.size.height ?? 0, yHigh?.size.height ?? 0)
        let ySpace = yLow == nil && yHigh == nil ? 0 : yHeight + Self.axisLabelPadding
        let xAxisIsBelow = !chart.points.isEmpty
        frame = CGRect(x: Self.padding + ySpace, y: Self.padding + titleSpace + (xAxisIsBelow ? 0 : xSpace), width: max(0, side - ySpace),
                       height: max(0, tall))
        quadrantSize = CGSize(width: max(0, (frame.width - Self.quadrantGap) / 2), height: max(0, (frame.height - Self.quadrantGap) / 2))
        let xMiddle = xAxisIsBelow ? frame.maxY + Self.axisLabelPadding + xHeight / 2 : frame.minY - Self.axisLabelPadding - xHeight / 2
        axisLabels = Self.xAxisLabels(low: xLow, high: xHigh, frame: frame, middle: xMiddle)
            + Self.yAxisLabels(low: yLow, high: yHigh, frame: frame, middle: frame.minX - Self.axisLabelPadding - yHeight / 2)
        // Half the title's padding above it, the other half below it.
        title?.center = CGPoint(x: Self.pageSide / 2, y: titleSpace / 2)
        self.title = title
    }

    /// The box of quadrant `index + 1`: 1 at the top right, then anticlockwise.
    func quadrantFrame(_ index: Int) -> CGRect {
        let isRight = index == 0 || index == 3
        let isTop = index < 2
        return CGRect(x: isRight ? frame.maxX - quadrantSize.width : frame.minX, y: isTop ? frame.minY : frame.maxY - quadrantSize.height,
                      width: quadrantSize.width, height: quadrantSize.height)
    }

    /// `label` measured and wrapped at `maximumWidth`, never narrower than 40 points; nil without a label.
    static func block(_ label: DiagramLabel?, measurer: some DiagramTextMeasuring, maximumWidth: CGFloat) -> DiagramTextBlock? {
        label.map { label in DiagramTextBlock(label: label, measurer: measurer, maximumWidth: max(maximumWidth, narrowestTextWidth)) }
    }

    /// The x axis's texts on the line through `middle`: the low end's in the left half's middle, or from the left edge
    /// without a high end; the high end's in the right half's middle.
    private static func xAxisLabels(low: DiagramTextBlock?, high: DiagramTextBlock?, frame: CGRect, middle: CGFloat) -> [QuadrantChartAxisLabel] {
        var labels: [QuadrantChartAxisLabel] = []
        if let low {
            let center = high == nil ? frame.minX + low.size.width / 2 : frame.minX + frame.width / 4
            labels.append(placed(low, at: CGPoint(x: center, y: middle)))
        }
        if let high { labels.append(placed(high, at: CGPoint(x: frame.minX + frame.width * 3 / 4, y: middle))) }
        return labels
    }

    /// The y axis's texts turned on the line through `middle`: the low end's in the lower half's middle, or from the
    /// bottom edge without a high end; the high end's in the upper half's middle.
    private static func yAxisLabels(low: DiagramTextBlock?, high: DiagramTextBlock?, frame: CGRect, middle: CGFloat) -> [QuadrantChartAxisLabel] {
        var labels: [QuadrantChartAxisLabel] = []
        if let low {
            let center = high == nil ? frame.maxY - low.size.width / 2 : frame.minY + frame.height * 3 / 4
            labels.append(placed(low, at: CGPoint(x: middle, y: center), isTurned: true))
        }
        if let high { labels.append(placed(high, at: CGPoint(x: middle, y: frame.minY + frame.height / 4), isTurned: true)) }
        return labels
    }

    private static func placed(_ text: DiagramTextBlock, at center: CGPoint, isTurned: Bool = false) -> QuadrantChartAxisLabel {
        var placed = text
        placed.center = center
        return QuadrantChartAxisLabel(text: placed, isTurned: isTurned)
    }
}

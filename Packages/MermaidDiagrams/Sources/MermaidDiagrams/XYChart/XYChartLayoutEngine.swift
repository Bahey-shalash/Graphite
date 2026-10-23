import CoreGraphics

/// Lays an XY chart out as Pele does, on its page of 700 by 500 points: the bold title above, the plot with a grid
/// line at each value mark, bars in the middle of their slots side by side (seven tenths of a slot for a slot's
/// bars), lines over them with dots and their point labels, the axes with 4-point ticks and their labels and titles,
/// and the legend 24 points right of the plot in rows of 26 points with 12-point swatches. A horizontal chart turns
/// the axes: categories down the left, values along the bottom.
public enum XYChartLayoutEngine {
    /// Pele's chart width and height.
    static let pageSize = CGSize(width: 700, height: 500)
    /// Around the chart.
    static let padding: CGFloat = 8
    /// Between the title and what is below it.
    static let titleGap: CGFloat = 12
    static let tickLength: CGFloat = 4
    /// Between the bottom axis' ticks and labels, and between its labels and title.
    static let bottomLabelGap: CGFloat = 4
    /// Between the left axis' ticks and labels, and between its labels and title.
    static let leftLabelGap: CGFloat = 6
    /// Between the plot (and a horizontal chart's point labels) and the legend.
    static let legendGap: CGFloat = 24
    static let legendRowHeight: CGFloat = 26
    /// Above and below a legend title of several lines, together.
    static let legendRowPadding: CGFloat = 6
    static let swatchSide: CGFloat = 12
    static let swatchTextGap: CGFloat = 8
    /// The widest a legend title is before it wraps, as a share of the page's width; a horizontal chart's categories
    /// wrap at the same.
    static let legendWidthShare: CGFloat = 0.3
    /// The longest an axis' title is before it wraps, as a share of the page's side along it.
    static let axisTitleShare: CGFloat = 0.8
    /// About how far apart the value axis' marks are, on the left and along the bottom.
    static let leftValueMarkSpacing: CGFloat = 56
    static let bottomValueMarkSpacing: CGFloat = 80
    /// About how far apart a numeric category axis' marks are, on the left and along the bottom.
    static let leftRangeMarkSpacing: CGFloat = 32
    static let bottomRangeMarkSpacing: CGFloat = 80
    /// The room a category without a label takes along the axis.
    static let emptyCategoryExtent: CGFloat = 8
    /// Between two categories' labels along the bottom.
    static let categoryLabelSpacing: CGFloat = 12
    /// A vertical chart's categories wrap at their slot's width, less what is around the plot and a margin, and never
    /// below the narrowest width.
    static let narrowestCategoryWrap: CGFloat = 48
    static let categoryWrapAllowance: CGFloat = 64
    static let categoryWrapMargin: CGFloat = 8
    /// Between a vertical chart's point labels and its plot's top.
    static let pointLabelGap: CGFloat = 4
    /// The room a horizontal chart keeps right of its plot for point labels: their width and this, at most this share
    /// of the page's width.
    static let pointLabelReachGap: CGFloat = 12
    static let pointLabelReachShare: CGFloat = 0.25

    public static func layout(_ chart: XYChart, typography: DiagramTypography) throws(XYChartLayoutError) -> XYChartLayout {
        try layout(chart, text: XYChartText(titleText: typography.boldNodeText, smallText: typography.edgeText, tinyText: typography.axisText),
                   font: typography.font)
    }

    static func layout(_ chart: XYChart, text: XYChartText<some DiagramTextMeasuring>, font: DiagramFont) throws(XYChartLayoutError) -> XYChartLayout {
        guard !chart.series.isEmpty else { throw .noSeries }
        let frame = XYChartFrame(chart: chart, text: text)
        let series = XYChartSeriesPlacement(chart: chart, frame: frame, text: text)
        let axes = XYChartAxes(frame: frame)
        return XYChartLayout(size: pageSize, font: font, title: frame.title.map { title in placed(title, x: pageSize.width / 2, top: padding) },
                             plotFrame: frame.plot, gridLines: axes.gridLines, axisLines: axes.axisLines + series.baseline,
                             axisLabels: axes.labels, bottomAxisTitle: axes.bottomTitle, leftAxisTitle: axes.leftTitle, bars: series.bars,
                             lines: series.lines, pointLabels: series.pointLabels, legend: legend(frame))
    }

    /// The legend's rows from the plot's right, centered down it, as many as fit the page's height.
    private static func legend(_ frame: XYChartFrame) -> [XYChartLegendEntry] {
        let rowHeights = frame.legendTexts.map { entry in max(legendRowHeight, entry.text.size.height + legendRowPadding) }
        var rowTop = frame.plot.minY + max(0, (frame.plot.height - rowHeights.reduce(0, +)) / 2)
        let left = frame.plot.maxX + frame.pointLabelReach + legendGap
        var entries: [XYChartLegendEntry] = []
        for (entry, rowHeight) in zip(frame.legendTexts, rowHeights) {
            guard rowTop + rowHeight <= pageSize.height else { break }
            let middle = rowTop + rowHeight / 2
            var text = entry.text
            text.center = CGPoint(x: left + swatchSide + swatchTextGap + text.size.width / 2, y: middle)
            let swatch = CGRect(x: left, y: middle - swatchSide / 2, width: swatchSide, height: swatchSide)
            entries.append(XYChartLegendEntry(seriesIndex: entry.seriesIndex, kind: entry.kind, swatch: swatch, text: text))
            rowTop += rowHeight
        }
        return entries
    }

    /// `block` centered across at `x`, its top at `top`.
    static func placed(_ block: DiagramTextBlock, x: CGFloat, top: CGFloat) -> DiagramTextBlock {
        var placed = block
        placed.center = CGPoint(x: x, y: top + block.size.height / 2)
        return placed
    }
}

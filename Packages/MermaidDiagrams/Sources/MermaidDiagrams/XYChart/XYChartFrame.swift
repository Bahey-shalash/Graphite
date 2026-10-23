import CoreGraphics

/// Where an XY chart's plot goes on its page and what is measured around it, as Pele arranges them: the title above,
/// room for the tallest point label over the plot, the left axis' title, labels and ticks on its left, the bottom
/// axis' ticks, labels and title below it, and the legend (and a horizontal chart's point labels) on its right. The
/// value axis is the left one of a vertical chart and the bottom one of a horizontal chart.
struct XYChartFrame {
    let isHorizontal: Bool
    /// The title, measured, not placed yet.
    let title: DiagramTextBlock?
    /// The legend's titles, measured, each with its series' place and kind.
    let legendTexts: [(seriesIndex: Int, kind: XYChartSeriesKind, text: DiagramTextBlock)]
    /// The room right of the plot a horizontal chart keeps for its point labels.
    let pointLabelReach: CGFloat
    let valueScale: XYChartValueScale
    let categoryScale: XYChartCategoryScale
    let leftTitle: DiagramTextBlock?
    let bottomTitle: DiagramTextBlock?
    let leftMarks: [XYChartMark]
    let bottomMarks: [XYChartMark]
    let plot: CGRect

    /// What the frame's measurements need.
    private struct Measurements {
        let legendSpace: CGFloat
        let categoryLabels: [DiagramTextBlock]
        let categorySize: CGSize
        let pointLabelWidth: CGFloat
    }

    init(chart: XYChart, text: XYChartText<some DiagramTextMeasuring>) {
        let page = XYChartLayoutEngine.pageSize
        let padding = XYChartLayoutEngine.padding
        isHorizontal = chart.orientation == .horizontal
        title = chart.title.flatMap { title in text.title(DiagramLabelDecoder.label(from: title, form: .plain), maximumWidth: page.width - 2 * padding) }
        legendTexts = chart.series.enumerated().compactMap { index, series in
            text.small(series.title, maximumWidth: page.width * XYChartLayoutEngine.legendWidthShare).map { block in (index, series.kind, block) }
        }
        var valueScale = XYChartValueScale(chart: chart)
        categoryScale = XYChartCategoryScale(chart: chart)
        let categoryAxisTitle = text.small(chart.xAxis.title, maximumWidth: (isHorizontal ? page.height : page.width) * XYChartLayoutEngine.axisTitleShare)
        let valueAxisTitle = text.small(chart.yAxis.title, maximumWidth: (isHorizontal ? page.width : page.height) * XYChartLayoutEngine.axisTitleShare)
        leftTitle = isHorizontal ? categoryAxisTitle : valueAxisTitle
        bottomTitle = isHorizontal ? valueAxisTitle : categoryAxisTitle
        let measurements = Self.measurements(chart: chart, legendTexts: legendTexts, categoryScale: categoryScale, isHorizontal: isHorizontal, text: text)
        let top = padding + (title.map { title in title.size.height + XYChartLayoutEngine.titleGap } ?? 0)
            + Self.headroom(isHorizontal: isHorizontal, pointLabelWidth: measurements.pointLabelWidth, text: text)
        let bottomLabelHeight = isHorizontal || !categoryScale.isCategorical ? text.smallText.lineHeight : measurements.categorySize.height
        let bottomSpace = XYChartLayoutEngine.tickLength + (bottomLabelHeight > 0 ? bottomLabelHeight + XYChartLayoutEngine.bottomLabelGap : 0)
            + (bottomTitle.map { title in title.size.height + XYChartLayoutEngine.bottomLabelGap } ?? 0)
        let plotHeight = max(1, page.height - padding - bottomSpace - top)
        leftMarks = isHorizontal
            ? Self.categoryMarks(categoryScale, length: plotHeight, measurements: measurements, isHorizontal: isHorizontal, text: text)
            : valueScale.marks(length: plotHeight, spacing: XYChartLayoutEngine.leftValueMarkSpacing, text: text.smallText)
        let leftLabelWidth = leftMarks.map(\.label.size.width).max() ?? 0
        let left = padding + (leftTitle.map { title in title.size.height + XYChartLayoutEngine.leftLabelGap } ?? 0)
            + (leftLabelWidth > 0 ? leftLabelWidth + XYChartLayoutEngine.leftLabelGap : 0) + XYChartLayoutEngine.tickLength
        let besidePoints = measurements.pointLabelWidth > 0 ? measurements.pointLabelWidth + XYChartLayoutEngine.pointLabelReachGap : 0
        pointLabelReach = isHorizontal ? min(page.width * XYChartLayoutEngine.pointLabelReachShare, besidePoints) : 0
        var plotWidth = max(1, page.width - padding - left - measurements.legendSpace - pointLabelReach)
        bottomMarks = isHorizontal
            ? valueScale.marks(length: plotWidth, spacing: XYChartLayoutEngine.bottomValueMarkSpacing, text: text.smallText)
            : Self.categoryMarks(categoryScale, length: plotWidth, measurements: measurements, isHorizontal: isHorizontal, text: text)
        if measurements.legendSpace + pointLabelReach == 0 {
            let overhang = bottomMarks.map { mark in CGFloat(mark.fraction) * plotWidth + mark.label.size.width / 2 - plotWidth }.max() ?? 0
            plotWidth = max(1, plotWidth - max(0, overhang))
        }
        self.valueScale = valueScale
        plot = CGRect(x: left, y: top, width: plotWidth, height: plotHeight)
    }

    /// The room over the plot of a vertical chart: a line of point labels when a line has them, else half a line for
    /// the top mark's label.
    private static func headroom(isHorizontal: Bool, pointLabelWidth: CGFloat, text: XYChartText<some DiagramTextMeasuring>) -> CGFloat {
        guard !isHorizontal else { return 0 }
        return pointLabelWidth > 0 ? text.tinyText.lineHeight + XYChartLayoutEngine.pointLabelGap : text.smallText.lineHeight / 2
    }

    private static func measurements(chart: XYChart, legendTexts: [(seriesIndex: Int, kind: XYChartSeriesKind, text: DiagramTextBlock)],
                                     categoryScale: XYChartCategoryScale,
                                     isHorizontal: Bool, text: XYChartText<some DiagramTextMeasuring>) -> Measurements {
        let page = XYChartLayoutEngine.pageSize
        let legendWidth = legendTexts.map { entry in entry.text.size.width + XYChartLayoutEngine.swatchSide + XYChartLayoutEngine.swatchTextGap }.max()
        let legendSpace = legendWidth.map { width in width + XYChartLayoutEngine.legendGap } ?? 0
        var categoryLabels: [DiagramTextBlock] = []
        if case .categories(let categories) = categoryScale.kind {
            let wrappingWidth = isHorizontal ? page.width * XYChartLayoutEngine.legendWidthShare
                : max(XYChartLayoutEngine.narrowestCategoryWrap, (page.width - 2 * XYChartLayoutEngine.padding - XYChartLayoutEngine.categoryWrapAllowance
                    - legendSpace) * CGFloat(categoryScale.slot) - XYChartLayoutEngine.categoryWrapMargin)
            categoryLabels = categories.map { category in text.smallBlock(category, maximumWidth: wrappingWidth) }
        }
        let pointLabelWidth = chart.series.flatMap(\.pointLabels).map { label in text.tinyBlock(label).size.width }.max() ?? 0
        return Measurements(legendSpace: legendSpace, categoryLabels: categoryLabels,
                            categorySize: CGSize(width: categoryLabels.map(\.size.width).max() ?? 0, height: categoryLabels.map(\.size.height).max() ?? 0),
                            pointLabelWidth: pointLabelWidth)
    }

    /// The category axis' marks, spaced so that labels along it, or the round numbers of its range, do not run into
    /// each other.
    private static func categoryMarks(_ scale: XYChartCategoryScale, length: CGFloat, measurements: Measurements, isHorizontal: Bool,
                                      text: XYChartText<some DiagramTextMeasuring>) -> [XYChartMark] {
        let labelExtent = measurements.categoryLabels.isEmpty ? XYChartLayoutEngine.emptyCategoryExtent
            : isHorizontal ? measurements.categorySize.height : measurements.categorySize.width + XYChartLayoutEngine.categoryLabelSpacing
        return scale.marks(length: length, categoryLabels: measurements.categoryLabels, labelExtent: labelExtent,
                           rangeSpacing: isHorizontal ? XYChartLayoutEngine.leftRangeMarkSpacing : XYChartLayoutEngine.bottomRangeMarkSpacing,
                           text: text.smallText)
    }
}

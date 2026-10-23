import CoreGraphics

/// Lays a quadrant chart out in Pele's style on a page of 500 by 500 points: the bold title at the top, the four
/// quadrants filling the plot 4 points apart with their texts in the middle (at their top once the chart has points),
/// the axes' texts in the smaller size at the left and below (above before the chart has points), and the points at
/// their coordinates with their texts where they overlap nothing (`QuadrantChartPointPlacement`).
public enum QuadrantChartLayoutEngine {
    /// Between a quadrant's top and its text, once the chart has points: Pele's `quadrantTextTopPadding`.
    static let quadrantTextTopPadding: CGFloat = 5

    public static func layout(_ chart: QuadrantChart, typography: DiagramTypography) -> QuadrantChartLayout {
        layout(chart, quadrantText: typography.nodeText, axisText: typography.edgeText, pointText: typography.axisText,
               titleText: typography.boldNodeText, font: typography.font)
    }

    static func layout<Measurer: DiagramTextMeasuring>(_ chart: QuadrantChart, quadrantText: Measurer, axisText: Measurer, pointText: Measurer,
                                                       titleText: Measurer, font: DiagramFont) -> QuadrantChartLayout {
        let plot = QuadrantChartPlot(chart: chart, axisText: axisText, titleText: titleText)
        var quadrants: [QuadrantChartLayoutQuadrant] = []
        var textBoxes: [CGRect] = []
        for index in 0..<QuadrantChart.quadrantCount {
            let frame = plot.quadrantFrame(index)
            var text = QuadrantChartPlot.block(chart.quadrantLabels[index], measurer: quadrantText,
                                               maximumWidth: plot.quadrantSize.width - QuadrantChartPlot.textInset)
            let height = text?.size.height ?? 0
            let center = CGPoint(x: frame.midX, y: chart.points.isEmpty ? frame.midY : frame.minY + quadrantTextTopPadding + height / 2)
            text?.center = center
            textBoxes.append(text?.frame ?? CGRect(origin: center, size: .zero))
            quadrants.append(QuadrantChartLayoutQuadrant(frame: frame, text: text))
        }
        let pointTexts = chart.points.map { point in
            DiagramTextBlock(label: point.label, measurer: pointText, maximumWidth: QuadrantChartPointPlacement.textWidth)
        }
        let points = QuadrantChartPointPlacement(chart: chart, plot: plot, quadrantTextBoxes: textBoxes, pointTexts: pointTexts).placed()
        return QuadrantChartLayout(size: CGSize(width: QuadrantChartPlot.pageSide, height: QuadrantChartPlot.pageSide), font: font,
                                   quadrants: quadrants, axisLabels: plot.axisLabels, points: points, title: plot.title)
    }
}

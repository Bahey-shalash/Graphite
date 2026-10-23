import CoreGraphics

/// An XY chart's axes as Pele draws them: the grid across the plot at the value marks, the left and bottom axis lines,
/// a tick and a label at each mark, and the axes' titles.
struct XYChartAxes {
    let gridLines: [XYChartSegment]
    let axisLines: [XYChartSegment]
    let labels: [DiagramTextBlock]
    let leftTitle: DiagramTextBlock?
    let bottomTitle: DiagramTextBlock?

    init(frame: XYChartFrame) {
        let plot = frame.plot
        let tick = XYChartLayoutEngine.tickLength
        let valueMarks = frame.isHorizontal ? frame.bottomMarks : frame.leftMarks
        gridLines = valueMarks.map { mark in XYChartAxes.rule(at: mark.fraction, in: plot, isHorizontal: frame.isHorizontal) }
        var lines = [XYChartSegment(start: CGPoint(x: plot.minX, y: plot.minY), end: CGPoint(x: plot.minX, y: plot.maxY)),
                     XYChartSegment(start: CGPoint(x: plot.minX, y: plot.maxY), end: CGPoint(x: plot.maxX, y: plot.maxY))]
        var labels: [DiagramTextBlock] = []
        for mark in frame.leftMarks {
            let markY = frame.isHorizontal ? plot.minY + CGFloat(mark.fraction) * plot.height : plot.maxY - CGFloat(mark.fraction) * plot.height
            lines.append(XYChartSegment(start: CGPoint(x: plot.minX, y: markY), end: CGPoint(x: plot.minX - tick, y: markY)))
            var label = mark.label
            label.center = CGPoint(x: plot.minX - tick - XYChartLayoutEngine.leftLabelGap - label.size.width / 2, y: markY)
            labels.append(label)
        }
        for mark in frame.bottomMarks {
            let markX = plot.minX + CGFloat(mark.fraction) * plot.width
            lines.append(XYChartSegment(start: CGPoint(x: markX, y: plot.maxY), end: CGPoint(x: markX, y: plot.maxY + tick)))
            labels.append(XYChartLayoutEngine.placed(mark.label, x: markX, top: plot.maxY + tick + XYChartLayoutEngine.bottomLabelGap))
        }
        axisLines = lines
        self.labels = labels
        let padding = XYChartLayoutEngine.padding
        leftTitle = frame.leftTitle.map { title in
            var placed = title
            placed.center = CGPoint(x: padding + title.size.height / 2, y: plot.midY)
            return placed
        }
        bottomTitle = frame.bottomTitle.map { title in
            XYChartLayoutEngine.placed(title, x: plot.midX, top: XYChartLayoutEngine.pageSize.height - padding - title.size.height)
        }
    }

    /// A line across the plot at `fraction` of the value axis: down the plot in a horizontal chart, across it otherwise.
    static func rule(at fraction: Double, in plot: CGRect, isHorizontal: Bool) -> XYChartSegment {
        if isHorizontal {
            let ruleX = plot.minX + CGFloat(fraction) * plot.width
            return XYChartSegment(start: CGPoint(x: ruleX, y: plot.minY), end: CGPoint(x: ruleX, y: plot.maxY))
        }
        let ruleY = plot.maxY - CGFloat(fraction) * plot.height
        return XYChartSegment(start: CGPoint(x: plot.minX, y: ruleY), end: CGPoint(x: plot.maxX, y: ruleY))
    }
}

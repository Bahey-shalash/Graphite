import CoreGraphics

/// Where an XY chart's series go in its plot, as Pele places them: a slot's bars side by side in seven tenths of it,
/// from zero (or the value axis' nearer end) to their values, and each line through its values, cut where it leaves
/// the value range, with a dot on each value inside it and its point labels above (or, in a horizontal chart,
/// right of) the dots.
struct XYChartSeriesPlacement {
    private(set) var bars: [XYChartBar] = []
    private(set) var lines: [XYChartLine] = []
    private(set) var pointLabels: [DiagramTextBlock] = []
    /// The line bars stand on when the value range runs both sides of zero; empty otherwise.
    private(set) var baseline: [XYChartSegment] = []

    /// The share of a slot a slot's bars take together.
    static let barGroupShare = 0.7
    /// The gap between two bars of a slot: a fifth of a bar's thickness, at most 2 points.
    static let barGapShare = 0.2
    static let largestBarGap = 2.0
    /// The least room a place along the category axis has for its line's dots to be drawn.
    static let smallestDottedSpan: CGFloat = 12
    /// How far right of its dot a horizontal chart's point label starts, and how far above its dot a vertical
    /// chart's point label ends.
    static let pointLabelSideOffset: CGFloat = 10
    static let pointLabelRaise: CGFloat = 6

    private let frame: XYChartFrame
    /// The room each place has along the category axis, in points.
    private let span: CGFloat
    /// Where zero is along the value axis, kept within it.
    private let baseFraction: Double

    init(chart: XYChart, frame: XYChartFrame, text: XYChartText<some DiagramTextMeasuring>) {
        self.frame = frame
        span = (frame.isHorizontal ? frame.plot.height : frame.plot.width) * CGFloat(frame.categoryScale.slot)
        baseFraction = Self.clamped(frame.valueScale.fraction(of: 0))
        let barCount = chart.series.filter { series in series.kind == .bar }.count
        if barCount > 0, baseFraction > 0, baseFraction < 1 {
            baseline = [XYChartAxes.rule(at: baseFraction, in: frame.plot, isHorizontal: frame.isHorizontal)]
        }
        var barIndex = 0
        for (seriesIndex, series) in chart.series.enumerated() {
            let count = frame.categoryScale.isCategorical ? min(series.values.count, frame.categoryScale.placeCount) : series.values.count
            switch series.kind {
            case .bar:
                placeBars(series, seriesIndex: seriesIndex, count: count, barIndex: barIndex, barCount: barCount)
                barIndex += 1
            case .line:
                placeLine(series, seriesIndex: seriesIndex, count: count, text: text)
            }
        }
    }

    private mutating func placeBars(_ series: XYChartSeries, seriesIndex: Int, count: Int, barIndex: Int, barCount: Int) {
        let thickness = Double(span) * Self.barGroupShare / Double(max(barCount, 1))
        let gap = barCount > 1 ? min(Self.largestBarGap, thickness * Self.barGapShare) : 0
        let offset = (Double(barIndex) - Double(barCount - 1) / 2) * thickness - (thickness - gap) / 2
        for index in 0..<count {
            guard let value = series.values[index].flatMap(XYChartValueScale.drawable) else { continue }
            let place = frame.categoryScale.place(index, of: count)
            let valueFraction = Self.clamped(frame.valueScale.fraction(of: value))
            let lower = min(baseFraction, valueFraction)
            let upper = max(baseFraction, valueFraction)
            let rectangle: CGRect
            if frame.isHorizontal {
                rectangle = CGRect(x: point(place: place, valueFraction: lower).x, y: point(place: place, valueFraction: 0).y + CGFloat(offset),
                                   width: CGFloat(upper - lower) * frame.plot.width, height: CGFloat(thickness - gap))
            } else {
                rectangle = CGRect(x: point(place: place, valueFraction: 0).x + CGFloat(offset), y: point(place: place, valueFraction: upper).y,
                                   width: CGFloat(thickness - gap), height: CGFloat(upper - lower) * frame.plot.height)
            }
            bars.append(XYChartBar(seriesIndex: seriesIndex, frame: rectangle))
        }
    }

    /// The line from value to value, cut where it leaves the value range as Pele cuts it: a run ends where the line
    /// leaves the range or a value is missing, and the next starts where it comes back.
    private mutating func placeLine(_ series: XYChartSeries, seriesIndex: Int, count: Int, text: XYChartText<some DiagramTextMeasuring>) {
        var runs: [[CGPoint]] = []
        var dots: [CGPoint] = []
        var isDrawing = false
        var previous: (place: Double, valueFraction: Double)?
        for index in 0..<count {
            guard let value = series.values[index].flatMap(XYChartValueScale.drawable) else {
                previous = nil
                continue
            }
            let place = frame.categoryScale.place(index, of: count)
            let valueFraction = frame.valueScale.fraction(of: value)
            let isInside = valueFraction >= 0 && valueFraction <= 1
            if let previous {
                appendSegment(from: previous, to: (place, valueFraction), isDrawing: isDrawing, to: &runs)
            } else if isInside {
                runs.append([point(place: place, valueFraction: valueFraction)])
            }
            isDrawing = isInside
            previous = (place, valueFraction)
            guard isInside else { continue }
            let dot = point(place: place, valueFraction: valueFraction)
            if span >= Self.smallestDottedSpan { dots.append(dot) }
            if index < series.pointLabels.count { placePointLabel(text.tinyBlock(series.pointLabels[index]), at: dot) }
        }
        lines.append(XYChartLine(seriesIndex: seriesIndex, runs: runs, dots: dots))
    }

    /// The part of the line from one value to the next inside the value range, if any: it continues the run when it
    /// starts where the last one ended, and starts a new run otherwise.
    private func appendSegment(from start: (place: Double, valueFraction: Double), to end: (place: Double, valueFraction: Double),
                               isDrawing: Bool, to runs: inout [[CGPoint]]) {
        let rise = end.valueFraction - start.valueFraction
        var entry = 0.0
        var exit = 1.0
        if rise != 0 {
            let bottomCrossing = -start.valueFraction / rise
            let topCrossing = (1 - start.valueFraction) / rise
            entry = max(entry, min(bottomCrossing, topCrossing))
            exit = min(exit, max(bottomCrossing, topCrossing))
        } else if end.valueFraction < 0 || end.valueFraction > 1 {
            return
        }
        guard entry <= exit else { return }
        func pointAt(_ share: Double) -> CGPoint {
            point(place: start.place + (end.place - start.place) * share, valueFraction: start.valueFraction + rise * share)
        }
        if !isDrawing || entry > 0 || runs.isEmpty { runs.append([pointAt(entry)]) }
        runs[runs.count - 1].append(pointAt(exit))
    }

    private mutating func placePointLabel(_ label: DiagramTextBlock, at dot: CGPoint) {
        guard !label.lines.isEmpty else { return }
        var placed = label
        if frame.isHorizontal {
            placed.center = CGPoint(x: dot.x + Self.pointLabelSideOffset + label.size.width / 2, y: dot.y)
        } else {
            let halfWidth = label.size.width / 2
            placed.center = CGPoint(x: max(min(dot.x, frame.plot.maxX - halfWidth), frame.plot.minX + halfWidth),
                                    y: dot.y - Self.pointLabelRaise - label.size.height / 2)
        }
        pointLabels.append(placed)
    }

    /// The point at `place` along the category axis and `valueFraction` along the value axis.
    private func point(place: Double, valueFraction: Double) -> CGPoint {
        let plot = frame.plot
        if frame.isHorizontal {
            return CGPoint(x: plot.minX + CGFloat(valueFraction) * plot.width, y: plot.minY + CGFloat(place) * plot.height)
        }
        return CGPoint(x: plot.minX + CGFloat(place) * plot.width, y: plot.maxY - CGFloat(valueFraction) * plot.height)
    }

    private static func clamped(_ fraction: Double) -> Double {
        min(max(fraction, 0), 1)
    }
}

import CoreGraphics
import Foundation

/// The places along an XY chart's category axis (Mermaid's x axis), as fractions of its length, as Pele finds them:
/// categories and bars sit in the middle of equal slots; a line's points on a range run from end to end.
struct XYChartCategoryScale {
    enum Kind {
        case categories([DiagramLabel])
        /// A range with two different finite ends.
        case range(start: Double, end: Double)
        /// A range whose ends are the same value: its one mark is in the middle.
        case singleValue(Double)
        /// A range with an infinite end: no marks.
        case unmarked
    }

    let kind: Kind
    /// How many places the axis is divided into: the categories, else the most values of a series; at least one.
    let placeCount: Int
    /// The share of the axis' length each place has.
    let slot: Double
    /// The room kept at each end of a range, half a slot when the chart has bars.
    let inset: Double

    init(chart: XYChart) {
        var hasHalfSlotInset = chart.series.contains { series in series.kind == .bar }
        switch chart.xAxis.scale {
        case .categories(let categories):
            kind = .categories(categories)
            placeCount = max(categories.count, 1)
            hasHalfSlotInset = true
        case .range(let start, let end):
            let drawableStart = XYChartValueScale.drawable(start)
            let drawableEnd = XYChartValueScale.drawable(end)
            if let drawableStart, let drawableEnd, drawableStart != drawableEnd {
                kind = .range(start: drawableStart, end: drawableEnd)
            } else {
                kind = drawableStart.map(Kind.singleValue) ?? .unmarked
            }
            placeCount = max(1, chart.series.map(\.values.count).max() ?? 1)
        }
        slot = 1 / Double(placeCount)
        inset = hasHalfSlotInset ? slot / 2 : 0
    }

    var isCategorical: Bool {
        if case .categories = kind { return true }
        return false
    }

    /// Where the `index`th of a series' `count` values is placed, from 0 to 1 along the axis.
    func place(_ index: Int, of count: Int) -> Double {
        if isCategorical { return (Double(index) + 0.5) * slot }
        let share: Double
        if count > 1 {
            share = Double(index) / Double(count - 1)
        } else if case .range = kind {
            share = 0
        } else {
            share = 0.5
        }
        return inset + share * (1 - 2 * inset)
    }

    /// The labelled places along an axis `length` points long: each category, thinned out where labels would run
    /// into each other (`labelExtent` is the most room one takes along the axis), or the range's round numbers about
    /// `rangeSpacing` points apart.
    func marks(length: CGFloat, categoryLabels: [DiagramTextBlock], labelExtent: CGFloat, rangeSpacing: CGFloat,
               text: some DiagramTextMeasuring) -> [XYChartMark] {
        switch kind {
        case .categories(let categories):
            let every = max(1, Int((Double(labelExtent) / (Double(length) * slot)).rounded(.up)))
            return stride(from: 0, to: categories.count, by: every).map { index in
                XYChartMark(fraction: (Double(index) + 0.5) * slot, label: categoryLabels[index])
            }
        case .range(let start, let end):
            let count = max(XYChartScaleMarks.fewestMarkSpans, min(XYChartScaleMarks.mostMarkSpans, Int((length / rangeSpacing).rounded(.down))))
            let step = XYChartTicks.step(span: (end - start).magnitude, count: count)
            return XYChartTicks.values(from: min(start, end), to: max(start, end), step: step).map { value in
                XYChartMark(fraction: inset + (value - start) / (end - start) * (1 - 2 * inset), label: XYChartScaleMarks.numberLabel(value, text: text))
            }
        case .singleValue(let value):
            return [XYChartMark(fraction: 0.5, label: XYChartScaleMarks.numberLabel(value, text: text))]
        case .unmarked:
            return []
        }
    }
}

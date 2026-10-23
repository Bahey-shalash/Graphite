import CoreGraphics
import Foundation

/// The values along an XY chart's value axis, as Pele finds them: the y axis' range as written, else the values'
/// own, where bars stand on zero, widened when all values are equal and grown to whole steps of its marks once they
/// are found. The value at the axis' start may be the larger, which turns the axis.
struct XYChartValueScale {
    /// The value at the axis' start: the bottom of a vertical chart, the left of a horizontal one.
    private(set) var startValue: Double
    /// The value at the axis' end.
    private(set) var endValue: Double
    /// Whether the range is the y axis' as written, which its marks do not grow.
    let isWritten: Bool

    /// The largest magnitude a value is drawn at: beyond it, a value is drawn at it.
    static let largestMagnitude = 1e300
    /// How far past a whole step a range end may be from rounding and still be on it.
    private static let stepTolerance = 1e-9

    init(chart: XYChart) {
        if let range = chart.yAxis.range, let start = Self.drawable(range.start), let end = Self.drawable(range.end), start != end {
            startValue = start
            endValue = end
            isWritten = true
            return
        }
        isWritten = false
        let values = chart.series.flatMap { series in series.values.compactMap { value in value.flatMap(Self.drawable) } }
        var lower = values.min() ?? 0
        var upper = values.max() ?? 0
        if chart.series.contains(where: { series in series.kind == .bar }) {
            lower = min(lower, 0)
            upper = max(upper, 0)
        }
        if lower == upper {
            if lower == 0 {
                upper = 1
            } else {
                lower -= lower.magnitude / 2
                upper += upper.magnitude / 2
            }
        }
        startValue = lower
        endValue = upper
    }

    /// A finite value, kept within `largestMagnitude`, or nil for an infinite one, which is not drawn.
    static func drawable(_ value: Double) -> Double? {
        value.isFinite ? min(max(value, -largestMagnitude), largestMagnitude) : nil
    }

    /// Where `value` is along the axis, from 0 at its start to 1 at its end; outside them beyond the range.
    func fraction(of value: Double) -> Double {
        (value - startValue) / (endValue - startValue)
    }

    /// The marks along an axis `length` points long, about `spacing` points apart (from 2 to 10 of them), each with its
    /// value written as `text` measures it. A range not written grows to the marks' whole steps first.
    mutating func marks(length: CGFloat, spacing: CGFloat, text: some DiagramTextMeasuring) -> [XYChartMark] {
        let count = max(XYChartScaleMarks.fewestMarkSpans, min(XYChartScaleMarks.mostMarkSpans, Int((length / spacing).rounded(.down))))
        let step = XYChartTicks.step(span: (endValue - startValue).magnitude, count: count)
        if !isWritten {
            startValue = XYChartTicks.value(at: floor(XYChartTicks.index(of: startValue, step: step) + Self.stepTolerance), step: step)
            endValue = XYChartTicks.value(at: ceil(XYChartTicks.index(of: endValue, step: step) - Self.stepTolerance), step: step)
        }
        return XYChartTicks.values(from: min(startValue, endValue), to: max(startValue, endValue), step: step).map { value in
            XYChartMark(fraction: fraction(of: value), label: XYChartScaleMarks.numberLabel(value, text: text))
        }
    }
}

/// A labelled place along an axis: how far along it is, from 0 to 1, and its label.
struct XYChartMark {
    let fraction: Double
    let label: DiagramTextBlock
}

/// What the value and category axes' marks share.
enum XYChartScaleMarks {
    /// The fewest and most parts an axis is divided into by its marks.
    static let fewestMarkSpans = 2
    static let mostMarkSpans = 10
    /// The widest a mark's label is before it wraps: wide enough that it does not.
    static let unwrappedWidth: CGFloat = 4_000

    /// A number written as JavaScript writes it, measured on one line.
    static func numberLabel(_ value: Double, text: some DiagramTextMeasuring) -> DiagramTextBlock {
        DiagramTextBlock(label: DiagramLabel(JavaScriptNumberText.text(value)), measurer: text, maximumWidth: unwrappedWidth)
    }
}

import Foundation

/// The marks along an XY chart's numeric axis, as Pele finds them: a step of 1, 2 or 5 times a power of ten, and its
/// multiples within a range. A step below one is held as the negative of its inverse, a whole number, so that marks
/// are found by division and are written without rounding noise (`0.3`, not `0.30000000000000004`).
enum XYChartTicks {
    /// The most marks along one axis.
    static let maximumMarkCount = 100
    /// Where a unit of the step rounds up to the next of 1, 2, 5 and 10: their geometric means, as Pele's.
    private static let twoThreshold = 1.41
    private static let fiveThreshold = 3.16
    private static let tenThreshold = 7.07

    /// The step that divides `span` into about `count` parts.
    static func step(span: Double, count: Int) -> Double {
        let raw = span / Double(max(count, 1))
        let power = floor(log10(raw))
        let unit = raw / pow(10, power)
        let factor: Double = unit >= tenThreshold ? 10 : unit >= fiveThreshold ? 5 : unit >= twoThreshold ? 2 : 1
        return power < 0 ? -pow(10, -power) / factor : factor * pow(10, power)
    }

    /// How many steps from zero `value` is.
    static func index(of value: Double, step: Double) -> Double {
        step > 0 ? value / step : value * -step
    }

    /// The value `index` steps from zero.
    static func value(at index: Double, step: Double) -> Double {
        step > 0 ? index * step : index / -step
    }

    /// The multiples of `step` from `lower` to `upper`, both included, at most `maximumMarkCount` of them.
    static func values(from lower: Double, to upper: Double, step: Double) -> [Double] {
        var first = javaScriptRounded(index(of: lower, step: step))
        if value(at: first, step: step) < lower { first += 1 }
        var last = javaScriptRounded(index(of: upper, step: step))
        if value(at: last, step: step) > upper { last -= 1 }
        var values: [Double] = []
        var markIndex = first
        while markIndex <= last, values.count < maximumMarkCount {
            values.append(value(at: markIndex, step: step))
            markIndex += 1
        }
        return values
    }

    /// `Math.round`: to the nearest whole number, a half up toward positive infinity.
    private static func javaScriptRounded(_ number: Double) -> Double {
        (number + 0.5).rounded(.down)
    }
}

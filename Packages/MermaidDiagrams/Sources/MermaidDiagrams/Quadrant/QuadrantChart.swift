/// A Mermaid quadrant chart (`quadrantChart`) as its text describes it: the four quadrants' texts, the axes' texts at
/// their low and high ends, the points in the order they are written with their styles, and the classes of styles
/// `classDef` names.
public struct QuadrantChart: Equatable, Sendable {
    /// `title …` in the chart, else `title:` in the front matter, else nil.
    public internal(set) var title: String?
    /// The texts of quadrants 1 to 4, in that order: top right, top left, bottom left, bottom right; nil where the
    /// chart gives none.
    public internal(set) var quadrantLabels: [DiagramLabel?]
    /// `x-axis low --> high`: the text at the x axis's left end and at its right end, or nil.
    public internal(set) var xAxisLowLabel: DiagramLabel?
    public internal(set) var xAxisHighLabel: DiagramLabel?
    /// `y-axis low --> high`: the text at the y axis's bottom end and at its top end, or nil.
    public internal(set) var yAxisLowLabel: DiagramLabel?
    public internal(set) var yAxisHighLabel: DiagramLabel?
    public internal(set) var points: [QuadrantChartPoint]
    /// The styles each `classDef` gives, by class name; a later `classDef` of a name replaces an earlier one.
    public internal(set) var classStyles: [String: QuadrantChartPointStyle]
    /// `accTitle: …`, the short name a screen reader gives the chart, or nil.
    public internal(set) var accessibilityTitle: String?
    /// `accDescr: …` or `accDescr { … }`, the longer description a screen reader reads, or nil.
    public internal(set) var accessibilityDescription: String?

    /// Quadrants 1 to 4.
    public static let quadrantCount = 4

    init(title: String? = nil, quadrantLabels: [DiagramLabel?] = Array(repeating: nil, count: quadrantCount), xAxisLowLabel: DiagramLabel? = nil,
         xAxisHighLabel: DiagramLabel? = nil, yAxisLowLabel: DiagramLabel? = nil, yAxisHighLabel: DiagramLabel? = nil, points: [QuadrantChartPoint] = [],
         classStyles: [String: QuadrantChartPointStyle] = [:], accessibilityTitle: String? = nil, accessibilityDescription: String? = nil) {
        self.title = title
        self.quadrantLabels = quadrantLabels
        self.xAxisLowLabel = xAxisLowLabel
        self.xAxisHighLabel = xAxisHighLabel
        self.yAxisLowLabel = yAxisLowLabel
        self.yAxisHighLabel = yAxisHighLabel
        self.points = points
        self.classStyles = classStyles
        self.accessibilityTitle = accessibilityTitle
        self.accessibilityDescription = accessibilityDescription
    }
}

/// A point of a quadrant chart: its text, where it is, and its style.
public struct QuadrantChartPoint: Equatable, Sendable {
    public let label: DiagramLabel
    /// Where the point is from left to right and from bottom to top, as JavaScript's `Number` reads what is written
    /// (`0.75`), or nil when that is not a number. A point outside 0 to 1 on either axis is not drawn.
    public let xCoordinate: Double?
    public let yCoordinate: Double?
    /// The class after `:::` (`Point:::important: [0.1, 0.2]`), or nil.
    public let className: String?
    /// The styles written after the point, which take the place of its class's.
    public let style: QuadrantChartPointStyle

    init(label: DiagramLabel, xCoordinate: Double?, yCoordinate: Double?, className: String?, style: QuadrantChartPointStyle) {
        self.label = label
        self.xCoordinate = xCoordinate
        self.yCoordinate = yCoordinate
        self.className = className
        self.style = style
    }
}

/// The styles a point or a class may give: `radius: 10`, `color: #ff3300`, `stroke-color: #10f0f0` and
/// `stroke-width: 5px`. Each is nil where it is not written.
public struct QuadrantChartPointStyle: Equatable, Sendable {
    /// In points.
    public internal(set) var radius: Double?
    public internal(set) var color: QuadrantChartColor?
    public internal(set) var strokeColor: QuadrantChartColor?
    /// In points.
    public internal(set) var strokeWidth: Double?

    init(radius: Double? = nil, color: QuadrantChartColor? = nil, strokeColor: QuadrantChartColor? = nil, strokeWidth: Double? = nil) {
        self.radius = radius
        self.color = color
        self.strokeColor = strokeColor
        self.strokeWidth = strokeWidth
    }

    /// These styles where they are written, else `fallback`'s: a point's own styles over its class's.
    func overriding(_ fallback: QuadrantChartPointStyle?) -> QuadrantChartPointStyle {
        QuadrantChartPointStyle(radius: radius ?? fallback?.radius, color: color ?? fallback?.color, strokeColor: strokeColor ?? fallback?.strokeColor,
                                strokeWidth: strokeWidth ?? fallback?.strokeWidth)
    }
}

/// A color a quadrant chart's text gives in hexadecimal (`#ff3300`, `#f30`, with or without `#`), in sRGB components
/// from 0 to 255.
public struct QuadrantChartColor: Equatable, Sendable {
    public let red: UInt8
    public let green: UInt8
    public let blue: UInt8

    init(red: UInt8, green: UInt8, blue: UInt8) {
        self.red = red
        self.green = green
        self.blue = blue
    }
}

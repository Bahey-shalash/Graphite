/// A Mermaid pie chart (`pie`) as its text describes it: the slices in the order they are written, each label once
/// (a later slice with a label already used is left out, as in Mermaid), whether the legend shows the values, and
/// the titles.
public struct PieChart: Equatable, Sendable {
    public internal(set) var slices: [PieChartSlice]
    /// `showData` after `pie`: the legend shows each slice's value after its label.
    public internal(set) var showsValues: Bool
    /// `title …` in the chart, else `title:` in the front matter, or nil. As written, with runs of spaces made one.
    public internal(set) var title: String?
    /// `accTitle: …`, the short name a screen reader gives the chart, or nil.
    public internal(set) var accessibilityTitle: String?
    /// `accDescr: …` or `accDescr { … }`, the longer description a screen reader reads, its lines joined by line
    /// breaks, or nil.
    public internal(set) var accessibilityDescription: String?

    init(slices: [PieChartSlice] = [], showsValues: Bool = false, title: String? = nil, accessibilityTitle: String? = nil,
         accessibilityDescription: String? = nil) {
        self.slices = slices
        self.showsValues = showsValues
        self.title = title
        self.accessibilityTitle = accessibilityTitle
        self.accessibilityDescription = accessibilityDescription
    }
}

/// One slice of a pie chart: its label, read as plain lines, and its value, zero or more.
public struct PieChartSlice: Equatable, Sendable {
    public let label: DiagramLabel
    /// The value as written, never negative: a slice's share of the pie is its value over the sum of all values.
    public let value: Double

    init(label: DiagramLabel, value: Double) {
        self.label = label
        self.value = value
    }
}

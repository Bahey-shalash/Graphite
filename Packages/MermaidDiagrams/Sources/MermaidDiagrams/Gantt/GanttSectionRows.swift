import CoreGraphics

/// A Gantt chart's sections down its rows: each section's name measured, wrapped at 180 points, and the runs of rows
/// that share a section, every other section (by the order sections first have a task, in Pele's four section
/// styles) on a band of the surface color.
struct GanttSectionRows {
    /// The section of each row.
    private let rowSections: [String]
    /// Each section's place in the order sections first have a task.
    private let sectionOrder: [String: Int]
    private let names: [String: DiagramTextBlock]
    /// The width of the widest name.
    let widestName: CGFloat

    /// Pele's number of section styles, of which the even ones are shaded.
    static let sectionStyleCount = 4

    init(tasks: [GanttTask], measurer: some DiagramTextMeasuring) {
        rowSections = tasks.map(\.section)
        var order: [String: Int] = [:]
        var names: [String: DiagramTextBlock] = [:]
        for section in rowSections where order[section] == nil {
            order[section] = order.count
            names[section] = DiagramTextBlock(label: DiagramLabelDecoder.label(from: section, form: .plain), measurer: measurer,
                                              maximumWidth: GanttLayoutEngine.sectionWrappingWidth)
        }
        sectionOrder = order
        self.names = names
        widestName = names.values.map(\.size.width).max() ?? 0
    }

    /// The shaded bands, as wide as the page, and each run's name centered down it at the left.
    func bandsAndNames(top: CGFloat, rowHeight: CGFloat, pageWidth: CGFloat) -> ([CGRect], [DiagramTextBlock]) {
        var bands: [CGRect] = []
        var placedNames: [DiagramTextBlock] = []
        var row = 0
        while row < rowSections.count {
            let section = rowSections[row]
            var end = row + 1
            while end < rowSections.count, rowSections[end] == section { end += 1 }
            let band = CGRect(x: 0, y: top + CGFloat(row) * rowHeight, width: pageWidth, height: CGFloat(end - row) * rowHeight)
            let style = (sectionOrder[section] ?? 0) % Self.sectionStyleCount
            if (sectionOrder.count > 1 || !section.isEmpty), style % 2 == 0 { bands.append(band) }
            if var name = names[section], !name.lines.isEmpty {
                name.center = CGPoint(x: GanttLayoutEngine.padding + GanttLayoutEngine.sectionInset + name.size.width / 2, y: band.midY)
                placedNames.append(name)
            }
            row = end
        }
        return (bands, placedNames)
    }
}

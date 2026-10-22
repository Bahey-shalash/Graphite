/// The periods of one section, or the periods written before the first section, which lead.
struct TimelineGroup {
    let sectionIndex: Int?
    var periodIndices: [Int]

    /// One group per section, in order, after a leading group of the periods before the first section when there are any.
    static func groups(of diagram: TimelineDiagram) -> [TimelineGroup] {
        var sections = diagram.sections.indices.map { section in TimelineGroup(sectionIndex: section, periodIndices: []) }
        var leading = TimelineGroup(sectionIndex: nil, periodIndices: [])
        for (index, period) in diagram.periods.enumerated() {
            if let section = period.sectionIndex { sections[section].periodIndices.append(index) } else { leading.periodIndices.append(index) }
        }
        return leading.periodIndices.isEmpty ? sections : [leading] + sections
    }
}

import Foundation

/// The timeline inputs of the benchmark: Mermaid's 14 documentation examples, as Pele collects them, and generated
/// timelines of sections, periods and events.
enum TimelineCorpus {
    static func documentationExamples() throws -> [String] {
        guard let location = Bundle.module.url(forResource: "timeline-docs", withExtension: "json", subdirectory: "Resources") else {
            throw FlowchartCorpus.MissingResource()
        }
        return try JSONDecoder().decode([String].self, from: Data(contentsOf: location))
    }

    /// `periodCount` periods of two events each, a section every `periodsPerSection` periods, written down when `isDown`.
    static func generated(periodCount: Int, periodsPerSection: Int = 5, isDown: Bool = false) -> String {
        var source = isDown ? "timeline TD\n  title Generated\n" : "timeline\n  title Generated\n"
        for period in 0..<periodCount {
            if period.isMultiple(of: periodsPerSection) { source += "  section Part \(period / periodsPerSection + 1)\n" }
            source += "    \(1900 + period) : Event \(period) a : Event \(period) b\n"
        }
        return source
    }
}

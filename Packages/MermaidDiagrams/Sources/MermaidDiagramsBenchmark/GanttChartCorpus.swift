import Foundation

/// The Gantt charts the benchmark times: Mermaid's eleven documentation examples, as Pele's corpus collects them
/// (`tests/corpus/gantt-docs.json`), and generated charts of many tasks in sections, each after the one before it or
/// from a date, on weeks without weekends.
enum GanttChartCorpus {
    /// The moment every chart is drawn on: 2014-01-15 12:00 UTC, inside the documentation's charts.
    static let now = Date(timeIntervalSince1970: 1_389_787_200)
    static let timeZone = TimeZone(identifier: "UTC") ?? .gmt

    static func documentationExamples() throws -> [String] {
        guard let location = Bundle.module.url(forResource: "gantt-docs", withExtension: "json", subdirectory: "Resources") else {
            throw FlowchartCorpus.MissingResource()
        }
        return try JSONDecoder().decode([String].self, from: Data(contentsOf: location))
    }

    /// A chart of `taskCount` tasks in sections of ten, with durations from the same linear congruential generator and
    /// seed as `FlowchartCorpus.mesh`: every fourth task starts on a date, the others after the task before them.
    static func chart(taskCount: Int) -> String {
        var seed: UInt32 = 7
        var source = "gantt\n    title Generated plan\n    dateFormat YYYY-MM-DD\n    excludes weekends\n"
        for task in 0..<taskCount {
            if task % 10 == 0 { source += "    section Phase \(task / 10 + 1)\n" }
            seed = seed &* 1_664_525 &+ 1_013_904_223
            let days = 1 + Int(Double(seed) / 4_294_967_296 * 9)
            let start = task % 4 == 0 ? "2014-01-\(String(format: "%02d", 1 + task % 28))" : "after t\(task - 1)"
            let tag = task % 7 == 0 ? "crit, " : (task % 5 == 0 ? "done, " : "")
            source += "    Task \(task) : \(tag)t\(task), \(start), \(days)d\n"
        }
        return source
    }
}

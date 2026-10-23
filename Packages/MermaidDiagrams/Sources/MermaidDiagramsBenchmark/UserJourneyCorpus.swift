import Foundation

/// The user journeys the benchmark times: Mermaid's documentation example, as Pele's corpus collects it
/// (`tests/corpus/journey-docs.json`), and generated journeys of sections, tasks and actors.
enum UserJourneyCorpus {
    static func documentationExamples() throws -> [String] {
        guard let location = Bundle.module.url(forResource: "journey-docs", withExtension: "json", subdirectory: "Resources") else {
            throw FlowchartCorpus.MissingResource()
        }
        return try JSONDecoder().decode([String].self, from: Data(contentsOf: location))
    }

    /// The actors the generated journeys name, a task taking one to three of them in turn.
    private static let actorNames = ["Ana", "Ben", "Chloé", "Dev", "Eli"]

    /// `taskCount` tasks with scores from 1 to 5 in turn and one to three actors each, a section every
    /// `tasksPerSection` tasks.
    static func generated(taskCount: Int, tasksPerSection: Int = 5) -> String {
        var source = "journey\n  title Generated journey\n"
        for task in 0..<taskCount {
            if task.isMultiple(of: tasksPerSection) { source += "  section Stage \(task / tasksPerSection + 1)\n" }
            let actors = (0...(task % 3)).map { offset in actorNames[(task + offset) % actorNames.count] }
            source += "    Step \(task + 1): \(task % 5 + 1): \(actors.joined(separator: ", "))\n"
        }
        return source
    }
}

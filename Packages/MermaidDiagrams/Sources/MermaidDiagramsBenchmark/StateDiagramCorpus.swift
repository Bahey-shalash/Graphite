import Foundation

/// State diagrams to read, lay out and time: Mermaid's 22 documentation examples, as Pele collects them, and
/// machines generated as Pele's benchmark generates its meshes.
enum StateDiagramCorpus {
    /// The first documentation example: five states, one start and one end, six transitions.
    static var firstDocumentationExample: String {
        get throws { try documentationExamples()[0] }
    }

    static func documentationExamples() throws -> [String] {
        guard let location = Bundle.module.url(forResource: "state-docs", withExtension: "json", subdirectory: "Resources") else {
            throw FlowchartCorpus.MissingResource()
        }
        return try JSONDecoder().decode([String].self, from: Data(contentsOf: location))
    }

    /// A machine of `stateCount` states: a start, each state reached from a random earlier one, `extraTransitionCount`
    /// labelled transitions between random states, and an end after the last, from the linear congruential generator
    /// and seed of Pele's `mesh`.
    static func machine(stateCount: Int, extraTransitionCount: Int) -> String {
        var seed: UInt32 = 7
        func random() -> Double {
            seed = seed &* 1_664_525 &+ 1_013_904_223
            return Double(seed) / 4_294_967_296
        }
        var source = "stateDiagram-v2\n  [*] --> s0\n"
        for state in 1..<stateCount { source += "  s\(Int(random() * Double(state))) --> s\(state)\n" }
        for transition in 0..<extraTransitionCount {
            source += "  s\(Int(random() * Double(stateCount))) --> s\(Int(random() * Double(stateCount))) : event \(transition)\n"
        }
        return source + "  s\(stateCount - 1) --> [*]\n"
    }
}

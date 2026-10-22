import Foundation

/// The sequence diagrams the benchmark measures: Mermaid's 38 sequence diagram documentation examples, as Pele
/// collects them (`tests/corpus/sequence-docs.json`), and a long conversation generated the way Pele generates its
/// flowchart meshes.
enum SequenceCorpus {
    static func documentationExamples() throws -> [String] {
        guard let location = Bundle.module.url(forResource: "sequence-docs", withExtension: "json", subdirectory: "Resources") else {
            throw FlowchartCorpus.MissingResource()
        }
        return try JSONDecoder().decode([String].self, from: Data(contentsOf: location))
    }

    /// `messageCount` numbered messages between random participants of `participantCount` (the same linear
    /// congruential generator and seed as Pele's meshes), a note over each tenth message's two participants, and every
    /// twenty messages in a loop of their own.
    static func conversation(participantCount: Int, messageCount: Int) -> String {
        var seed: UInt32 = 7
        func randomParticipant() -> Int {
            seed = seed &* 1_664_525 &+ 1_013_904_223
            return Int(Double(seed) / 4_294_967_296 * Double(participantCount))
        }
        let loopLength = 20
        let noteInterval = 10
        var text = "sequenceDiagram\n  autonumber\n"
        for index in 0..<participantCount { text += "  participant p\(index) as Participant \(index)\n" }
        for message in 0..<messageCount {
            if message % loopLength == 0 { text += "  loop round \(message / loopLength)\n" }
            let sender = randomParticipant()
            let receiver = randomParticipant()
            text += "  p\(sender)\(message % 2 == 0 ? "->>" : "-->>")p\(receiver): message \(message)\n"
            if message % noteInterval == 0 { text += "  Note over p\(sender),p\(receiver): note \(message)\n" }
            if message % loopLength == loopLength - 1 || message == messageCount - 1 { text += "  end\n" }
        }
        return text
    }
}

import Foundation

/// The inputs of Pele's sequence benchmark: Mermaid's 38 sequence diagram documentation examples, as Pele collects
/// them (`tests/corpus/sequence-docs.json`).
enum SequenceCorpus {
    static func documentationExamples() throws -> [String] {
        guard let location = Bundle.module.url(forResource: "sequence-docs", withExtension: "json", subdirectory: "Resources") else {
            throw FlowchartCorpus.MissingResource()
        }
        return try JSONDecoder().decode([String].self, from: Data(contentsOf: location))
    }
}

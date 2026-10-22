import Foundation

/// State diagrams to read, lay out and time: Mermaid's 22 documentation examples, as Pele collects them.
enum StateDiagramCorpus {
    static func documentationExamples() throws -> [String] {
        guard let location = Bundle.module.url(forResource: "state-docs", withExtension: "json", subdirectory: "Resources") else {
            throw FlowchartCorpus.MissingResource()
        }
        return try JSONDecoder().decode([String].self, from: Data(contentsOf: location))
    }
}

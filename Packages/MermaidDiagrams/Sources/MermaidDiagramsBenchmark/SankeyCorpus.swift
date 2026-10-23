import Foundation

/// The Sankey diagram inputs of the benchmark and the tests: Mermaid's 8 documentation examples, as Pele collects them
/// (`tests/corpus/sankey-docs.json`), and the energy flows Mermaid 12.1.0's `sankey.spec.ts` reads (`energy.csv`, with
/// its comment lines, blank lines and quoted fields, in Pele's `tests/compat/sankey`).
enum SankeyCorpus {
    static func documentationExamples() throws -> [String] {
        guard let location = Bundle.module.url(forResource: "sankey-docs", withExtension: "json", subdirectory: "Resources") else {
            throw FlowchartCorpus.MissingResource()
        }
        return try JSONDecoder().decode([String].self, from: Data(contentsOf: location))
    }

    /// The rows of `energy.csv`, which the spec puts after `sankey-beta` or `sankey`, a blank line and a space.
    static func energyRows() throws -> String {
        guard let location = Bundle.module.url(forResource: "sankey-energy", withExtension: "csv", subdirectory: "Resources") else {
            throw FlowchartCorpus.MissingResource()
        }
        return try String(contentsOf: location, encoding: .utf8)
    }
}

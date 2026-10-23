import Foundation

/// The Sankey diagram inputs of the benchmark and the tests: Mermaid's 8 documentation examples, as Pele collects them
/// (`tests/corpus/sankey-docs.json`), the energy flows Mermaid 12.1.0's `sankey.spec.ts` reads (`energy.csv`, with
/// its comment lines, blank lines and quoted fields, in Pele's `tests/compat/sankey`), and flows generated in layers
/// with the seed of Pele's generated graphs.
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

    /// Flows through `layerCount` layers of `nodesPerLayer` nodes: each node of a layer flows into two nodes of the next,
    /// chosen and valued from 1 to 99 by the same linear congruential generator and seed as `FlowchartCorpus.mesh`.
    static func generated(layerCount: Int, nodesPerLayer: Int) -> String {
        var seed: UInt32 = 7
        func next(below bound: Int) -> Int {
            seed = seed &* 1_664_525 &+ 1_013_904_223
            return Int(Double(seed) / 4_294_967_296 * Double(bound))
        }
        var source = "sankey\n"
        for layer in 0..<(layerCount - 1) {
            for node in 0..<nodesPerLayer {
                let first = next(below: nodesPerLayer)
                let second = (first + 1 + next(below: nodesPerLayer - 1)) % nodesPerLayer
                for target in [first, second] { source += "L\(layer) N\(node),L\(layer + 1) N\(target),\(1 + next(below: 99))\n" }
            }
        }
        return source
    }
}

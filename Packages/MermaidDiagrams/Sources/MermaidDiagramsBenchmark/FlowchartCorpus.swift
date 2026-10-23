import Foundation

/// The inputs of Pele's flowchart benchmark (`scripts/bench.mjs`): Mermaid's 114 documentation examples, and trees
/// and meshes generated the way Pele generates them, with the same seed.
enum FlowchartCorpus {
    /// The 7-node flowchart of Pele's comparison with Mermaid (`scripts/bench-mermaid.mjs`).
    static let sevenNodeFlowchart = """
    flowchart TD
      A[Start] --> B{Is it working?}
      B -->|Yes| C[Ship it]
      B -->|No| D[Debug]
      D --> E[Fix]
      E --> B
      C --> F[Celebrate]
      F --> G[Done]
    """

    static func documentationExamples() throws -> [String] {
        guard let location = Bundle.module.url(forResource: "flowchart-docs", withExtension: "json", subdirectory: "Resources") else {
            throw MissingResource()
        }
        return try JSONDecoder().decode([String].self, from: Data(contentsOf: location))
    }

    /// `chain(n, fan)` of Pele's benchmark: each node's parent is the one `fan` places before it, as a tree.
    static func tree(nodeCount: Int, fan: Int = 3) -> String {
        var source = "flowchart TD\n"
        for node in 1..<nodeCount {
            let parent = (node - 1) / fan
            source += "  n\(parent)[Node \(parent)] --> n\(node)[Node \(node)]\n"
        }
        return source
    }

    /// `mesh(n, extra)` of Pele's benchmark: a random tree and `extraEdgeCount` labelled edges between random
    /// nodes, from the same linear congruential generator and seed.
    static func mesh(nodeCount: Int, extraEdgeCount: Int) -> String {
        var seed: UInt32 = 7
        func random() -> Double {
            seed = seed &* 1_664_525 &+ 1_013_904_223
            return Double(seed) / 4_294_967_296
        }
        var source = "flowchart TD\n"
        for node in 1..<nodeCount { source += "  n\(Int(random() * Double(node))) --> n\(node)\n" }
        for edge in 0..<extraEdgeCount { source += "  n\(Int(random() * Double(nodeCount))) -->|label \(edge)| n\(Int(random() * Double(nodeCount)))\n" }
        return source
    }

    /// Groups in boxes, for the cluster layout: `pairCount` pairs of groups, the second of each pair inside the first,
    /// each group a chain of `nodesPerGroup` nodes; an edge from each group's last node to the next group's first, which
    /// crosses the borders between them, and an edge from each pair's outer group itself to the next pair's.
    static func groups(pairCount: Int, nodesPerGroup: Int) -> String {
        func chain(_ group: String) -> String {
            (0..<(nodesPerGroup - 1)).map { node in "    \(group)n\(node)[Node \(node)] --> \(group)n\(node + 1)[Node \(node + 1)]\n" }.joined()
        }
        var source = "flowchart TD\n"
        for pair in 0..<pairCount {
            source += "  subgraph outer\(pair) [Outer \(pair)]\n" + chain("outer\(pair)")
            source += "  subgraph inner\(pair) [Inner \(pair)]\n" + chain("inner\(pair)") + "  end\n  end\n"
            source += "  outer\(pair)n\(nodesPerGroup - 1) --> inner\(pair)n0\n"
            if pair > 0 {
                source += "  inner\(pair - 1)n\(nodesPerGroup - 1) --> outer\(pair)n0\n  outer\(pair - 1) --> outer\(pair)\n"
            }
        }
        return source
    }

    /// The documentation examples are not in the module's resources.
    struct MissingResource: Error {}
}

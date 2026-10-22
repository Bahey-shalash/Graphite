import Foundation

/// The mindmap inputs of the benchmark: Mermaid's 13 documentation examples, as Pele collects them, and generated
/// trees in the shape of Pele's flowchart trees.
enum MindmapCorpus {
    static func documentationExamples() throws -> [String] {
        guard let location = Bundle.module.url(forResource: "mindmap-docs", withExtension: "json", subdirectory: "Resources") else {
            throw FlowchartCorpus.MissingResource()
        }
        return try JSONDecoder().decode([String].self, from: Data(contentsOf: location))
    }

    /// A mindmap of `nodeCount` nodes in which each node's parent is the one `fan` places before it, as Pele's
    /// generated flowchart trees: each node written under its parent, indented two spaces a level.
    static func tree(nodeCount: Int, fan: Int = 3) -> String {
        var childrenByNode = [[Int]](repeating: [], count: nodeCount)
        for node in 1..<max(nodeCount, 1) { childrenByNode[(node - 1) / fan].append(node) }
        var source = "mindmap\n"
        var pending: [(node: Int, depth: Int)] = nodeCount > 0 ? [(0, 1)] : []
        while let (node, depth) = pending.popLast() {
            source += String(repeating: "  ", count: depth) + "Node \(node)\n"
            for child in childrenByNode[node].reversed() { pending.append((child, depth + 1)) }
        }
        return source
    }
}

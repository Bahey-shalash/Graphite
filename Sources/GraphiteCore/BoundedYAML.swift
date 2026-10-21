import Foundation
import Yams

/// Loads note frontmatter with bounded work. YAML aliases repeat a node wherever they
/// appear, so a few hundred bytes of nested aliases ("billion laughs") expand to millions
/// of values and hang indexing. Composing the node tree shares aliased nodes; counting the
/// expanded tree stops at the budget, and only a document within it becomes values.
enum BoundedYAML {
    /// Without aliases every node takes at least one byte of YAML, so the byte count
    /// bounds a plain document; the allowance leaves room for ordinary alias reuse.
    private static let aliasExpansionAllowance = 10_000

    static func load(_ yaml: String) -> Any? {
        guard !YAMLNesting.exceedsSafeDepth(yaml), !YAMLAliasExpansion.exceedsAnchorCount(yaml), let root = try? Yams.compose(yaml: yaml),
              !YAMLAliasExpansion.exceedsLimits(root, sourceByteCount: yaml.utf8.count),
              isWithinExpansionBudget(root, yamlByteCount: yaml.utf8.count) else { return nil }
        return root.any
    }

    /// Whether `root`, with every alias expanded, stays within the node budget for YAML of
    /// `yamlByteCount` bytes. Code that converts or serializes a composed node tree checks
    /// this first, because both expand aliases.
    static func isWithinExpansionBudget(_ root: Node, yamlByteCount: Int) -> Bool {
        let maximumNodeCount = yamlByteCount + aliasExpansionAllowance
        // Nodes are counted when found rather than when visited, so the pending list
        // never holds more than the budget either.
        var nodeCount = 1
        var pendingNodes = [root]
        while let node = pendingNodes.popLast() {
            switch node {
            case .mapping(let mapping):
                nodeCount += 2 * mapping.count
                guard nodeCount <= maximumNodeCount else { return false }
                for (key, value) in mapping { pendingNodes.append(key); pendingNodes.append(value) }
            case .sequence(let sequence):
                nodeCount += sequence.count
                guard nodeCount <= maximumNodeCount else { return false }
                pendingNodes.append(contentsOf: sequence)
            case .scalar, .alias:
                break
            }
        }
        return true
    }
}

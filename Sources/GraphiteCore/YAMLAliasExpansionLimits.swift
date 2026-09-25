import Foundation
import Yams

/// A YAML alias (`*name`) repeats the node anchored as `&name`. Yams resolves aliases
/// while composing and the copies share storage, so a few hundred bytes of anchors that
/// each repeat the previous one ten times stand for millions of nodes ("billion
/// laughs"), and a chain of anchors that each hold the previous one builds a tree far
/// deeper than its text, which `YAMLNesting` cannot see.
///
/// Two checks bound this. Before composing, `exceedsAnchorCount` limits the anchors,
/// since releasing a composed tree is recursive: a chain about 1,800 levels deep
/// crashed on the 512 KB stack of a Swift concurrency thread when the tree was freed
/// (Sep 2026, debug build). After composing, `exceedsLimits` refuses a tree whose
/// expansion is out of proportion to its text or deeper than text within
/// `YAMLNesting`'s limits can nest, before any walk over it (converting frontmatter,
/// reading a base's filters, writing a base back) pays for the expansion.
public enum YAMLAliasExpansion {
    /// The deepest composed tree allowed to exist, with a wide margin under the
    /// measured crash.
    static let maximumComposedDepth = 1_000
    /// An alias can only repeat an anchor completed before it, so a chain has at most
    /// one link per anchor, and each link nests at most `maximumDepth` levels.
    public static var maximumAnchorCount: Int { maximumComposedDepth / maximumDepth - 1 }

    /// Whether the YAML may define more than `maximumAnchorCount` anchors. It counts
    /// `&` where a node can start (after a line break, whitespace, `[`, `{`, `,` or `:`)
    /// and a name follows. Text that only looks like an anchor can make it count too
    /// many, never too few, so quoted text is counted too: a quote inside plain text
    /// (`[x "y, &a [*b]]`) reads like the start of a quoted scalar, and skipping from it
    /// would miss real anchors. A comment is skipped only on a line without quotes,
    /// where its `#` cannot be inside a quoted scalar that ends before an anchor.
    public static func exceedsAnchorCount(_ yaml: String) -> Bool {
        let lineBreaks: Set<Unicode.Scalar> = ["\n", "\r", "\u{85}", "\u{2028}", "\u{2029}"]
        let charactersBeforeNodeStart: Set<Unicode.Scalar> = [" ", "\t", "[", "{", ",", ":", "\u{FEFF}"]
        var anchorCount = 0
        var lineHasQuote = false
        var previous: Unicode.Scalar = "\n"
        var isInComment = false
        let scalars = Array(yaml.unicodeScalars)
        for (scalarIndex, scalar) in scalars.enumerated() {
            defer { previous = scalar }
            if lineBreaks.contains(scalar) {
                isInComment = false
                lineHasQuote = false
                continue
            }
            if isInComment { continue }
            if lineBreaks.contains(previous) {
                lineHasQuote = scalars[scalarIndex...].prefix { lineScalar in !lineBreaks.contains(lineScalar) }.contains { lineScalar in lineScalar == "\"" || lineScalar == "'" }
            }
            if scalar == "#", !lineHasQuote, previous == " " || previous == "\t" || lineBreaks.contains(previous) {
                isInComment = true
            } else if scalar == "&", lineBreaks.contains(previous) || charactersBeforeNodeStart.contains(previous),
                      scalarIndex + 1 < scalars.count, !" \t&".unicodeScalars.contains(scalars[scalarIndex + 1]), !lineBreaks.contains(scalars[scalarIndex + 1]) {
                anchorCount += 1
                if anchorCount > maximumAnchorCount { return true }
            }
        }
        return false
    }

    /// Without aliases, every node and every byte of scalar text comes from at least
    /// one source byte, so the weight below stays under twice the source size (escapes
    /// such as `\L` decode to three bytes from two). Only repeated aliases reach this.
    static let expandedWeightPerSourceByte = 4
    /// Room for small documents that repeat a few anchors on purpose.
    static let minimumExpandedWeight = 65_536
    /// Each column of block indentation and each flow bracket can open one level, plus
    /// the document's root and a leaf value. The editor's tests parse and write a base
    /// this deep on the 512 KB stack of a Swift concurrency thread.
    public static var maximumDepth: Int { YAMLNesting.maximumBlockIndentation + YAMLNesting.maximumFlowDepth + 2 }

    /// Whether the tree, with every alias expanded, holds more nodes and scalar text
    /// than `sourceByteCount` bytes of YAML can write out, or nests deeper than
    /// `maximumDepth`. The walk stops as soon as a limit is passed, so a hostile tree
    /// costs no more than the limit.
    public static func exceedsLimits(_ rootNode: Node, sourceByteCount: Int) -> Bool {
        let maximumWeight = minimumExpandedWeight + expandedWeightPerSourceByte * max(sourceByteCount, 0)
        var weight = 0
        // An explicit stack: the tree may be deeper than the thread's stack allows to recurse.
        var pendingNodes: [(node: Node, depth: Int)] = [(rootNode, 1)]
        while let (node, depth) = pendingNodes.popLast() {
            guard depth <= maximumDepth else { return true }
            weight += 1
            switch node {
            case .scalar(let scalar):
                weight += scalar.string.utf8.count
            case .sequence(let sequence):
                pendingNodes.append(contentsOf: sequence.map { itemNode in (itemNode, depth + 1) })
            case .mapping(let mapping):
                for (keyNode, valueNode) in mapping {
                    pendingNodes.append((keyNode, depth + 1))
                    pendingNodes.append((valueNode, depth + 1))
                }
            case .alias:
                // Composing resolves every alias to its anchored node; an unresolved one has no content.
                break
            }
            if weight > maximumWeight { return true }
        }
        return false
    }
}


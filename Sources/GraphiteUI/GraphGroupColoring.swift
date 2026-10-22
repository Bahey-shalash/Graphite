import SwiftUI
import GraphiteCore

/// The colors a vault's groups give a graph: each group's color, in the groups' order, and
/// the group that colors each file, by the file's identifier.
struct GraphGroupColoring: Equatable {
    /// Each group's color; nil for a group whose stored color Graphite cannot read.
    private(set) var colors: [Color?] = []
    private(set) var groupIndexByIdentifier: [String: Int] = [:]

    init() {}

    /// How `groups` color the files of `vaultGraph`, the whole vault's graph, so that a
    /// group's `tag:` words match while the filters hide tags.
    init(groups: [GraphColorGroup], vaultGraph: LinkGraph) {
        colors = groups.map { group in group.colorHex.flatMap(Color.init(graphiteHex:)) }
        groupIndexByIdentifier = vaultGraph.colorGroupIndexes(for: groups.map(\.query))
    }

    /// The color of a group by its index, as `GraphCanvasModel.groupIndexes` gives it.
    func color(ofGroup groupIndex: Int) -> Color? {
        colors.indices.contains(groupIndex) ? colors[groupIndex] : nil
    }
}

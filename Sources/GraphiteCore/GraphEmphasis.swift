import Foundation

/// Which nodes of a graph stand out while one is focused (under the finger or the pointer,
/// dragged, or a chosen tag), as in Obsidian: the focused node and its neighbors stay bright
/// and the rest steps back. It also says whose names are placed first.
public struct GraphEmphasis {
    public let focusedIndex: Int?
    /// The note open in the editor.
    public let openIndex: Int?
    /// Each node's neighbors, by index.
    private let neighborIndexes: [Set<Int>]

    public init(focusedIndex: Int?, openIndex: Int?, neighborIndexes: [Set<Int>]) {
        self.focusedIndex = focusedIndex
        self.openIndex = openIndex
        self.neighborIndexes = neighborIndexes
    }

    public func isNeighborOfFocused(_ index: Int) -> Bool {
        guard let focusedIndex, neighborIndexes.indices.contains(focusedIndex) else { return false }
        return neighborIndexes[focusedIndex].contains(index)
    }

    /// Whether a node steps back because another is focused and it is not one of its neighbors.
    public func isDimmed(_ index: Int) -> Bool {
        focusedIndex != nil && focusedIndex != index && !isNeighborOfFocused(index)
    }

    /// Whether a node is drawn in the accent color: the open note and the focused node.
    public func isAccented(_ index: Int) -> Bool {
        index == openIndex || index == focusedIndex
    }

    /// Whether a link is one of the focused node's, drawn in the accent.
    public func isFocusedLink(source: Int, target: Int) -> Bool {
        focusedIndex != nil && (source == focusedIndex || target == focusedIndex)
    }

    /// How early a node's name is placed (`GraphNamePlacement`): the open note's (3), then
    /// the focused node's (2), then its neighbors' (1), then the others' (0). Names of
    /// importance above 0 are drawn whole at any zoom.
    public func nameImportance(ofNodeAt index: Int) -> Int {
        if index == openIndex { return 3 }
        if index == focusedIndex { return 2 }
        return isNeighborOfFocused(index) ? 1 : 0
    }
}

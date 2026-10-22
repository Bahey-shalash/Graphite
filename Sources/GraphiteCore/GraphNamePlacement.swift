import Foundation

/// Which names the graph draws so that none covers another: the most important names are
/// placed first, and a name that would cover one already placed is left out at this zoom,
/// coming back as the person zooms in and the nodes move apart. A grid of cells finds the
/// names near each one, so the work grows with the names on screen, not with their square.
public enum GraphNamePlacement {
    public struct Candidate: Equatable, Sendable {
        public var nodeIndex: Int
        /// Where the name would be drawn, in points, with the room it keeps around it.
        public var frame: CGRect
        /// A name is placed before every name of lower importance: the open note's, then the
        /// focused node's, then its neighbors', then the others.
        public var importance: Int
        /// Among names of one importance, the larger node's is placed first.
        public var nodeRadius: Double

        public init(nodeIndex: Int, frame: CGRect, importance: Int, nodeRadius: Double) {
            self.nodeIndex = nodeIndex
            self.frame = frame
            self.importance = importance
            self.nodeRadius = nodeRadius
        }
    }

    /// The side of the grid's cells, in points: about a short name's width, so that a name
    /// covers a few cells.
    static let cellSidePoints = 80.0

    /// The node indexes of the names to draw, in the order they were placed.
    public static func placedNames(_ candidates: [Candidate]) -> [Int] {
        let ordered = candidates.filter { candidate in candidate.frame.isFinite }.sorted { first, second in
            if first.importance != second.importance { return first.importance > second.importance }
            if first.nodeRadius != second.nodeRadius { return first.nodeRadius > second.nodeRadius }
            return first.nodeIndex < second.nodeIndex
        }
        var framesByCell: [SIMD2<Int>: [CGRect]] = [:]
        var placed: [Int] = []
        for candidate in ordered {
            let cells = cells(covering: candidate.frame)
            let coversAPlacedName = cells.contains { cell in
                framesByCell[cell]?.contains { placedFrame in placedFrame.intersects(candidate.frame) } ?? false
            }
            guard !coversAPlacedName else { continue }
            for cell in cells { framesByCell[cell, default: []].append(candidate.frame) }
            placed.append(candidate.nodeIndex)
        }
        return placed
    }

    private static func cells(covering frame: CGRect) -> [SIMD2<Int>] {
        let firstColumn = Int((frame.minX / cellSidePoints).rounded(.down)), lastColumn = Int((frame.maxX / cellSidePoints).rounded(.down))
        let firstRow = Int((frame.minY / cellSidePoints).rounded(.down)), lastRow = Int((frame.maxY / cellSidePoints).rounded(.down))
        var cells: [SIMD2<Int>] = []
        cells.reserveCapacity((lastColumn - firstColumn + 1) * (lastRow - firstRow + 1))
        for column in firstColumn...lastColumn {
            for row in firstRow...lastRow { cells.append(SIMD2(column, row)) }
        }
        return cells
    }
}

private extension CGRect {
    /// Whether every edge is a finite number, so the grid can hold it.
    var isFinite: Bool { minX.isFinite && minY.isFinite && maxX.isFinite && maxY.isFinite && !isNull }
}

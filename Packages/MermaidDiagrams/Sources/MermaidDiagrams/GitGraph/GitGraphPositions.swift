import CoreGraphics

/// Where a Git graph's commits stand along the history and its lanes across it, before the page is placed around
/// them: commits one after another in the order they were made, each a step or the room it and its neighbour need
/// after the last, and lanes as far apart as their content needs, at least a lane's gap.
struct GitGraphPositions {
    /// Each commit's place along the history, the first at 0.
    let along: [CGFloat]
    /// Each lane's place across the history, the first at 0.
    let across: [CGFloat]
    /// The place of the last commit along the history, 0 without commits.
    var lastAlong: CGFloat { along.last ?? 0 }
    /// Each lane's commits' places along the history, in increasing order.
    private let alongByLane: [[CGFloat]]

    init(diagram: GitGraphDiagram, room: GitGraphRoom) {
        var along: [CGFloat] = []
        for index in diagram.commits.indices {
            guard let previous = along.last else {
                along.append(0)
                continue
            }
            let halfLengths = room.halfLengths[index - 1] + room.halfLengths[index]
            let lead = room.tagLeads[index]
            let step = max(GitGraphGeometry.commitStep, halfLengths + GitGraphGeometry.gap,
                           lead > 0 ? room.halfLengths[index - 1] + GitGraphGeometry.curveLength + lead : 0)
            along.append(previous + step)
        }
        var across: [CGFloat] = []
        for lane in diagram.branches.indices {
            guard let previous = across.last else {
                across.append(0)
                continue
            }
            across.append(previous + max(GitGraphGeometry.laneGap, room.laneReachAfter[lane - 1] + room.laneReachBefore[lane] + GitGraphGeometry.gap))
        }
        var alongByLane = diagram.branches.map { _ in [CGFloat]() }
        for (index, commit) in diagram.commits.enumerated() { alongByLane[commit.branchIndex].append(along[index]) }
        self.along = along
        self.across = across
        self.alongByLane = alongByLane
    }

    /// Whether a commit of `lane` stands strictly between `start` and `end` along the history, where a connector
    /// running along the lane would cross it.
    func isOccupied(lane: Int, after start: CGFloat, before end: CGFloat) -> Bool {
        let places = alongByLane[lane]
        var low = 0
        var high = places.count
        while low < high {
            let middle = (low + high) / 2
            if places[middle] <= start { low = middle + 1 } else { high = middle }
        }
        return low < places.count && places[low] < end
    }
}

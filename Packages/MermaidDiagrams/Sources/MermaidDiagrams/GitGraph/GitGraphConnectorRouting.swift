import CoreGraphics

/// The lines from each commit's parents to it, routed as Pele routes them: straight along a lane; between lanes, an
/// S-curve that leaves the parent at once and runs along the commit's lane when that lane is free; else one that runs
/// along the parent's lane (a merge's, when its lane is free) or along the empty strip beside the commit's lane, and
/// turns in just before the commit, or before its tags when it comes from their side.
struct GitGraphConnectorRouting {
    let diagram: GitGraphDiagram
    let room: GitGraphRoom
    let positions: GitGraphPositions
    let geometry: GitGraphGeometry

    /// Every commit's connectors, commit by commit and parent by parent, in diagram space.
    func connectors() -> [GitGraphLayoutConnector] {
        var connectors: [GitGraphLayoutConnector] = []
        for (index, commit) in diagram.commits.enumerated() {
            for (parentPlace, parent) in commit.parentIndices.enumerated() {
                connectors.append(connector(from: parent, to: index, isSecondParent: parentPlace > 0))
            }
        }
        return connectors
    }

    private func connector(from parent: Int, to child: Int, isSecondParent: Bool) -> GitGraphLayoutConnector {
        let parentLane = diagram.commits[parent].branchIndex
        let lane = diagram.commits[child].branchIndex
        let start = (along: positions.along[parent], across: positions.across[parentLane])
        let end = (along: positions.along[child], across: positions.across[lane])
        guard parentLane != lane else {
            let line = DiagramPath(start: point(start.along, start.across), segments: [.line(to: point(end.along, end.across))])
            return GitGraphLayoutConnector(path: line, laneIndex: lane, style: .alongLane)
        }
        let isMerge = isSecondParent && diagram.commits[child].kind == .merge
        let path = route(from: start, to: end, parentLane: parentLane, lane: lane, tagLead: room.tagLeads[child], isMerge: isMerge)
        return GitGraphLayoutConnector(path: path, laneIndex: isMerge ? parentLane : lane, style: isSecondParent && !isMerge ? .cherryPick : .acrossLanes)
    }

    /// A route between two lanes, from a parent earlier along the history than the commit.
    private func route(from start: (along: CGFloat, across: CGFloat), to end: (along: CGFloat, across: CGFloat), parentLane: Int, lane: Int,
                       tagLead: CGFloat, isMerge: Bool) -> DiagramPath {
        var segments: [DiagramPathSegment] = []
        if !isMerge, !positions.isOccupied(lane: lane, after: start.along, before: end.along) {
            let curve = min(GitGraphGeometry.curveLength, end.along - start.along)
            segments.append(turn(at: start.along, length: curve, from: start.across, to: end.across))
            segments.append(.line(to: point(end.along, end.across)))
            return DiagramPath(start: point(start.along, start.across), segments: segments)
        }
        let turnEnd = parentLane < lane && end.along - tagLead > start.along ? end.along - tagLead : end.along
        var curve = min(GitGraphGeometry.curveLength, turnEnd - start.along)
        var runAcross = start.across
        if !isMerge || positions.isOccupied(lane: parentLane, after: start.along, before: end.along) {
            // Neither lane is free to run along: the strip beside the commit's lane, past one lane's ids and before
            // the next one's tags, stays empty.
            runAcross = start.across > end.across ? end.across + room.laneReachAfter[lane] + GitGraphGeometry.gap / 2
                : end.across - room.laneReachBefore[lane] - GitGraphGeometry.gap / 2
            curve = min(GitGraphGeometry.curveLength, (turnEnd - start.along) / 2)
            segments.append(turn(at: start.along, length: curve, from: start.across, to: runAcross))
        }
        segments.append(.line(to: point(turnEnd - curve, runAcross)))
        segments.append(turn(at: turnEnd - curve, length: curve, from: runAcross, to: end.across))
        if turnEnd < end.along { segments.append(.line(to: point(end.along, end.across))) }
        return DiagramPath(start: point(start.along, start.across), segments: segments)
    }

    /// An S-curve from `start` along the history to `start + length`, across from `from` to `to`, its controls halfway along.
    private func turn(at start: CGFloat, length: CGFloat, from: CGFloat, to: CGFloat) -> DiagramPathSegment {
        let middle = start + length / 2
        return .curve(to: point(start + length, to), control1: point(middle, from), control2: point(middle, to))
    }

    private func point(_ along: CGFloat, _ across: CGFloat) -> CGPoint {
        geometry.point(along: along, across: across)
    }
}

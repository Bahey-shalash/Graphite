import CoreGraphics

/// Places a Git graph's lanes, commits, ids and tags in diagram space as Pele does, and the rectangle they cover. A
/// lane runs from before the first commit to past the last, its name's box at its start; a commit's id is turned an
/// eighth of a turn from a corner beside its dot (below in a horizontal graph, left in a vertical one, the text
/// trailing back the way the history came); its tags stack above it, the first furthest out, or stand in a row to
/// its right.
struct GitGraphPlacement {
    private(set) var lanes: [GitGraphLayoutLane] = []
    private(set) var commits: [GitGraphLayoutCommit] = []
    /// What everything placed covers, connectors excepted, which run inside it.
    private(set) var bounds = CGRect.null

    init(diagram: GitGraphDiagram, room: GitGraphRoom, positions: GitGraphPositions, geometry: GitGraphGeometry) {
        for (lane, name) in room.names.enumerated() {
            placeLane(name: name, across: positions.across[lane], lastAlong: positions.lastAlong, geometry: geometry)
        }
        for (index, commit) in diagram.commits.enumerated() {
            let center = geometry.point(along: positions.along[index], across: positions.across[commit.branchIndex])
            let dotReach = GitGraphGeometry.dotRadius + 1
            include(CGRect(x: center.x - dotReach, y: center.y - dotReach, width: 2 * dotReach, height: 2 * dotReach))
            commits.append(GitGraphLayoutCommit(center: center, laneIndex: commit.branchIndex, symbol: Self.symbol(of: commit),
                                                label: room.labels[index].map { label in placedLabel(label, beside: center, direction: geometry.direction) },
                                                tags: placedTags(room.tags[index], beside: center, isVertical: geometry.isVertical)))
        }
        if bounds.isNull { bounds = .zero }
    }

    private mutating func placeLane(name: DiagramTextBlock, across: CGFloat, lastAlong: CGFloat, geometry: GitGraphGeometry) {
        let lineStart = geometry.point(along: -GitGraphGeometry.laneLead, across: across)
        let lineEnd = geometry.point(along: lastAlong + GitGraphGeometry.laneTail, across: across)
        include(CGRect(origin: lineStart, size: .zero))
        include(CGRect(origin: lineEnd, size: .zero))
        guard !name.lines.isEmpty else {
            lanes.append(GitGraphLayoutLane(lineStart: lineStart, lineEnd: lineEnd, nameFrame: nil, name: nil))
            return
        }
        let boxSize = CGSize(width: name.size.width + GitGraphGeometry.nameBoxPadding.width, height: name.size.height + GitGraphGeometry.nameBoxPadding.height)
        let boxLength = geometry.isVertical ? boxSize.height : boxSize.width
        let boxCenter = geometry.point(along: -GitGraphGeometry.laneLead - boxLength / 2, across: across)
        let frame = CGRect(x: boxCenter.x - boxSize.width / 2, y: boxCenter.y - boxSize.height / 2, width: boxSize.width, height: boxSize.height)
        include(frame)
        var placedName = name
        placedName.center = boxCenter
        lanes.append(GitGraphLayoutLane(lineStart: lineStart, lineEnd: lineEnd, nameFrame: frame, name: placedName))
    }

    /// The id turned about its corner beside the dot: up to the right after a horizontal or downward history, down to
    /// the right after an upward one.
    private mutating func placedLabel(_ label: DiagramTextBlock, beside center: CGPoint, direction: GitGraphDirection) -> GitGraphLayoutCommitLabel {
        let cosine = GitGraphGeometry.eighthTurnCosine
        let cornerInset = cosine * label.size.height / 2
        let isVertical = direction != .leftToRight
        let isUpward = direction == .bottomToTop
        let corner = isVertical ? CGPoint(x: center.x - GitGraphGeometry.dotRadius - GitGraphGeometry.labelOffset - cornerInset, y: center.y)
            : CGPoint(x: center.x + GitGraphGeometry.labelOffset, y: center.y + GitGraphGeometry.dotRadius + GitGraphGeometry.labelOffset + cornerInset)
        let angle: CGFloat = isUpward ? .pi / 4 : -.pi / 4
        let reach = cosine * label.size.width + cornerInset
        include(CGRect(x: corner.x - reach, y: isUpward ? corner.y - reach : corner.y - cornerInset, width: reach + cornerInset, height: reach + cornerInset))
        var text = label
        text.center = CGPoint(x: corner.x - label.size.width / 2 * cos(angle), y: corner.y - label.size.width / 2 * sin(angle))
        let outset = GitGraphGeometry.labelPatchOutset
        let patchSize = CGSize(width: label.size.width + outset.width, height: label.size.height + outset.height)
        return GitGraphLayoutCommitLabel(text: text, angle: angle, patchSize: patchSize)
    }

    /// Tags stacked above the commit, the first furthest out, or in a row to its right in a vertical graph.
    private mutating func placedTags(_ tags: [DiagramTextBlock], beside center: CGPoint, isVertical: Bool) -> [GitGraphLayoutTag] {
        var offset = GitGraphGeometry.dotRadius + GitGraphGeometry.tagGap
        var placed: [GitGraphLayoutTag] = []
        for tag in isVertical ? tags : tags.reversed() {
            let length = GitGraphGeometry.tagLength(tag)
            let height = tag.size.height
            let left = isVertical ? center.x + offset : center.x - length / 2
            let middle = isVertical ? center.y : center.y - offset - height / 2
            offset += isVertical ? length + GitGraphGeometry.rowTagGap : height + GitGraphGeometry.stackedTagGap
            let frame = CGRect(x: left, y: middle - height / 2, width: length, height: height)
            include(frame)
            var text = tag
            text.center = CGPoint(x: left + GitGraphGeometry.tagPointLength + GitGraphGeometry.tagTextLead + tag.size.width / 2, y: middle)
            placed.append(GitGraphLayoutTag(frame: frame, text: text))
        }
        return isVertical ? placed : placed.reversed()
    }

    private mutating func include(_ rectangle: CGRect) {
        bounds = bounds.union(rectangle)
    }

    /// A commit's symbol: its `type:`, else a ring for a merge, a cherry for a cherry-pick, a dot for a commit.
    static func symbol(of commit: GitGraphCommit) -> GitGraphCommitSymbol {
        switch (commit.kind, commit.type) {
        case (.cherryPick, _): .cherryPick
        case (.merge, nil): .merge
        case (.commit, nil), (_, .normal): .normal
        case (_, .reverse): .reverse
        case (_, .highlight): .highlight
        }
    }
}

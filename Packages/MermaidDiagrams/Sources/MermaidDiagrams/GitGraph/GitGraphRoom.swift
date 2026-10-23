import CoreGraphics

/// A Git graph's text measured, and the room each commit and lane needs, as Pele works it out: along the history on
/// either side of each commit, and across it on each side of each lane. A horizontal graph's tags stand above their
/// commit and its ids below; a vertical graph's ids stand left of their commit and its tags in a row to the right.
struct GitGraphRoom {
    /// Each commit's id, measured; nil for a commit without one drawn.
    let labels: [DiagramTextBlock?]
    let tags: [[DiagramTextBlock]]
    /// Each branch's name, measured.
    let names: [DiagramTextBlock]
    /// How much room each commit needs along the history on either side of its center.
    let halfLengths: [CGFloat]
    /// How far before a commit a connector coming from a lane above joins its lane, clear of the commit's tags: 0 when
    /// it has no tags or no such connector, or in a vertical graph.
    let tagLeads: [CGFloat]
    /// How far each lane's content reaches across toward the previous lane, and toward the next.
    let laneReachBefore: [CGFloat]
    let laneReachAfter: [CGFloat]

    init<Measurer: DiagramTextMeasuring>(diagram: GitGraphDiagram, smallText: Measurer, branchText: Measurer, isVertical: Bool) {
        labels = diagram.commits.map { commit in Self.label(of: commit, measurer: smallText) }
        tags = diagram.commits.map { commit in
            commit.tags.map { tag in DiagramTextBlock(label: tag, measurer: smallText, maximumWidth: GitGraphGeometry.wrappingWidth) }
        }
        names = diagram.branches.map { branch in DiagramTextBlock(label: branch.label, measurer: branchText, maximumWidth: GitGraphGeometry.wrappingWidth) }
        var before = [CGFloat](repeating: GitGraphGeometry.dotRadius, count: diagram.branches.count)
        var after = before
        var halfLengths: [CGFloat] = []
        var tagHalfLengths: [CGFloat] = []
        for (index, commit) in diagram.commits.enumerated() {
            let commitRoom = Self.room(label: labels[index], tags: tags[index], isVertical: isVertical)
            halfLengths.append(commitRoom.halfLength)
            tagHalfLengths.append(commitRoom.tagHalfLength)
            before[commit.branchIndex] = max(before[commit.branchIndex], isVertical ? commitRoom.labelSide : commitRoom.tagSide)
            after[commit.branchIndex] = max(after[commit.branchIndex], isVertical ? commitRoom.tagSide : commitRoom.labelSide)
        }
        for (lane, name) in names.enumerated() where !name.lines.isEmpty {
            let reach = isVertical ? name.size.width / 2 + GitGraphGeometry.verticalNameReach : name.size.height / 2 + GitGraphGeometry.horizontalNameReach
            before[lane] = max(before[lane], reach)
            after[lane] = max(after[lane], reach)
        }
        self.halfLengths = halfLengths
        tagLeads = isVertical ? halfLengths.map { _ in 0 } : diagram.commits.indices.map { index in
            let lane = diagram.commits[index].branchIndex
            let comesFromAbove = diagram.commits[index].parentIndices.contains { parent in diagram.commits[parent].branchIndex < lane }
            return tagHalfLengths[index] > 0 && comesFromAbove ? tagHalfLengths[index] + GitGraphGeometry.tagClearance : 0
        }
        laneReachBefore = before
        laneReachAfter = after
    }

    /// A commit's id as Mermaid labels it: a commit's always, a merge's when `id:` wrote it, a cherry-pick's never.
    private static func label(of commit: GitGraphCommit, measurer: some DiagramTextMeasuring) -> DiagramTextBlock? {
        let isLabelled = commit.kind == .commit || (commit.kind == .merge && commit.hasWrittenIdentifier)
        let label = DiagramLabelDecoder.label(from: commit.identifier, form: .literal)
        guard isLabelled, !label.isEmpty else { return nil }
        return DiagramTextBlock(label: label, measurer: measurer, maximumWidth: GitGraphGeometry.wrappingWidth)
    }

    /// The room one commit needs: along the history, the most of its dot and its widest tag; across, its dot and its
    /// tags on one side, its dot and its turned id on the other.
    private static func room(label: DiagramTextBlock?, tags: [DiagramTextBlock], isVertical: Bool)
        -> (halfLength: CGFloat, tagHalfLength: CGFloat, tagSide: CGFloat, labelSide: CGFloat) {
        var tagsAlong: CGFloat = 0
        var tagsAcross: CGFloat = 0
        for tag in tags {
            let length = GitGraphGeometry.tagLength(tag)
            tagsAlong = max(tagsAlong, isVertical ? tag.size.height : length)
            tagsAcross += isVertical ? length + GitGraphGeometry.rowTagGap : tag.size.height + GitGraphGeometry.stackedTagGap
        }
        let labelAcross = label.map { label in GitGraphGeometry.labelOffset + GitGraphGeometry.eighthTurnCosine * (label.size.width + label.size.height) } ?? 0
        let dot = GitGraphGeometry.dotRadius
        return (max(dot, tagsAlong / 2), tagsAlong / 2, dot + (tags.isEmpty ? 0 : GitGraphGeometry.tagGap + tagsAcross), dot + labelAcross)
    }
}

import CoreGraphics

/// Lays a Git graph out in Pele's style: one lane per branch, 44 points apart or as far as their ids, tags and names
/// need, commits along the history 44 points apart or as far as their tags need, ids in three quarters of the text size
/// turned an eighth of a turn, tags in boxes, branch names in seven eighths of the size in boxes at the lanes' start,
/// and the title above.
public enum GitGraphLayoutEngine {
    /// Around the whole diagram.
    static let padding: CGFloat = 8
    /// Between the title and the diagram.
    static let titleGap: CGFloat = 16

    public static func layout(_ diagram: GitGraphDiagram, typography: DiagramTypography) throws(GitGraphLayoutError) -> GitGraphLayout {
        try layout(diagram, smallText: typography.axisText, branchText: typography.edgeText, titleText: typography.boldNodeText, font: typography.font)
    }

    /// `smallText` measures ids and tags, `branchText` branch names and `titleText` the title, in bold.
    static func layout<Measurer: DiagramTextMeasuring>(_ diagram: GitGraphDiagram, smallText: Measurer, branchText: Measurer, titleText: Measurer,
                                                       font: DiagramFont) throws(GitGraphLayoutError) -> GitGraphLayout {
        guard !diagram.setsGitGraphOptions else { throw .optionsNotApplied }
        let geometry = GitGraphGeometry(direction: diagram.direction)
        let room = GitGraphRoom(diagram: diagram, smallText: smallText, branchText: branchText, isVertical: geometry.isVertical)
        let positions = GitGraphPositions(diagram: diagram, room: room)
        let connectors = GitGraphConnectorRouting(diagram: diagram, room: room, positions: positions, geometry: geometry).connectors()
        let placement = GitGraphPlacement(diagram: diagram, room: room, positions: positions, geometry: geometry)
        let title = diagram.title.map { title in
            DiagramTextBlock(label: DiagramLabelDecoder.label(from: title, form: .plain), measurer: titleText, maximumWidth: GitGraphGeometry.wrappingWidth)
        }.flatMap { block in block.lines.isEmpty ? nil : block }
        let body = placement.bounds
        let titleHeight = title.map { title in title.size.height + titleGap } ?? 0
        let innerWidth = max(body.width, title?.size.width ?? 0)
        let size = CGSize(width: (innerWidth + 2 * padding).rounded(.up), height: (body.height + titleHeight + 2 * padding).rounded(.up))
        let offset = CGVector(dx: padding - body.minX + (innerWidth - body.width) / 2, dy: padding + titleHeight - body.minY)
        var placedTitle = title
        placedTitle?.center = CGPoint(x: size.width / 2, y: padding + (title?.size.height ?? 0) / 2)
        return GitGraphLayout(size: size, font: font, direction: diagram.direction, lanes: placement.lanes.map { lane in lane.translated(by: offset) },
                              connectors: connectors.map { connector in connector.translated(by: offset) },
                              commits: placement.commits.map { commit in commit.translated(by: offset) }, title: placedTitle)
    }
}

extension GitGraphLayoutLane {
    func translated(by offset: CGVector) -> GitGraphLayoutLane {
        GitGraphLayoutLane(lineStart: lineStart.translated(by: offset), lineEnd: lineEnd.translated(by: offset),
                           nameFrame: nameFrame?.offsetBy(dx: offset.dx, dy: offset.dy), name: name?.translated(by: offset))
    }
}

extension GitGraphLayoutConnector {
    func translated(by offset: CGVector) -> GitGraphLayoutConnector {
        GitGraphLayoutConnector(path: path.translated(by: offset), laneIndex: laneIndex, style: style)
    }
}

extension GitGraphLayoutCommit {
    func translated(by offset: CGVector) -> GitGraphLayoutCommit {
        GitGraphLayoutCommit(center: center.translated(by: offset), laneIndex: laneIndex, symbol: symbol,
                             label: label.map { label in GitGraphLayoutCommitLabel(text: label.text.translated(by: offset), angle: label.angle,
                                                                                   patchSize: label.patchSize) },
                             tags: tags.map { tag in
                                 GitGraphLayoutTag(frame: tag.frame.offsetBy(dx: offset.dx, dy: offset.dy), text: tag.text.translated(by: offset))
                             })
    }
}

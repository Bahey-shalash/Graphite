import Foundation
import CoreGraphics

/// The part of an endless board a view shows: how much it is magnified, and which board
/// point is at the view's top-left corner.
public struct CanvasViewport: Equatable, Sendable {
    /// Far enough out to see a board of many thousands of cards at once.
    public static let minimumScale: CGFloat = 0.01
    public static let maximumScale: CGFloat = 4
    /// "Zoom to fit" never magnifies: a small board is shown at its own size.
    public static let maximumFittingScale: CGFloat = 1

    /// View points per board pixel.
    public var scale: CGFloat
    public var origin: CGPoint

    public init(scale: CGFloat = 1, origin: CGPoint = .zero) {
        self.scale = Self.clampedScale(scale); self.origin = origin
    }

    public static func clampedScale(_ scale: CGFloat) -> CGFloat {
        guard scale.isFinite else { return 1 }
        return min(max(scale, minimumScale), maximumScale)
    }

    public func viewPoint(forBoardPoint boardPoint: CGPoint) -> CGPoint {
        CGPoint(x: (boardPoint.x - origin.x) * scale, y: (boardPoint.y - origin.y) * scale)
    }

    public func boardPoint(forViewPoint viewPoint: CGPoint) -> CGPoint {
        CGPoint(x: viewPoint.x / scale + origin.x, y: viewPoint.y / scale + origin.y)
    }

    public func viewFrame(forBoardFrame boardFrame: CGRect) -> CGRect {
        CGRect(origin: viewPoint(forBoardPoint: boardFrame.origin), size: CGSize(width: boardFrame.width * scale, height: boardFrame.height * scale))
    }

    /// The part of the board a view of this size shows.
    public func visibleBoardFrame(viewSize: CGSize) -> CGRect {
        CGRect(origin: origin, size: CGSize(width: viewSize.width / scale, height: viewSize.height / scale))
    }

    public mutating func pan(byViewTranslation translation: CGSize) {
        origin.x -= translation.width / scale
        origin.y -= translation.height / scale
    }

    /// Magnifies by `factor`, keeping the board point under `viewPoint` where it is, as a
    /// pinch keeps what is between the fingers.
    public mutating func zoom(by factor: CGFloat, around viewPoint: CGPoint) {
        let anchoredBoardPoint = boardPoint(forViewPoint: viewPoint)
        scale = Self.clampedScale(scale * factor)
        origin = CGPoint(x: anchoredBoardPoint.x - viewPoint.x / scale, y: anchoredBoardPoint.y - viewPoint.y / scale)
    }

    /// The viewport that shows all of `boardFrame` centered in the view, with `padding`
    /// view points around it.
    public static func fitting(_ boardFrame: CGRect, in viewSize: CGSize, padding: CGFloat, maximumScale: CGFloat = maximumFittingScale) -> CanvasViewport {
        guard !boardFrame.isNull, boardFrame.width > 0, boardFrame.height > 0, viewSize.width > 0, viewSize.height > 0 else {
            // Nothing to fit: the board's origin goes to the middle of the view.
            return CanvasViewport(scale: 1, origin: CGPoint(x: -viewSize.width / 2, y: -viewSize.height / 2))
        }
        let availableWidth = max(viewSize.width - 2 * padding, 1), availableHeight = max(viewSize.height - 2 * padding, 1)
        let scale = clampedScale(min(availableWidth / boardFrame.width, availableHeight / boardFrame.height, maximumScale))
        return CanvasViewport(scale: scale, origin: CGPoint(x: boardFrame.midX - viewSize.width / scale / 2, y: boardFrame.midY - viewSize.height / scale / 2))
    }

    /// Moves the board as little as possible so that `boardFrame` lies inside
    /// `unobscuredViewFrame`, the part of the view nothing covers, such as the part above
    /// the keyboard. A frame larger than that part is shown from its top-left corner.
    public mutating func reveal(_ boardFrame: CGRect, in unobscuredViewFrame: CGRect, margin: CGFloat) {
        let target = unobscuredViewFrame.insetBy(dx: min(margin, unobscuredViewFrame.width / 2), dy: min(margin, unobscuredViewFrame.height / 2))
        let frame = viewFrame(forBoardFrame: boardFrame)
        var translation = CGSize.zero
        if frame.width > target.width || frame.minX < target.minX { translation.width = target.minX - frame.minX }
        else if frame.maxX > target.maxX { translation.width = target.maxX - frame.maxX }
        if frame.height > target.height || frame.minY < target.minY { translation.height = target.minY - frame.minY }
        else if frame.maxY > target.maxY { translation.height = target.maxY - frame.maxY }
        pan(byViewTranslation: translation)
    }
}

/// The curve a connection is drawn as: a cubic Bézier between two card sides.
public struct CanvasEdgeRoute: Equatable, Sendable {
    public let start: CGPoint
    public let startControl: CGPoint
    public let endControl: CGPoint
    public let end: CGPoint
    public let fromSide: CanvasSide
    public let toSide: CanvasSide

    /// The point at `parameter` of the way along the curve, from 0 to 1.
    public func point(at parameter: CGFloat) -> CGPoint {
        let remaining = 1 - parameter
        let startWeight = remaining * remaining * remaining, startControlWeight = 3 * remaining * remaining * parameter
        let endControlWeight = 3 * remaining * parameter * parameter, endWeight = parameter * parameter * parameter
        return CGPoint(x: startWeight * start.x + startControlWeight * startControl.x + endControlWeight * endControl.x + endWeight * end.x,
                       y: startWeight * start.y + startControlWeight * startControl.y + endControlWeight * endControl.y + endWeight * end.y)
    }

    /// Where the connection's label sits.
    public var midpoint: CGPoint { point(at: 0.5) }

    /// A frame the whole curve lies in: a Bézier curve stays inside the hull of its points.
    public var bounds: CGRect {
        let horizontalPositions = [start.x, startControl.x, endControl.x, end.x], verticalPositions = [start.y, startControl.y, endControl.y, end.y]
        let minimumX = horizontalPositions.min() ?? 0, minimumY = verticalPositions.min() ?? 0
        return CGRect(x: minimumX, y: minimumY, width: (horizontalPositions.max() ?? 0) - minimumX, height: (verticalPositions.max() ?? 0) - minimumY)
    }

    /// How far `point` is from the curve, measured against short straight pieces of it.
    public func distance(to point: CGPoint) -> CGFloat {
        var shortestDistance = CGFloat.infinity
        var segmentStart = start
        for sampleIndex in 1...Self.hitTestingSegmentCount {
            let segmentEnd = self.point(at: CGFloat(sampleIndex) / CGFloat(Self.hitTestingSegmentCount))
            shortestDistance = min(shortestDistance, CanvasGeometry.distance(from: point, toSegmentFrom: segmentStart, to: segmentEnd))
            segmentStart = segmentEnd
        }
        return shortestDistance
    }

    private static let hitTestingSegmentCount = 32

    /// The three corners of the arrowhead at the curve's end, tip first, pointing into
    /// the card the way the curve arrives.
    public func arrowhead(atStart: Bool, length: CGFloat, halfWidth: CGFloat) -> [CGPoint] {
        let tip = atStart ? start : end
        let side = atStart ? fromSide : toSide
        // The curve arrives at right angles to the side, so the arrow points against the
        // side's outward direction.
        let outward = CanvasGeometry.outwardDirection(of: side)
        let base = CGPoint(x: tip.x + outward.dx * length, y: tip.y + outward.dy * length)
        return [tip, CGPoint(x: base.x - outward.dy * halfWidth, y: base.y + outward.dx * halfWidth),
                CGPoint(x: base.x + outward.dy * halfWidth, y: base.y - outward.dx * halfWidth)]
    }
}

/// What a touch on the board lands on.
public enum CanvasHitTarget: Equatable, Sendable {
    case node(String)
    case edge(String)
}

/// One of the eight places a selected card is resized by.
public enum CanvasResizeHandle: CaseIterable, Sendable {
    case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left

    public var movesLeftEdge: Bool { self == .topLeft || self == .left || self == .bottomLeft }
    public var movesRightEdge: Bool { self == .topRight || self == .right || self == .bottomRight }
    public var movesTopEdge: Bool { self == .topLeft || self == .top || self == .topRight }
    public var movesBottomEdge: Bool { self == .bottomLeft || self == .bottom || self == .bottomRight }

    /// Where the handle sits on a card's frame.
    public func position(on frame: CGRect) -> CGPoint {
        CGPoint(x: movesLeftEdge ? frame.minX : movesRightEdge ? frame.maxX : frame.midX,
                y: movesTopEdge ? frame.minY : movesBottomEdge ? frame.maxY : frame.midY)
    }
}

public enum CanvasGeometry {
    /// Obsidian's grid: cards snap to multiples of 20 pixels.
    public static let gridSpacing: CGFloat = 20
    /// The smallest a card is resized to, so it can still be seen and grabbed.
    public static let minimumCardSideLength: CGFloat = 40
    /// How far a connection's curve leaves its card before it turns, as Obsidian draws
    /// them: half the distance between the two ends, within these bounds.
    public static let minimumControlDistance: CGFloat = 70
    public static let maximumControlDistance: CGFloat = 150

    // MARK: Connections

    /// The middle of a card's side, where connections attach.
    public static func anchor(of frame: CGRect, side: CanvasSide) -> CGPoint {
        switch side {
        case .top: CGPoint(x: frame.midX, y: frame.minY)
        case .right: CGPoint(x: frame.maxX, y: frame.midY)
        case .bottom: CGPoint(x: frame.midX, y: frame.maxY)
        case .left: CGPoint(x: frame.minX, y: frame.midY)
        }
    }

    static func outwardDirection(of side: CanvasSide) -> CGVector {
        switch side {
        case .top: CGVector(dx: 0, dy: -1)
        case .right: CGVector(dx: 1, dy: 0)
        case .bottom: CGVector(dx: 0, dy: 1)
        case .left: CGVector(dx: -1, dy: 0)
        }
    }

    /// The sides a connection uses. A side the file names is kept; a side it leaves open
    /// is the one that brings the two ends closest together.
    public static func sides(from fromFrame: CGRect, to toFrame: CGRect, fromSide: CanvasSide?, toSide: CanvasSide?) -> (fromSide: CanvasSide, toSide: CanvasSide) {
        if let fromSide, let toSide { return (fromSide, toSide) }
        var closest: (fromSide: CanvasSide, toSide: CanvasSide, distance: CGFloat)?
        for candidateFromSide in fromSide.map({ side in [side] }) ?? CanvasSide.allCases {
            for candidateToSide in toSide.map({ side in [side] }) ?? CanvasSide.allCases {
                let fromAnchor = anchor(of: fromFrame, side: candidateFromSide), toAnchor = anchor(of: toFrame, side: candidateToSide)
                let distance = hypot(toAnchor.x - fromAnchor.x, toAnchor.y - fromAnchor.y)
                if closest.map({ closest in distance < closest.distance }) ?? true { closest = (candidateFromSide, candidateToSide, distance) }
            }
        }
        return (closest?.fromSide ?? .right, closest?.toSide ?? .left)
    }

    /// The curve of a connection between two cards.
    public static func route(from fromFrame: CGRect, to toFrame: CGRect, fromSide: CanvasSide?, toSide: CanvasSide?) -> CanvasEdgeRoute {
        let chosenSides = sides(from: fromFrame, to: toFrame, fromSide: fromSide, toSide: toSide)
        return route(from: anchor(of: fromFrame, side: chosenSides.fromSide), fromSide: chosenSides.fromSide,
                     to: anchor(of: toFrame, side: chosenSides.toSide), toSide: chosenSides.toSide)
    }

    /// The curve between two points that leaves and arrives at right angles to the sides.
    public static func route(from start: CGPoint, fromSide: CanvasSide, to end: CGPoint, toSide: CanvasSide) -> CanvasEdgeRoute {
        let controlDistance = min(max(hypot(end.x - start.x, end.y - start.y) / 2, minimumControlDistance), maximumControlDistance)
        let fromDirection = outwardDirection(of: fromSide), toDirection = outwardDirection(of: toSide)
        return CanvasEdgeRoute(start: start,
                               startControl: CGPoint(x: start.x + fromDirection.dx * controlDistance, y: start.y + fromDirection.dy * controlDistance),
                               endControl: CGPoint(x: end.x + toDirection.dx * controlDistance, y: end.y + toDirection.dy * controlDistance),
                               end: end, fromSide: fromSide, toSide: toSide)
    }

    /// The side of `frame` nearest to `point`, for a connection dropped on a card.
    public static func nearestSide(of frame: CGRect, to point: CGPoint) -> CanvasSide {
        CanvasSide.allCases.min { firstSide, secondSide in
            let firstAnchor = anchor(of: frame, side: firstSide), secondAnchor = anchor(of: frame, side: secondSide)
            return hypot(point.x - firstAnchor.x, point.y - firstAnchor.y) < hypot(point.x - secondAnchor.x, point.y - secondAnchor.y)
        } ?? .left
    }

    static func distance(from point: CGPoint, toSegmentFrom segmentStart: CGPoint, to segmentEnd: CGPoint) -> CGFloat {
        let segmentX = segmentEnd.x - segmentStart.x, segmentY = segmentEnd.y - segmentStart.y
        let squaredLength = segmentX * segmentX + segmentY * segmentY
        guard squaredLength > 0 else { return hypot(point.x - segmentStart.x, point.y - segmentStart.y) }
        let projection = min(max(((point.x - segmentStart.x) * segmentX + (point.y - segmentStart.y) * segmentY) / squaredLength, 0), 1)
        return hypot(point.x - (segmentStart.x + projection * segmentX), point.y - (segmentStart.y + projection * segmentY))
    }

    // MARK: Layout

    /// The frame around every card; null for an empty board.
    public static func bounds(of nodes: [CanvasNode]) -> CGRect {
        nodes.reduce(CGRect.null) { bounds, node in bounds.union(node.frame) }
    }

    /// The cards that move with a group: those lying wholly inside it, as in Obsidian.
    public static func nodes(inside group: CanvasNode, among nodes: [CanvasNode]) -> [CanvasNode] {
        nodes.filter { node in node.id != group.id && group.frame.contains(node.frame) }
    }

    /// The order cards are read aloud in: rows from the top, each from the left, and a
    /// group just before the first card inside it. Cards whose tops are within
    /// `rowTolerance` of the first card of a row belong to that row.
    public static func readingOrder(of nodes: [CanvasNode], rowTolerance: CGFloat = 40) -> [CanvasNode] {
        let groups = nodes.filter(\.isGroup)
        let groupsWithCards = groups.filter { group in nodes.contains { node in !node.isGroup && group.frame.contains(node.frame) } }
        let namesOfGroupsWithCards = Set(groupsWithCards.map(\.id))
        // A group with nothing in it is read where it lies, like a card.
        let nodesFromTop = nodes.filter { node in !namesOfGroupsWithCards.contains(node.id) }.sorted { firstNode, secondNode in
            (firstNode.frame.minY, firstNode.frame.minX) < (secondNode.frame.minY, secondNode.frame.minX)
        }
        var ordered: [CanvasNode] = []
        var row: [CanvasNode] = []
        func finishRow() {
            ordered += row.sorted { firstNode, secondNode in (firstNode.frame.minX, firstNode.frame.minY) < (secondNode.frame.minX, secondNode.frame.minY) }
            row.removeAll(keepingCapacity: true)
        }
        for node in nodesFromTop {
            if let rowTop = row.first?.frame.minY, node.frame.minY - rowTop > rowTolerance { finishRow() }
            row.append(node)
        }
        finishRow()
        // Larger groups first, so a group inside another is read after the one around it.
        let groupsFromLargest = groupsWithCards.sorted { firstGroup, secondGroup in
            firstGroup.frame.width * firstGroup.frame.height > secondGroup.frame.width * secondGroup.frame.height
        }
        for group in groupsFromLargest {
            let firstInside = ordered.firstIndex { node in !node.isGroup && group.frame.contains(node.frame) } ?? ordered.count
            ordered.insert(group, at: firstInside)
        }
        return ordered
    }

    // MARK: Hit testing

    /// What is at `point`: the topmost card, else a connection within `edgeTolerance`,
    /// else a group by its label or its border. A group's inside is empty board, as in
    /// Obsidian, so a selection can be drawn and cards added inside a group.
    /// - Parameters:
    ///   - groupLabelFrames: Where each group's label is drawn, by the group's identifier.
    ///   - borderTolerance: How close to a group's border counts as on it.
    public static func target(at point: CGPoint, nodes: [CanvasNode], edgeRoutes: [(identifier: String, route: CanvasEdgeRoute)], edgeTolerance: CGFloat,
                              groupLabelFrames: [String: CGRect] = [:], borderTolerance: CGFloat) -> CanvasHitTarget? {
        if let card = nodes.last(where: { node in !node.isGroup && node.frame.contains(point) }) { return .node(card.id) }
        var closestEdge: (identifier: String, distance: CGFloat)?
        for (identifier, route) in edgeRoutes where route.bounds.insetBy(dx: -edgeTolerance, dy: -edgeTolerance).contains(point) {
            let distance = route.distance(to: point)
            if distance <= edgeTolerance, closestEdge.map({ closestEdge in distance < closestEdge.distance }) ?? true { closestEdge = (identifier, distance) }
        }
        if let closestEdge { return .edge(closestEdge.identifier) }
        let groups = nodes.filter(\.isGroup)
        if let labeledGroup = groups.last(where: { group in groupLabelFrames[group.id]?.contains(point) == true }) { return .node(labeledGroup.id) }
        // The innermost of nested groups is the one whose border is meant.
        let groupsOnBorder = groups.filter { group in
            group.frame.insetBy(dx: -borderTolerance, dy: -borderTolerance).contains(point)
                && !group.frame.insetBy(dx: min(borderTolerance, group.frame.width / 2), dy: min(borderTolerance, group.frame.height / 2)).contains(point)
        }
        return groupsOnBorder.min { firstGroup, secondGroup in
            firstGroup.frame.width * firstGroup.frame.height < secondGroup.frame.width * secondGroup.frame.height
        }.map { group in .node(group.id) }
    }

    /// The cards a selection rectangle takes: those it touches, and a group only when it
    /// holds the whole group, so drawing a selection inside a group leaves the group out.
    public static func nodes(selectedBy selectionFrame: CGRect, among nodes: [CanvasNode]) -> [CanvasNode] {
        nodes.filter { node in node.isGroup ? selectionFrame.contains(node.frame) : selectionFrame.intersects(node.frame) }
    }

    // MARK: Snapping

    /// A frame after snapping, and the lines it snapped to, which are drawn as guides.
    public struct SnapResult: Equatable, Sendable {
        public var frame: CGRect
        /// The horizontal position of a vertical line another card shares with this one.
        public var verticalGuide: CGFloat?
        public var horizontalGuide: CGFloat?
    }

    /// Moves `frame` onto another card's edge or middle when one is within `tolerance`,
    /// and otherwise onto the grid, on each axis separately, as Obsidian does.
    /// - Parameters:
    ///   - gridSpacing: Nil when snapping to the grid is off.
    ///   - otherFrames: The cards to line up with; empty when snapping to objects is off.
    public static func snappedMove(of frame: CGRect, otherFrames: [CGRect], gridSpacing: CGFloat?, tolerance: CGFloat) -> SnapResult {
        var result = SnapResult(frame: frame)
        let horizontalSnap = objectSnap(of: [frame.minX, frame.midX, frame.maxX], to: otherFrames.flatMap { other in [other.minX, other.midX, other.maxX] }, tolerance: tolerance)
        if let horizontalSnap {
            result.frame.origin.x += horizontalSnap.adjustment
            result.verticalGuide = horizontalSnap.line
        } else if let gridSpacing {
            result.frame.origin.x = (frame.minX / gridSpacing).rounded() * gridSpacing
        }
        let verticalSnap = objectSnap(of: [frame.minY, frame.midY, frame.maxY], to: otherFrames.flatMap { other in [other.minY, other.midY, other.maxY] }, tolerance: tolerance)
        if let verticalSnap {
            result.frame.origin.y += verticalSnap.adjustment
            result.horizontalGuide = verticalSnap.line
        } else if let gridSpacing {
            result.frame.origin.y = (frame.minY / gridSpacing).rounded() * gridSpacing
        }
        return result
    }

    /// Resizes `originalFrame` by dragging `handle` by `translation`, snapping the edges
    /// that move, and never below the smallest size.
    public static func snappedResize(of originalFrame: CGRect, handle: CanvasResizeHandle, translation: CGSize, otherFrames: [CGRect],
                                     gridSpacing: CGFloat?, tolerance: CGFloat) -> SnapResult {
        var minimumX = originalFrame.minX, maximumX = originalFrame.maxX, minimumY = originalFrame.minY, maximumY = originalFrame.maxY
        var verticalGuide: CGFloat?, horizontalGuide: CGFloat?
        func snapped(_ position: CGFloat, to lines: [CGFloat]) -> (position: CGFloat, guide: CGFloat?) {
            if let snap = objectSnap(of: [position], to: lines, tolerance: tolerance) { return (snap.line, snap.line) }
            if let gridSpacing { return ((position / gridSpacing).rounded() * gridSpacing, nil) }
            return (position, nil)
        }
        let verticalLines = otherFrames.flatMap { other in [other.minX, other.maxX] }, horizontalLines = otherFrames.flatMap { other in [other.minY, other.maxY] }
        if handle.movesLeftEdge {
            let snap = snapped(originalFrame.minX + translation.width, to: verticalLines)
            minimumX = min(snap.position, maximumX - minimumCardSideLength); verticalGuide = snap.position == minimumX ? snap.guide : nil
        }
        if handle.movesRightEdge {
            let snap = snapped(originalFrame.maxX + translation.width, to: verticalLines)
            maximumX = max(snap.position, minimumX + minimumCardSideLength); verticalGuide = snap.position == maximumX ? snap.guide : nil
        }
        if handle.movesTopEdge {
            let snap = snapped(originalFrame.minY + translation.height, to: horizontalLines)
            minimumY = min(snap.position, maximumY - minimumCardSideLength); horizontalGuide = snap.position == minimumY ? snap.guide : nil
        }
        if handle.movesBottomEdge {
            let snap = snapped(originalFrame.maxY + translation.height, to: horizontalLines)
            maximumY = max(snap.position, minimumY + minimumCardSideLength); horizontalGuide = snap.position == maximumY ? snap.guide : nil
        }
        return SnapResult(frame: CGRect(x: minimumX, y: minimumY, width: maximumX - minimumX, height: maximumY - minimumY),
                          verticalGuide: verticalGuide, horizontalGuide: horizontalGuide)
    }

    /// The smallest move that puts one of `positions` on one of `lines`, when one is
    /// within `tolerance`.
    private static func objectSnap(of positions: [CGFloat], to lines: [CGFloat], tolerance: CGFloat) -> (adjustment: CGFloat, line: CGFloat)? {
        var best: (adjustment: CGFloat, line: CGFloat)?
        for position in positions {
            for line in lines {
                let adjustment = line - position
                guard abs(adjustment) <= tolerance else { continue }
                if best.map({ best in abs(adjustment) < abs(best.adjustment) }) ?? true { best = (adjustment, line) }
            }
        }
        return best
    }
}

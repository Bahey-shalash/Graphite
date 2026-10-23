import CoreGraphics

/// Places a quadrant chart's points as Pele does. A point is drawn when both its coordinates are numbers from 0 to 1,
/// x to the right and y up, in its own styles over its class's. Its text goes to the first place, inside the plot,
/// that overlaps nothing placed before it: below the point, above it, right of it, left of it, or below its quadrant's
/// text; a second round lets it cross the gaps between quadrants; when no place is free it takes the first place
/// inside the plot. Above 300 points the search is skipped and each text takes that first place.
struct QuadrantChartPointPlacement {
    let chart: QuadrantChart
    let plot: QuadrantChartPlot
    /// The boxes of the quadrants' texts, quadrant 1 first; a quadrant without text has an empty box where its text's
    /// middle would be.
    let quadrantTextBoxes: [CGRect]
    /// Each point's text measured, in the order the points are written.
    let pointTexts: [DiagramTextBlock]

    /// Pele's `pointRadius`.
    static let standardRadius: CGFloat = 5
    /// The largest radius and outline width drawn, as Pele bounds them.
    static let largestRadius: CGFloat = 2_000
    static let largestStrokeWidth: CGFloat = 400
    /// Between a point and its text: Pele's `pointTextPadding`.
    static let textPadding: CGFloat = 5
    /// The width a point's text wraps at.
    static let textWidth: CGFloat = 200
    /// Above this many points, texts are not kept apart.
    static let largestCarefulPointCount = 300
    /// Half the height a line of a point's text keeps clear, as a share of its font size: Pele's.
    static let lineHalfHeightRatio: CGFloat = 0.6

    /// A point drawn, before its text is placed.
    private struct DrawnPoint {
        let center: CGPoint
        let radius: CGFloat
        let fill: QuadrantChartPaint
        let stroke: QuadrantChartStroke?
        let text: DiagramTextBlock
        /// How far the point reaches from its center, its outline included.
        var reach: CGFloat { radius + (stroke?.width ?? 0) / 2 }
    }

    func placed() -> [QuadrantChartLayoutPoint] {
        let drawn = zip(chart.points, pointTexts).compactMap(drawnPoint)
        let isCareful = drawn.count <= Self.largestCarefulPointCount
        var taken = gapBoxes + quadrantTextBoxes
        if isCareful { taken += drawn.map { point in point.center.box(halfWidth: point.reach, halfHeight: point.reach) } }
        var points: [QuadrantChartLayoutPoint] = []
        points.reserveCapacity(drawn.count)
        for point in drawn {
            let halfSize = halfSize(of: point.text)
            let center = textCenter(point, halfSize: halfSize, taken: isCareful ? taken : nil)
            if isCareful { taken.append(center.box(halfWidth: halfSize.width, halfHeight: halfSize.height)) }
            var text = point.text
            text.center = center
            points.append(QuadrantChartLayoutPoint(center: point.center, radius: point.radius, fill: point.fill, stroke: point.stroke, text: text))
        }
        return points
    }

    /// The point drawn at its coordinates in its styles, or nil when either coordinate is not a number from 0 to 1.
    private func drawnPoint(_ point: QuadrantChartPoint, text: DiagramTextBlock) -> DrawnPoint? {
        guard let xCoordinate = point.xCoordinate, let yCoordinate = point.yCoordinate, (0...1).contains(xCoordinate),
              (0...1).contains(yCoordinate) else { return nil }
        let style = point.style.overriding(point.className.flatMap { name in chart.classStyles[name] })
        let stroke = style.strokeWidth.map { width in
            QuadrantChartStroke(paint: style.strokeColor.map(QuadrantChartPaint.written) ?? .firstSeries, width: min(CGFloat(width), Self.largestStrokeWidth))
        }
        let frame = plot.frame
        return DrawnPoint(center: CGPoint(x: frame.minX + CGFloat(xCoordinate) * frame.width, y: frame.minY + CGFloat(1 - yCoordinate) * frame.height),
                          radius: min(CGFloat(style.radius ?? Self.standardRadius), Self.largestRadius),
                          fill: style.color.map(QuadrantChartPaint.written) ?? .firstSeries, stroke: stroke, text: text)
    }

    /// The half width and the half height a text keeps clear: its widest line's half, and Pele's line height.
    private func halfSize(of text: DiagramTextBlock) -> CGSize {
        CGSize(width: text.size.width / 2,
               height: text.fontSize * Self.lineHalfHeightRatio + (text.size.height - text.lineHeight) / 2)
    }

    /// Where the point's text goes: the first free place of the two rounds, else the first place inside the plot, else
    /// below the point. Every place is free when `taken` is nil.
    private func textCenter(_ point: DrawnPoint, halfSize: CGSize, taken: [CGRect]?) -> CGPoint {
        let places = candidatePlaces(point, halfSize: halfSize)
        var chosen: CGPoint?
        for round in 0..<2 {
            for (place, isClamped, margin) in places {
                let center = isClamped && point.text.size.width < plot.frame.width ? clamped(place, halfWidth: halfSize.width, margin: margin) : place
                let box = center.box(halfWidth: halfSize.width, halfHeight: halfSize.height)
                guard isInsidePlot(box) else { continue }
                let isFree = taken.map { boxes in Self.isClear(box, of: boxes.dropFirst(round == 0 ? 0 : gapBoxes.count)) } ?? true
                if chosen == nil || isFree { chosen = center }
                if isFree { return center }
            }
        }
        return chosen ?? places[0].place
    }

    /// Below the point, above it, right of it, left of it, and below its quadrant's text, each with whether it is moved
    /// across to stay inside the plot, and how far from the plot's edges it then stays.
    private func candidatePlaces(_ point: DrawnPoint, halfSize: CGSize) -> [(place: CGPoint, isClamped: Bool, margin: CGFloat)] {
        let away = point.reach + Self.textPadding
        let inset = min(away, max(0, (plot.quadrantSize.width - point.text.size.width) / 2))
        let quadrantText = quadrantTextBoxes[quadrantIndex(of: point.center)]
        let belowQuadrantText = max(point.center.y + away, quadrantText.maxY + Self.textPadding) + halfSize.height
        let center = point.center
        return [
            (CGPoint(x: center.x, y: center.y + away + halfSize.height), true, 0),
            (CGPoint(x: center.x, y: center.y - away - halfSize.height), true, 0),
            (CGPoint(x: center.x + away + halfSize.width, y: center.y), false, 0),
            (CGPoint(x: center.x - away - halfSize.width, y: center.y), false, 0),
            (CGPoint(x: center.x, y: belowQuadrantText), true, inset),
        ]
    }

    /// `place` moved across, as little as it takes, to keep the text `margin` inside the plot's edges.
    private func clamped(_ place: CGPoint, halfWidth: CGFloat, margin: CGFloat) -> CGPoint {
        let frame = plot.frame
        return CGPoint(x: min(max(place.x, frame.minX + halfWidth + margin), frame.maxX - halfWidth - margin), y: place.y)
    }

    /// Whether `box` is inside the plot, its edges on the plot's edges included.
    private func isInsidePlot(_ box: CGRect) -> Bool {
        let frame = plot.frame
        return box.minX >= frame.minX && box.maxX <= frame.maxX && box.minY >= frame.minY && box.maxY <= frame.maxY
    }

    /// The quadrant a point is in, by index: 0 at the top right, then anticlockwise.
    private func quadrantIndex(of center: CGPoint) -> Int {
        let isLeft = center.x < plot.frame.midX
        let isTop = center.y < plot.frame.midY
        if isLeft { return isTop ? 1 : 2 }
        return isTop ? 0 : 3
    }

    /// The gaps between the quadrants: the one down the middle and the one across it.
    private var gapBoxes: [CGRect] {
        let frame = plot.frame
        let size = plot.quadrantSize
        return [CGRect(x: frame.minX + size.width, y: frame.minY, width: frame.width - 2 * size.width, height: frame.height),
                CGRect(x: frame.minX, y: frame.minY + size.height, width: frame.width, height: frame.height - 2 * size.height)]
    }

    /// Whether `box` overlaps none of `boxes`, edges that only touch apart; an empty box is a point that a box overlaps
    /// when the point is strictly inside it.
    private static func isClear(_ box: CGRect, of boxes: ArraySlice<CGRect>) -> Bool {
        !boxes.contains { other in box.minX < other.maxX && box.maxX > other.minX && box.minY < other.maxY && box.maxY > other.minY }
    }
}

private extension CGPoint {
    func box(halfWidth: CGFloat, halfHeight: CGFloat) -> CGRect {
        CGRect(x: x - halfWidth, y: y - halfHeight, width: 2 * halfWidth, height: 2 * halfHeight)
    }
}

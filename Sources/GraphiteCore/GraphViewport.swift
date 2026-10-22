import Foundation

/// Where the graph view looks: how far it is zoomed in and how far the graph is moved, as
/// pure geometry between the layout's positions and points in the view. Drawing, hit
/// testing, the pinch and the fit all go through it, so they agree.
public struct GraphViewport: Equatable, Sendable {
    /// Points on screen per point of the layout.
    public private(set) var scale: Double
    /// How far the layout's origin sits from the middle of the view, in points.
    public private(set) var offset: SIMD2<Double>

    /// As far out as a pinch zooms: a vault of 100,000 notes still fits a phone.
    public static let minimumScale = 0.05
    /// As far in as a pinch zooms.
    public static let maximumScale = 6.0
    /// The fit leaves this much room at each edge of the view.
    static let fitMarginPoints = 16.0
    /// The fit never zooms a small graph in further than this, so a few notes keep their size.
    static let maximumFitScale = 2.2
    /// The room a line of names takes under its nodes when the fit makes room for it.
    static let nameHeightPoints = 26.0
    /// Half the width of a name, per character, at the size names are drawn.
    static let halfNameWidthPerCharacterPoints = 3.2
    /// How many times the fit shrinks to make room for the widest names at the edges.
    static let maximumFitPasses = 6
    /// Names that overflow the view by less than this fit.
    static let fitTolerancePoints = 0.5
    /// The most one pass of the fit shrinks the zoom by.
    static let smallestShrinkRatioPerPass = 0.5

    public init(scale: Double = 1, offset: SIMD2<Double> = .zero) {
        self.scale = scale
        self.offset = offset
    }

    /// Where a layout position is drawn in a view of this size.
    public func screenPoint(_ position: SIMD2<Double>, in size: CGSize) -> CGPoint {
        CGPoint(x: size.width / 2 + offset.x + position.x * scale, y: size.height / 2 + offset.y + position.y * scale)
    }

    /// The layout position under a point of a view of this size.
    public func graphPosition(_ point: CGPoint, in size: CGSize) -> SIMD2<Double> {
        SIMD2((point.x - size.width / 2 - offset.x) / scale, (point.y - size.height / 2 - offset.y) / scale)
    }

    /// Moves the graph by a distance on screen, as a finger drags it.
    public mutating func move(by translation: SIMD2<Double>) {
        offset += translation
    }

    /// Zooms to `newScale`, kept between the minimum and the maximum, with the layout point
    /// under `anchor` staying under it, as under the fingers of a pinch.
    public mutating func zoom(to newScale: Double, keepingInPlace anchor: CGPoint, in size: CGSize) {
        let anchorPosition = graphPosition(anchor, in: size)
        scale = min(max(newScale, Self.minimumScale), Self.maximumScale)
        let anchorAfter = screenPoint(anchorPosition, in: size)
        offset += SIMD2(anchor.x - anchorAfter.x, anchor.y - anchorAfter.y)
    }

    /// Puts a layout position in the middle of the view, zoomed in to at least `minimumScale`.
    public mutating func center(on position: SIMD2<Double>, zoomingInTo minimumScale: Double) {
        scale = max(scale, minimumScale)
        offset = -position * scale
    }

    /// The room a node's name needs when the fit makes room for it.
    public struct NameRoom: Equatable, Sendable {
        public var characterCount: Int
        /// The zoom from which the name is drawn; 0 when it always is.
        public var shownFromScale: Double

        public init(characterCount: Int, shownFromScale: Double) {
            self.characterCount = characterCount
            self.shownFromScale = shownFromScale
        }
    }

    /// The viewport that shows every position in a view of this size, at most a little larger
    /// than the layout's own size, with room for the names drawn at that zoom: below the
    /// nodes, and at the left and right edges. Nil without positions, for a view without
    /// room, or when `names` does not give one room per position.
    public static func fitting(_ positions: [SIMD2<Double>], names: [NameRoom], in size: CGSize) -> GraphViewport? {
        guard size.width > 0, size.height > 0, positions.count == names.count, var lower = positions.first else { return nil }
        var upper = lower
        for position in positions {
            lower = pointwiseMin(lower, position)
            upper = pointwiseMax(upper, position)
        }
        let margin = fitMarginPoints
        let width = max(upper.x - lower.x, 1), height = max(upper.y - lower.y, 1)
        var fitted = min(max(min((size.width - margin * 2) / width, (size.height - margin * 2) / height), minimumScale), maximumFitScale)
        let showsNames = names.map { name in fitted >= name.shownFromScale }
        let nameHeight = showsNames.contains(true) ? nameHeightPoints : 0
        let halfNameWidths = names.indices.map { index in showsNames[index] ? Double(names[index].characterCount) * halfNameWidthPerCharacterPoints : 0 }
        fitted = min(fitted, max((size.height - margin * 2 - nameHeight) / height, minimumScale))
        var screenCenterX = (lower.x + upper.x) / 2 * fitted
        // Names at the edges need room too: shrink until the widest reach fits.
        for _ in 0..<maximumFitPasses {
            var left = Double.infinity, right = -Double.infinity
            for index in positions.indices {
                left = min(left, positions[index].x * fitted - halfNameWidths[index])
                right = max(right, positions[index].x * fitted + halfNameWidths[index])
            }
            screenCenterX = (left + right) / 2
            let overflow = (right - left) - (size.width - margin * 2)
            guard overflow > fitTolerancePoints else { break }
            fitted = max(fitted * max((width * fitted - overflow) / (width * fitted), smallestShrinkRatioPerPass), minimumScale)
        }
        let screenCenterY = (lower.y + upper.y) / 2 * fitted + nameHeight / 2
        return GraphViewport(scale: fitted, offset: SIMD2(-screenCenterX, -screenCenterY))
    }
}

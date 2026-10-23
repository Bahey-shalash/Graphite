import CoreGraphics

/// The geometry of commits' symbols, Pele's: a dot 7 points in radius; a square a point wider than the dot on each
/// side with rounded corners; a ring 6 points in radius around a dot of 2.5; and the marks drawn on a dot in the
/// background color, a cross on a reverse commit and a cherry on a cherry-pick. The marks of every commit gather here.
struct GitGraphSymbolDrawing {
    let reverseCrosses = CGMutablePath()
    let cherryStems = CGMutablePath()
    let cherryFruits = CGMutablePath()

    static let squareCornerRadius: CGFloat = 2
    static let ringRadius: CGFloat = GitGraphGeometry.dotRadius - 1
    static let mergeDotRadius: CGFloat = 2.5
    /// How far each arm of a reverse commit's cross reaches from the center, across and down.
    static let crossReach: CGFloat = 3
    /// The cherry's stem, from the left fruit up to its top and down to the right fruit, from the dot's center.
    static let cherryStemPoints = [CGVector(dx: -2.6, dy: 1), CGVector(dx: 0.8, dy: -4.2), CGVector(dx: 2.6, dy: 1)]
    static let cherryFruitCenters = [CGVector(dx: -2.6, dy: 2.2), CGVector(dx: 2.6, dy: 2.2)]
    static let cherryFruitRadius: CGFloat = 1.8

    /// Adds `symbol` at `center`: its fills to `symbols`, a merge's ring to `rings`, its marks to the shared paths.
    func add(_ symbol: GitGraphCommitSymbol, at center: CGPoint, symbols: CGMutablePath, rings: CGMutablePath) {
        switch symbol {
        case .normal:
            symbols.addEllipse(in: Self.circle(at: center, radius: GitGraphGeometry.dotRadius))
        case .reverse:
            symbols.addEllipse(in: Self.circle(at: center, radius: GitGraphGeometry.dotRadius))
            let reach = Self.crossReach
            reverseCrosses.addLines(between: [CGPoint(x: center.x - reach, y: center.y - reach), CGPoint(x: center.x + reach, y: center.y + reach)])
            reverseCrosses.addLines(between: [CGPoint(x: center.x - reach, y: center.y + reach), CGPoint(x: center.x + reach, y: center.y - reach)])
        case .highlight:
            let square = Self.circle(at: center, radius: GitGraphGeometry.dotRadius + 1)
            symbols.addRoundedRect(in: square, cornerWidth: Self.squareCornerRadius, cornerHeight: Self.squareCornerRadius)
        case .merge:
            rings.addEllipse(in: Self.circle(at: center, radius: Self.ringRadius))
            symbols.addEllipse(in: Self.circle(at: center, radius: Self.mergeDotRadius))
        case .cherryPick:
            symbols.addEllipse(in: Self.circle(at: center, radius: GitGraphGeometry.dotRadius))
            cherryStems.addLines(between: Self.cherryStemPoints.map { offset in center.translated(by: offset) })
            for fruit in Self.cherryFruitCenters { cherryFruits.addEllipse(in: Self.circle(at: center.translated(by: fruit), radius: Self.cherryFruitRadius)) }
        }
    }

    /// The square around a circle of `radius` at `center`.
    private static func circle(at center: CGPoint, radius: CGFloat) -> CGRect {
        CGRect(x: center.x - radius, y: center.y - radius, width: 2 * radius, height: 2 * radius)
    }
}

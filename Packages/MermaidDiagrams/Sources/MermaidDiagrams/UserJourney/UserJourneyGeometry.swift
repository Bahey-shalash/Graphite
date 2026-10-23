import CoreGraphics

/// Pele's spacing of a user journey, in points.
enum UserJourneyGeometry {
    /// Inside a card, across and down from its text.
    static let cardPadding = CGSize(width: 10, height: 8)
    /// Between two cards.
    static let cardGap: CGFloat = 12
    /// Inside a section's band above and below its heading, and between the band and the cards.
    static let bandPadding: CGFloat = 6
    /// The room at the left of the chart for the scale's numbers.
    static let scaleGutter: CGFloat = 24
    /// How far a scale line starts left of the first card.
    static let scaleLineOverhang: CGFloat = 6
    /// Between a scale number's right edge and the first card.
    static let scaleTextGap: CGFloat = 12
    /// Between two levels of the scale.
    static let levelSpacing: CGFloat = 26
    /// Between the cards' bottom and the top face's top.
    static let chartGap: CGFloat = 16
    static let faceRadius: CGFloat = 11
    static let dotRadius: CGFloat = 5
    /// Between the centers of two dots on a card, at most.
    static let dotSpacing: CGFloat = 13
    /// Between a legend dot and its name.
    static let dotTextGap: CGFloat = 6
    /// Between two legend entries on a row, and between two rows.
    static let legendEntryGap: CGFloat = 20
    static let legendRowGap: CGFloat = 4
    /// Between the lowest face and the legend.
    static let legendGap: CGFloat = 16
    /// The narrowest the legend's rows are before they wrap.
    static let narrowestLegendWidth: CGFloat = 240

    /// Above a card's dots, below its text.
    static let dotRowGap: CGFloat = 6
    /// The height a card gives its actors' dots, when the journey names any actor.
    static let dotRowHeight = 2 * dotRadius + dotRowGap

    /// The scale's levels, the highest first.
    static let levels = Array(stride(from: Int(UserJourneyTask.highestLevel), through: Int(UserJourneyTask.lowestLevel), by: -1))

    /// How far below the highest level's line `level` is.
    static func offset(ofLevel level: Double) -> CGFloat {
        CGFloat(UserJourneyTask.highestLevel - level) * levelSpacing
    }
}

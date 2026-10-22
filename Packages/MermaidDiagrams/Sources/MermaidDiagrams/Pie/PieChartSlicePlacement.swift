import CoreGraphics
import Foundation

/// Where a pie chart's slices and their percentages go, as Pele places them: each slice's share of the whole (none,
/// and the slice not drawn, under one percent), its percentage inside it three quarters of the way out, or outside
/// the rim when the slice is too thin for it, moved along the rim until it overlaps no other percentage there.
struct PieChartSlicePlacement {
    /// Each slice's share of the whole, from 0 to 1; zero for a slice that is not drawn.
    let shares: [Double]
    /// Each drawn slice's percentage, measured; nil for a slice that is not drawn.
    let percentages: [DiagramTextBlock?]
    /// Whether each slice's percentage goes outside the rim.
    let isOutsideRim: [Bool]
    let radius: CGFloat
    /// The room the pie takes beyond its radius on each side: some when a percentage goes outside the rim.
    let outsideLabelRoom: CGFloat

    /// How far out a percentage inside its slice is, as a share of the radius: Mermaid's default `textPosition`.
    static let percentagePosition: CGFloat = 0.75
    /// The room beyond the radius for percentages outside the rim, whose middles are half of it out.
    static let outsideRoom: CGFloat = 28
    /// How much wider than its percentage a slice's chord must be for the percentage to go inside.
    static let thinSliceMargin: CGFloat = 6
    /// The least gap between two percentages outside the rim.
    static let outsideSeparation: CGFloat = 2
    /// The most steps a percentage outside the rim moves along it, each of two points.
    static let maximumPlacementSteps = 360
    static let placementStepLength: CGFloat = 2
    /// The smallest share drawn, in percent: Pele's.
    static let smallestDrawnPercent = 1.0

    init(values: [Double], smallText: some DiagramTextMeasuring, radius: CGFloat) {
        let sum = values.reduce(0, +)
        shares = values.map { value in
            let share = sum > 0 ? value / sum : 0
            return share * 100 >= Self.smallestDrawnPercent ? share : 0
        }
        percentages = shares.map { share in
            share > 0 ? DiagramTextBlock(label: DiagramLabel(Self.percentageText(share)), measurer: smallText, maximumWidth: .greatestFiniteMagnitude) : nil
        }
        isOutsideRim = zip(shares, percentages).map { share, percentage in
            guard let percentage, share < 0.5 else { return false }
            let chord = 2 * radius * Self.percentagePosition * CGFloat(sin(share * .pi))
            return chord < percentage.size.width + Self.thinSliceMargin
        }
        self.radius = radius
        outsideLabelRoom = isOutsideRim.contains(true) ? Self.outsideRoom : 0
    }

    /// A share in whole percent, a half rounded up, as JavaScript's `toFixed(0)` writes it.
    static func percentageText(_ share: Double) -> String {
        "\(Int((share * 100).rounded(.toNearestOrAwayFromZero)))%"
    }

    /// The drawn slices around `center`, clockwise from the top, each with its percentage placed.
    func placed(around center: CGPoint) -> [PieChartLayoutSlice] {
        var slices: [PieChartLayoutSlice] = []
        var outsidePercentages: [OutsidePercentage] = []
        var angle: CGFloat = 0
        for (index, share) in shares.enumerated() {
            guard let percentage = percentages[index] else { continue }
            let endAngle = angle + CGFloat(share) * 2 * .pi
            let middle = (angle + endAngle) / 2
            var placed = percentage
            if isOutsideRim[index] {
                let point = outsidePoint(for: percentage, from: middle, apartFrom: outsidePercentages)
                outsidePercentages.append(OutsidePercentage(middle: point, width: percentage.size.width))
                placed.center = CGPoint(x: center.x + point.x, y: center.y + point.y)
            } else {
                placed.center = Self.point(at: middle, distance: radius * Self.percentagePosition, from: center)
            }
            slices.append(PieChartLayoutSlice(seriesIndex: index, startAngle: angle, endAngle: endAngle, percentage: placed,
                                              percentagePlacement: isOutsideRim[index] ? .outsideRim : .insideSlice))
            angle = endAngle
        }
        return slices
    }

    /// The middle of a percentage outside the rim, relative to the pie's center: at the slice's middle angle, or
    /// moved clockwise along the rim until it is apart from the percentages already there.
    private func outsidePoint(for percentage: DiagramTextBlock, from middle: CGFloat, apartFrom others: [OutsidePercentage]) -> CGPoint {
        let rim = radius + Self.outsideRoom / 2
        var angle = middle
        var point = Self.point(at: angle, distance: rim, from: .zero)
        var step = 0
        while step < Self.maximumPlacementSteps, !isApart(point, width: percentage.size.width, fontSize: percentage.fontSize, from: others) {
            angle += Self.placementStepLength / rim
            point = Self.point(at: angle, distance: rim, from: .zero)
            step += 1
        }
        return point
    }

    /// Whether a percentage centered at `point` is apart from each of `others`, across by their half widths or down
    /// by a line of their text.
    private func isApart(_ point: CGPoint, width: CGFloat, fontSize: CGFloat, from others: [OutsidePercentage]) -> Bool {
        others.allSatisfy { other in
            abs(point.x - other.middle.x) >= (width + other.width) / 2 + Self.outsideSeparation
                || abs(point.y - other.middle.y) >= fontSize + Self.outsideSeparation
        }
    }

    /// A percentage already placed outside the rim: its middle relative to the pie's center, and its width.
    private struct OutsidePercentage {
        let middle: CGPoint
        let width: CGFloat
    }

    /// The point `distance` from `center` at `angle` radians clockwise from the top, on a page whose y runs down.
    static func point(at angle: CGFloat, distance: CGFloat, from center: CGPoint) -> CGPoint {
        CGPoint(x: center.x + CGFloat(sin(Double(angle))) * distance, y: center.y - CGFloat(cos(Double(angle))) * distance)
    }
}

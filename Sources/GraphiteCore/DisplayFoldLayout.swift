/**
 * File: DisplayFoldLayout.swift
 * -----------------------------
 * Layer: Core
 * Description: Where content goes on a display that folds, as iPhone Duo's inner display does: the largest part no
 *              fold crosses, the split fraction that puts a divider on the fold, and an even column count over it.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 21/10/2026
 */

import CoreGraphics

/// Where content goes on a display that folds, as iPhone Duo's inner display does. While the
/// display is partly folded the system reports each fold as a division: a band, in the
/// view's own coordinates, that content must not straddle. A band taller than wide is a fold
/// down the middle of a display held like a book; a band wider than tall is a fold across it.
public enum DisplayFoldLayout {
    /// The largest part of `container` that no division crosses, or `container` itself when
    /// none does. Equal parts go to the leading (or top) one, where reading starts.
    public static func largestUndividedRegion(of container: CGRect, divisions: [CGRect]) -> CGRect {
        var regions = [container]
        for division in divisions {
            regions = regions.flatMap { region in parts(of: region, besides: division) }
        }
        return regions.reduce(nil) { (largest: CGRect?, region: CGRect) in
            guard let largest else { return region }
            return region.width * region.height > largest.width * largest.height ? region : largest
        } ?? container
    }

    /// The split fraction that centres a divider `dividerWidthPoints` wide on the first fold
    /// running down a split `splitWidthPoints` wide (whose sides share the width the divider
    /// leaves, the first side taking the fraction), or nil when no fold runs down the split
    /// or the fraction that reaches it falls outside `allowedRange`.
    public static func splitFraction(dividingAt divisions: [CGRect], splitWidthPoints: CGFloat, dividerWidthPoints: CGFloat,
                                     allowedRange: ClosedRange<Double>) -> Double? {
        let sidesWidthPoints = splitWidthPoints - dividerWidthPoints
        guard sidesWidthPoints > 0,
              let fold = divisions.first(where: { division in
                  isFoldDownTheMiddle(division) && division.midX > 0 && division.midX < splitWidthPoints
              })
        else { return nil }
        let fraction = Double((fold.midX - dividerWidthPoints / 2) / sidesWidthPoints)
        return allowedRange.contains(fraction) ? fraction : nil
    }

    /// How many columns of at least `minimumColumnWidthPoints`, `spacingPoints` apart, fit in
    /// `availableWidthPoints`. Over a fold the count is even, so the fold falls between two
    /// columns rather than through tiles; one column stays one.
    public static func columnCount(availableWidthPoints: CGFloat, minimumColumnWidthPoints: CGFloat, spacingPoints: CGFloat,
                                   isDividedByFold: Bool) -> Int {
        guard minimumColumnWidthPoints > 0 else { return 1 }
        let fittingCount = max(Int(((availableWidthPoints + spacingPoints) / (minimumColumnWidthPoints + spacingPoints)).rounded(.down)), 1)
        guard isDividedByFold, fittingCount > 1 else { return fittingCount }
        return fittingCount - fittingCount % 2
    }

    /// Whether any fold runs down the middle of a view `widthPoints` wide.
    public static func hasFoldDownTheMiddle(_ divisions: [CGRect], widthPoints: CGFloat) -> Bool {
        divisions.contains { division in isFoldDownTheMiddle(division) && division.maxX > 0 && division.minX < widthPoints }
    }

    private static func isFoldDownTheMiddle(_ division: CGRect) -> Bool { division.height >= division.width }

    /// The parts of `region` on either side of `division`; the region whole when the
    /// division does not cross it.
    private static func parts(of region: CGRect, besides division: CGRect) -> [CGRect] {
        guard region.intersects(division) else { return [region] }
        if isFoldDownTheMiddle(division) {
            let leading = CGRect(x: region.minX, y: region.minY, width: max(division.minX - region.minX, 0), height: region.height)
            let trailing = CGRect(x: division.maxX, y: region.minY, width: max(region.maxX - division.maxX, 0), height: region.height)
            return [leading, trailing].filter { part in part.width > 0 }
        }
        let top = CGRect(x: region.minX, y: region.minY, width: region.width, height: max(division.minY - region.minY, 0))
        let bottom = CGRect(x: region.minX, y: division.maxY, width: region.width, height: max(region.maxY - division.maxY, 0))
        return [top, bottom].filter { part in part.height > 0 }
    }
}

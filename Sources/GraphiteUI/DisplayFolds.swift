/**
 * File: DisplayFolds.swift
 * ------------------------
 * Layer: UI
 * Description: The folds the system reports for a partly folded display, read from a view's geometry, and the
 *              modifier that lays a view drawn over others out beside the fold.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 21/10/2026
 */

import SwiftUI
import GraphiteCore

/// The folds of a partly folded display (iPhone Duo's inner display), as the system reports
/// them: its active division regions, in the geometry's own coordinates. Empty on a display
/// that does not fold, on a flat one, before iOS 27.1 and on the Mac.
enum DisplayFolds {
    static func activeDivisions(in geometry: GeometryProxy) -> [CGRect] {
        #if os(iOS)
        if #available(iOS 27.1, *) {
            return geometry.reservedRegions(kind: .division).filter(\.isActive).map(\.frame)
        }
        #endif
        return []
    }
}

extension View {
    /// Lays the view out in the largest part of the space offered to it that no fold crosses,
    /// as system alerts and sheets move aside on a partly folded display; with no fold it
    /// gets the whole space, placed by `alignment`. For a view drawn over others (a palette,
    /// a banner, a floating player), which would otherwise sit across the fold.
    func placedBesideDisplayFold(alignment: Alignment) -> some View {
        GeometryReader { geometry in
            let region = DisplayFoldLayout.largestUndividedRegion(of: CGRect(origin: .zero, size: geometry.size),
                                                                  divisions: DisplayFolds.activeDivisions(in: geometry))
            self.frame(width: region.width, height: region.height, alignment: alignment)
                .offset(x: region.minX, y: region.minY)
        }
    }
}

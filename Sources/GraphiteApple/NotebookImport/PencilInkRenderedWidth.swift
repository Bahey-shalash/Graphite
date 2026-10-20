import Foundation
import GraphiteCore

/// How wide PencilKit draws a stroke point of a given size, for each ink an imported stroke uses. A point's
/// `PKStrokePoint.size` is not the width PencilKit draws, and the relation differs for each ink.
///
/// Measured from `PKDrawing.image(from:scale:)`, which draws identically on iPadOS 27 and macOS 27: straight strokes at
/// 4 pixels per point, counting as ink the rows at least half as opaque as the stroke's middle, averaged over three
/// renderings. Force, altitude and drawing speed do not change the drawn width of stored points. The azimuth turns
/// the fountain pen's nib and the marker's tip; the widths here are with them across the stroke, as
/// `ImportedStrokeBuilder` turns them. Along the stroke the fountain pen draws a quarter of the width, the marker
/// about a third. The pencil's grain makes its edge vary by about 2%.
enum PencilInkRenderedWidth {
    /// One measurement: a point size and the width PencilKit draws it, both in points.
    struct Measurement: Equatable {
        let pointSize: Double
        let renderedWidth: Double
    }

    /// Monoline, pen and the fountain pen across: exactly twice the size less 4 points, nothing below a size of 2.
    static let solidInkMeasurements = [Measurement(pointSize: 2, renderedWidth: 0), Measurement(pointSize: 48, renderedWidth: 92)]
    static let pencilMeasurements = [
        Measurement(pointSize: 0.25, renderedWidth: 0.14), Measurement(pointSize: 0.5, renderedWidth: 0.41),
        Measurement(pointSize: 0.75, renderedWidth: 0.67), Measurement(pointSize: 1, renderedWidth: 0.99),
        Measurement(pointSize: 1.25, renderedWidth: 1.39), Measurement(pointSize: 1.5, renderedWidth: 1.95),
        Measurement(pointSize: 1.75, renderedWidth: 2.63), Measurement(pointSize: 2, renderedWidth: 3.07),
        Measurement(pointSize: 2.5, renderedWidth: 4.04), Measurement(pointSize: 3, renderedWidth: 4.96),
        Measurement(pointSize: 4, renderedWidth: 6.82), Measurement(pointSize: 6, renderedWidth: 10.35),
        Measurement(pointSize: 8, renderedWidth: 13.75), Measurement(pointSize: 12, renderedWidth: 20.7),
        Measurement(pointSize: 16, renderedWidth: 27.6), Measurement(pointSize: 24, renderedWidth: 40.9),
        Measurement(pointSize: 32, renderedWidth: 55.4), Measurement(pointSize: 48, renderedWidth: 82.8)
    ]
    static let markerMeasurements = [
        Measurement(pointSize: 0.25, renderedWidth: 0.12), Measurement(pointSize: 0.5, renderedWidth: 0.36),
        Measurement(pointSize: 0.75, renderedWidth: 0.97), Measurement(pointSize: 1, renderedWidth: 1.5),
        Measurement(pointSize: 1.5, renderedWidth: 2), Measurement(pointSize: 2, renderedWidth: 2.5),
        Measurement(pointSize: 2.5, renderedWidth: 3.5), Measurement(pointSize: 3, renderedWidth: 4),
        Measurement(pointSize: 4, renderedWidth: 5.29), Measurement(pointSize: 5, renderedWidth: 6.75),
        Measurement(pointSize: 6, renderedWidth: 8), Measurement(pointSize: 8, renderedWidth: 10.75),
        Measurement(pointSize: 12, renderedWidth: 16.25), Measurement(pointSize: 16, renderedWidth: 21.5),
        Measurement(pointSize: 24, renderedWidth: 32.5), Measurement(pointSize: 32, renderedWidth: 43.75),
        Measurement(pointSize: 48, renderedWidth: 65.63)
    ]

    /// In increasing order of both size and width.
    static func measurements(for ink: ImportedStroke.Ink) -> [Measurement] {
        switch ink {
        case .monoline, .pen, .fountainPen: solidInkMeasurements
        case .pencil: pencilMeasurements
        case .highlighter: markerMeasurements
        }
    }

    /// The point size PencilKit draws `renderedWidth` points wide in this ink: interpolated between the two nearest
    /// measurements, beyond the widest along the last two, and below the narrowest towards nothing. A width that is
    /// not a positive number gives the size of the narrowest measurement.
    static func pointSize(forRenderedWidth renderedWidth: Double, ink: ImportedStroke.Ink) -> Double {
        let table = measurements(for: ink)
        guard let narrowest = table.first, table.count > 1 else { return 0 }
        guard renderedWidth.isFinite, renderedWidth > 0 else { return narrowest.pointSize }
        if renderedWidth <= narrowest.renderedWidth, narrowest.renderedWidth > 0 {
            return narrowest.pointSize * renderedWidth / narrowest.renderedWidth
        }
        let upperIndex = max(table.firstIndex { measurement in measurement.renderedWidth >= renderedWidth } ?? table.count - 1, 1)
        let lower = table[upperIndex - 1], upper = table[upperIndex]
        let widthRange = upper.renderedWidth - lower.renderedWidth
        guard widthRange > 0 else { return upper.pointSize }
        return lower.pointSize + (renderedWidth - lower.renderedWidth) * (upper.pointSize - lower.pointSize) / widthRange
    }
}

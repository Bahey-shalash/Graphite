import Foundation
import CoreGraphics
import PencilKit
import GraphiteCore
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// Builds the PencilKit stroke that shows an imported stroke on Graphite's canvas and carries it in the page's
/// re-editing record. Each sample becomes one control point at its location, sized so PencilKit draws the sample's
/// width (`PencilInkRenderedWidth`); the samples are used as planned, never resampled.
enum ImportedStrokeBuilder {
    /// Even timing, as if the stroke were drawn at a steady speed; PencilKit draws stored points the same at any speed.
    static let secondsBetweenSamples = 0.008
    /// The Pencil's state where the source recorded none: normal pressure, held upright.
    static let neutralForce = 1.0
    static let neutralAzimuthRadians = 0.0
    static let neutralAltitudeRadians = Double.pi / 2
    /// Each sample draws at full strength; the color's own alpha makes a stroke translucent.
    static let sampleOpacity = 1.0

    /// The stroke in the page canvas's drawing space (page points, origin top-left), which the plan's positions are in.
    /// Samples whose location or width is not a finite number are left out; nil when no sample is left, since
    /// PencilKit cannot hold a stroke without points.
    static func stroke(for importedStroke: ImportedStroke, creationDate: Date) -> PKStroke? {
        let samples = importedStroke.samples.filter { sample in
            sample.location.x.isFinite && sample.location.y.isFinite && sample.width.isFinite
        }
        guard !samples.isEmpty else { return nil }
        let tipAzimuths = turnsTipAcrossStroke(importedStroke.ink) ? acrossStrokeAzimuths(along: samples.map(\.location)) : nil
        let controlPoints = samples.indices.map { sampleIndex in
            let sample = samples[sampleIndex]
            let pointSize = PencilInkRenderedWidth.pointSize(forRenderedWidth: sample.width, ink: importedStroke.ink)
            return PKStrokePoint(location: sample.location, timeOffset: Double(sampleIndex) * secondsBetweenSamples,
                                 size: CGSize(width: pointSize, height: pointSize), opacity: sampleOpacity,
                                 force: sample.force ?? neutralForce,
                                 azimuth: tipAzimuths?[sampleIndex] ?? sample.azimuthRadians ?? neutralAzimuthRadians,
                                 altitude: sample.altitudeRadians ?? neutralAltitudeRadians)
        }
        let ink = PKInk(inkType(for: importedStroke.ink), color: platformColor(importedStroke.color))
        return PKStroke(ink: ink, path: PKStrokePath(controlPoints: controlPoints, creationDate: creationDate))
    }

    static func inkType(for ink: ImportedStroke.Ink) -> PKInk.InkType {
        switch ink {
        case .monoline: .monoline
        case .pen: .pen
        case .fountainPen: .fountainPen
        case .pencil: .pencil
        case .highlighter: .marker
        }
    }

    /// The inks whose tip is not round: their drawn width depends on the azimuth, and the planned width is the width
    /// across the stroke, so the tip is turned across it at every sample whatever the source recorded.
    static func turnsTipAcrossStroke(_ ink: ImportedStroke.Ink) -> Bool {
        switch ink {
        case .fountainPen, .highlighter: true
        case .monoline, .pen, .pencil: false
        }
    }

    /// At each location, the azimuth that turns a tip across the stroke: a quarter turn from the direction between the
    /// neighbouring samples. A location with no direction (a dot, or neighbours at one place) keeps the previous
    /// azimuth, and a stroke without any direction has the tip of a stroke along the rows.
    static func acrossStrokeAzimuths(along locations: [CGPoint]) -> [Double] {
        var azimuths: [Double] = []
        var previousAzimuth = Double.pi / 2
        for locationIndex in locations.indices {
            let earlier = locations[max(locationIndex - 1, 0)]
            let later = locations[min(locationIndex + 1, locations.count - 1)]
            let horizontalDistance = later.x - earlier.x, verticalDistance = later.y - earlier.y
            if horizontalDistance != 0 || verticalDistance != 0 {
                previousAzimuth = Double(atan2(verticalDistance, horizontalDistance)) + .pi / 2
            }
            azimuths.append(previousAzimuth)
        }
        return azimuths
    }

    #if canImport(UIKit)
    private static func platformColor(_ color: NotebookImportColor) -> UIColor {
        UIColor(cgColor: CGColor(srgbRed: color.red, green: color.green, blue: color.blue, alpha: color.alpha))
    }
    #else
    private static func platformColor(_ color: NotebookImportColor) -> NSColor {
        NSColor(srgbRed: color.red, green: color.green, blue: color.blue, alpha: color.alpha)
    }
    #endif
}

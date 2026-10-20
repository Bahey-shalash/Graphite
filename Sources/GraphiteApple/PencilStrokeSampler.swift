import CoreGraphics
import PencilKit
import GraphiteCore
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// Reads PencilKit strokes as geometry that other formats can store.
public enum PencilStrokeSampler {
    private static let sampleSpacing: CGFloat = 1

    /// The visible pieces of a stroke's center line in drawing coordinates. Parts removed
    /// by the pixel eraser are separate pieces, so they are never bridged by a straight
    /// line. The pieces are cut where the center line leaves `visibleArea(of:)`, not at
    /// `maskedPathRanges`, which misplaces the gaps of any moved stroke.
    public static func visibleSegments(of stroke: PKStroke) -> [[VectorStrokeSample]] {
        let samples = centerLineSamples(of: stroke)
        guard let visibleArea = visibleArea(of: stroke) else { return samples.isEmpty ? [] : [samples] }
        var segments: [[VectorStrokeSample]] = []
        var currentSegment: [VectorStrokeSample] = []
        for sample in samples {
            if visibleArea.contains(sample.point, using: .winding) {
                currentSegment.append(sample)
            } else if !currentSegment.isEmpty {
                segments.append(currentSegment)
                currentSegment = []
            }
        }
        if !currentSegment.isEmpty { segments.append(currentSegment) }
        return segments
    }

    /// Ink color as it appears on white paper. Dynamic colors resolve in light mode
    /// because exported drawings do not change with the viewer's appearance.
    public static func color(of stroke: PKStroke) -> VectorInkColor {
        let components = lightAppearanceComponents(of: stroke.ink.color)
        let opacities = stroke.path.map(\.opacity)
        let averageOpacity = opacities.isEmpty ? 1 : opacities.reduce(0, +) / CGFloat(opacities.count)
        return VectorInkColor(clampingRed: Double(components.red), green: Double(components.green), blue: Double(components.blue),
                              alpha: Double(components.alpha * min(max(averageOpacity, 0), 1)))
    }

    #if canImport(UIKit)
    private static func lightAppearanceComponents(of color: UIColor) -> (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        let resolvedColor = color.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 1
        if !resolvedColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha),
           let components = standardComponents(of: resolvedColor.cgColor) {
            // A color UIKit cannot express as RGB (a pattern, for example) is converted by
            // Core Graphics instead of silently becoming black.
            return components
        }
        return (red, green, blue, alpha)
    }
    #else
    /// AppKit resolves a dynamic color in the current drawing appearance, so the light one is made current.
    private static func lightAppearanceComponents(of color: NSColor) -> (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        var resolvedColor: NSColor?
        if let lightAppearance = NSAppearance(named: .aqua) {
            lightAppearance.performAsCurrentDrawingAppearance { resolvedColor = color.usingColorSpace(.extendedSRGB) }
        }
        if let rgbColor = resolvedColor ?? color.usingColorSpace(.extendedSRGB) {
            return (rgbColor.redComponent, rgbColor.greenComponent, rgbColor.blueComponent, rgbColor.alphaComponent)
        }
        return standardComponents(of: color.cgColor) ?? (0, 0, 0, 1)
    }
    #endif

    private static func standardComponents(of color: CGColor) -> (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat)? {
        guard let standardColorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let convertedColor = color.converted(to: standardColorSpace, intent: .defaultIntent, options: nil),
              let components = convertedColor.components, components.count == 4 else { return nil }
        return (components[0], components[1], components[2], components[3])
    }

    /// Where a stroke the pixel eraser touched is still visible, in drawing coordinates,
    /// or nil when nothing was erased. PencilKit draws the mask in the stroke's own space,
    /// moved with the stroke's transform. (`maskedPathRanges` compares the untransformed
    /// mask with the transformed path, so it misplaces the gaps of any moved stroke, and
    /// every stroke is moved when a drawing is cropped for export.)
    public static func visibleArea(of stroke: PKStroke) -> CGPath? {
        guard let mask = stroke.mask else { return nil }
        var transform = stroke.transform
        // Callers fill and test the area with the nonzero rule; a normalized path has no
        // overlaps, so it covers the same region under either rule.
        #if canImport(UIKit)
        let usesEvenOddRule = mask.usesEvenOddFillRule
        #else
        let usesEvenOddRule = mask.windingRule == .evenOdd
        #endif
        let maskPath = usesEvenOddRule ? mask.cgPath.normalized(using: .evenOdd) : mask.cgPath
        return maskPath.copy(using: &transform)
    }

    /// The whole center line in drawing coordinates, erased parts included.
    static func centerLineSamples(of stroke: PKStroke) -> [VectorStrokeSample] {
        let transform = stroke.transform
        let widthScale = abs(transform.a * transform.d - transform.b * transform.c).squareRoot()
        return stroke.path.interpolatedPoints(in: nil, by: .distance(sampleSpacing)).map { strokePoint in
            VectorStrokeSample(point: strokePoint.location.applying(transform), width: Double(strokePoint.size.width * widthScale))
        }
    }
}

public enum PencilVectorConverter {
    /// `drawing` must already be in export coordinates: origin at the top-left corner.
    public static func vectorDrawing(from drawing: PKDrawing, size: CGSize, background: DrawingBackground) -> VectorDrawing {
        let shapes = drawing.strokes.compactMap { stroke in
            let color = PencilStrokeSampler.color(of: stroke)
            guard let visibleArea = PencilStrokeSampler.visibleArea(of: stroke) else {
                return StrokeOutliner.shape(forSegments: PencilStrokeSampler.visibleSegments(of: stroke), color: color)
            }
            // The whole outline clipped to the eraser mask matches PencilKit's rendering,
            // including erasures that only trim the edge of a wide stroke.
            return StrokeOutliner.shape(forSegments: [PencilStrokeSampler.centerLineSamples(of: stroke)], color: color, clippedTo: visibleArea)
        }
        return VectorDrawing(size: size, background: background, shapes: shapes)
    }
}

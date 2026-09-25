#if canImport(UIKit)
import UIKit
import PencilKit
import GraphiteCore

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
        let resolvedColor = stroke.ink.color.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 1
        if !resolvedColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha),
           let standardColorSpace = CGColorSpace(name: CGColorSpace.sRGB),
           let convertedColor = resolvedColor.cgColor.converted(to: standardColorSpace, intent: .defaultIntent, options: nil),
           let components = convertedColor.components, components.count == 4 {
            // A color UIKit cannot express as RGB (a pattern, for example) is converted by
            // Core Graphics instead of silently becoming black.
            red = components[0]; green = components[1]; blue = components[2]; alpha = components[3]
        }
        let opacities = stroke.path.map(\.opacity)
        let averageOpacity = opacities.isEmpty ? 1 : opacities.reduce(0, +) / CGFloat(opacities.count)
        return VectorInkColor(clampingRed: Double(red), green: Double(green), blue: Double(blue), alpha: Double(alpha * min(max(averageOpacity, 0), 1)))
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
        let maskPath = mask.usesEvenOddFillRule ? mask.cgPath.normalized(using: .evenOdd) : mask.cgPath
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
#endif

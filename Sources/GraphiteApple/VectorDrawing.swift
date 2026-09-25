import Foundation
import CoreGraphics
import ImageIO
import GraphiteCore

public struct VectorInkColor: Sendable, Equatable {
    public let red: Double
    public let green: Double
    public let blue: Double
    public let alpha: Double
    public init(red: Double, green: Double, blue: Double, alpha: Double) {
        self.red = red; self.green = green; self.blue = blue; self.alpha = alpha
    }

    /// Components limited to 0...1. Wide-gamut inks (Display P3 from the color picker)
    /// read back as extended sRGB values outside that range, which the PDF, SVG and PNG
    /// writers would otherwise each handle differently. NaN becomes 0.
    public init(clampingRed red: Double, green: Double, blue: Double, alpha: Double) {
        func clamped(_ component: Double) -> Double { component.isNaN ? 0 : min(max(component, 0), 1) }
        self.init(red: clamped(red), green: clamped(green), blue: clamped(blue), alpha: clamped(alpha))
    }
}

/// A point on a stroke's center line and the ink width there, in drawing points.
public struct VectorStrokeSample: Sendable, Equatable {
    public let point: CGPoint
    public let width: Double
    public init(point: CGPoint, width: Double) {
        self.point = point
        self.width = width
    }
}

/// One stroke as filled outlines. All subpaths are filled together with the nonzero
/// rule, so overlapping parts of a translucent stroke are not darkened twice.
public struct VectorShape: Sendable, Equatable {
    public let subpaths: [[CGPoint]]
    public let color: VectorInkColor
    public init(subpaths: [[CGPoint]], color: VectorInkColor) {
        self.subpaths = subpaths
        self.color = color
    }
}

/// A drawing in a top-left coordinate system, shared by the SVG and PDF writers.
public struct VectorDrawing: Sendable, Equatable {
    public let size: CGSize
    public let background: DrawingBackground
    public let shapes: [VectorShape]
    public init(size: CGSize, background: DrawingBackground, shapes: [VectorShape]) {
        self.size = size
        self.background = background
        self.shapes = shapes
    }
}

/// Turns variable-width center lines into closed outlines with round caps.
public enum StrokeOutliner {
    private static let minimumRadius = 0.2
    private static let duplicatePointDistance = 0.05
    private static let simplificationTolerance = 0.1
    /// Where the path bends more tightly than this multiple of the ink radius, the
    /// offset outline can fold over itself, so a round join is added.
    private static let tightTurnRadiusMultiple = 1.5
    /// Largest distance, in drawing points, between a clipped curve and the straight
    /// segments that replace it; well under a pixel at 2x.
    private static let clipFlatteningTolerance = 0.05

    /// - Parameter visibleArea: The region where the stroke is visible, when the pixel
    ///   eraser removed parts of it. The outline is intersected with it, so erased gaps
    ///   stay exactly as wide as PencilKit draws them instead of being refilled by the
    ///   round caps at the cut ends.
    public static func shape(forSegments segments: [[VectorStrokeSample]], color: VectorInkColor, clippedTo visibleArea: CGPath? = nil) -> VectorShape? {
        var subpaths = segments.flatMap(subpaths(forSamples:))
        if let visibleArea, !subpaths.isEmpty {
            subpaths = clipped(subpaths, to: visibleArea)
        }
        return subpaths.isEmpty ? nil : VectorShape(subpaths: subpaths, color: color)
    }

    /// The part of a nonzero-filled outline inside `visibleArea`, as polygons. Core
    /// Graphics returns boolean results that fill the same with either fill rule, so the
    /// writers' nonzero rule stays correct.
    static func clipped(_ subpaths: [[CGPoint]], to visibleArea: CGPath) -> [[CGPoint]] {
        let outline = CGMutablePath()
        for subpath in subpaths where subpath.count > 2 {
            outline.addLines(between: subpath)
            outline.closeSubpath()
        }
        let visibleOutline = outline.intersection(visibleArea, using: .winding).flattened(threshold: clipFlatteningTolerance)
        var clippedSubpaths: [[CGPoint]] = []
        var currentSubpath: [CGPoint] = []
        func finishSubpath() {
            if currentSubpath.count > 2 { clippedSubpaths.append(currentSubpath) }
            currentSubpath = []
        }
        visibleOutline.applyWithBlock { elementPointer in
            let element = elementPointer.pointee
            switch element.type {
            case .moveToPoint:
                finishSubpath()
                currentSubpath = [element.points[0]]
            case .addLineToPoint:
                currentSubpath.append(element.points[0])
            case .addQuadCurveToPoint:
                // A flattened path has no curves; keep the end point if one ever appears.
                currentSubpath.append(element.points[1])
            case .addCurveToPoint:
                currentSubpath.append(element.points[2])
            case .closeSubpath:
                finishSubpath()
            @unknown default:
                break
            }
        }
        finishSubpath()
        return clippedSubpaths
    }

    public static func subpaths(forSamples rawSamples: [VectorStrokeSample]) -> [[CGPoint]] {
        let samples = withoutDuplicatePoints(rawSamples.filter { sample in sample.point.x.isFinite && sample.point.y.isFinite && sample.width.isFinite })
        guard let firstSample = samples.first, let lastSample = samples.last else { return [] }
        if samples.count == 1 {
            return [circle(center: firstSample.point, radius: radius(of: firstSample))]
        }
        var tangents: [CGVector] = []
        var leftSide: [CGPoint] = []
        var rightSide: [CGPoint] = []
        for sampleIndex in samples.indices {
            let previousPoint = samples[max(sampleIndex - 1, 0)].point
            let nextPoint = samples[min(sampleIndex + 1, samples.count - 1)].point
            let tangent = normalized(CGVector(dx: nextPoint.x - previousPoint.x, dy: nextPoint.y - previousPoint.y)) ?? tangents.last ?? CGVector(dx: 1, dy: 0)
            tangents.append(tangent)
            let normal = CGVector(dx: -tangent.dy, dy: tangent.dx)
            let sampleRadius = radius(of: samples[sampleIndex])
            let point = samples[sampleIndex].point
            leftSide.append(CGPoint(x: point.x + normal.dx * sampleRadius, y: point.y + normal.dy * sampleRadius))
            rightSide.append(CGPoint(x: point.x - normal.dx * sampleRadius, y: point.y - normal.dy * sampleRadius))
        }
        let firstTangent = tangents[0], lastTangent = tangents[tangents.count - 1]
        var outline = simplified(leftSide, tolerance: simplificationTolerance)
        outline += roundCap(center: lastSample.point, tangent: lastTangent, radius: radius(of: lastSample), isEnd: true)
        outline += simplified(rightSide, tolerance: simplificationTolerance).reversed()
        outline += roundCap(center: firstSample.point, tangent: firstTangent, radius: radius(of: firstSample), isEnd: false)
        var subpaths = [outline]
        let outlineIsCounterclockwise = signedArea(outline) >= 0
        for sampleIndex in 1..<(samples.count - 1) where hasTightTurn(at: sampleIndex, in: samples) {
            let join = circle(center: samples[sampleIndex].point, radius: radius(of: samples[sampleIndex]))
            // Same orientation as the outline, so the nonzero rule adds coverage.
            subpaths.append(outlineIsCounterclockwise ? join : join.reversed())
        }
        return subpaths
    }

    private static func radius(of sample: VectorStrokeSample) -> Double { max(sample.width / 2, minimumRadius) }

    private static func withoutDuplicatePoints(_ samples: [VectorStrokeSample]) -> [VectorStrokeSample] {
        var kept: [VectorStrokeSample] = []
        for sample in samples {
            if let lastKept = kept.last, distance(lastKept.point, sample.point) < duplicatePointDistance {
                kept[kept.count - 1] = VectorStrokeSample(point: lastKept.point, width: max(lastKept.width, sample.width))
            } else {
                kept.append(sample)
            }
        }
        return kept
    }

    private static func hasTightTurn(at sampleIndex: Int, in samples: [VectorStrokeSample]) -> Bool {
        let previousPoint = samples[sampleIndex - 1].point, point = samples[sampleIndex].point, nextPoint = samples[sampleIndex + 1].point
        guard let incoming = normalized(CGVector(dx: point.x - previousPoint.x, dy: point.y - previousPoint.y)),
              let outgoing = normalized(CGVector(dx: nextPoint.x - point.x, dy: nextPoint.y - point.y)) else { return false }
        let turnAngle = acos(min(1, max(-1, incoming.dx * outgoing.dx + incoming.dy * outgoing.dy)))
        let averageSegmentLength = (distance(previousPoint, point) + distance(point, nextPoint)) / 2
        guard turnAngle > 0.01, averageSegmentLength > 0 else { return false }
        let curvatureRadius = averageSegmentLength / turnAngle
        return curvatureRadius < radius(of: samples[sampleIndex]) * tightTurnRadiusMultiple
    }

    /// Half circle from the left side to the right side (end) or back (start).
    private static func roundCap(center: CGPoint, tangent: CGVector, radius: Double, isEnd: Bool) -> [CGPoint] {
        let normal = CGVector(dx: -tangent.dy, dy: tangent.dx)
        let segmentCount = circleSegmentCount(radius: radius) / 2
        let direction = isEnd ? 1.0 : -1.0
        return (1..<segmentCount).map { segmentIndex in
            let angle = Double.pi * Double(segmentIndex) / Double(segmentCount)
            return CGPoint(x: center.x + direction * radius * (normal.dx * cos(angle) + tangent.dx * sin(angle)),
                           y: center.y + direction * radius * (normal.dy * cos(angle) + tangent.dy * sin(angle)))
        }
    }

    private static func circle(center: CGPoint, radius: Double) -> [CGPoint] {
        let segmentCount = circleSegmentCount(radius: radius)
        return (0..<segmentCount).map { segmentIndex in
            let angle = 2 * Double.pi * Double(segmentIndex) / Double(segmentCount)
            return CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
        }
    }

    private static func circleSegmentCount(radius: Double) -> Int {
        let maximumChordLength = 1.0
        // Clamped before converting: a corrupt stroke width near 1e19 would overflow Int.
        let segmentCount = min(48, max(12, (2 * Double.pi * radius / maximumChordLength).rounded(.up)))
        return Int(segmentCount) & ~1
    }

    static func signedArea(_ polygon: [CGPoint]) -> Double {
        guard polygon.count > 2 else { return 0 }
        var doubledArea = 0.0
        for pointIndex in polygon.indices {
            let point = polygon[pointIndex], nextPoint = polygon[(pointIndex + 1) % polygon.count]
            doubledArea += point.x * nextPoint.y - nextPoint.x * point.y
        }
        return doubledArea / 2
    }

    /// Iterative Ramer–Douglas–Peucker simplification (no recursion for long strokes).
    static func simplified(_ points: [CGPoint], tolerance: Double) -> [CGPoint] {
        guard points.count > 2 else { return points }
        var keeps = [Bool](repeating: false, count: points.count)
        keeps[0] = true; keeps[points.count - 1] = true
        var pendingRanges = [(0, points.count - 1)]
        while let (startIndex, endIndex) = pendingRanges.popLast() {
            guard endIndex > startIndex + 1 else { continue }
            var farthestIndex = startIndex, farthestDistance = 0.0
            for pointIndex in (startIndex + 1)..<endIndex {
                let pointDistance = distance(from: points[pointIndex], toSegmentFrom: points[startIndex], to: points[endIndex])
                if pointDistance > farthestDistance { farthestDistance = pointDistance; farthestIndex = pointIndex }
            }
            if farthestDistance > tolerance {
                keeps[farthestIndex] = true
                pendingRanges.append((startIndex, farthestIndex))
                pendingRanges.append((farthestIndex, endIndex))
            }
        }
        return points.indices.compactMap { pointIndex in keeps[pointIndex] ? points[pointIndex] : nil }
    }

    private static func distance(_ firstPoint: CGPoint, _ secondPoint: CGPoint) -> Double {
        hypot(firstPoint.x - secondPoint.x, firstPoint.y - secondPoint.y)
    }

    private static func distance(from point: CGPoint, toSegmentFrom segmentStart: CGPoint, to segmentEnd: CGPoint) -> Double {
        let segmentX = segmentEnd.x - segmentStart.x, segmentY = segmentEnd.y - segmentStart.y
        let squaredLength = segmentX * segmentX + segmentY * segmentY
        guard squaredLength > 0 else { return distance(point, segmentStart) }
        let projection = max(0, min(1, ((point.x - segmentStart.x) * segmentX + (point.y - segmentStart.y) * segmentY) / squaredLength))
        return distance(point, CGPoint(x: segmentStart.x + projection * segmentX, y: segmentStart.y + projection * segmentY))
    }

    private static func normalized(_ vector: CGVector) -> CGVector? {
        let length = hypot(vector.dx, vector.dy)
        guard length > 1e-9 else { return nil }
        return CGVector(dx: vector.dx / length, dy: vector.dy / length)
    }
}

public enum VectorDrawingRenderer {
    /// Draws into a context whose origin is the drawing's top-left corner, y down.
    public static func draw(_ drawing: VectorDrawing, in context: CGContext) {
        // sRGB, like the SVG writer's hex colors and PencilKit's resolved ink components.
        // `CGColor(red:green:blue:alpha:)` is Generic RGB and shifts every color.
        if drawing.background == .white {
            context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
            context.fill(CGRect(origin: .zero, size: drawing.size))
        }
        for shape in drawing.shapes {
            context.beginPath()
            for subpath in shape.subpaths {
                guard let firstPoint = subpath.first else { continue }
                context.move(to: firstPoint)
                for point in subpath.dropFirst() { context.addLine(to: point) }
                context.closePath()
            }
            context.setFillColor(CGColor(srgbRed: shape.color.red, green: shape.color.green, blue: shape.color.blue, alpha: shape.color.alpha))
            context.fillPath(using: .winding)
        }
    }

    /// An sRGB PNG raster of the vector content, for previews.
    public static func pngData(for drawing: VectorDrawing, maximumPixelDimension: Int) throws -> Data {
        try ImageEncoding.pngData(from: image(for: drawing, maximumPixelDimension: maximumPixelDimension))
    }

    /// An sRGB raster of the vector content, for previews that display it directly.
    public static func image(for drawing: VectorDrawing, maximumPixelDimension: Int) throws -> CGImage {
        let width = drawing.size.width, height = drawing.size.height
        // `max` ignores a NaN side, so each side is checked before sizing the bitmap.
        guard width.isFinite, height.isFinite, width >= 0, height >= 0, max(width, height) > 0, maximumPixelDimension > 0 else {
            throw GraphiteError.invalidFile("The drawing has no size.")
        }
        let longestSide = max(width, height)
        let scale = min(2, Double(maximumPixelDimension) / longestSide)
        let pixelWidth = max(1, Int((drawing.size.width * scale).rounded())), pixelHeight = max(1, Int((drawing.size.height * scale).rounded()))
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: pixelWidth, height: pixelHeight, bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw GraphiteError.unavailable("Cannot allocate the drawing preview.")
        }
        context.translateBy(x: 0, y: Double(pixelHeight))
        context.scaleBy(x: scale, y: -scale)
        draw(drawing, in: context)
        guard let image = context.makeImage() else { throw GraphiteError.unavailable("Cannot render the drawing preview.") }
        return image
    }
}

public enum ImageEncoding {
    /// An ordinary PNG of already decoded pixels, for a view that must hand PNG bytes on,
    /// such as when copying an image it shows.
    public static func pngData(from image: CGImage) throws -> Data {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, "public.png" as CFString, 1, nil) else {
            throw GraphiteError.invalidFile("Cannot create a PNG image.")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw GraphiteError.invalidFile("Cannot finish the PNG image.") }
        return output as Data
    }
}

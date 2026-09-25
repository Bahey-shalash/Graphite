import Foundation
import CoreGraphics
import PDFKit
import GraphiteCore
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// Standard PDF ink for one Pencil stroke. Each segment is a separate path so that
/// parts removed by the eraser are not bridged by a straight line.
public struct PortableInkStroke: Sendable, Equatable {
    public let segments: [[CGPoint]]
    public let width: Double
    public let red: Double
    public let green: Double
    public let blue: Double
    public let alpha: Double
    /// Stored as the standard `/NM` annotation name so later edits can find this stroke.
    public let name: String?
    /// The stroke's filled outline in page space, with the width variation PencilKit drew.
    /// When present it becomes the annotation's appearance; `/InkList` keeps the center line.
    public let outline: [[CGPoint]]?

    public init(name: String?, segments: [[CGPoint]], width: Double, red: Double, green: Double, blue: Double, alpha: Double, outline: [[CGPoint]]?) {
        self.name = name
        self.segments = segments
        self.width = width
        self.red = red; self.green = green; self.blue = blue; self.alpha = alpha
        self.outline = outline?.filter { subpath in subpath.count > 2 }
    }
}

/// An `/Ink` annotation whose normal appearance (`/AP`) is the stroke's filled outline.
///
/// PDFKit writes whatever `draw(with:in:)` draws as the appearance stream, so Preview,
/// PDFKit, Poppler and Ghostscript show the width variation the Pencil made. The
/// `/InkList` center line stays in the file: readers that rebuild ink appearances, or
/// edit the annotation, fall back to a line of the average width.
///
/// Only documents that are written use this class. PDFKit draws annotations for display
/// in unrotated page space and expects them to apply the page rotation themselves, but
/// generates appearance streams in page space; a subclass cannot tell the two apart, so
/// the displayed document keeps plain ink annotations (the Pencil canvas shows the ink).
final class PDFOutlinedInkAnnotation: PDFAnnotation {
    // Optional object references only: PDFKit copies annotations (page duplication,
    // export) through Objective-C, which leaves Swift properties zeroed until
    // `copy(with:)` sets them, and a zeroed optional reference is a valid nil.
    // Never mutated after the annotation is shared, since PDFKit renders on other threads.
    private var outlinePath: CGPath?
    private var fillColor: CGColor?

    init(bounds: CGRect, outlineSubpaths: [[CGPoint]], fillColor: CGColor) {
        let path = CGMutablePath()
        for subpath in outlineSubpaths {
            guard let firstPoint = subpath.first else { continue }
            path.move(to: firstPoint)
            for point in subpath.dropFirst() { path.addLine(to: point) }
            path.closeSubpath()
        }
        outlinePath = path.copy()
        self.fillColor = fillColor
        super.init(bounds: bounds, forType: .ink, withProperties: nil)
    }

    override init(bounds: CGRect, forType annotationType: PDFAnnotationSubtype, withProperties properties: [AnyHashable: Any]?) {
        super.init(bounds: bounds, forType: annotationType, withProperties: properties)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func copy(with zone: NSZone? = nil) -> Any {
        let copiedAnnotation = super.copy(with: zone)
        if let copiedAnnotation = copiedAnnotation as? PDFOutlinedInkAnnotation {
            copiedAnnotation.outlinePath = outlinePath
            copiedAnnotation.fillColor = fillColor
        }
        return copiedAnnotation
    }

    override func draw(with box: PDFDisplayBox, in context: CGContext) {
        guard let outlinePath, let fillColor else {
            super.draw(with: box, in: context)
            return
        }
        context.saveGState()
        // The outline is in page space, but PDFKit generates the appearance stream with
        // the MediaBox origin as the origin. Pages whose MediaBox does not start at (0, 0),
        // common in cropped PDFs, would otherwise get ink outside the appearance's box.
        if let mediaBoxOrigin = page?.bounds(for: .mediaBox).origin {
            context.translateBy(x: -mediaBoxOrigin.x, y: -mediaBoxOrigin.y)
        }
        context.addPath(outlinePath)
        context.setFillColor(fillColor)
        // Nonzero winding fills overlapping parts of one translucent stroke once.
        context.fillPath(using: .winding)
        context.restoreGState()
    }
}

enum PDFInkAnnotationFactory {
    /// Center-line points closer than this to the simplified line are dropped from `/InkList`.
    private static let inkListSimplificationTolerance = 0.2
    /// Room around the ink so no reader clips anti-aliased edges at the annotation rectangle.
    private static let boundsMargin = 1.0

    /// `drawsOutline` selects the outlined appearance for documents that are written.
    static func annotation(for stroke: PortableInkStroke, group: String, drawsOutline: Bool) -> PDFAnnotation? {
        let segments = stroke.segments.filter { segment in !segment.isEmpty && segment.allSatisfy { point in point.x.isFinite && point.y.isFinite } }
        guard !segments.isEmpty, stroke.width.isFinite else { return nil }
        let color = CGColor(srgbRed: stroke.red, green: stroke.green, blue: stroke.blue, alpha: stroke.alpha)
        let outline = stroke.outline ?? []
        let inkPoints = Array(segments.joined()) + Array(outline.joined())
        let inkBounds = bounds(of: inkPoints).insetBy(dx: -(stroke.width / 2 + boundsMargin), dy: -(stroke.width / 2 + boundsMargin))
        let annotation: PDFAnnotation = outline.isEmpty || !drawsOutline
            ? PDFAnnotation(bounds: inkBounds, forType: .ink, withProperties: nil)
            : PDFOutlinedInkAnnotation(bounds: inkBounds, outlineSubpaths: outline, fillColor: color)
        #if canImport(UIKit)
        annotation.color = UIColor(cgColor: color)
        #else
        annotation.color = NSColor(cgColor: color) ?? .black
        #endif
        // One path per segment: PDFKit writes each added path as its own InkList
        // entry, while subpaths of a single path would be joined into one line.
        for segment in segments {
            var points = StrokeOutliner.simplified(segment, tolerance: inkListSimplificationTolerance)
            // A single tap still needs a visible mark in readers that draw the InkList.
            if points.count == 1, let onlyPoint = points.first { points.append(CGPoint(x: onlyPoint.x + 0.01, y: onlyPoint.y)) }
            annotation.add(path(through: points.map { point in CGPoint(x: point.x - inkBounds.minX, y: point.y - inkBounds.minY) }))
        }
        let border = PDFBorder()
        border.lineWidth = max(0.5, stroke.width)
        annotation.border = border
        annotation.shouldPrint = true
        annotation.setValue(group, forAnnotationKey: PDFPageManager.groupKey)
        if let name = stroke.name { annotation.setPersistentName(name) }
        return annotation
    }

    private static func bounds(of points: [CGPoint]) -> CGRect {
        guard let firstPoint = points.first else { return .null }
        var minimumX = firstPoint.x, maximumX = firstPoint.x, minimumY = firstPoint.y, maximumY = firstPoint.y
        for point in points {
            minimumX = min(minimumX, point.x); maximumX = max(maximumX, point.x)
            minimumY = min(minimumY, point.y); maximumY = max(maximumY, point.y)
        }
        return CGRect(x: minimumX, y: minimumY, width: maximumX - minimumX, height: maximumY - minimumY)
    }

    #if canImport(UIKit)
    private static func path(through points: [CGPoint]) -> UIBezierPath {
        let path = UIBezierPath()
        for (pointIndex, point) in points.enumerated() {
            if pointIndex == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        return path
    }
    #else
    private static func path(through points: [CGPoint]) -> NSBezierPath {
        let path = NSBezierPath()
        for (pointIndex, point) in points.enumerated() {
            if pointIndex == 0 { path.move(to: point) } else { path.line(to: point) }
        }
        return path
    }
    #endif
}

/// Re-editing data for one page's Pencil ink: the PencilKit drawing and, for each of its
/// strokes in drawing order, the `/NM` name of the annotation that shows it (empty when
/// the stroke has no visible ink). Stored on the first annotation of the ink group.
public struct PDFEditableInkRecord: Sendable, Equatable {
    public let drawingData: Data
    public let strokeNames: [String]
    public init(drawingData: Data, strokeNames: [String]) {
        self.drawingData = drawingData
        self.strokeNames = strokeNames
    }
}

/// One change to a page's Pencil ink: annotations removed by name (or the whole group),
/// strokes added, and the new re-editing record. Only strokes that changed are
/// converted and written, so the cost of a stroke does not grow with the page.
///
/// Archiving the drawing for the record costs time proportional to the page, so an update
/// can defer it: the group keeps the record it has (moved to the group's new first
/// annotation when that one is removed), and a later update writes the current record.
/// Until then the kept record's stroke names do not match the annotations, so the group
/// is not editable when read back; the later update must come before the document is
/// read for re-editing or written.
public struct PDFInkUpdate: Sendable, Equatable {
    public enum Removal: Sendable, Equatable {
        case strokes(Set<String>)
        /// Replaces every annotation of the group, used when the stroke names are unknown.
        case entireGroup
    }

    public let pageIndex: Int
    public let group: String
    public let removal: Removal
    public let addedStrokes: [PortableInkStroke]
    /// The new re-editing record; nil removes it, unless `defersEditableRecord`.
    public let editableRecord: PDFEditableInkRecord?
    /// True when the group keeps its current record and a later update writes the new one.
    public let defersEditableRecord: Bool

    public init(pageIndex: Int, group: String, removal: Removal, addedStrokes: [PortableInkStroke], editableRecord: PDFEditableInkRecord?,
                defersEditableRecord: Bool = false) {
        self.pageIndex = pageIndex
        self.group = group
        self.removal = removal
        self.addedStrokes = addedStrokes
        self.editableRecord = defersEditableRecord ? nil : editableRecord
        self.defersEditableRecord = defersEditableRecord
    }

    /// One update equivalent to applying `self` and then `later`, or nil when they
    /// concern different pages or groups. Keeps the session's edit list short.
    public func merged(with later: PDFInkUpdate) -> PDFInkUpdate? {
        guard later.pageIndex == pageIndex, later.group == group else { return nil }
        // A later update that defers its record leaves the record this one wrote, or kept.
        let mergedRecord = later.defersEditableRecord ? editableRecord : later.editableRecord
        let mergedDefersRecord = later.defersEditableRecord && defersEditableRecord
        switch later.removal {
        case .entireGroup:
            return PDFInkUpdate(pageIndex: pageIndex, group: group, removal: .entireGroup, addedStrokes: later.addedStrokes,
                                editableRecord: mergedRecord, defersEditableRecord: mergedDefersRecord)
        case .strokes(let laterRemovedNames):
            let namesAddedHere = Set(addedStrokes.compactMap(\.name))
            let mergedRemoval: Removal
            switch removal {
            case .entireGroup: mergedRemoval = .entireGroup
            case .strokes(let removedNames): mergedRemoval = .strokes(removedNames.union(laterRemovedNames.subtracting(namesAddedHere)))
            }
            let survivingStrokes = addedStrokes.filter { stroke in stroke.name.map { name in !laterRemovedNames.contains(name) } ?? true }
            return PDFInkUpdate(pageIndex: pageIndex, group: group, removal: mergedRemoval, addedStrokes: survivingStrokes + later.addedStrokes,
                                editableRecord: mergedRecord, defersEditableRecord: mergedDefersRecord)
        }
    }
}

/// The ink group on a page whose strokes Graphite can edit again, read from the file.
public struct PDFEditableInkGroup: Sendable, Equatable {
    public let group: String
    public let record: PDFEditableInkRecord
    /// False for files written before stroke names were stored: the first edit then
    /// replaces the whole group, because strokes cannot be matched to annotations.
    public var hasStrokeNames: Bool { !record.strokeNames.isEmpty }
}

public enum PDFInkGroups {
    public static let defaultGroup = "GraphitePageInkV1"
    /// Bounds the re-editing metadata read from a file before it is decoded.
    public static let maximumEncodedDrawingBytes = DrawingLimits.maximumPayloadBytes * 2
    public static let maximumEncodedStrokeNameBytes = 16 * 1_048_576

    /// The group of ink annotations Graphite can edit on this page, or nil when there is
    /// none. A group qualifies when its first annotation carries the drawing, and when
    /// its stroke names still match its annotations one to one. Annotations removed,
    /// added, or renamed by another application make the group read-only: its visible
    /// ink stays exactly as it is and new strokes go into a new group.
    public static func editableGroup(on page: PDFPage) -> PDFEditableInkGroup? {
        var groupsInOrder: [String] = []
        var annotationsByGroup: [String: [PDFAnnotation]] = [:]
        for annotation in page.annotations {
            guard let group = annotation.value(forAnnotationKey: PDFPageManager.groupKey) as? String else { continue }
            if annotationsByGroup[group] == nil { groupsInOrder.append(group) }
            annotationsByGroup[group, default: []].append(annotation)
        }
        for group in groupsInOrder {
            guard let groupAnnotations = annotationsByGroup[group], let carrier = groupAnnotations.first,
                  let encodedDrawing = carrier.value(forAnnotationKey: PDFPageManager.drawingKey) as? String,
                  encodedDrawing.utf8.count <= maximumEncodedDrawingBytes,
                  let drawingData = Data(base64Encoded: encodedDrawing) else { continue }
            let encodedNames = carrier.value(forAnnotationKey: PDFPageManager.strokeNamesKey) as? String
            guard let encodedNames else {
                return PDFEditableInkGroup(group: group, record: PDFEditableInkRecord(drawingData: drawingData, strokeNames: []))
            }
            guard encodedNames.utf8.count <= maximumEncodedStrokeNameBytes else { continue }
            let strokeNames = decodeStrokeNames(encodedNames)
            let annotationNames = groupAnnotations.map { annotation in annotation.persistentName ?? "" }
            let namedStrokes = strokeNames.filter { name in !name.isEmpty }
            guard !strokeNames.isEmpty, !annotationNames.contains(""), Set(annotationNames).count == annotationNames.count,
                  Set(namedStrokes).count == namedStrokes.count, Set(namedStrokes) == Set(annotationNames) else { continue }
            return PDFEditableInkGroup(group: group, record: PDFEditableInkRecord(drawingData: drawingData, strokeNames: strokeNames))
        }
        return nil
    }

    /// The group for new ink on a page without an editable group. It never reuses a
    /// group already on the page, so saving cannot replace another application's ink.
    public static func newGroup(on page: PDFPage) -> String {
        let usesDefaultGroup = page.annotations.contains { annotation in
            annotation.value(forAnnotationKey: PDFPageManager.groupKey) as? String == defaultGroup
        }
        return usesDefaultGroup ? "GraphitePageInk-" + UUID().uuidString : defaultGroup
    }

    static func encodeStrokeNames(_ strokeNames: [String]) -> String {
        // Stroke names are UUID strings, which never contain the separator. A single
        // empty name would encode as an empty string, so a count prefix keeps it.
        "\(strokeNames.count):" + strokeNames.joined(separator: ",")
    }

    static func decodeStrokeNames(_ encodedNames: String) -> [String] {
        guard let separatorIndex = encodedNames.firstIndex(of: ":"), let count = Int(encodedNames[..<separatorIndex]), count >= 0 else { return [] }
        let names = encodedNames[encodedNames.index(after: separatorIndex)...].split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        if count == 0 { return [] }
        return names.count == count ? names : []
    }
}

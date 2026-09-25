#if canImport(UIKit)
import Foundation
import UIKit
import PencilKit
import GraphiteCore

/// Identifies a PencilKit stroke's visible state without comparing its points. A stroke
/// the lasso moved, recolored or resized, or the pixel eraser cut, gets a new fingerprint.
///
/// Built for every stroke of the page on every change, so it stores only values and
/// references, never arrays.
struct PDFStrokeFingerprint: Hashable {
    let creationDate: Date
    let randomSeed: UInt32
    let pointCount: Int
    let firstLocation: CGPoint
    let lastLocation: CGPoint
    let transform: CGAffineTransform
    /// The eraser cuts a stroke by changing its mask, not its path. A second cut inside a
    /// stroke that already has one leaves the mask's bounds unchanged, so the whole mask
    /// is compared (CGPath equality compares its elements).
    let maskPath: CGPath?
    let inkType: PKInk.InkType
    let red: CGFloat
    let green: CGFloat
    let blue: CGFloat
    let alpha: CGFloat

    init(stroke: PKStroke) {
        creationDate = stroke.path.creationDate
        randomSeed = stroke.randomSeed
        pointCount = stroke.path.count
        firstLocation = stroke.path.first?.location ?? .zero
        lastLocation = stroke.path.last?.location ?? .zero
        transform = stroke.transform
        maskPath = stroke.mask?.cgPath
        inkType = stroke.ink.inkType
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        stroke.ink.color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        self.red = red; self.green = green; self.blue = blue; self.alpha = alpha
    }

    static func == (leftFingerprint: Self, rightFingerprint: Self) -> Bool {
        leftFingerprint.creationDate == rightFingerprint.creationDate && leftFingerprint.randomSeed == rightFingerprint.randomSeed
            && leftFingerprint.pointCount == rightFingerprint.pointCount && leftFingerprint.firstLocation == rightFingerprint.firstLocation
            && leftFingerprint.lastLocation == rightFingerprint.lastLocation && leftFingerprint.transform == rightFingerprint.transform
            && leftFingerprint.maskPath == rightFingerprint.maskPath && leftFingerprint.inkType == rightFingerprint.inkType
            && leftFingerprint.red == rightFingerprint.red && leftFingerprint.green == rightFingerprint.green
            && leftFingerprint.blue == rightFingerprint.blue && leftFingerprint.alpha == rightFingerprint.alpha
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(creationDate)
        hasher.combine(randomSeed)
        hasher.combine(pointCount)
        hasher.combine(firstLocation.x); hasher.combine(firstLocation.y)
        hasher.combine(transform.a); hasher.combine(transform.b); hasher.combine(transform.c)
        hasher.combine(transform.d); hasher.combine(transform.tx); hasher.combine(transform.ty)
    }
}

/// Converts PencilKit strokes on one PDF page into standard ink annotations, remembering
/// which annotation shows which stroke so that each change converts only new strokes.
///
/// Owned by the page's canvas on the main actor. Conversion is proportional to the
/// strokes that changed; comparing fingerprints and archiving the drawing are the only
/// work proportional to the page. Updates can defer the archiving, which then happens
/// once in `deferredEditableRecordUpdate(for:pageIndex:)` instead of at every change.
public struct PDFPageInkTracker {
    public let group: String
    private var namesByFingerprint: [PDFStrokeFingerprint: [String]] = [:]
    /// False until the strokes are matched to annotations; the next update then
    /// replaces the group's annotations as a whole.
    private var knowsAnnotationNames: Bool
    /// The annotation name of each stroke of the drawing last passed to `update`.
    private var strokeNamesInDrawingOrder: [String] = []
    /// True while an update deferred the re-editing record and no later one wrote it.
    public private(set) var hasDeferredEditableRecord = false

    /// A tracker for an editable group read from a file, and the drawing to show.
    /// Returns nil when the stored drawing cannot be decoded.
    public static func restoring(_ editableGroup: PDFEditableInkGroup) -> (tracker: PDFPageInkTracker, drawing: PKDrawing)? {
        guard let drawing = try? PKDrawing(data: editableGroup.record.drawingData) else { return nil }
        return restoring(editableGroup, decodedDrawing: drawing)
    }

    /// The same, with the group's drawing already decoded from its record, so the decode,
    /// which takes tens of milliseconds for a full page, can run away from the main actor.
    public static func restoring(_ editableGroup: PDFEditableInkGroup, decodedDrawing drawing: PKDrawing) -> (tracker: PDFPageInkTracker, drawing: PKDrawing)? {
        let record = editableGroup.record
        var tracker = PDFPageInkTracker(group: editableGroup.group, knowsAnnotationNames: false)
        if editableGroup.hasStrokeNames {
            guard record.strokeNames.count == drawing.strokes.count else { return nil }
            for (stroke, name) in zip(drawing.strokes, record.strokeNames) {
                tracker.namesByFingerprint[PDFStrokeFingerprint(stroke: stroke), default: []].append(name)
            }
            tracker.knowsAnnotationNames = true
        }
        return (tracker, drawing)
    }

    /// A tracker for a group that has no annotations yet.
    public init(group: String) {
        self.init(group: group, knowsAnnotationNames: true)
    }

    private init(group: String, knowsAnnotationNames: Bool) {
        self.group = group
        self.knowsAnnotationNames = knowsAnnotationNames
    }

    /// The edit that makes the page's annotations match `drawing`, which is in the
    /// page overlay's coordinates. With `defersEditableRecord`, the drawing is not
    /// archived; `deferredEditableRecordUpdate(for:pageIndex:)` must then write the record
    /// before the document is saved or its ink is read for re-editing (see `PDFInkUpdate`).
    public mutating func update(for drawing: PKDrawing, pageIndex: Int, coordinates: PageCoordinates, defersEditableRecord: Bool = false) -> PDFInkUpdate {
        var unmatchedNames = knowsAnnotationNames ? namesByFingerprint : [:]
        var matchedNames: [PDFStrokeFingerprint: [String]] = [:]
        var strokeNames: [String] = []
        var addedStrokes: [PortableInkStroke] = []
        for stroke in drawing.strokes {
            let fingerprint = PDFStrokeFingerprint(stroke: stroke)
            let name: String
            if var candidates = unmatchedNames[fingerprint], let existingName = candidates.popLast() {
                unmatchedNames[fingerprint] = candidates
                name = existingName
            } else if let portableStroke = Self.portableStroke(for: stroke, name: UUID().uuidString, coordinates: coordinates) {
                addedStrokes.append(portableStroke)
                name = portableStroke.name ?? ""
            } else {
                // A stroke the eraser removed entirely has no annotation.
                name = ""
            }
            matchedNames[fingerprint, default: []].append(name)
            strokeNames.append(name)
        }
        let removal: PDFInkUpdate.Removal = knowsAnnotationNames
            ? .strokes(Set(unmatchedNames.values.joined().filter { name in !name.isEmpty }))
            : .entireGroup
        namesByFingerprint = matchedNames
        knowsAnnotationNames = true
        strokeNamesInDrawingOrder = strokeNames
        hasDeferredEditableRecord = defersEditableRecord
        let record = defersEditableRecord ? nil : editableRecord(for: drawing)
        return PDFInkUpdate(pageIndex: pageIndex, group: group, removal: removal, addedStrokes: addedStrokes,
                            editableRecord: record, defersEditableRecord: defersEditableRecord)
    }

    /// The update that writes the re-editing record earlier updates deferred, or nil when
    /// none is pending. `drawing` is the drawing last passed to `update`.
    public mutating func deferredEditableRecordUpdate(for drawing: PKDrawing, pageIndex: Int) -> PDFInkUpdate? {
        guard hasDeferredEditableRecord else { return nil }
        assert(drawing.strokes.count == strokeNamesInDrawingOrder.count, "The drawing changed without an update.")
        hasDeferredEditableRecord = false
        return PDFInkUpdate(pageIndex: pageIndex, group: group, removal: .strokes([]), addedStrokes: [], editableRecord: editableRecord(for: drawing))
    }

    private func editableRecord(for drawing: PKDrawing) -> PDFEditableInkRecord? {
        drawing.strokes.isEmpty ? nil : PDFEditableInkRecord(drawingData: drawing.dataRepresentation(), strokeNames: strokeNamesInDrawingOrder)
    }

    /// One stroke as standard ink in page space: its visible pieces as `/InkList`
    /// paths, and its variable-width outline for the appearance stream.
    static func portableStroke(for stroke: PKStroke, name: String, coordinates: PageCoordinates) -> PortableInkStroke? {
        let overlaySegments = PencilStrokeSampler.visibleSegments(of: stroke)
        let widthScale = coordinates.cropBox.width / coordinates.overlaySize.width
        let pageSegments = overlaySegments.map { segment in
            segment.map { sample in VectorStrokeSample(point: coordinates.pdfPoint(fromOverlay: sample.point), width: sample.width * widthScale) }
        }
        let widths = pageSegments.joined().map(\.width)
        guard !widths.isEmpty else { return nil }
        let color = PencilStrokeSampler.color(of: stroke)
        let outline = appearanceOutline(for: stroke, pageSegments: pageSegments, widthScale: widthScale, color: color, coordinates: coordinates)
        let averageWidth = widths.reduce(0, +) / Double(widths.count)
        return PortableInkStroke(name: name, segments: pageSegments.map { segment in segment.map(\.point) }, width: max(0.5, averageWidth),
                                 red: color.red, green: color.green, blue: color.blue, alpha: color.alpha, outline: outline)
    }

    /// The appearance outline in page space. A stroke the pixel eraser touched is outlined
    /// whole and clipped to its visible area, as `PencilVectorConverter` does, so the round
    /// caps at the cut ends do not refill the erased gaps.
    private static func appearanceOutline(for stroke: PKStroke, pageSegments: [[VectorStrokeSample]], widthScale: CGFloat,
                                          color: VectorInkColor, coordinates: PageCoordinates) -> [[CGPoint]]? {
        guard let overlayVisibleArea = PencilStrokeSampler.visibleArea(of: stroke) else {
            return StrokeOutliner.shape(forSegments: pageSegments, color: color)?.subpaths
        }
        let cropBox = coordinates.cropBox
        var overlayToPage = CGAffineTransform(a: cropBox.width / coordinates.overlaySize.width, b: 0,
                                              c: 0, d: -cropBox.height / coordinates.overlaySize.height,
                                              tx: cropBox.minX, ty: cropBox.maxY)
        guard let pageVisibleArea = overlayVisibleArea.copy(using: &overlayToPage) else {
            return StrokeOutliner.shape(forSegments: pageSegments, color: color)?.subpaths
        }
        let pageCenterLine = PencilStrokeSampler.centerLineSamples(of: stroke).map { sample in
            VectorStrokeSample(point: coordinates.pdfPoint(fromOverlay: sample.point), width: sample.width * widthScale)
        }
        return StrokeOutliner.shape(forSegments: [pageCenterLine], color: color, clippedTo: pageVisibleArea)?.subpaths
    }
}
#endif

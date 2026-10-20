import Foundation
import CoreGraphics
import PDFKit
import PencilKit
import GraphiteCore

/// Puts a page's imported strokes on its PDF page the way every Graphite save does: a PencilKit drawing turned into a
/// `PDFInkUpdate` by a fresh `PDFPageInkTracker`, applied by `PDFPageManager`. The page gets a new ink group whose
/// re-editing record is the drawing, so Graphite edits the imported ink as its own.
///
/// Each stroke's annotation shows the planned shape rather than the one sampled back from PencilKit: the source's
/// outline when the plan has one, otherwise the outline of the planned samples at their planned widths, in the
/// planned color. PencilKit stores a point's size, not the width it draws (`PencilInkRenderedWidth`), so the shape
/// sampled back would be as wide as the sizes. The canvas and every PDF reader then show the planned width.
enum ImportedPageInk {
    /// The narrowest `/InkList` width written, as for ink drawn in Graphite.
    static let minimumInkWidthPoints = 0.5

    static func apply(_ strokes: [ImportedStroke], toPageAt pageIndex: Int, of document: PDFDocument, pageSize: CGSize,
                      strokeCreationDate: Date) throws {
        guard !strokes.isEmpty, let page = document.page(at: pageIndex) else { return }
        let coordinates = try PageCoordinates(cropBox: page.bounds(for: .cropBox), overlaySize: pageSize)
        // A stroke without a usable sample has no PencilKit stroke and so no annotation.
        let builtStrokes = strokes.compactMap { importedStroke in
            ImportedStrokeBuilder.stroke(for: importedStroke, creationDate: strokeCreationDate).map { pencilStroke in
                (planned: importedStroke, pencil: pencilStroke)
            }
        }
        guard !builtStrokes.isEmpty else { return }
        var tracker = PDFPageInkTracker(group: PDFInkGroups.newGroup(on: page))
        let sampledUpdate = tracker.update(for: PKDrawing(strokes: builtStrokes.map(\.pencil)), pageIndex: pageIndex, coordinates: coordinates)
        let plannedUpdate = withPlannedAppearances(sampledUpdate, strokes: builtStrokes.map(\.planned), coordinates: coordinates)
        try PDFPageManager.apply(.updateInk(plannedUpdate), to: document, drawsInkOutlines: true)
    }

    /// The update with each added stroke's appearance, width and color taken from its plan. The record's stroke names
    /// are in drawing order, which is the order of `strokes`, with an empty name for a stroke that has no annotation.
    private static func withPlannedAppearances(_ update: PDFInkUpdate, strokes: [ImportedStroke], coordinates: PageCoordinates) -> PDFInkUpdate {
        let strokeNames = update.editableRecord?.strokeNames ?? []
        var strokeIndexByName: [String: Int] = [:]
        for (strokeIndex, name) in strokeNames.enumerated() where !name.isEmpty && strokeIndex < strokes.count {
            strokeIndexByName[name] = strokeIndex
        }
        let plannedStrokes = update.addedStrokes.map { sampledStroke in
            guard let name = sampledStroke.name, let strokeIndex = strokeIndexByName[name] else { return sampledStroke }
            return plannedStroke(replacing: sampledStroke, with: strokes[strokeIndex], coordinates: coordinates)
        }
        return PDFInkUpdate(pageIndex: update.pageIndex, group: update.group, removal: update.removal, addedStrokes: plannedStrokes,
                            editableRecord: update.editableRecord)
    }

    private static func plannedStroke(replacing sampledStroke: PortableInkStroke, with importedStroke: ImportedStroke,
                                      coordinates: PageCoordinates) -> PortableInkStroke {
        let pageSamples = importedStroke.samples.map { sample in
            VectorStrokeSample(point: coordinates.pdfPoint(fromOverlay: sample.location), width: sample.width)
        }
        let outline = importedStroke.outline.map { subpaths in
            subpaths.map { subpath in subpath.map(coordinates.pdfPoint(fromOverlay:)) }
        } ?? StrokeOutliner.subpaths(forSamples: pageSamples)
        let finiteWidths = importedStroke.samples.map(\.width).filter(\.isFinite)
        let averageWidth = finiteWidths.isEmpty ? sampledStroke.width : finiteWidths.reduce(0, +) / Double(finiteWidths.count)
        let color = VectorInkColor(clampingRed: importedStroke.color.red, green: importedStroke.color.green,
                                   blue: importedStroke.color.blue, alpha: importedStroke.color.alpha)
        return PortableInkStroke(name: sampledStroke.name, segments: sampledStroke.segments, width: max(minimumInkWidthPoints, averageWidth),
                                 red: color.red, green: color.green, blue: color.blue, alpha: color.alpha, outline: outline)
    }
}

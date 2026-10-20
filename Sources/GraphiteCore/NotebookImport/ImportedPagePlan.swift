import CoreGraphics
import Foundation

/// One page of an imported notebook as Graphite will write it: a PDF page of `sizeInPoints`, its background as page
/// content, and its ink as PencilKit strokes. Every position is in page points with the origin at the page's top-left
/// corner and y downwards, the drawing space of Graphite's page canvas (`PageCoordinates` with an overlay the page's
/// size). Planned by `GoodnotesPagePlanner` and `NotabilityPagePlanner`, written by GraphiteApple's import writer.
public struct ImportedPagePlan: Sendable, Equatable {
    /// The source page this plan was made from, from 1.
    public let sourcePageNumber: Int
    public let sizeInPoints: CGSize
    public let background: ImportedPageBackground
    /// In drawing order.
    public let strokes: [ImportedStroke]
    /// What was simplified or left out on this page, and why.
    public let report: [ImportReportEntry]

    public init(sourcePageNumber: Int, sizeInPoints: CGSize, background: ImportedPageBackground, strokes: [ImportedStroke],
                report: [ImportReportEntry]) {
        self.sourcePageNumber = sourcePageNumber
        self.sizeInPoints = sizeInPoints
        self.background = background
        self.strokes = strokes
        self.report = report
    }
}

/// What became of one source page: planned, or left out with the reason.
public enum ImportedPageOutcome: Sendable, Equatable {
    case planned(ImportedPagePlan)
    case leftOut(sourcePageNumber: Int, report: [ImportReportEntry])
}

/// A file inside the source notebook, by its path from the notebook's own root (`attachments/<id>` in a Goodnotes
/// archive, `PDFs/<name>.pdf` inside a Notability note's folder), read through `ImportSourceFiles`.
public struct ImportedSourceFile: Sendable, Hashable {
    public let path: NotebookArchivePath

    public init(path: NotebookArchivePath) {
        self.path = path
    }

    public var pathInSource: String { path.text }
}

/// What a page shows under its ink.
public enum ImportedPageBackground: Sendable, Equatable {
    /// A page of a PDF in the source, drawn as it is, scaled to the page: Goodnotes' paper (template or imported PDF)
    /// and Notability's imported PDF pages.
    case pdfPage(ImportedSourceFile, pageNumber: Int)
    /// A plain paper of this colour, until the source's ruling has a Graphite paper (design step 5).
    case plainColor(NotebookImportColor)
}

/// One stroke, sampled into the points PencilKit needs.
public struct ImportedStroke: Sendable, Equatable {
    public enum Ink: Sendable, Hashable {
        /// One width along the stroke: Goodnotes' ball pen.
        case monoline
        /// A width at each point: Notability's pen.
        case pen
        /// Goodnotes' fountain and brush pens.
        case fountainPen
        case pencil
        case highlighter
    }

    public let ink: Ink
    public let color: NotebookImportColor
    /// At least one sample; the source's points along the stroke, in order.
    public let samples: [ImportedStrokeSample]
    /// The exact filled outline the source app draws, closed subpaths in page points, when the source stores one. The
    /// writer gives it to the stroke's PDF annotation as its appearance, so every PDF reader shows the source's shape.
    public let outline: [[CGPoint]]?

    public init(ink: Ink, color: NotebookImportColor, samples: [ImportedStrokeSample], outline: [[CGPoint]]?) {
        self.ink = ink
        self.color = color
        self.samples = samples
        self.outline = outline
    }
}

extension ImportedStroke {
    /// The stroke without samples whose position or width is not a finite number (a damaged source), or nil when none
    /// is left; an outline with a non-finite point is dropped, leaving PencilKit's own appearance.
    func keepingFiniteSamples() -> ImportedStroke? {
        let finiteSamples = samples.filter { sample in
            sample.location.x.isFinite && sample.location.y.isFinite && sample.width.isFinite && sample.width >= 0
        }
        guard !finiteSamples.isEmpty else { return nil }
        let finiteOutline = outline.flatMap { subpaths in
            subpaths.allSatisfy { subpath in subpath.allSatisfy { point in point.x.isFinite && point.y.isFinite } } ? subpaths : nil
        }
        return ImportedStroke(ink: ink, color: color, samples: finiteSamples, outline: finiteOutline)
    }
}

/// A point of a stroke with the ink's width there and, when the source recorded them, the Apple Pencil's state.
public struct ImportedStrokeSample: Sendable, Equatable {
    public let location: CGPoint
    /// The stroke's full width at this point, in page points.
    public let width: Double
    /// 0 to the Pencil's maximum, as the source stores it; nil when the source has none.
    public let force: Double?
    /// Radians; nil when the source has none.
    public let azimuthRadians: Double?
    /// Radians, 0 (flat) to π/2 (upright); nil when the source has none.
    public let altitudeRadians: Double?

    public init(location: CGPoint, width: Double, force: Double?, azimuthRadians: Double?, altitudeRadians: Double?) {
        self.location = location
        self.width = width
        self.force = force
        self.azimuthRadians = azimuthRadians
        self.altitudeRadians = altitudeRadians
    }
}

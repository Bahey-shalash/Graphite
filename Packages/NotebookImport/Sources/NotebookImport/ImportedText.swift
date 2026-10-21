import CoreGraphics
import Foundation

/// A stretch of typed text with one look, in page points: its font, size, colour, underline and web link. Line breaks
/// are `\n`.
public struct ImportedTextRun: Sendable, Equatable {
    public let text: String
    public let font: ImportedTextFont
    public let sizeInPoints: Double
    public let color: NotebookImportColor
    public let isUnderlined: Bool
    public let link: URL?

    public init(text: String, font: ImportedTextFont, sizeInPoints: Double, color: NotebookImportColor, isUnderlined: Bool, link: URL?) {
        self.text = text
        self.font = font
        self.sizeInPoints = sizeInPoints
        self.color = color
        self.isUnderlined = isUnderlined
        self.link = link
    }
}

/// How the source names a run's font: Goodnotes by its family ("Helvetica Neue", "Georgia"), Notability by its
/// PostScript name, which also gives the face ("HelveticaNeue-Bold").
public enum ImportedTextFont: Sendable, Hashable {
    case family(String)
    case postScriptName(String)
}

/// The text of a text box: runs the planner read, or Cocoa RTF that only the platform's RTF reader reads (Goodnotes'
/// older text boxes), its font sizes in source units, `pointsPerUnit` points each.
public enum ImportedTextContent: Sendable, Equatable {
    case runs([ImportedTextRun])
    case rtf(String, pointsPerUnit: Double)
}

/// Typed text written as one Graphite text box over the page's ink: Goodnotes' text boxes, sticky notes and older RTF
/// text boxes. Positions are page points from the page's top-left corner, y downwards, like every position of a plan.
public struct ImportedTextBox: Sendable, Equatable {
    public let content: ImportedTextContent
    /// The box's top-left corner as its text reads.
    public let origin: CGPoint
    /// Along the text, in points.
    public let width: Double
    /// Across the text, in points; nil for a box as tall as its text.
    public let height: Double?
    /// Clockwise about `origin`, as the page is seen.
    public let rotationRadiansClockwise: Double
    /// The room between the box's sides and its text, in points: the first baseline is this plus the font's ascent.
    public let padding: Double
    /// Nil for a box without a fill.
    public let fillColor: NotebookImportColor?

    public init(content: ImportedTextContent, origin: CGPoint, width: Double, height: Double?, rotationRadiansClockwise: Double,
                padding: Double, fillColor: NotebookImportColor?) {
        self.content = content
        self.origin = origin
        self.width = width
        self.height = height
        self.rotationRadiansClockwise = rotationRadiansClockwise
        self.padding = padding
        self.fillColor = fillColor
    }
}

/// Typed text that starts on one page and flows onto the next ones, as Notability's body text does: laid out
/// `width` points wide from `left`, starting `top` points below the top of the page that carries it. A page holds the
/// whole lines that fit above its bottom edge; the rest starts at the top of the next page, and pages are added after
/// the note's last one, of `continuationPageSize` on `continuationBackground`, while text is left. Measuring lines
/// needs the platform's text layout, so the writer cuts the text into pages.
public struct ImportedFlowingText: Sendable, Equatable {
    public let runs: [ImportedTextRun]
    public let left: Double
    public let top: Double
    public let width: Double
    public let continuationPageSize: CGSize
    public let continuationBackground: ImportedPageBackground

    public init(runs: [ImportedTextRun], left: Double, top: Double, width: Double, continuationPageSize: CGSize,
                continuationBackground: ImportedPageBackground) {
        self.runs = runs
        self.left = left
        self.top = top
        self.width = width
        self.continuationPageSize = continuationPageSize
        self.continuationBackground = continuationBackground
    }
}

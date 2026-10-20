import CoreGraphics
import Foundation

/// One page of a Goodnotes notebook with its elements that are not erased, in drawing order.
public struct GoodnotesPage: Sendable, Equatable {
    public let descriptor: GoodnotesPageDescriptor
    public let elements: [GoodnotesElement]
    /// What the page's layer holds that this reader does not know, and what it skipped.
    public let issues: [GoodnotesReadingIssue]
}

/// An element's place in the drawing order: elements are drawn sorted by counter, then replica. Elements that share
/// both keep the order of the layer file.
public struct GoodnotesDrawingPosition: Sendable, Hashable, Comparable {
    public let counter: UInt64
    public let replica: UInt64

    public static func < (left: GoodnotesDrawingPosition, right: GoodnotesDrawingPosition) -> Bool {
        (left.counter, left.replica) < (right.counter, right.replica)
    }
}

public struct GoodnotesElement: Sendable, Equatable {
    public let identifier: String
    public let drawingPosition: GoodnotesDrawingPosition
    public let content: GoodnotesElementContent
}

public enum GoodnotesElementContent: Sendable, Equatable {
    /// Ink, a shape, highlighter or tape.
    case stroke(GoodnotesStroke)
    case picture(GoodnotesPicture)
    case shapeFill(GoodnotesShapeFill)
    case textBox(GoodnotesTextBox)
    /// An older text box, its text as Cocoa RTF.
    case rtfTextBox(GoodnotesRTFTextBox)
    case stickyNote(GoodnotesStickyNote)
    /// A text element in RTF with no frame (one sample, empty; its purpose is not known).
    case rtfTextElement(rtf: String)
}

public struct GoodnotesStroke: Sendable, Equatable {
    public enum Ink: Sendable, Equatable {
        /// Ink 0, stored as absent: the ball pen and the highlighter.
        case ballPenOrHighlighter
        /// Ink 1: the fountain pen, the brush pen and tape, which the file tells apart only by width and field 20.
        case fountainPenBrushPenOrTape
        /// Ink 4: the older varying-width ink.
        case olderVaryingWidth
        /// Ink 5.
        case pencil
        case unknown(UInt64)
    }

    public let ink: Ink
    public let color: NotebookImportColor
    /// Highlighter ink, drawn after all other ink and multiplied into it.
    public let isHighlighter: Bool
    public let isTape: Bool
    /// The same on every stroke of a saved drawing put on the page.
    public let groupIdentifier: String?
    /// Added to every point: a lasso move.
    public let offset: CGVector
    /// Present when the stroke was drawn as a shape; its path is then empty.
    public let shape: GoodnotesShape?
    public let path: GoodnotesStrokePath
}

/// A shape's geometry, on a stroke or on a fill.
public struct GoodnotesShape: Sendable, Equatable {
    public enum Geometry: Sendable, Equatable {
        /// A line has two points.
        case polyline([CGPoint])
        /// An arc of a circle from the first point through the second to the third.
        case arcThroughThreePoints(CGPoint, CGPoint, CGPoint)
        case rectangle(centre: CGPoint, size: CGSize, angleRadians: Double)
        case ellipse(centre: CGPoint, radii: CGSize, angleRadians: Double)
    }

    public let geometry: Geometry? // nil when the record has no geometry field
    public let width: Double?
}

public struct GoodnotesPicture: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case jpeg2000Sticker
        /// Kept as the original GIF file.
        case animatedGIF
        /// 1 on the turned picture of the samples; its meaning is not known.
        case unknown(UInt64)
    }

    /// The attachment that holds the picture file; nil when the attachment is not in the log.
    public let attachment: GoodnotesAttachment?
    /// The picture as drawn, turned.
    public let boundingBox: CGRect
    /// The picture file is drawn stretched to `size`, turned about `centre` by `rotationRadians`, clockwise.
    public let centre: CGPoint
    public let size: CGSize
    public let rotationRadians: Double
    /// Nil for photos and PNG stickers.
    public let kind: Kind?
}

/// A shape's fill, its own element in the drawing order.
public struct GoodnotesShapeFill: Sendable, Equatable {
    public let color: NotebookImportColor
    public let shape: GoodnotesShape?
    /// The strokes whose outline the fill fills.
    public let outlineStrokeIdentifiers: [String]
    public let offset: CGVector
}

/// Typed text with its attributes, decompressed from a text box or a sticky note.
public struct GoodnotesRichText: Sendable, Equatable {
    public struct Attributes: Sendable, Equatable {
        public let color: NotebookImportColor?
        public let link: String?
        public let fontName: String?
        /// In Goodnotes units; nil when unset (stored as -404).
        public let sizeInUnits: Double?
    }

    public let text: String
    /// One run of attributes each; how several runs mark their ranges is not known yet.
    public let runs: [Attributes]
    public let defaultAttributes: Attributes?
}

/// A text box is drawn at its stored size and font size, multiplied by `scale`, with its top-left corner at `origin`,
/// turned clockwise about that corner by `rotationRadians`.
public struct GoodnotesTextBox: Sendable, Equatable {
    public let origin: CGPoint
    public let rotationRadians: Double
    public let scale: Double
    /// Before scaling.
    public let size: CGSize?
    /// The four inset values in field order; which side each one is is not established.
    public let insets: [Double]?
    public let richText: GoodnotesRichText
}

public struct GoodnotesRTFTextBox: Sendable, Equatable {
    public let frame: CGRect
    /// The frame inset by 10 units on each side.
    public let textFrame: CGRect
    /// The only copy of the text: fonts, sizes in half-points, colours and `HYPERLINK` fields.
    public let rtf: String
}

public struct GoodnotesStickyNote: Sendable, Equatable {
    public let origin: CGPoint
    public let size: CGSize
    public let paperColor: NotebookImportColor
    public let richText: GoodnotesRichText
    /// Printed by Goodnotes at the bottom of the note.
    public let authorName: String
}

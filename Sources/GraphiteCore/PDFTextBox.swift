import Foundation
import CoreGraphics

/// The look of a text box as a whole: how its lines align and how far apart they are, and
/// its optional fill, border and padding.
public struct PDFTextBoxStyle: Sendable, Hashable, Codable {
    public var alignment: PDFTextAlignment
    /// The distance between lines as a multiple of the font's own, 1 for single spacing.
    public var lineSpacing: Double
    public var fillColor: PDFTextColor?
    public var borderColor: PDFTextColor?
    /// In points; no border is drawn at 0 or without a color.
    public var borderWidth: Double
    /// The room between the box's sides and its text, in points.
    public var padding: Double

    public static let lineSpacingRange: ClosedRange<Double> = 0.5...4
    public static let borderWidthRange: ClosedRange<Double> = 0...24
    public static let paddingRange: ClosedRange<Double> = 0...144
    /// A new box's padding: room for the caret beside the text.
    public static let defaultPadding: Double = 4
    public static let plain = PDFTextBoxStyle(alignment: .left)

    public init(alignment: PDFTextAlignment, lineSpacing: Double = 1, fillColor: PDFTextColor? = nil, borderColor: PDFTextColor? = nil,
                borderWidth: Double = 0, padding: Double = defaultPadding) {
        func clamped(_ value: Double, to range: ClosedRange<Double>, otherwise fallback: Double) -> Double {
            value.isFinite ? min(max(value, range.lowerBound), range.upperBound) : fallback
        }
        self.alignment = alignment
        self.lineSpacing = clamped(lineSpacing, to: Self.lineSpacingRange, otherwise: 1)
        self.fillColor = fillColor
        self.borderColor = borderColor
        self.borderWidth = clamped(borderWidth, to: Self.borderWidthRange, otherwise: 0)
        self.padding = clamped(padding, to: Self.paddingRange, otherwise: Self.defaultPadding)
    }

    /// Whether a border is drawn.
    public var hasBorder: Bool { borderColor != nil && borderWidth > 0 }
}

/// Typed text on a PDF page: a standard `/FreeText` annotation in the file, which every
/// PDF reader shows.
///
/// The box is placed by its top-left corner, `origin`, which is where its first line
/// starts, and turned by `rotationRadians` about that corner, as Goodnotes places its text
/// boxes. Its width is chosen; its height follows the text (`PDFTextBoxLayout` in
/// GraphiteApple measures it). Coordinates are the page's own, which count upward from the
/// bottom of its box; the angle is clockwise as the page is seen unturned.
public struct PDFTextBox: Sendable, Equatable {
    /// The annotation's name, unique in its document.
    public let name: String
    /// The text and its looks, in the normalized form (`PDFTextRun.normalized`).
    public var runs: [PDFTextRun] { didSet { if runs != PDFTextRun.normalized(runs) { runs = PDFTextRun.normalized(runs) } } }
    public var origin: CGPoint
    public var width: Double
    public var height: Double
    public var rotationRadians: Double
    public var style: PDFTextBoxStyle
    /// Entries of the annotation another application wrote that Graphite does not use,
    /// written back with the box so they are not lost (`/IT`, `/Subj`, vendor keys).
    public var preservedEntries: [String: PDFPreservedValue]

    /// The smallest width a box is made or resized to, in points.
    public static let minimumWidth: Double = 12
    /// The most text one box holds, in UTF-16 units, as for a note pasted whole.
    public static let maximumTextUTF16Count = 200_000
    /// The most runs one box holds.
    public static let maximumRunCount = 8_192
    public static let annotationTypeName = "FreeText"

    public init(name: String = UUID().uuidString, runs: [PDFTextRun], origin: CGPoint, width: Double, height: Double,
                rotationRadians: Double = 0, style: PDFTextBoxStyle = .plain, preservedEntries: [String: PDFPreservedValue] = [:]) {
        self.name = name
        self.runs = PDFTextRun.normalized(runs)
        self.origin = origin
        self.width = width.isFinite ? max(width, Self.minimumWidth) : Self.minimumWidth
        self.height = height.isFinite ? max(height, 0) : 0
        self.rotationRadians = PictureRotation.normalized(rotationRadians)
        self.style = style
        self.preservedEntries = preservedEntries
    }

    /// The text without its looks: what `/Contents` holds and what Search finds.
    public var plainText: String { runs.map(\.text).joined() }

    /// The looks of the start of the text, which `/DA` and `/DS` give as the box's default.
    public var leadingAttributes: PDFTextAttributes { runs.first?.attributes ?? .plain }

    public var isEmpty: Bool { plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// Whether the box can be written: finite, inside the bounds of a page, within its limits.
    public var hasValidGeometry: Bool {
        [Double(origin.x), Double(origin.y), width, height, rotationRadians].allSatisfy(\.isFinite) && width > 0 && height > 0
            && plainText.utf16.count <= Self.maximumTextUTF16Count && runs.count <= Self.maximumRunCount
    }

    // MARK: Geometry

    /// The direction the text runs, one point long, in page coordinates.
    public var textDirection: CGVector { CGVector(dx: cos(rotationRadians), dy: -sin(rotationRadians)) }
    /// The direction lines follow each other, down the box, one point long.
    public var lineDirection: CGVector { CGVector(dx: -sin(rotationRadians), dy: -cos(rotationRadians)) }

    /// A point of the box, given as a distance along the text and down from its top-left
    /// corner, in page coordinates.
    public func pagePoint(along distanceAlongText: Double, down distanceDown: Double) -> CGPoint {
        let along = textDirection, down = lineDirection
        return CGPoint(x: Double(origin.x) + distanceAlongText * Double(along.dx) + distanceDown * Double(down.dx),
                       y: Double(origin.y) + distanceAlongText * Double(along.dy) + distanceDown * Double(down.dy))
    }

    /// The box's corners in page coordinates: top left, top right, bottom right, bottom left
    /// as the text reads.
    public var corners: [CGPoint] {
        [pagePoint(along: 0, down: 0), pagePoint(along: width, down: 0), pagePoint(along: width, down: height), pagePoint(along: 0, down: height)]
    }

    /// The upright rectangle around the box as turned: the annotation's `/Rect`.
    public var annotationBounds: CGRect {
        let points = corners
        let xs = points.map(\.x), ys = points.map(\.y)
        guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else { return .null }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// Where a page point is in the box's own terms: along the text and down from its corner.
    public func boxPoint(fromPage pagePoint: CGPoint) -> (alongText: Double, down: Double) {
        let offsetX = Double(pagePoint.x - origin.x), offsetY = Double(pagePoint.y - origin.y)
        let along = textDirection, down = lineDirection
        return (offsetX * Double(along.dx) + offsetY * Double(along.dy), offsetX * Double(down.dx) + offsetY * Double(down.dy))
    }

    /// Whether the box, as turned, covers a point of the page.
    public func contains(_ pagePoint: CGPoint) -> Bool {
        let position = boxPoint(fromPage: pagePoint)
        return position.alongText >= 0 && position.alongText <= width && position.down >= 0 && position.down <= height
    }

    /// The box's middle in page coordinates.
    public var middle: CGPoint { pagePoint(along: width / 2, down: height / 2) }

    /// The box moved so its middle is at a point, keeping its size and angle.
    public func movingMiddle(to newMiddle: CGPoint) -> PDFTextBox {
        var moved = self
        let currentMiddle = middle
        moved.origin = CGPoint(x: origin.x + newMiddle.x - currentMiddle.x, y: origin.y + newMiddle.y - currentMiddle.y)
        return moved
    }

    /// The box turned to another angle about its middle, as its rotate handle turns it.
    public func rotated(to radians: Double) -> PDFTextBox {
        let keptMiddle = middle
        var turned = self
        turned.rotationRadians = PictureRotation.normalized(radians)
        return turned.movingMiddle(to: keptMiddle)
    }

    /// The angle that shows the text upright on a page shown turned by quarter turns clockwise.
    public static func uprightRotation(forPageQuarterTurns quarterTurns: Int) -> Double {
        PictureRotation.normalized(-Double(((quarterTurns % 4) + 4) % 4) * .pi / 2)
    }

    /// The same box with another name, for a copy that sits beside it in the same document.
    public func renamed(_ newName: String) -> PDFTextBox {
        PDFTextBox(name: newName, runs: runs, origin: origin, width: width, height: height, rotationRadians: rotationRadians,
                   style: style, preservedEntries: preservedEntries)
    }

    /// The box with its text and padding scaled about its top-left corner, as a selection
    /// resized together with ink scales everything in it.
    public func scaled(by factor: Double) -> PDFTextBox {
        guard factor.isFinite, factor > 0 else { return self }
        var scaled = self
        scaled.runs = runs.map { run in PDFTextRun(text: run.text, attributes: run.attributes.scaled(by: factor)) }
        scaled.width = max(width * factor, Self.minimumWidth)
        scaled.height = height * factor
        scaled.style = PDFTextBoxStyle(alignment: style.alignment, lineSpacing: style.lineSpacing, fillColor: style.fillColor,
                                       borderColor: style.borderColor, borderWidth: style.borderWidth * factor, padding: style.padding * factor)
        return scaled
    }
}

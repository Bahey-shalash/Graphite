import CoreGraphics
import Foundation

/// How a note's continuous document is cut into the pages of Notability's PDF export, as the reference reader
/// computes it: x in points = `leftInsetPoints` + x × `pointsPerUnit`, and page n shows y from (n − 1) ×
/// `pageHeightInUnits`. Values the note does not determine are nil: a reflowable note stores no page width, and an
/// unknown paper size has no export size.
public struct NotabilityPageGeometry: Sendable, Equatable {
    /// Every export seen draws the document's x = 0 this far from the page's left edge.
    public static let leftInsetPoints = 15.9375
    /// Notability's "Letter (Optimized)" page, 16:21, and the A4 page of an imported PDF's export.
    private static let letterPageSize = CGSize(width: 612.0, height: 803.25)
    private static let a4PageSize = CGSize(width: 595.2756, height: 842.7541)

    /// The page width in document units: stored for a locked layout, absent for a reflowable one.
    public let pageWidthInUnits: Double?
    public let exportPageSizeInPoints: CGSize?
    public let pointsPerUnit: Double?
    public let pageHeightInUnits: Double?

    /// The divisions are made in the reference reader's order, so every value equals its value exactly.
    public init(pageWidthInUnits: Double?, paper: NotabilityPaper) {
        self.pageWidthInUnits = pageWidthInUnits
        let exportPageSize = Self.exportPageSize(of: paper)
        exportPageSizeInPoints = exportPageSize
        // Only a finite, positive width cuts the document into pages; any other gives no page count.
        guard let exportPageSize, let pageWidthInUnits, pageWidthInUnits.isFinite, pageWidthInUnits > 0 else {
            pointsPerUnit = nil
            pageHeightInUnits = nil
            return
        }
        let pointsPerUnit = Double(exportPageSize.width) / pageWidthInUnits
        self.pointsPerUnit = pointsPerUnit
        pageHeightInUnits = pointsPerUnit == 0 ? nil : Double(exportPageSize.height) / pointsPerUnit
    }

    /// The export page of the paper's size, turned for a landscape paper; nil for an absent or unknown size.
    public static func exportPageSize(of paper: NotabilityPaper) -> CGSize? {
        let portraitSize: CGSize
        switch paper.size {
        case .letter?: portraitSize = letterPageSize
        case .a4?: portraitSize = a4PageSize
        case .unknown?, nil: return nil
        }
        guard paper.orientation == .landscape else { return portraitSize }
        return CGSize(width: portraitSize.height, height: portraitSize.width)
    }

    /// The page a vertical position falls on, from 1, as a real number so that a position far outside any page still
    /// compares in order: the floor of y / page height, plus one. Nil when the page height is unknown; not finite
    /// when the position is not.
    func pagePosition(ofVerticalPosition verticalPosition: Double) -> Double? {
        guard let pageHeightInUnits else { return nil }
        return Self.flooredQuotient(verticalPosition, pageHeightInUnits) + 1
    }

    /// The page number a page position names, when it is a whole number `Int` holds.
    static func pageNumber(fromPagePosition pagePosition: Double) -> Int? {
        Int(exactly: pagePosition)
    }

    /// Python's float floor division (`//`), whose result can differ from `floor(dividend / divisor)` by one when
    /// the quotient is rounded; pages are cut the way the reference reader cuts them.
    static func flooredQuotient(_ dividend: Double, _ divisor: Double) -> Double {
        let remainder = fmod(dividend, divisor)
        var quotient = (dividend - remainder) / divisor
        if remainder != 0, (divisor < 0) != (remainder < 0) { quotient -= 1 }
        guard quotient != 0 else { return (dividend / divisor).sign == .minus ? -0.0 : 0.0 }
        var flooredQuotient = quotient.rounded(.down)
        if quotient - flooredQuotient > 0.5 { flooredQuotient += 1 }
        return flooredQuotient
    }
}

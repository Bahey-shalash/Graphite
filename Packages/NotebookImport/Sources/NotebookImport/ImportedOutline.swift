import CoreGraphics
import Foundation

/// An entry of the imported notebook's outline: a title for a place on a page, written as a PDF outline item.
public struct ImportedOutlineEntry: Sendable, Equatable {
    public let title: String
    /// The source page it names, from 1, as in `ImportedPagePlan.sourcePageNumber`.
    public let sourcePageNumber: Int
    /// Where on the page, in page points from its top-left corner; nil for the top of the page.
    public let pointInPoints: CGPoint?

    public init(title: String, sourcePageNumber: Int, pointInPoints: CGPoint?) {
        self.title = title
        self.sourcePageNumber = sourcePageNumber
        self.pointInPoints = pointInPoints
    }
}

/// A notebook's outline, in its order, and what of it the import leaves out.
public struct ImportedOutlinePlan: Sendable, Equatable {
    public let entries: [ImportedOutlineEntry]
    /// `outlineEntriesWithoutPage`, when it applies.
    public let report: [ImportReportEntry]

    public init(entries: [ImportedOutlineEntry], report: [ImportReportEntry]) {
        self.entries = entries
        self.report = report
    }

    /// A notebook without an outline, such as a Notability note: Notability keeps none.
    public static let none = ImportedOutlinePlan(entries: [], report: [])
}

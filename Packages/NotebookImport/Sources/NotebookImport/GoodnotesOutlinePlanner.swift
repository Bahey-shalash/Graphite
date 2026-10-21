import CoreGraphics
import Foundation

/// Plans a Goodnotes notebook's outline (`GoodnotesNotebook.outlineEntries`, already in Goodnotes' order) as PDF outline
/// entries: each names its page by the page's place in the notebook and a point on it in page points (Goodnotes units
/// times 6/11, the same origin and direction). An entry whose page is not among the notebook's pages, such as a
/// deleted page, is left out and counted.
public enum GoodnotesOutlinePlanner {
    public static func plan(_ notebook: GoodnotesNotebook) -> ImportedOutlinePlan {
        var pageNumberByIdentifier: [String: Int] = [:]
        for (pageIndex, page) in notebook.pages.enumerated() where pageNumberByIdentifier[page.identifier] == nil {
            pageNumberByIdentifier[page.identifier] = pageIndex + 1
        }
        var entries: [ImportedOutlineEntry] = []
        var withoutPageCount = 0
        for entry in notebook.outlineEntries {
            guard let pageNumber = pageNumberByIdentifier[entry.pageIdentifier] else {
                withoutPageCount += 1
                continue
            }
            entries.append(ImportedOutlineEntry(title: entry.title, sourcePageNumber: pageNumber, pointInPoints: pointInPoints(entry.pointOnPage)))
        }
        return ImportedOutlinePlan(entries: entries, report: withoutPageCount > 0 ? [.outlineEntriesWithoutPage(count: withoutPageCount)] : [])
    }

    /// Goodnotes stores an infinite point for an entry that names the page as a whole.
    private static func pointInPoints(_ unitPoint: CGPoint) -> CGPoint? {
        guard unitPoint.x.isFinite, unitPoint.y.isFinite else { return nil }
        return CGPoint(x: unitPoint.x * GoodnotesPagePlanner.pointsPerUnit, y: unitPoint.y * GoodnotesPagePlanner.pointsPerUnit)
    }
}

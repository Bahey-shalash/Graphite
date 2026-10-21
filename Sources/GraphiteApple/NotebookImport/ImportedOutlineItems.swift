import Foundation
import PDFKit
import NotebookImport

/// Writes an imported notebook's outline as PDF outline items: first in the outline, before the bookmarks the pages
/// added (invariant PDF-06), in the source's order, each pointing to its page at its point, or at the page's top-left
/// corner when it names the page as a whole.
enum ImportedOutlineItems {
    /// Adds `entries` to `document`, whose pages are written; returns how many name a source page that was not
    /// written (left out by its plan), which are left out.
    static func insert(_ entries: [ImportedOutlineEntry], into document: PDFDocument, pageIndexBySourcePageNumber: [Int: Int]) -> Int {
        guard !entries.isEmpty else { return 0 }
        let root = document.outlineRoot ?? PDFOutline()
        var insertedCount = 0
        for entry in entries {
            guard let pageIndex = pageIndexBySourcePageNumber[entry.sourcePageNumber], let page = document.page(at: pageIndex) else { continue }
            let item = PDFOutline()
            item.label = entry.title
            item.destination = PDFDestination(page: page, at: destinationPoint(entry.pointInPoints, on: page))
            root.insertChild(item, at: insertedCount)
            insertedCount += 1
        }
        if insertedCount > 0 { document.outlineRoot = root }
        return entries.count - insertedCount
    }

    /// A point in page points from the top-left corner, in the PDF page's own space (origin at the bottom left).
    private static func destinationPoint(_ point: CGPoint?, on page: PDFPage) -> CGPoint {
        guard let point else { return PDFPageManager.visibleTopLeft(of: page) }
        let box = page.bounds(for: .cropBox)
        return CGPoint(x: box.minX + point.x, y: box.maxY - point.y)
    }
}

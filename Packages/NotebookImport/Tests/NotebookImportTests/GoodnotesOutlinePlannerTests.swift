import CoreGraphics
import XCTest
@testable import NotebookImport

/// A Goodnotes outline planned as PDF outline entries: each on its page by the page's place in the notebook, at its
/// point in page points, in Goodnotes' order; an entry of a page the notebook no longer has is counted, not guessed.
final class GoodnotesOutlinePlannerTests: XCTestCase {
    private static func page(_ identifier: String) -> GoodnotesPageDescriptor {
        GoodnotesPageDescriptor(identifier: identifier, layerIdentifier: nil, paper: nil, isBookmarked: false, isFlagged: false)
    }

    private static func entry(_ title: String, on pageIdentifier: String, at point: CGPoint) -> GoodnotesOutlineEntry {
        GoodnotesOutlineEntry(identifier: "ENTRY-\(title)", title: title, orderKey: title, pageIdentifier: pageIdentifier, pointOnPage: point)
    }

    private static func notebook(pages: [String], outline: [GoodnotesOutlineEntry]) -> GoodnotesNotebook {
        GoodnotesNotebook(schemaVersion: 26, title: "", pages: pages.map(page), deletedPageCount: 0, outlineEntries: outline, recordings: [], issues: [])
    }

    func testEachEntryNamesItsPageByPlaceAndItsPointInPagePoints() {
        let plan = GoodnotesOutlinePlanner.plan(Self.notebook(pages: ["A", "B", "C"], outline: [
            Self.entry("Introduction", on: "A", at: CGPoint(x: 110, y: 220)),
            Self.entry("Methods", on: "C", at: CGPoint(x: 0, y: 1650))
        ]))
        XCTAssertEqual(plan.entries.map(\.title), ["Introduction", "Methods"])
        XCTAssertEqual(plan.entries.map(\.sourcePageNumber), [1, 3])
        let points = plan.entries.compactMap(\.pointInPoints)
        XCTAssertEqual(points.count, 2)
        for (point, expected) in zip(points, [CGPoint(x: 60, y: 120), CGPoint(x: 0, y: 900)]) {
            XCTAssertEqual(point.x, expected.x, accuracy: 1e-9, "Units are 6/11 of a point.")
            XCTAssertEqual(point.y, expected.y, accuracy: 1e-9)
        }
        XCTAssertEqual(plan.report, [])
    }

    func testAnInfinitePointNamesTheTopOfThePage() {
        let plan = GoodnotesOutlinePlanner.plan(Self.notebook(pages: ["A"], outline: [
            Self.entry("Whole page", on: "A", at: CGPoint(x: Double.infinity, y: Double.infinity)),
            Self.entry("Half known", on: "A", at: CGPoint(x: 10, y: Double.nan))
        ]))
        XCTAssertEqual(plan.entries.map(\.pointInPoints), [nil, nil])
    }

    func testAnEntryOfAPageTheNotebookDoesNotHaveIsCountedAsLeftOut() {
        let plan = GoodnotesOutlinePlanner.plan(Self.notebook(pages: ["A"], outline: [
            Self.entry("Deleted", on: "GONE", at: .zero),
            Self.entry("Kept", on: "A", at: .zero),
            Self.entry("Also deleted", on: "GONE", at: .zero)
        ]))
        XCTAssertEqual(plan.entries.map(\.title), ["Kept"])
        XCTAssertEqual(plan.report, [.outlineEntriesWithoutPage(count: 2)])
        XCTAssertEqual(ImportReportEntry.outlineEntriesWithoutPage(count: 2).kind.category, .leftOut)
        XCTAssertEqual(ImportReportEntry.outlineEntriesWithoutPage(count: 2).count, 2)
    }

    func testANotebookWithoutAnOutlinePlansNone() {
        XCTAssertEqual(GoodnotesOutlinePlanner.plan(Self.notebook(pages: ["A"], outline: [])), .none)
    }
}

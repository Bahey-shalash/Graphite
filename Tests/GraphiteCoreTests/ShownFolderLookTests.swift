import XCTest
@testable import GraphiteCore

final class ShownFolderLookTests: XCTestCase {
    private let finderGreenStar = FinderFolderLook(tags: [FinderTag(name: "Green", color: .green)], iconMark: .symbol("star.fill"),
                                                   hasCustomIconFlag: true, hasCustomIconFile: false)

    func testWithoutFinderTheStoredStyleIsDrawn() {
        XCTAssertEqual(ShownFolderLook.resolve(stored: nil, finder: .plain), .plain)
        XCTAssertEqual(ShownFolderLook.resolve(stored: FolderStyle(color: .teal), finder: .plain), .drawnByGraphite(FolderStyle(color: .teal)))
    }

    func testOnlyFinderHasALook() {
        XCTAssertEqual(ShownFolderLook.resolve(stored: nil, finder: finderGreenStar),
                       .drawnByFinder(FolderStyle(color: .green, mark: .symbol("star.fill"))))
    }

    func testWhatGraphiteWroteIsDrawnByFinder() {
        let stored = FolderStyle(color: .green, mark: .symbol("star.fill"))
        XCTAssertEqual(ShownFolderLook.resolve(stored: stored, finder: finderGreenStar), .drawnByFinder(stored))
    }

    func testAColorNoTagHasStaysGraphitesDrawing() {
        let stored = FolderStyle(color: .custom(red: 1, green: 2, blue: 3), mark: .symbol("star.fill"))
        let finder = FinderFolderLook(tags: [], iconMark: .symbol("star.fill"), hasCustomIconFlag: true, hasCustomIconFile: false)
        XCTAssertEqual(ShownFolderLook.resolve(stored: stored, finder: finder), .drawnByGraphite(stored))
    }

    func testAChangeMadeInFinderWins() {
        let stored = FolderStyle(color: .red, mark: .symbol("heart.fill"))
        XCTAssertEqual(ShownFolderLook.resolve(stored: stored, finder: finderGreenStar),
                       .drawnByFinder(FolderStyle(color: .green, mark: .symbol("star.fill"))))
    }
}

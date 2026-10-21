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

    func testAPictureGraphiteWroteIsFindersCustomIcon() throws {
        let picture = FolderPicture(path: try VaultPath(".obsidian/graphite-folder-icons/0123456789abcdef.png"), layout: .onFolder)
        let stored = FolderStyle(mark: .picture(picture))
        let finder = FinderFolderLook(tags: [], iconMark: nil, hasCustomIconFlag: true, hasCustomIconFile: true)
        XCTAssertEqual(ShownFolderLook.resolve(stored: stored, finder: finder), .drawnByFinder(stored))
        let tinted = FolderStyle(color: .red, mark: .picture(picture))
        let redFinder = FinderFolderLook(tags: [FinderTag(name: "Red", color: .red)], iconMark: nil, hasCustomIconFlag: true, hasCustomIconFile: true)
        XCTAssertEqual(ShownFolderLook.resolve(stored: tinted, finder: redFinder), .drawnByGraphite(tinted))
    }

    func testAPictureSetInFinderShowsAsFinders() {
        let finder = FinderFolderLook(tags: [], iconMark: nil, hasCustomIconFlag: true, hasCustomIconFile: true)
        XCTAssertEqual(ShownFolderLook.resolve(stored: nil, finder: finder), .drawnByFinder(FolderStyle()))
        XCTAssertEqual(ShownFolderLook.resolve(stored: FolderStyle(mark: .symbol("star.fill")), finder: finder), .drawnByFinder(FolderStyle()))
    }
}


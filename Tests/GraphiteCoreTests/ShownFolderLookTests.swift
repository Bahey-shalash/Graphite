import XCTest
@testable import GraphiteCore

final class ShownFolderLookTests: XCTestCase {
    private let finderGreenStar = FinderFolderLook(tags: [FinderTag(name: "Green", color: .green)], iconMark: .symbol("star.fill"),
                                                   hasCustomIconFlag: true, hasCustomIconFile: false)

    private func resolve(_ stored: FolderStyle?, _ finder: FinderFolderLook, canWritePictures: Bool = true) -> ShownFolderLook {
        ShownFolderLook.resolve(stored: stored, finder: finder, canWritePictures: canWritePictures)
    }

    func testWithNeitherTheFolderIsPlain() {
        XCTAssertEqual(resolve(nil, .plain), .plain)
    }

    /// A style not yet written shows as Graphite's until its write lands.
    func testAStyleWaitingForItsWriteIsGraphites() {
        XCTAssertEqual(resolve(FolderStyle(color: .green), .plain), .drawnByGraphite(FolderStyle(color: .green)))
    }

    func testOnlyFinderHasALook() {
        XCTAssertEqual(resolve(nil, finderGreenStar), .drawnByFinder(FolderStyle(color: .green, mark: .symbol("star.fill"))))
        let tagOnly = FinderFolderLook(tags: [FinderTag(name: "Red", color: .red)], iconMark: nil, hasCustomIconFlag: false, hasCustomIconFile: false)
        XCTAssertEqual(resolve(nil, tagOnly), .drawnByFinder(FolderStyle(color: .red)))
    }

    func testWhatGraphiteWroteIsTheSystemsIcon() {
        let stored = FolderStyle(color: .green, mark: .symbol("star.fill"))
        XCTAssertEqual(resolve(stored, finderGreenStar), .drawnByFinder(stored))
    }

    /// A color no tag has is written as the nearest tag color, and then agrees.
    func testAColorNoTagHasAgreesWithItsNearestTag() {
        let stored = FolderStyle(color: .custom(red: 30, green: 200, blue: 60), mark: .symbol("star.fill"))
        XCTAssertEqual(resolve(stored, finderGreenStar), .drawnByFinder(stored))
    }

    func testAChangeMadeInFinderWins() {
        let stored = FolderStyle(color: .red, mark: .symbol("heart.fill"))
        XCTAssertEqual(resolve(stored, finderGreenStar), .drawnByFinder(FolderStyle(color: .green, mark: .symbol("star.fill"))))
    }

    func testAPictureIsTheCustomIconOnTheMacAndGraphitesOnIOS() throws {
        let picture = FolderPicture(path: try VaultPath(".obsidian/graphite-folder-icons/0123456789abcdef.png"), layout: .onFolder)
        let stored = FolderStyle(color: .red, mark: .picture(picture))
        let macFolder = FinderFolderLook(tags: [FinderTag(name: "Red", color: .red)], iconMark: nil, hasCustomIconFlag: true, hasCustomIconFile: true)
        XCTAssertEqual(resolve(stored, macFolder), .drawnByFinder(stored))
        let iPadFolder = FinderFolderLook(tags: [FinderTag(name: "Red", color: .red)], iconMark: nil, hasCustomIconFlag: false, hasCustomIconFile: false)
        XCTAssertEqual(resolve(stored, iPadFolder, canWritePictures: false), .drawnByGraphite(stored))
    }
}

final class FolderLookReconciliationTests: XCTestCase {
    private func action(_ stored: FolderStyle?, _ finder: FinderFolderLook, canWritePictures: Bool = true) -> FolderLookReconciliation {
        FolderLookReconciliation.action(stored: stored, finder: finder, canWritePictures: canWritePictures)
    }

    /// The owner's bug of 2026-10-21: looks chosen before Graphite wrote folder attributes stayed in its file only.
    func testAStyleOnlyInGraphitesFileIsWrittenToThePlainFolder() {
        let style = FolderStyle(color: .red, mark: .emoji("⚡️"))
        XCTAssertEqual(action(style, .plain), .writeAttributes(style))
    }

    func testNothingToDoWhenBothAgreeOrThereIsNoStyle() {
        let finder = FinderFolderLook(tags: [FinderTag(name: "Green", color: .green)], iconMark: .symbol("airplane"), hasCustomIconFlag: true, hasCustomIconFile: false)
        XCTAssertEqual(action(FolderStyle(color: .green, mark: .symbol("airplane")), finder), .none)
        XCTAssertEqual(action(nil, finder), .none)
        XCTAssertEqual(action(nil, .plain), .none)
    }

    func testALookChangedInFinderBecomesTheStyle() {
        let finder = FinderFolderLook(tags: [FinderTag(name: "Green", color: .green)], iconMark: .emoji("🥸"), hasCustomIconFlag: true, hasCustomIconFile: false)
        XCTAssertEqual(action(FolderStyle(color: .orange, mark: .symbol("airplane")), finder), .adoptFinderLook(FolderStyle(color: .green, mark: .emoji("🥸"))))
    }

    func testAPictureIsKeptWhileFinderShowsItsCustomIcon() throws {
        let picture = FolderPicture(path: try VaultPath(".obsidian/graphite-folder-icons/0123456789abcdef.png"), layout: .wholeIcon)
        let finder = FinderFolderLook(tags: [FinderTag(name: "Blue", color: .blue)], iconMark: nil, hasCustomIconFlag: true, hasCustomIconFile: true)
        XCTAssertEqual(action(FolderStyle(mark: .picture(picture)), finder), .adoptFinderLook(FolderStyle(color: .blue, mark: .picture(picture))))
    }

    /// On iOS a picture cannot be written, so only its color is compared.
    func testAPictureOnIOSAgreesWithItsColor() throws {
        let picture = FolderPicture(path: try VaultPath(".obsidian/graphite-folder-icons/0123456789abcdef.png"), layout: .onFolder)
        let finder = FinderFolderLook(tags: [FinderTag(name: "Red", color: .red)], iconMark: nil, hasCustomIconFlag: false, hasCustomIconFile: false)
        XCTAssertEqual(action(FolderStyle(color: .red, mark: .picture(picture)), finder, canWritePictures: false), .none)
    }

    func testNearestTagColors() {
        XCTAssertEqual(FinderTagColor(nearestTo: .pink), .red)
        XCTAssertEqual(FinderTagColor(nearestTo: .teal), .blue)
        XCTAssertEqual(FinderTagColor(nearestTo: .custom(red: 140, green: 40, blue: 200)), .purple)
        XCTAssertEqual(FinderTagColor(nearestTo: .custom(red: 250, green: 220, blue: 20)), .yellow)
        XCTAssertEqual(FinderTagColor(nearestTo: .custom(red: 120, green: 120, blue: 125)), .gray)
        XCTAssertNil(FinderTagColor(nearestTo: .unknown("sunset")))
    }
}

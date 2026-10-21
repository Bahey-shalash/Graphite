import XCTest
@testable import GraphiteCore

final class FinderFolderLookChangeTests: XCTestCase {
    private let systemNames: [FinderTagColor: String] = [.green: "Grün", .red: "Rot"]

    func testWritesTheColorTagLastAndKeepsOtherTags() {
        let current = FinderFolderLook(tags: [FinderTag(name: "Rot", color: .red), FinderTag(name: "Work", color: .blue)],
                                       iconMark: nil, hasCustomIconFlag: false, hasCustomIconFile: false)
        let change = FinderFolderLookChange.change(for: FolderStyle(color: .green, mark: .emoji("🥸")), from: current, colorTagNames: systemNames)
        XCTAssertEqual(change.tags, [FinderTag(name: "Work", color: .blue), FinderTag(name: "Grün", color: .green)])
        XCTAssertEqual(change.labelColor, .green)
        XCTAssertEqual(change.iconAttributeData, Data(#"{"emoji":"🥸"}"#.utf8))
        XCTAssertTrue(change.setsCustomIconFlag)
    }

    func testClearingRemovesTheColorTagTheIconAndTheFlag() {
        let current = FinderFolderLook(tags: [FinderTag(name: "Green", color: .green)], iconMark: .symbol("star.fill"),
                                       hasCustomIconFlag: true, hasCustomIconFile: false)
        let change = FinderFolderLookChange.change(for: nil, from: current, colorTagNames: systemNames)
        XCTAssertEqual(change.tags, [])
        XCTAssertNil(change.iconAttributeData)
        XCTAssertFalse(change.setsCustomIconFlag)
    }

    func testAColorNoTagHasWritesNoColorTag() {
        let change = FinderFolderLookChange.change(for: FolderStyle(color: .teal), from: .plain, colorTagNames: systemNames)
        XCTAssertEqual(change.tags, [])
        XCTAssertFalse(change.setsCustomIconFlag)
    }

    func testAPictureIsWrittenAsTheCustomIconFile() throws {
        let picture = FolderPicture(path: try VaultPath(".obsidian/graphite-folder-icons/0123456789abcdef.png"), layout: .wholeIcon)
        let current = FinderFolderLook(tags: [], iconMark: .emoji("🥸"), hasCustomIconFlag: true, hasCustomIconFile: false)
        let change = FinderFolderLookChange.change(for: FolderStyle(mark: .picture(picture)), from: current, colorTagNames: systemNames)
        XCTAssertEqual(change.customIconFile, .write(picture))
        XCTAssertNil(change.iconAttributeData)
        XCTAssertTrue(change.setsCustomIconFlag)
    }

    func testAnotherLookReplacesACustomIconFile() {
        let current = FinderFolderLook(tags: [], iconMark: nil, hasCustomIconFlag: true, hasCustomIconFile: true)
        XCTAssertEqual(FinderFolderLookChange.change(for: FolderStyle(mark: .symbol("star.fill")), from: current, colorTagNames: systemNames).customIconFile, .remove)
        XCTAssertEqual(FinderFolderLookChange.change(for: FolderStyle(mark: .symbol("star.fill")), from: .plain, colorTagNames: systemNames).customIconFile, .keep)
    }
}


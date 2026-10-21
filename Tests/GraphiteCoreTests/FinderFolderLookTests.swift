import XCTest
@testable import GraphiteCore

final class FinderFolderLookTests: XCTestCase {
    /// The bytes macOS 27's Finder wrote on a folder given a "Green" tag and the nerd-face
    /// emoji (read from a real folder with `xattr -px`).
    private let finderTagsBytes: [UInt8] = [
        0x62, 0x70, 0x6C, 0x69, 0x73, 0x74, 0x30, 0x30, 0xA1, 0x01, 0x57, 0x47, 0x72, 0x65, 0x65, 0x6E,
        0x0A, 0x31, 0x08, 0x0A, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x01, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x02, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x12
    ]
    private let finderIconBytes = Data(#"{"emoji":"🥸"}"#.utf8)
    private let finderInformationBytes: [UInt8] = [0, 0, 0, 0, 0, 0, 0, 0, 0x04, 0x02] + [UInt8](repeating: 0, count: 22)

    func testReadsWhatFinderWrote() {
        let look = FinderFolderLook(tagsData: Data(finderTagsBytes), iconData: finderIconBytes,
                                    finderInformationData: Data(finderInformationBytes), hasCustomIconFile: false)
        XCTAssertEqual(look.tags, [FinderTag(name: "Green", color: .gray)])
        XCTAssertEqual(look.mark, .emoji("🥸"))
        XCTAssertTrue(look.isCustomized)
        // The tag is named Green but carries color 1, which Finder draws gray.
        XCTAssertEqual(look.style, FolderStyle(color: .gray, mark: .emoji("🥸")))
    }

    func testTheMarkCountsOnlyWithTheCustomIconFlag() {
        let look = FinderFolderLook(tagsData: nil, iconData: Data(#"{"sym":"star.fill"}"#.utf8), finderInformationData: nil, hasCustomIconFile: false)
        XCTAssertNil(look.mark)
        XCTAssertFalse(look.isCustomized)
    }

    func testATagAloneDoesNotTintTheFolder() {
        let look = FinderFolderLook(tags: [FinderTag(name: "Red", color: .red)], iconMark: nil, hasCustomIconFlag: false, hasCustomIconFile: false)
        XCTAssertFalse(look.isCustomized)
        XCTAssertEqual(look.style, FolderStyle(color: .red))
    }

    func testTheLastColoredTagIsTheColor() {
        let look = FinderFolderLook(tags: [FinderTag(name: "Red", color: .red), FinderTag(name: "Green", color: .green), FinderTag(name: "Work", color: nil)],
                                    iconMark: .symbol("star.fill"), hasCustomIconFlag: true, hasCustomIconFile: false)
        XCTAssertEqual(look.color, .green)
    }

    func testFinderDrawsTheSymbolWhenBothAreThere() {
        XCTAssertEqual(FinderFolderLook.mark(from: Data(#"{"sym":"star.fill","emoji":"🥸"}"#.utf8)), .symbol("star.fill"))
        XCTAssertNil(FinderFolderLook.mark(from: Data(#"{"sym":""}"#.utf8)))
        XCTAssertNil(FinderFolderLook.mark(from: Data("not json".utf8)))
    }

    func testMalformedTagsAreNoTags() {
        XCTAssertEqual(FinderFolderLook.tags(from: Data("garbage".utf8)), [])
        XCTAssertEqual(FinderFolderLook.tags(from: Data(repeating: 0, count: FinderFolderLook.maximumTagsBytes + 1)), [])
        XCTAssertEqual(FinderTag(storedText: "Work\n9"), FinderTag(name: "Work", color: nil))
    }

    func testTheCustomIconFlagAndLabelKeepTheOtherBytes() throws {
        let existing = Data([UInt8](repeating: 0, count: 8) + [0x00, 0x05] + [UInt8](repeating: 0, count: 21) + [0x07])
        let set = try XCTUnwrap(FinderFolderLook.finderInformation(existing, settingCustomIconFlag: true, labelColor: .orange))
        XCTAssertEqual([UInt8](set)[8...9], [0x04, 0x0F])
        XCTAssertEqual([UInt8](set)[31], 0x07)
        let cleared = try XCTUnwrap(FinderFolderLook.finderInformation(set, settingCustomIconFlag: false, labelColor: nil))
        XCTAssertEqual([UInt8](cleared)[8...9], [0x00, 0x01])
        XCTAssertNil(FinderFolderLook.finderInformation(nil, settingCustomIconFlag: false, labelColor: nil))
    }

    func testTagsAreWrittenAsFinderWritesThem() throws {
        let tagsData = try XCTUnwrap(FinderFolderLook.tagsAttributeData(for: [FinderTag(name: "Work", color: nil), FinderTag(name: "Green", color: .green)]))
        XCTAssertEqual(FinderFolderLook.tags(from: tagsData), [FinderTag(name: "Work", color: nil), FinderTag(name: "Green", color: .green)])
        XCTAssertEqual(try PropertyListSerialization.propertyList(from: tagsData, format: nil) as? [String], ["Work", "Green\n2"])
        XCTAssertNil(FinderFolderLook.tagsAttributeData(for: []))
    }

    func testTheIconAttributeIsWhatFinderWrites() {
        XCTAssertEqual(String(decoding: FinderFolderLook.iconAttributeData(for: .emoji("🥸")) ?? Data(), as: UTF8.self), #"{"emoji":"🥸"}"#)
        XCTAssertEqual(String(decoding: FinderFolderLook.iconAttributeData(for: .symbol("star.fill")) ?? Data(), as: UTF8.self), #"{"sym":"star.fill"}"#)
    }
}

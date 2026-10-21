import XCTest
import GraphiteTestSupport
@testable import GraphiteCore

final class FolderStyleListTests: XCTestCase {
    private let writtenByANewerBuild = """
    {
      "folders": {
        "Courses/BA1": {"color": "green", "symbol": "face.smiling", "pinned": true},
        "Courses/BA2": {"color": "sunset"},
        "Broken": "not an object"
      },
      "version": 3
    }
    """

    func testReadsColorsAndSymbols() throws {
        let list = try FolderStyleList(configurationData: Data(writtenByANewerBuild.utf8))
        XCTAssertEqual(list.style(for: try VaultPath("Courses/BA1"))?.color, .green)
        XCTAssertEqual(list.style(for: try VaultPath("Courses/BA1"))?.mark, .symbol("face.smiling"))
        XCTAssertEqual(list.style(for: try VaultPath("Courses/BA2"))?.color, .unknown("sunset"))
        XCTAssertNil(list.style(for: try VaultPath("Courses")))
    }

    func testRoundTripKeepsWhatThisBuildDoesNotKnow() throws {
        let list = try FolderStyleList(configurationData: Data(writtenByANewerBuild.utf8))
        let rewritten = try JSONSerialization.jsonObject(with: list.configurationData()) as? [String: Any]
        XCTAssertEqual(rewritten?["version"] as? Int, 3)
        let folders = try XCTUnwrap(rewritten?["folders"] as? [String: Any])
        XCTAssertEqual(folders["Broken"] as? String, "not an object")
        XCTAssertEqual((folders["Courses/BA2"] as? [String: Any])?["color"] as? String, "sunset")
        XCTAssertEqual((folders["Courses/BA1"] as? [String: Any])?["pinned"] as? Bool, true)
    }

    func testChangingAColorKeepsTheFoldersOtherKeys() throws {
        var list = try FolderStyleList(configurationData: Data(writtenByANewerBuild.utf8))
        list.setStyle(FolderStyle(color: .red), for: try VaultPath("Courses/BA1"))
        let folders = try JSONSerialization.jsonObject(with: list.configurationData()) as? [String: Any]
        let entry = try XCTUnwrap((folders?["folders"] as? [String: Any])?["Courses/BA1"] as? [String: Any])
        XCTAssertEqual(entry["color"] as? String, "red")
        XCTAssertEqual(entry["pinned"] as? Bool, true)
        XCTAssertNil(entry["symbol"])
    }

    func testAFileThatIsNotThisFormatIsRefusedNotEmptied() {
        XCTAssertThrowsError(try FolderStyleList(configurationData: Data("[1, 2]".utf8))) { error in
            XCTAssertEqual(error as? FolderStyleListError, .notAJSONObject)
        }
        XCTAssertThrowsError(try FolderStyleList(configurationData: Data(#"{"folders": [1]}"#.utf8))) { error in
            XCTAssertEqual(error as? FolderStyleListError, .foldersNotAnObject)
        }
    }

    func testMissingFileMeansNoStyles() throws {
        XCTAssertTrue(try FolderStyleList(configurationData: nil).styles.isEmpty)
    }

    func testStylesFollowAMovedFolderAndTheFoldersInsideIt() throws {
        var list = FolderStyleList()
        list.setStyle(FolderStyle(color: .blue), for: try VaultPath("Courses"))
        list.setStyle(FolderStyle(color: .green), for: try VaultPath("Courses/BA1"))
        list.setStyle(FolderStyle(color: .gray), for: try VaultPath("Coursework"))
        XCTAssertTrue(list.followMove(from: try VaultPath("Courses"), to: try VaultPath("EPFL/Courses")))
        XCTAssertEqual(list.style(for: try VaultPath("EPFL/Courses"))?.color, .blue)
        XCTAssertEqual(list.style(for: try VaultPath("EPFL/Courses/BA1"))?.color, .green)
        XCTAssertEqual(list.style(for: try VaultPath("Coursework"))?.color, .gray)
        XCTAssertNil(list.style(for: try VaultPath("Courses")))
    }

    func testDeletingAFolderForgetsItsStyles() throws {
        var list = FolderStyleList()
        list.setStyle(FolderStyle(color: .blue), for: try VaultPath("Courses/BA1"))
        XCTAssertTrue(list.forget(try VaultPath("Courses")))
        XCTAssertTrue(list.styles.isEmpty)
        XCTAssertFalse(list.forget(try VaultPath("Courses")))
    }

    func testVaultWithoutStylesGetsNoFile() async throws {
        let vault = try TemporaryVault.make(prefix: "FolderStyles", for: self).root
        let store = VaultStore(root: vault)
        _ = try await store.updateFolderStyles { list in list.forget(.root) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: vault.appendingPathComponent(FolderStyleList.configurationPath).path))
        let lab = try VaultPath("Lab")
        _ = try await store.updateFolderStyles { list in list.setStyle(FolderStyle(color: .orange, mark: .symbol("flask")), for: lab) }
        let stored = try await store.folderStyles().style(for: lab)
        XCTAssertEqual(stored, FolderStyle(color: .orange, mark: .symbol("flask")))
    }

    /// The file Graphite wrote before emoji and "no color" existed reads the same today.
    func testTheEarlierFormatStillReads() throws {
        let earlierFile = #"{"folders": {"Lab": {"color": "orange", "symbol": "flask"}, "Notes": {"color": "teal"}}}"#
        let list = try FolderStyleList(configurationData: Data(earlierFile.utf8))
        XCTAssertEqual(list.style(for: try VaultPath("Lab")), FolderStyle(color: .orange, mark: .symbol("flask")))
        XCTAssertEqual(list.style(for: try VaultPath("Notes")), FolderStyle(color: .teal))
    }

    func testNoColorIsWrittenSoEarlierBuildsStillShowTheEmoji() throws {
        var list = FolderStyleList()
        list.setStyle(FolderStyle(mark: .emoji("🥸")), for: try VaultPath("Lab"))
        let folders = try JSONSerialization.jsonObject(with: list.configurationData()) as? [String: Any]
        let entry = try XCTUnwrap((folders?["folders"] as? [String: Any])?["Lab"] as? [String: Any])
        XCTAssertEqual(entry["color"] as? String, "none")
        XCTAssertEqual(entry["emoji"] as? String, "🥸")
        let reread = try FolderStyleList(configurationData: list.configurationData())
        XCTAssertEqual(reread.style(for: try VaultPath("Lab")), FolderStyle(mark: .emoji("🥸")))
    }

    func testAnyColorIsKeptAsHexadecimal() throws {
        var list = FolderStyleList()
        list.setStyle(FolderStyle(color: .custom(red: 0x1A, green: 0x2B, blue: 0xFF)), for: try VaultPath("Lab"))
        let reread = try FolderStyleList(configurationData: list.configurationData())
        XCTAssertEqual(reread.style(for: try VaultPath("Lab"))?.color, .custom(red: 0x1A, green: 0x2B, blue: 0xFF))
        XCTAssertEqual(FolderColor(rawValue: "#1a2bff"), .custom(red: 0x1A, green: 0x2B, blue: 0xFF))
        XCTAssertEqual(FolderColor(rawValue: "#1A2B"), .unknown("#1A2B"))
        XCTAssertEqual(FolderColor.custom(red: 0x1A, green: 0x2B, blue: 0xFF).rawValue, "#1A2BFF")
    }

    func testASymbolWinsOverAnEmojiAsInFinder() throws {
        let both = #"{"folders": {"Lab": {"color": "none", "symbol": "flask", "emoji": "🥸"}}}"#
        let list = try FolderStyleList(configurationData: Data(both.utf8))
        XCTAssertEqual(list.style(for: try VaultPath("Lab"))?.mark, .symbol("flask"))
    }

    func testAPlainStyleRemovesTheEntryUnlessAnotherBuildKeptKeysInIt() throws {
        var list = try FolderStyleList(configurationData: Data(writtenByANewerBuild.utf8))
        list.setStyle(FolderStyle(), for: try VaultPath("Courses/BA2"))
        XCTAssertNil(list.style(for: try VaultPath("Courses/BA2")))
        list.setStyle(nil, for: try VaultPath("Courses/BA1"))
        let folders = try JSONSerialization.jsonObject(with: list.configurationData()) as? [String: Any]
        let entry = try XCTUnwrap((folders?["folders"] as? [String: Any])?["Courses/BA1"] as? [String: Any])
        XCTAssertEqual(entry["pinned"] as? Bool, true)
        XCTAssertEqual(entry["color"] as? String, "none")
    }

    func testTheFirstEmojiTypedIsTaken() {
        XCTAssertEqual(FolderMark.firstEmoji(in: "ab😀🎉"), "😀")
        XCTAssertEqual(FolderMark.firstEmoji(in: "👍🏽"), "👍🏽")
        XCTAssertEqual(FolderMark.firstEmoji(in: "👩‍💻"), "👩‍💻")
        XCTAssertEqual(FolderMark.firstEmoji(in: "❤️"), "❤️")
        XCTAssertEqual(FolderMark.firstEmoji(in: "1️⃣"), "1️⃣")
        XCTAssertNil(FolderMark.firstEmoji(in: "1#*"))
        XCTAssertNil(FolderMark.firstEmoji(in: "©"))
        XCTAssertNil(FolderMark.firstEmoji(in: ""))
    }

    func testAPictureIsKeptWithItsLayout() throws {
        let picture = FolderPicture(path: try VaultPath(".obsidian/graphite-folder-icons/0123456789abcdef.png"), layout: .wholeIcon)
        var list = FolderStyleList()
        list.setStyle(FolderStyle(color: .green, mark: .picture(picture)), for: try VaultPath("Lab"))
        let reread = try FolderStyleList(configurationData: list.configurationData())
        XCTAssertEqual(reread.style(for: try VaultPath("Lab")), FolderStyle(color: .green, mark: .picture(picture)))
        XCTAssertEqual(reread.style(for: try VaultPath("Lab"))?.picture, picture)
    }

    /// A style file edited by hand cannot point a tile at a note or a file outside Graphite's folder.
    func testAPictureOutsideGraphitesFolderIsIgnored() throws {
        let edited = #"{"folders": {"Lab": {"color": "none", "picture": "Notes/secret.png", "emoji": "🥸"}, "Old": {"picture": ".obsidian/graphite-folder-icons/a.png", "pictureLayout": "stacked"}}}"#
        let list = try FolderStyleList(configurationData: Data(edited.utf8))
        XCTAssertEqual(list.style(for: try VaultPath("Lab"))?.mark, .emoji("🥸"))
        XCTAssertEqual(list.style(for: try VaultPath("Old"))?.picture?.layout, .unknown("stacked"))
    }

    func testPicturesAreSavedOnceAndUnusedOnesRemoved() async throws {
        let vault = try TemporaryVault.make(prefix: "FolderPictures", files: ["Lab/Note.md": "x"], for: self)
        let store = VaultStore(root: vault.root)
        let first = try await store.saveFolderPicture(Data("first".utf8))
        let again = try await store.saveFolderPicture(Data("first".utf8))
        XCTAssertEqual(again, first)
        let second = try await store.saveFolderPicture(Data("second".utf8))
        let handPlaced = try vault.writeFile(".obsidian/graphite-folder-icons/Logo.png", text: "kept")
        let lab = try VaultPath("Lab")
        _ = try await store.updateFolderStyles { list in list.setStyle(FolderStyle(mark: .picture(FolderPicture(path: second, layout: .onFolder))), for: lab) }

        XCTAssertFalse(FileManager.default.fileExists(atPath: try first.url(in: vault.root).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: try second.url(in: vault.root).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: handPlaced.path))
        _ = try await store.updateFolderStyles { list in list.setStyle(nil, for: lab) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: try second.url(in: vault.root).path))
    }
}

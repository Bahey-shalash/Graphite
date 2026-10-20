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
        XCTAssertEqual(list.style(for: try VaultPath("Courses/BA1"))?.symbolName, "face.smiling")
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
        _ = try await store.updateFolderStyles { list in list.setStyle(FolderStyle(color: .orange, symbolName: "flask"), for: lab) }
        let stored = try await store.folderStyles().style(for: lab)
        XCTAssertEqual(stored, FolderStyle(color: .orange, symbolName: "flask"))
    }
}

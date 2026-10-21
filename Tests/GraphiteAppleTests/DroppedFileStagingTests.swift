import XCTest
@testable import GraphiteApple
import GraphiteTestSupport

final class DroppedFileStagingTests: XCTestCase {
    private var sourceFolder: URL!

    override func setUpWithError() throws {
        sourceFolder = try TemporaryVault.make(prefix: "DroppedFileStaging", for: self).root
    }

    private func source(named name: String, contents: String = "one") throws -> URL {
        let location = sourceFolder.appendingPathComponent(name)
        try Data(contents.utf8).write(to: location)
        return location
    }

    func testTheSuggestedNameWinsAndGetsTheTypesExtension() {
        XCTAssertEqual(DroppedFileStaging.fileName(suggestedName: "IMG_0042", fileName: "x1y2.tmp", fileExtension: "heic"), "IMG_0042.heic")
        XCTAssertEqual(DroppedFileStaging.fileName(suggestedName: "Slides.pdf", fileName: "x1y2.tmp", fileExtension: "pdf"), "Slides.pdf")
    }

    func testAHiddenOrMissingNameBecomesTheUnnamedStem() {
        XCTAssertEqual(DroppedFileStaging.fileName(suggestedName: nil, fileName: ".com.apple.Foundation.NSItemProvider.x1.jpeg", fileExtension: "jpeg"), "Dropped File.jpeg")
        XCTAssertEqual(DroppedFileStaging.fileName(suggestedName: "", fileName: ".hidden", fileExtension: ""), "Dropped File")
    }

    func testANameWithASlashIsNotUsed() {
        XCTAssertEqual(DroppedFileStaging.fileName(suggestedName: "a/b", fileName: "Own.pdf", fileExtension: "pdf"), "Own.pdf")
    }

    func testStagedCopiesOfFilesWithTheSameNameDoNotMeetAndAreRemoved() throws {
        let original = try source(named: "Same.pdf")
        let first = try DroppedFileStaging.stage(original)
        let second = try DroppedFileStaging.stage(original)
        XCTAssertNotEqual(first.folder, second.folder)
        XCTAssertEqual(try String(contentsOf: second.copy, encoding: .utf8), "one")
        DroppedFileStaging.discard([first.folder, second.folder])
        XCTAssertFalse(FileManager.default.fileExists(atPath: first.copy.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: second.copy.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: original.path), "Discarding never touches the original.")
    }

    func testAFolderIsStagedWithItsContents() throws {
        let folder = sourceFolder.appendingPathComponent("Week 1")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("n".utf8).write(to: folder.appendingPathComponent("Note.md"))
        let staged = try DroppedFileStaging.stage(folder)
        defer { DroppedFileStaging.discard([staged.folder]) }
        XCTAssertTrue(FileManager.default.fileExists(atPath: staged.copy.appendingPathComponent("Note.md").path))
    }

    func testACopyThatFailsLeavesNoFolderBehind() throws {
        let missing = sourceFolder.appendingPathComponent("Missing.pdf")
        XCTAssertThrowsError(try DroppedFileStaging.stage(missing))
    }
}

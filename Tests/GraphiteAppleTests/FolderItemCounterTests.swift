import XCTest
import GraphiteCore
@testable import GraphiteApple
import GraphiteTestSupport

final class FolderItemCounterTests: XCTestCase {
    func testItCountsFilesAndFoldersButNotHiddenOrLinkedItems() throws {
        let vault = try TemporaryVault.make(prefix: "FolderItemCounter", files: ["Course/A.md": "a", "Course/B.pdf": "b", "Course/Week 1/C.md": "c", "Course/.hidden": "h"], for: self)
        try FileManager.default.createSymbolicLink(at: vault.location(of: "Course/Link"), withDestinationURL: vault.location(of: "Course/A.md"))
        let counter = FolderItemCounter(root: vault.root)
        XCTAssertEqual(try counter.childCount(of: VaultPath("Course")), 3)
        XCTAssertEqual(try counter.childCount(of: VaultPath("Course/Week 1")), 1)
        XCTAssertEqual(try counter.childCount(of: .root), 1)
    }

    func testAnEmptyFolderHasNoItems() throws {
        let vault = try TemporaryVault.make(prefix: "FolderItemCounter", for: self)
        try FileManager.default.createDirectory(at: vault.location(of: "Empty"), withIntermediateDirectories: true)
        XCTAssertEqual(try FolderItemCounter(root: vault.root).childCount(of: VaultPath("Empty")), 0)
    }

    func testAFolderThatIsNotThereThrows() throws {
        let vault = try TemporaryVault.make(prefix: "FolderItemCounter", for: self)
        XCTAssertThrowsError(try FolderItemCounter(root: vault.root).childCount(of: VaultPath("Missing")))
    }
}

import XCTest
@testable import GraphiteCore

final class LibraryListingTests: XCTestCase {
    private func entry(_ path: String, isDirectory: Bool = false, modified: TimeInterval = 0) throws -> VaultEntry {
        VaultEntry(path: try VaultPath(path), isDirectory: isDirectory, size: 0, modified: Date(timeIntervalSince1970: modified))
    }

    func testFoldersComeFirstAndStayWhateverTheFilter() throws {
        let entries = [try entry("Week 2.pdf"), try entry("BA1", isDirectory: true), try entry("Summary.md"), try entry("Board.png")]
        let notebooks = LibraryListing.items(of: entries, filter: .notebooks, sortOrder: .alphabetical).map(\.path.rawValue)
        XCTAssertEqual(notebooks, ["BA1", "Week 2.pdf"])
        let all = LibraryListing.items(of: entries, filter: .all, sortOrder: .alphabetical).map(\.path.rawValue)
        XCTAssertEqual(all, ["BA1", "Board.png", "Summary.md", "Week 2.pdf"])
    }

    func testDateOrderAppliesToFiles() throws {
        let entries = [try entry("Old.md", modified: 1), try entry("New.md", modified: 2)]
        XCTAssertEqual(LibraryListing.items(of: entries, filter: .notes, sortOrder: .byModifiedTime).map(\.path.rawValue), ["New.md", "Old.md"])
    }

    func testFiltersMatchTheirKinds() {
        XCTAssertTrue(LibraryFilter.boards.includes(.canvas))
        XCTAssertTrue(LibraryFilter.boards.includes(.base))
        XCTAssertFalse(LibraryFilter.pictures.includes(.pdf))
        XCTAssertTrue(LibraryFilter.all.includes(.other))
    }
}

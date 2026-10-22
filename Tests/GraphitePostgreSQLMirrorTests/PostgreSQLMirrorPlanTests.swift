import XCTest
@testable import GraphitePostgreSQLMirror

/// What a copy writes, from the notes the index holds and the notes the database holds.
final class PostgreSQLMirrorPlanTests: XCTestCase {
    private func digests(_ content: String, links: String = "none") -> CopiedNoteDigests {
        CopiedNoteDigests(contentDigest: content, linksDigest: links)
    }

    func testAnUnchangedVaultWritesNothing() {
        let notes = ["Paris.md": digests("a"), "Notes/Lyon.md": digests("b", links: "x")]
        let plan = PostgreSQLMirrorPlan(indexedNotes: notes, copiedNotes: notes)
        XCTAssertTrue(plan.isEmpty)
    }

    func testNewChangedAndRemovedNotesAreWrittenAndDeleted() {
        let indexed = ["New.md": digests("n"), "Changed.md": digests("c2"), "Same.md": digests("s")]
        let copied = ["Changed.md": digests("c1"), "Same.md": digests("s"), "Gone.md": digests("g")]
        let plan = PostgreSQLMirrorPlan(indexedNotes: indexed, copiedNotes: copied)
        XCTAssertEqual(plan.notePathsToWrite, ["Changed.md", "New.md"])
        XCTAssertEqual(plan.notePathsToDelete, ["Gone.md"])
    }

    func testChangedLinksRewriteTheLinksAndTheNotesDigest() {
        let plan = PostgreSQLMirrorPlan(indexedNotes: ["Paris.md": digests("a", links: "after")], copiedNotes: ["Paris.md": digests("a", links: "before")])
        XCTAssertEqual(plan.notePathsToWrite, ["Paris.md"], "The row keeps the links digest, so it is written with its links.")
        XCTAssertTrue(plan.notePathsToDelete.isEmpty)
    }

    func testAMovedNoteIsDeletedAtItsOldPathAndWrittenAtItsNewOne() {
        let plan = PostgreSQLMirrorPlan(indexedNotes: ["Archive/Paris.md": digests("a")], copiedNotes: ["Paris.md": digests("a")])
        XCTAssertEqual(plan.notePathsToWrite, ["Archive/Paris.md"])
        XCTAssertEqual(plan.notePathsToDelete, ["Paris.md"])
    }

    func testAConfigurationNamesWhatIsMissing() {
        var configuration = PostgreSQLMirrorConfiguration()
        XCTAssertEqual(configuration.missingSetting, "the server's address")
        configuration.host = " localhost "
        XCTAssertEqual(configuration.missingSetting, "the database's name")
        configuration.databaseName = "notes"
        XCTAssertEqual(configuration.missingSetting, "the user's name")
        configuration.userName = "felix"
        XCTAssertNil(configuration.missingSetting)
        configuration.port = 0
        XCTAssertEqual(configuration.missingSetting, "a port between 1 and 65535")
        configuration.port = 5432
        configuration.schemaName = "  "
        XCTAssertEqual(configuration.missingSetting, "the schema's name")
        XCTAssertEqual(PostgreSQLMirrorConfiguration(host: " db.example.org\n", databaseName: "notes ", userName: " felix").trimmedForConnection,
                       PostgreSQLMirrorConfiguration(host: "db.example.org", databaseName: "notes", userName: "felix"))
    }
}

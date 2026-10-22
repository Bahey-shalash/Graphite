import XCTest
@testable import GraphitePostgreSQLMirror

/// The SQL text the mirror writes itself: quoting.
final class PostgreSQLMirrorStatementsTests: XCTestCase {
    func testIdentifiersAndLiteralsAreQuotedWhateverTheyHold() {
        XCTAssertEqual(PostgreSQLMirrorStatements.quotedIdentifier("graphite"), #""graphite""#)
        XCTAssertEqual(PostgreSQLMirrorStatements.quotedIdentifier(#"my "notes""#), #""my ""notes""""#)
        XCTAssertEqual(PostgreSQLMirrorStatements.quotedLiteral("Coordonnées"), "E'Coordonnées'")
        XCTAssertEqual(PostgreSQLMirrorStatements.quotedLiteral(#"it's a \ path"#), #"E'it''s a \\ path'"#)
        XCTAssertEqual(PostgreSQLMirrorStatements(schemaName: #"Notes "2026""#).schema, #""Notes ""2026""""#)
    }
}

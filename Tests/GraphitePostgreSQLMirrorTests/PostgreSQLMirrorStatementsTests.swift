import XCTest
import GraphiteCore
@testable import GraphitePostgreSQLMirror

/// The SQL text the mirror writes itself: quoting, and the view's property columns.
final class PostgreSQLMirrorStatementsTests: XCTestCase {
    func testIdentifiersAndLiteralsAreQuotedWhateverTheyHold() {
        XCTAssertEqual(PostgreSQLMirrorStatements.quotedIdentifier("graphite"), #""graphite""#)
        XCTAssertEqual(PostgreSQLMirrorStatements.quotedIdentifier(#"my "notes""#), #""my ""notes""""#)
        XCTAssertEqual(PostgreSQLMirrorStatements.quotedLiteral("Coordonnées"), "E'Coordonnées'")
        XCTAssertEqual(PostgreSQLMirrorStatements.quotedLiteral(#"it's a \ path"#), #"E'it''s a \\ path'"#)
        XCTAssertEqual(PostgreSQLMirrorStatements(schemaName: #"Notes "2026""#).schema, #""Notes ""2026""""#)
    }

    func testPropertiesMergeAcrossVaultsByNameWhateverTheirCapitals() {
        let columns = PostgreSQLMirrorStatements.viewColumns(from: [
            MirroredPropertyColumn(propertyName: "cours", propertyType: .text, noteCount: 3),
            MirroredPropertyColumn(propertyName: "Cours", propertyType: .text, noteCount: 10),
            MirroredPropertyColumn(propertyName: "pages", propertyType: .number, noteCount: 5),
            MirroredPropertyColumn(propertyName: "Pages", propertyType: .text, noteCount: 1),
        ])
        XCTAssertEqual(columns, [
            PostgreSQLMirrorStatements.ViewColumn(columnName: "Cours", spellings: ["Cours", "cours"], type: .text),
            PostgreSQLMirrorStatements.ViewColumn(columnName: "pages", spellings: ["pages", "Pages"], type: nil),
        ], "The most used spelling names the column; types that disagree are read as text.")
    }

    func testAPropertyNamedLikeAFixedColumnIsRenamedAndATooLongNameIsLeftOut() {
        let longName = String(repeating: "é", count: 32) // 64 bytes in UTF-8
        let columns = PostgreSQLMirrorStatements.viewColumns(from: [
            MirroredPropertyColumn(propertyName: "name", propertyType: .text, noteCount: 2),
            MirroredPropertyColumn(propertyName: longName, propertyType: .text, noteCount: 9),
            MirroredPropertyColumn(propertyName: "tags", propertyType: .tags, noteCount: 7),
        ])
        XCTAssertEqual(columns.map(\.columnName), ["tags (property)", "name (property)"])
        XCTAssertEqual(columns.map(\.spellings), [["tags"], ["name"]])
    }

    func testOnlyTheMostUsedPropertiesGetAColumn() {
        let manyColumns = (0..<1_200).map { number in MirroredPropertyColumn(propertyName: "property \(number)", propertyType: .text, noteCount: number) }
        let columns = PostgreSQLMirrorStatements.viewColumns(from: manyColumns)
        XCTAssertEqual(columns.count, PostgreSQLMirrorStatements.maximumPropertyColumns)
        XCTAssertEqual(columns.first?.columnName, "property 1199")
    }

    func testEachTypeIsReadSafelyAndDatesNeedInputValidation() {
        let number = PostgreSQLMirrorStatements.typedExpression(of: ["pages"], type: .number, validatesInput: true)
        XCTAssertEqual(number, "CASE WHEN jsonb_typeof(note.properties -> E'pages') = 'number' THEN (note.properties -> E'pages' #>> '{}')::double precision END")
        let date = PostgreSQLMirrorStatements.typedExpression(of: ["date"], type: .date, validatesInput: true)
        XCTAssertTrue(date.contains("pg_input_is_valid((note.properties -> E'date' #>> '{}'), 'date')"), date)
        XCTAssertEqual(PostgreSQLMirrorStatements.typedExpression(of: ["date"], type: .date, validatesInput: false), "(note.properties -> E'date' #>> '{}')",
                       "Without validation a malformed date would fail the whole query, so dates stay text.")
        let list = PostgreSQLMirrorStatements.typedExpression(of: ["Auteurs", "auteurs"], type: .multitext, validatesInput: true)
        XCTAssertTrue(list.hasPrefix("CASE jsonb_typeof(COALESCE(note.properties -> E'Auteurs', note.properties -> E'auteurs')) WHEN 'array'"), list)
    }

    func testTheViewHasTheGeometryOnlyWithPostGIS() {
        let statements = PostgreSQLMirrorStatements(schemaName: "graphite")
        let columns = [MirroredPropertyColumn(propertyName: "cours", propertyType: .text, noteCount: 1)]
        XCTAssertTrue(statements.notesWithPropertiesView(columns: columns, postGISSchema: "public", validatesInput: true).contains("note.geometry"))
        XCTAssertFalse(statements.notesWithPropertiesView(columns: columns, postGISSchema: nil, validatesInput: true).contains("geometry"))
    }
}

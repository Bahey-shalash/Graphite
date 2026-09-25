import XCTest
import SQLite3
@testable import GraphiteCore

/// `SearchTextTokens` must read words exactly as SQLite's `unicode61` tokenizer does, since
/// the index hands SQLite the words it reads and trusts its answers. These tests compare
/// the two on every assigned character, through the system's own SQLite.
final class CoreSearchQueryUnicode61AgreementTests: XCTestCase {
    /// Words SQLite's full-text index stores for each document, in order.
    private func unicode61Words(of documents: [String]) throws -> [[String]] {
        var database: OpaquePointer?
        guard sqlite3_open(":memory:", &database) == SQLITE_OK, let database else { throw XCTSkip("SQLite could not open an in-memory database.") }
        defer { sqlite3_close(database) }
        func execute(_ sql: String) throws {
            guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else { throw NSError(domain: "SQLite", code: 1, userInfo: [NSLocalizedDescriptionKey: String(cString: sqlite3_errmsg(database))]) }
        }
        try execute("CREATE VIRTUAL TABLE search USING fts5(body, tokenize='unicode61 remove_diacritics 2'); CREATE VIRTUAL TABLE words USING fts5vocab(search, instance); BEGIN")
        var insert: OpaquePointer?
        guard sqlite3_prepare_v2(database, "INSERT INTO search(rowid, body) VALUES (?, ?)", -1, &insert, nil) == SQLITE_OK else { throw XCTSkip("SQLite has no FTS5.") }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (documentIndex, document) in documents.enumerated() {
            sqlite3_bind_int64(insert, 1, Int64(documentIndex))
            sqlite3_bind_text(insert, 2, document, -1, transient)
            XCTAssertEqual(sqlite3_step(insert), SQLITE_DONE)
            sqlite3_reset(insert)
        }
        sqlite3_finalize(insert)
        try execute("COMMIT")
        var words = Array(repeating: [String](), count: documents.count)
        var select: OpaquePointer?
        XCTAssertEqual(sqlite3_prepare_v2(database, "SELECT doc, term FROM words ORDER BY doc, offset", -1, &select, nil), SQLITE_OK)
        while sqlite3_step(select) == SQLITE_ROW {
            let documentIndex = Int(sqlite3_column_int64(select, 0))
            guard let term = sqlite3_column_text(select, 1) else { continue }
            words[documentIndex].append(String(cString: term))
        }
        sqlite3_finalize(select)
        return words
    }

    /// Every assigned character outside ASCII, the private-use planes, and surrogates.
    private var assignedScalars: [Unicode.Scalar] {
        (UInt32(0x80)...UInt32(0xEFFFF)).compactMap { value in
            guard let scalar = Unicode.Scalar(value), scalar.properties.generalCategory != .unassigned else { return nil }
            return scalar
        }
    }

    private func assertAgreement(_ documents: [String], file: StaticString = #filePath, line: UInt = #line) throws {
        let expectedWords = try unicode61Words(of: documents)
        var mismatches: [String] = []
        for (document, expected) in zip(documents, expectedWords) {
            let words = SearchTextTokens(document).tokens.map(\.folded)
            if words != expected {
                mismatches.append("\(document.unicodeScalars.map { scalar in String(scalar.value, radix: 16) }.joined(separator: " ")): \(words) != \(expected)")
            }
        }
        XCTAssert(mismatches.isEmpty, "\(mismatches.count) differ, such as:\n" + mismatches.prefix(40).joined(separator: "\n"), file: file, line: line)
    }

    func testEveryCharacterStartsFoldsAndSeparatesWordsAsTheIndexDoes() throws {
        // Each character alone, and after a letter, where accents behave differently.
        try assertAgreement(assignedScalars.map { scalar in String(scalar) })
        try assertAgreement(assignedScalars.map { scalar in "a" + String(scalar) + "b" })
    }

    func testRealWordsInSeveralScriptsReadAsTheIndexReadsThem() throws {
        try assertAgreement([
            "Это мой новый дом, Ёлка и йогурт",
            "Το άλφα και το ωμέγα ΆΛΦΑ λόγος",
            "Die Straße, STRASSE und ẞ",
            "The ﬁrst ﬂow",
            "Café, cafe\u{301}, İstanbul, Ǆemal, ộ ǘ",
            "क्षत्रिय x\u{20DD}y",
            "I ❤️ this, 👍🏽 and 🇫🇷",
            "我今天去北京玩。東京タワーに行きました",
            "서울에서 만나요",
            "ＡＢＣ ⅷ ² µ ſ",
            "\u{301}accent first, e\u{301}\u{302}\u{323}x, Ǡ ǡ Ǟ ǖ, ΣΊΣΥΦΟΣ",
            "Private \u{E000}\u{F8FF} use and \u{F0000} planes",
        ])
    }
}

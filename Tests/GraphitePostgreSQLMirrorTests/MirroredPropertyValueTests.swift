import XCTest
import GraphiteCore
@testable import GraphitePostgreSQLMirror

/// Property values as the mirror's JSON holds them, typed as the vault types each property.
final class MirroredPropertyValueTests: XCTestCase {
    private func value(_ yaml: String, type: PropertyType?) throws -> MirroredPropertyValue {
        let entry = try XCTUnwrap(BaseFrontmatter.entries(fromYAML: "key: \(yaml)")?.first)
        return MirroredPropertyValue(node: entry.node, type: type)
    }

    private func json(_ value: MirroredPropertyValue) throws -> String {
        try MirrorJSON.encodedText([value])
    }

    func testScalarsFollowTheVaultsTypes() throws {
        XCTAssertEqual(try value("12", type: .number), .number(12))
        XCTAssertEqual(try value("12", type: .text), .text("12"), "A number written as text stays text.")
        XCTAssertEqual(try value("\"007\"", type: nil), .text("007"))
        XCTAssertEqual(try value("true", type: .checkbox), .boolean(true))
        XCTAssertEqual(try value("2026-10-12", type: .date), .text("2026-10-12"))
        XCTAssertEqual(try value("2026-10-12T14:30", type: nil), .text("2026-10-12T14:30"))
        XCTAssertEqual(try value("", type: .text), .null)
        XCTAssertEqual(try value("\"[[Politique monétaire]]\"", type: .text), .text("[[Politique monétaire]]"), "Links stay as written.")
        XCTAssertEqual(try value(".inf", type: .number), .text(".inf"), "JSON has no infinity.")
    }

    func testListsKeepYAMLsTypesExceptTagsAndAliases() throws {
        XCTAssertEqual(try value("[48.8566, 2.3522]", type: .multitext), .list([.number(48.8566), .number(2.3522)]))
        XCTAssertEqual(try value("[2024, cours]", type: .tags), .list([.text("2024"), .text("cours")]))
        XCTAssertEqual(try value("fiction, classic", type: .tags), .list([.text("fiction"), .text("classic")]),
                       "Obsidian reads a text tags value as several tags.")
        XCTAssertEqual(try value("seule", type: .multitext), .list([.text("seule")]))
        XCTAssertEqual(try value("", type: .aliases), .list([]))
    }

    func testMappingsBecomeObjects() throws {
        let entry = try XCTUnwrap(BaseFrontmatter.entries(fromYAML: "lieu:\n  ville: Lausanne\n  habitants: 140000\n")?.first)
        XCTAssertEqual(MirroredPropertyValue(node: entry.node, type: .text), .object(["ville": .text("Lausanne"), "habitants": .number(140_000)]))
        XCTAssertEqual(try json(MirroredPropertyValue(node: entry.node, type: nil)), #"[{"habitants":140000,"ville":"Lausanne"}]"#)
    }
}

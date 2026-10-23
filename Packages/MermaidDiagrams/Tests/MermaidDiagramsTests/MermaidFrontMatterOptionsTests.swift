import XCTest
@testable import MermaidDiagrams

/// A type's options under the front matter's `config:`, read from block YAML as Mermaid reads it with the JSON schema.
final class MermaidFrontMatterOptionsTests: XCTestCase {
    private func options(_ source: String, section: String = "sankey") -> [String: MermaidFrontMatterOptions.Value] {
        MermaidFrontMatterOptions(section: section, in: Array(source.utf8)).values
    }

    func testScalarsAreReadAsBooleansNumbersAndText() {
        let read = options("---\nconfig:\n  sankey:\n    showValues: false\n    width: 900\n    nodePadding: 2.5e1\n    prefix: \"$\"\n"
                           + "    suffix: ' TWh'\n    nodeAlignment: left # a comment\n---\nsankey\na,b,1")
        XCTAssertEqual(read["showValues"], .boolean(false))
        XCTAssertEqual(read["width"], .number(900))
        XCTAssertEqual(read["nodePadding"], .number(25))
        XCTAssertEqual(read["prefix"], .text("$"))
        XCTAssertEqual(read["suffix"], .text(" TWh"))
        XCTAssertEqual(read["nodeAlignment"], .text("left"))
    }

    func testANestedMappingIsACollectionAndOtherSectionsAreLeft() {
        let source = "---\ntitle: Energy\nconfig:\n  theme: dark\n  sankey:\n    nodeColors:\n      Electricity grid: \"#4e79a7\"\n"
            + "    labelStyle: outlined\n  xyChart:\n    width: 300\n---\nsankey\na,b,1"
        let read = options(source)
        XCTAssertEqual(read, ["nodeColors": .collection, "labelStyle": .text("outlined")])
        XCTAssertEqual(options(source, section: "xyChart"), ["width": .number(300)])
    }

    func testTextWithoutFrontMatterOrConfigurationHasNoOptions() {
        XCTAssertTrue(options("sankey\na,b,1").isEmpty)
        XCTAssertTrue(options("---\ntitle: Only a title\n---\nsankey\na,b,1").isEmpty)
        XCTAssertTrue(options("---\nconfig:\n  sankey:\n    width: 900\n").isEmpty, "Front matter without its closing line is not read")
    }

    func testOnlyTheJSONSchemasWordsAndNumbersAreBooleansAndNumbers() {
        let read = options("---\nconfig:\n  sankey:\n    a: True\n    b: 0x1F\n    c: .5\n    d: \"12\"\n    e: [1, 2]\n---\n")
        XCTAssertEqual(read["a"], .text("True"))
        XCTAssertEqual(read["b"], .text("0x1F"))
        XCTAssertEqual(read["c"], .number(0.5))
        XCTAssertEqual(read["d"], .text("12"))
        XCTAssertEqual(read["e"], .collection)
    }
}

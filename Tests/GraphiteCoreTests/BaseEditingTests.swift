import XCTest
@testable import GraphiteCore

final class BaseDefinitionEditorTests: XCTestCase {
    private let placesYAML = """
        filters:
          and:
            - categories.containsAny(link("Places"))
        formulas:
          Type icon: list(type)[0].asFile().properties.icon
        properties:
          file.name:
            displayName: Place
        pluginSettings:
          someKey: [1, 2, 3]
        views:
          - type: map
            name: Map
            order:
              - file.name
              - rating
            coordinates: note.coordinates
            markerIcon: formula.Type icon
            defaultZoom: 12
            futureOption:
              nested: true
          - type: table
            name: Places table
            filters: 'rating > 3'
        """

    func testEditsKeepUnknownKeysAndRoundTrip() throws {
        var editor = try BaseDefinitionEditor(yaml: placesYAML)
        try editor.setSort([BaseSortKey(property: .note("rating"), direction: .descending), BaseSortKey(property: .file("name"), direction: .ascending)], forViewAt: 0)
        try editor.setName("Map of places", forViewAt: 0)
        try editor.setLimit(20, forViewAt: 0)
        try editor.setOrder([.note("rating"), .file("name"), .note("address")], forViewAt: 0)
        try editor.setGroupBy(BaseSortKey(property: .note("type"), direction: .ascending), forViewAt: 1)
        try editor.setFilterExpressions(["rating > 3", " file.hasTag(\"visited\") ", ""], forViewAt: 1)
        let yaml = try editor.yaml()
        let definition = try BaseDefinition.parse(yaml)
        XCTAssertEqual(definition.views.map(\.name), ["Map of places", "Places table"])
        guard definition.views.count >= 2 else { return XCTFail("Expected two views") }
        let map = definition.views[0]
        XCTAssertEqual(map.sort, [BaseSortKey(property: .note("rating"), direction: .descending), BaseSortKey(property: .file("name"), direction: .ascending)])
        XCTAssertEqual(map.limit, 20)
        XCTAssertEqual(map.order, [.note("rating"), .file("name"), .note("address")])
        XCTAssertTrue(yaml.contains("- rating\n"), "Existing spellings are kept:\n\(yaml)")
        XCTAssertTrue(yaml.contains("- note.address"), "New properties get their prefix:\n\(yaml)")
        XCTAssertEqual(map.map.coordinatesProperty, .note("coordinates"))
        XCTAssertEqual(map.map.markerIconProperty, .formula("Type icon"))
        XCTAssertEqual(map.map.defaultZoom, 12)
        XCTAssertEqual(definition.views[1].groupBy, BaseSortKey(property: .note("type"), direction: .ascending))
        XCTAssertEqual(definition.views[1].filters, .and([.expression("rating > 3"), .expression("file.hasTag(\"visited\")")]))
        XCTAssertEqual(definition.filters, .and([.expression("categories.containsAny(link(\"Places\"))")]))
        XCTAssertEqual(definition.formulas, [BaseFormula(name: "Type icon", sourceText: "list(type)[0].asFile().properties.icon")])
        XCTAssertEqual(definition.displayName(for: .file("name")), "Place")
        XCTAssertTrue(yaml.contains("    futureOption:\n      nested: true\n"), "Unknown view options survive as written:\n\(yaml)")
        XCTAssertTrue(yaml.contains("pluginSettings:"), "Unknown top-level keys survive:\n\(yaml)")
    }

    func testWindowsLineEndingsAreKept() throws {
        var editor = try BaseDefinitionEditor(yaml: "views:\r\n  - type: table\r\n    name: Books\r\n")
        try editor.setName("Library", forViewAt: 0)
        let output = try editor.yaml()
        XCTAssertTrue(output.contains("name: Library\r\n"))
        XCTAssertFalse(output.replacingOccurrences(of: "\r\n", with: "").contains("\n"), "Every line ends with CRLF.")
    }

    func testRemovingAndClearingOptions() throws {
        var editor = try BaseDefinitionEditor(yaml: placesYAML)
        try editor.setSort([], forViewAt: 0)
        try editor.setLimit(nil, forViewAt: 0)
        try editor.setFilterExpressions([], forViewAt: 1)
        try editor.setOption("defaultZoom", number: nil, forViewAt: 0)
        try editor.setOption("image", text: "note.cover", forViewAt: 1)
        try editor.setOption("cardSize", number: 240, forViewAt: 1)
        let definition = try BaseDefinition.parse(try editor.yaml())
        guard definition.views.count >= 2 else { return XCTFail("Expected two views") }
        XCTAssertNil(definition.views[0].map.defaultZoom)
        XCTAssertNil(definition.views[1].filters)
        XCTAssertEqual(definition.views[1].cards.imageProperty, .note("cover"))
        XCTAssertEqual(definition.views[1].cards.cardSize, 240)
        XCTAssertThrowsError(try editor.setName("x", forViewAt: 9))
    }

    func testAddingDuplicatingAndRemovingViews() throws {
        var editor = try BaseDefinitionEditor(yaml: "")
        XCTAssertEqual(editor.viewCount, 0)
        let cardsIndex = editor.addView(type: .cards, name: "Gallery")
        XCTAssertEqual(cardsIndex, 1, "An empty base gains its default table first, as Obsidian shows it.")
        let copyIndex = try editor.duplicateView(at: 1, name: "Gallery copy")
        XCTAssertEqual(copyIndex, 2)
        try editor.removeView(at: 0)
        let definition = try BaseDefinition.parse(try editor.yaml())
        XCTAssertEqual(definition.views.map(\.name), ["Gallery", "Gallery copy"])
        XCTAssertEqual(definition.views.map(\.type), [.cards, .cards])
    }

    func testTextThatLooksLikeOtherTypesStaysText() throws {
        var editor = try BaseDefinitionEditor(yaml: "views:\n  - type: table\n    name: Table\n")
        try editor.setName("2025", forViewAt: 0)
        try editor.setFilterExpressions(["true", "status == \"done\" && note[\"a: b\"] != null"], forViewAt: 0)
        let yaml = try editor.yaml()
        XCTAssertTrue(yaml.contains("name: \"2025\""), yaml)
        let definition = try BaseDefinition.parse(yaml)
        XCTAssertEqual(definition.views[0].name, "2025")
        XCTAssertEqual(definition.views[0].filters, .and([.expression("true"), .expression("status == \"done\" && note[\"a: b\"] != null")]))
    }

    /// libyaml would otherwise escape emoji as `\U0001F534` in text nobody edited.
    func testUntouchedTextKeepsEmojiAndQuoting() throws {
        let yaml = """
            formulas:
              priority_label: 'if(priority == 1, "🔴 High", if(priority == 2, "🟡 Medium", "🟢 Low"))'
              status_icon: if(done, "✅", "⏳")
              private_use: "\u{E000} stays"
            views:
              - type: table
                name: "Active 🎯"
            """
        var editor = try BaseDefinitionEditor(yaml: yaml)
        try editor.setLimit(5, forViewAt: 0)
        let output = try editor.yaml()
        XCTAssertTrue(output.contains("priority_label: 'if(priority == 1, \"🔴 High\", if(priority == 2, \"🟡 Medium\", \"🟢 Low\"))'"), output)
        XCTAssertTrue(output.contains("status_icon: if(done, \"✅\", \"⏳\")"), output)
        XCTAssertTrue(output.contains("name: \"Active 🎯\""), output)
        XCTAssertFalse(output.contains("\\U"), output)
        let definition = try BaseDefinition.parse(output)
        XCTAssertEqual(definition.formulas.first { formula in formula.name == "private_use" }?.sourceText, "\u{E000} stays", "Existing private-use characters are never used as placeholders.")
        XCTAssertEqual(definition.views[0].name, "Active 🎯")
    }

    func testInvalidFilesAreRefused() {
        XCTAssertThrowsError(try BaseDefinitionEditor(yaml: "views: [unclosed"))
        XCTAssertThrowsError(try BaseDefinitionEditor(yaml: "- a list"))
    }

    func testFlatFilterDetection() {
        XCTAssertEqual(BaseFilter.flatExpressions(of: nil), [])
        XCTAssertEqual(BaseFilter.flatExpressions(of: .expression("a")), ["a"])
        XCTAssertEqual(BaseFilter.flatExpressions(of: .and([.expression("a"), .expression("b")])), ["a", "b"])
        XCTAssertNil(BaseFilter.flatExpressions(of: .or([.expression("a")])))
        XCTAssertNil(BaseFilter.flatExpressions(of: .and([.not([.expression("a")])])))
    }
}

final class BasePropertyEditingTests: XCTestCase {
    func testSetsOnePropertyAndKeepsTheBodyUnchanged() throws {
        let note = "---\ntitle: Dune\nstatus: reading\ntags:\n  - book\n---\n# Dune\n\nBody with [[links]] and trailing spaces  \n"
        let updated = try BasePropertyEditing.settingProperty("status", to: .text("done"), in: note)
        XCTAssertEqual(updated, "---\ntitle: Dune\nstatus: done\ntags:\n  - book\n---\n# Dune\n\nBody with [[links]] and trailing spaces  \n")
        let added = try BasePropertyEditing.settingProperty("rating", to: .number(4.5), in: note)
        XCTAssertTrue(added.hasPrefix("---\ntitle: Dune\nstatus: reading\ntags:\n  - book\nrating: 4.5\n---\n"), added)
        let removed = try BasePropertyEditing.settingProperty("Status", to: nil, in: note)
        XCTAssertFalse(removed.contains("status"), "Property names match in any capitalization.")
        XCTAssertTrue(removed.hasSuffix("# Dune\n\nBody with [[links]] and trailing spaces  \n"))
    }

    func testNotesWithoutFrontmatterGainOne() throws {
        let updated = try BasePropertyEditing.settingProperty("done", to: .checkbox(true), in: "Plain note\r\n")
        XCTAssertEqual(updated, "---\r\ndone: true\r\n---\r\nPlain note\r\n", "New frontmatter uses the note's line endings.")
        let crlfNote = "---\r\ntitle: A\r\n---\r\nBody\r\n"
        XCTAssertEqual(try BasePropertyEditing.settingProperty("title", to: .text("B"), in: crlfNote), "---\r\ntitle: B\r\n---\r\nBody\r\n")
    }

    func testRefusesEditsThatWouldLoseOtherData() {
        XCTAssertThrowsError(try BasePropertyEditing.settingProperty("status", to: .text("done"), in: "---\ntitle: [unclosed\n---\nBody"))
        // Other properties are copied as written, so only the nested list itself is refused.
        XCTAssertThrowsError(try BasePropertyEditing.settingProperty("items", to: .list(["a"]), in: "---\nitems:\n  - name: a\n    count: 1\n---\nBody")) { error in
            XCTAssertTrue(error.localizedDescription.contains("nested"), error.localizedDescription)
        }
        XCTAssertEqual(try BasePropertyEditing.settingProperty("status", to: .text("done"), in: "---\nitems:\n  - name: a\n    count: 1\n---\nBody"),
                       "---\nitems:\n  - name: a\n    count: 1\nstatus: done\n---\nBody")
        XCTAssertThrowsError(try BasePropertyEditing.settingProperty(" ", to: .text("x"), in: "Body"))
    }

    func testLinksAndDatesAreWrittenInObsidianForm() throws {
        let updated = try BasePropertyEditing.settingProperty("author", to: .text("[[Frank Herbert]]"), in: "---\ndue: 2025-09-20\n---\n")
        XCTAssertEqual(updated, "---\ndue: 2025-09-20\nauthor: \"[[Frank Herbert]]\"\n---\n")
        let entries = try XCTUnwrap(BaseFrontmatter.entries(fromYAML: try XCTUnwrap(BasePropertyEditing.frontmatterYAML(in: updated))))
        guard entries.count >= 2 else { return XCTFail("Expected two properties, got \(entries)") }
        guard case .link(let link) = BaseFrontmatter.value(of: entries[1].node, declaredType: nil, source: nil, calendar: BaseDateFormatting.displayCalendar) else {
            return XCTFail("The written link reads back as a link.")
        }
        XCTAssertEqual(link.target, "Frank Herbert")
    }
}

final class BaseColorParsingTests: XCTestCase {
    func testCSSColorsAndObsidianVariables() {
        XCTAssertEqual(BaseColorParsing.color(from: "#ff0000"), .rgba(red: 1, green: 0, blue: 0, alpha: 1))
        XCTAssertEqual(BaseColorParsing.color(from: "#0f08"), .rgba(red: 0, green: 1, blue: 0, alpha: Double(0x88) / 255))
        XCTAssertEqual(BaseColorParsing.color(from: "Red"), .rgba(red: 1, green: 0, blue: 0, alpha: 1))
        XCTAssertEqual(BaseColorParsing.color(from: "rgb(255, 128, 0)"), .rgba(red: 1, green: 128.0 / 255, blue: 0, alpha: 1))
        XCTAssertEqual(BaseColorParsing.color(from: "rgba(0 0 255 / 50%)"), .rgba(red: 0, green: 0, blue: 1, alpha: 0.5))
        guard case .rgba(let red, let green, let blue, _)? = BaseColorParsing.color(from: "hsl(120, 100%, 25%)") else { return XCTFail() }
        XCTAssertEqual(red, 0, accuracy: 0.001)
        XCTAssertEqual(green, 0.5, accuracy: 0.001)
        XCTAssertEqual(blue, 0, accuracy: 0.001)
        XCTAssertEqual(BaseColorParsing.color(from: "var(--color-accent)"), .accent)
        XCTAssertEqual(BaseColorParsing.color(from: "var(--color-purple)"), .theme("purple"))
        XCTAssertNil(BaseColorParsing.color(from: "not a color"))
        XCTAssertNil(BaseColorParsing.color(from: "#12"))
    }
}

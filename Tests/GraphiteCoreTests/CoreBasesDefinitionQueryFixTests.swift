import XCTest
import Yams
@testable import GraphiteCore

/// Regressions for reading `.base` files and frontmatter as Obsidian does, and for
/// writing a base back without disturbing what the user did not change.
final class CoreBasesDefinitionQueryFixTests: XCTestCase {
    // MARK: Aliases

    /// Six lines of anchors, each repeating the previous one ten times, stand for more
    /// than a million nodes.
    private let billionLaughs: String = {
        var lines = ["a0: &a0 [" + Array(repeating: "x", count: 10).joined(separator: ", ") + "]"]
        for level in 1...5 {
            lines.append("a\(level): &a\(level) [" + Array(repeating: "*a\(level - 1)", count: 10).joined(separator: ", ") + "]")
        }
        return lines.joined(separator: "\n")
    }()

    /// Two thousand anchors, each holding the previous one: a tree two thousand levels
    /// deep written on two thousand shallow lines, which `YAMLNesting` cannot see.
    private let aliasChain: String = {
        var lines = ["a0: &a0 [x]"]
        for level in 1..<2_000 { lines.append("a\(level): &a\(level) [*a\(level - 1)]") }
        lines.append("filters: *a1999")
        return lines.joined(separator: "\n")
    }()

    func testAnchorCountingSkipsTextThatOnlyLooksLikeAnchors() {
        let anchors = (0...YAMLAliasExpansion.maximumAnchorCount).map { index in "a\(index): &a\(index) x" }
        XCTAssertTrue(YAMLAliasExpansion.exceedsAnchorCount(anchors.joined(separator: "\n")))
        XCTAssertFalse(YAMLAliasExpansion.exceedsAnchorCount(anchors.dropLast().joined(separator: "\n")))
        let lookalikes = (0..<20).map { index in "f\(index): x && a & b R&D # &comment" }
        XCTAssertFalse(YAMLAliasExpansion.exceedsAnchorCount(lookalikes.joined(separator: "\n")))
        let hiddenByApostrophe = (0...YAMLAliasExpansion.maximumAnchorCount).map { index in "don't\(index): &a\(index) x" }
        XCTAssertTrue(YAMLAliasExpansion.exceedsAnchorCount(hiddenByApostrophe.joined(separator: "\n")), "An apostrophe inside a word does not start a quote.")
    }

    /// A quote inside plain text, or a `#` inside a quoted scalar, must not hide the
    /// anchors after it: these chains compose, and a long one crashes when released.
    func testAnchorCountingSeesAnchorsAfterQuotesAndHashes() throws {
        let anchorCount = YAMLAliasExpansion.maximumAnchorCount + 1
        var afterQuoteInPlainText = ["a0: &a0 [x]"]
        var afterHashInQuotes = ["a0: &a0 [x]"]
        for level in 1..<anchorCount {
            afterQuoteInPlainText.append("a\(level): [x \"y, &a\(level) [*a\(level - 1)]]")
            afterHashInQuotes.append("a\(level): [\"x #y\", &a\(level) [*a\(level - 1)]]")
        }
        for lines in [afterQuoteInPlainText, afterHashInQuotes] {
            let yaml = lines.joined(separator: "\n")
            XCTAssertNotNil(try Yams.compose(yaml: yaml), "Every line defines a real anchor:\n\(yaml)")
            XCTAssertTrue(YAMLAliasExpansion.exceedsAnchorCount(yaml), yaml)
        }
        XCTAssertTrue(YAMLAliasExpansion.exceedsAnchorCount((0..<anchorCount).map { index in "a\(index):\u{2028}&a\(index) x" }.joined(separator: "\n")),
                      "libyaml also breaks lines at LINE SEPARATOR.")
    }

    func testExpandingAliasesAreRefusedInFrontmatter() {
        let started = Date()
        XCTAssertNil(BaseFrontmatter.entries(fromYAML: billionLaughs))
        XCTAssertLessThan(Date().timeIntervalSince(started), 1, "The walk stops at the limit instead of expanding every alias.")
        let aliasChain = aliasChain
        XCTAssertNil(onSmallStack { BaseFrontmatter.entries(fromYAML: aliasChain) })

        let reused = BaseFrontmatter.entries(fromYAML: "shared: &shared [a, b]\ncopy: *shared\n")
        XCTAssertEqual(reused?.map(\.node), [.sequence([.scalar(text: "a", isPlain: true), .scalar(text: "b", isPlain: true)]),
                                             .sequence([.scalar(text: "a", isPlain: true), .scalar(text: "b", isPlain: true)])],
                       "A few aliases are ordinary YAML and still read.")
    }

    /// Few anchors, but each nests the previous one fifteen levels deeper: the text is
    /// shallow and the tree is not.
    func testDeepTreesBuiltFromFewAnchorsAreRefused() {
        var lines = ["a0: &a0 x"]
        for level in 1...YAMLAliasExpansion.maximumAnchorCount - 1 {
            lines.append("a\(level): &a\(level) " + String(repeating: "[", count: 15) + "*a\(level - 1)" + String(repeating: "]", count: 15))
        }
        lines.append("filters: *a\(YAMLAliasExpansion.maximumAnchorCount - 1)")
        let yaml = lines.joined(separator: "\n")
        XCTAssertFalse(YAMLAliasExpansion.exceedsAnchorCount(yaml))
        let expectedError = BaseDefinitionError.invalidYAML(BaseDefinitionError.aliasesExpandTooFarReason)
        let outcomes = onSmallStack { () -> [BaseDefinitionError?] in
            var errors: [BaseDefinitionError?] = []
            do { _ = try BaseDefinition.parse(yaml); errors.append(nil) } catch { errors.append(error as? BaseDefinitionError) }
            do { _ = try BaseDefinitionEditor(yaml: yaml); errors.append(nil) } catch { errors.append(error as? BaseDefinitionError) }
            return errors
        }
        XCTAssertEqual(outcomes, [expectedError, expectedError])
        XCTAssertNil(onSmallStack { BaseFrontmatter.entries(fromYAML: yaml) })
    }

    func testExpandingAliasesAreRefusedInBases() {
        let expectedError = BaseDefinitionError.invalidYAML(BaseDefinitionError.aliasesExpandTooFarReason)
        XCTAssertThrowsError(try BaseDefinition.parse(billionLaughs)) { error in XCTAssertEqual(error as? BaseDefinitionError, expectedError) }
        XCTAssertThrowsError(try BaseDefinitionEditor(yaml: billionLaughs)) { error in XCTAssertEqual(error as? BaseDefinitionError, expectedError) }
        let aliasChain = aliasChain
        let chainErrors = onSmallStack { () -> [BaseDefinitionError?] in
            var errors: [BaseDefinitionError?] = []
            do { _ = try BaseDefinition.parse(aliasChain); errors.append(nil) } catch { errors.append(error as? BaseDefinitionError) }
            do { _ = try BaseDefinitionEditor(yaml: aliasChain); errors.append(nil) } catch { errors.append(error as? BaseDefinitionError) }
            return errors
        }
        XCTAssertEqual(chainErrors, [expectedError, expectedError])
    }

    // MARK: Frontmatter

    func testExplicitTagsDecideTheTypeOfFrontmatterValues() throws {
        let entries = try XCTUnwrap(BaseFrontmatter.entries(fromYAML: "code: !!str 007\ncount: !!int \"7\"\nplain: 007\nquoted: \"007\"\n"))
        let calendar = BaseDateFormatting.displayCalendar
        let values = entries.map { entry in BaseFrontmatter.value(of: entry.node, declaredType: nil, source: nil, calendar: calendar) }
        XCTAssertEqual(values, [.string("007"), .number(7), .number(7), .string("007")])
    }

    func testPropertyEditNeverTurnsTaggedTextIntoANumber() throws {
        let note = "---\ncode: !!str 007\nstatus: draft\n---\nBody"
        // NoteProperties may learn to keep the tag; until then the edit must be refused.
        guard let updated = try? BasePropertyEditing.settingProperty("status", to: .text("done"), in: note) else { return }
        let entries = try XCTUnwrap(BaseFrontmatter.entries(fromYAML: try XCTUnwrap(BasePropertyEditing.frontmatterYAML(in: updated))))
        let code = try XCTUnwrap(entries.first { entry in entry.key == "code" })
        XCTAssertEqual(BaseFrontmatter.value(of: code.node, declaredType: nil, source: nil, calendar: BaseDateFormatting.displayCalendar), .string("007"), updated)
    }

    func testFrontmatterNestedPastTheLimitIsKeptAsText() throws {
        let depth = BaseFrontmatter.maximumNestingDepth + 2
        let yaml = "deep: " + String(repeating: "[", count: depth) + "value" + String(repeating: "]", count: depth)
        var node = try XCTUnwrap(BaseFrontmatter.entries(fromYAML: yaml)?.first?.node)
        while case .sequence(let items) = node, let onlyItem = items.first { node = onlyItem }
        guard case .scalar(let text, let isPlain) = node else { return XCTFail("The innermost value is text.") }
        XCTAssertTrue(text.contains("value"), text)
        XCTAssertTrue(text.hasPrefix("["), "The rest of the value is written in flow style: \(text)")
        XCTAssertFalse(isPlain)
    }

    // MARK: Reading bases

    func testNullRootsAreEmptyBases() throws {
        for yaml in ["~", "Null", "NULL", "null", "", "!!null"] {
            XCTAssertEqual(try BaseDefinition.parse(yaml).views.map(\.name), ["Table"], yaml)
            var editor = try BaseDefinitionEditor(yaml: yaml)
            try editor.setLimit(5, forViewAt: 0)
            XCTAssertEqual(try BaseDefinition.parse(try editor.yaml()).views.first?.limit, 5, yaml)
        }
    }

    func testNullValuesAreAbsentKeys() throws {
        let definition = try BaseDefinition.parse("""
            filters: null
            formulas: ~
            views:
              - type: null
                name: ~
                groupBy: null
                limit: ~
                order: [file.name, null]
                filters:
                  and:
              - type: table
                name: "null"
                filters: ~
            """)
        XCTAssertNil(definition.filters)
        XCTAssertEqual(definition.issues, [])
        XCTAssertEqual(definition.views.map(\.type), [.table, .table])
        XCTAssertEqual(definition.views.map(\.name), ["View 1", "null"])
        XCTAssertNil(definition.views[0].groupBy)
        XCTAssertNil(definition.views[0].limit)
        XCTAssertEqual(definition.views[0].order, [.file("name")])
        XCTAssertEqual(definition.views[0].filters, .and([]), "`and:` with nothing after it is an empty group.")
        XCTAssertFalse(definition.views[0].hasUnreadableFilters)
        XCTAssertNil(definition.views[1].filters)
        XCTAssertEqual(try BaseDefinition.parse("views: null\n").issues, [])
    }

    func testMergeKeysApplyToViews() throws {
        let definition = try BaseDefinition.parse("""
            views:
              - &gallery
                type: cards
                name: A
                limit: 10
                sort:
                  - &byName {property: file.name}
              - <<: *gallery
                name: B
              - <<: [*gallery]
                type: list
                name: C
                sort:
                  - <<: *byName
                    direction: DESC
            """)
        XCTAssertEqual(definition.views.map(\.type), [.cards, .cards, .list])
        XCTAssertEqual(definition.views.map(\.name), ["A", "B", "C"])
        XCTAssertEqual(definition.views.map(\.limit), [10, 10, 10])
        XCTAssertEqual(definition.views[2].sort, [BaseSortKey(property: .file("name"), direction: .descending)])
        XCTAssertEqual(definition.issues, [])
    }

    func testMapOptionsRejectNaN() throws {
        let definition = try BaseDefinition.parse("""
            views:
              - type: map
                name: A
                defaultZoom: nan
                minZoom: NaN
                maxZoom: nan
                mapHeight: nan
                center: [1, 2]
            """)
        let options = definition.views[0].map
        XCTAssertNil(options.defaultZoom)
        XCTAssertEqual(options.minimumZoom, 0)
        XCTAssertEqual(options.maximumZoom, 18)
        XCTAssertEqual(options.embeddedHeight, BaseMapOptions.defaultEmbeddedHeight)
        XCTAssertEqual(try BaseDefinition.parse("views:\n  - type: map\n    zoom: nan\n    defaultZoom: 3\n").views[0].map.defaultZoom, 3)
    }

    // MARK: Editing filters and views

    func testUnreadableFiltersAreNotReplacedByAnEdit() throws {
        let yaml = """
            views:
              - type: table
                name: A
                filters:
                  and: [status == "open"]
                  or: [owner == "me"]
              - type: table
                name: B
                filters:
                  and:
                    - a == 1
                    - bogus: x
              - type: table
                name: C
                filters:
                  and:
                    - a == 1
            """
        let definition = try BaseDefinition.parse(yaml)
        XCTAssertEqual(definition.views.map(\.hasUnreadableFilters), [true, true, false])
        var editor = try BaseDefinitionEditor(yaml: yaml)
        XCTAssertThrowsError(try editor.setFilterExpressions(["file.hasTag(\"x\")"], forViewAt: 0))
        XCTAssertThrowsError(try editor.setFilterExpressions(["a == 1", "b == 2"], forViewAt: 1))
        XCTAssertEqual(try editor.yaml(), yaml, "Refused edits change nothing.")
        try editor.setFilterExpressions(["a == 1", "b == 2"], forViewAt: 2)
        XCTAssertEqual(try BaseDefinition.parse(try editor.yaml()).views[2].filters, .and([.expression("a == 1"), .expression("b == 2")]))
    }

    func testViewsThatAreNotAListAreNeverOverwritten() throws {
        let mappingViews = "views:\n  foo:\n    type: cards\n"
        var editor = try BaseDefinitionEditor(yaml: mappingViews)
        XCTAssertThrowsError(try editor.setLimit(3, forViewAt: 0))
        editor.addView(type: .cards, name: "Gallery")
        XCTAssertThrowsError(try editor.yaml(), "Adding a view to it would delete `foo`.")

        var textViews = try BaseDefinitionEditor(yaml: "views:\n  - just text\n")
        XCTAssertThrowsError(try textViews.setLimit(3, forViewAt: 0)) { error in
            XCTAssertFalse(error.localizedDescription.contains("Reload"), "Reloading cannot help: \(error.localizedDescription)")
        }

        var nullViews = try BaseDefinitionEditor(yaml: "views: ~\n")
        try nullViews.setLimit(3, forViewAt: 0)
        XCTAssertEqual(try BaseDefinition.parse(try nullViews.yaml()).views.first?.limit, 3)
    }

    // MARK: Writing back

    private let commentedBase = """
        # My base comment
        ---
        filters:
          and:
            - file.hasTag("book")   # trailing comment
        formulas: {total: price * quantity}
        views:
          - type: table
            name: Books
            order: [file.name, status]
            custom: !mytag value
            label: !!str 123
            futureOption:
              nested: true
          # Gallery of covers
          - type: cards
            name: Covers
            limit: 20
        ...
        # after the document
        """

    func testUnchangedBaseIsWrittenBackByteForByte() throws {
        let editor = try BaseDefinitionEditor(yaml: commentedBase)
        XCTAssertEqual(try editor.yaml(), commentedBase)
    }

    func testEditsChangeOnlyTheEditedLines() throws {
        var editor = try BaseDefinitionEditor(yaml: commentedBase)
        try editor.setLimit(5, forViewAt: 0)
        try editor.setName("Library", forViewAt: 0)
        let output = try editor.yaml()
        let expected = commentedBase
            .replacingOccurrences(of: "    name: Books\n", with: "    name: Library\n")
            .replacingOccurrences(of: "      nested: true\n", with: "      nested: true\n    limit: 5\n")
        XCTAssertEqual(output, expected)
    }

    func testChangedListsKeepTheFilesIndentation() throws {
        var editor = try BaseDefinitionEditor(yaml: commentedBase)
        try editor.setSort([BaseSortKey(property: .note("status"), direction: .descending)], forViewAt: 1)
        try editor.setOrder([.note("status"), .file("name"), .note("author")], forViewAt: 0)
        let output = try editor.yaml()
        XCTAssertTrue(output.contains("    order:\n      - status\n      - file.name\n      - note.author\n    custom: !mytag value\n"), output)
        XCTAssertTrue(output.contains("    limit: 20\n    sort:\n      - property: note.status\n        direction: DESC\n...\n"), output)
        XCTAssertTrue(output.hasPrefix("# My base comment\n---\nfilters:\n  and:\n    - file.hasTag(\"book\")   # trailing comment\nformulas: {total: price * quantity}\n"), output)
        XCTAssertTrue(output.hasSuffix("...\n# after the document"), output)
    }

    func testAddingDuplicatingAndRemovingViewsKeepsOtherViewsAsWritten() throws {
        var added = try BaseDefinitionEditor(yaml: commentedBase)
        added.addView(type: .list, name: "Reading list")
        let addedOutput = try added.yaml()
        XCTAssertTrue(addedOutput.contains("    limit: 20\n  - type: list\n    name: Reading list\n    order:\n      - file.name\n...\n"), addedOutput)
        XCTAssertTrue(addedOutput.contains("  # Gallery of covers\n"), addedOutput)

        var duplicated = try BaseDefinitionEditor(yaml: commentedBase)
        try duplicated.duplicateView(at: 0, name: "Books copy")
        let duplicatedOutput = try duplicated.yaml()
        XCTAssertTrue(duplicatedOutput.contains("    custom: !mytag value\n    label: !!str 123\n"), "The original view keeps its tags:\n\(duplicatedOutput)")
        let copy = try XCTUnwrap(try Yams.compose(yaml: duplicatedOutput)?["views"]?.sequence?[1].mapping)
        XCTAssertEqual(copy["name"]?.string, "Books copy")
        XCTAssertEqual(copy["label"]?.scalar?.style, .doubleQuoted, "A copied `!!str 123` stays text:\n\(duplicatedOutput)")
        XCTAssertEqual(try BaseDefinition.parse(duplicatedOutput).views.map(\.name), ["Books", "Books copy", "Covers"])

        var removed = try BaseDefinitionEditor(yaml: commentedBase)
        try removed.removeView(at: 0)
        let removedOutput = try removed.yaml()
        XCTAssertTrue(removedOutput.contains("views:\n  # Gallery of covers\n  - type: cards\n"), removedOutput)
        XCTAssertEqual(try BaseDefinition.parse(removedOutput).views.map(\.name), ["Covers"])
    }

    func testRewrittenViewKeepsExplicitStringTags() throws {
        // A view written in flow style is replaced whole when it changes.
        var editor = try BaseDefinitionEditor(yaml: "views:\n  - {type: table, name: !!str 123, count: !!int \"7\"}\n")
        try editor.setLimit(3, forViewAt: 0)
        let output = try editor.yaml()
        let view = try XCTUnwrap(try Yams.compose(yaml: output)?["views"]?.sequence?.first?.mapping)
        XCTAssertEqual(view["name"]?.scalar?.style, .doubleQuoted, output)
        XCTAssertEqual(view["count"]?.int, 7, output)
        XCTAssertEqual(try BaseDefinition.parse(output).views.first?.name, "123")
    }

    func testLineEndingsAreKeptPerLine() throws {
        var carriageReturns = try BaseDefinitionEditor(yaml: "views:\r  - type: table\r    name: X\r")
        try carriageReturns.setLimit(3, forViewAt: 0)
        XCTAssertEqual(try carriageReturns.yaml(), "views:\r  - type: table\r    name: X\r    limit: 3\r")

        let mixed = "filters: a == 1\nformulas:\n  x: 1\r\nviews:\n  - type: table\n    name: X\n"
        var mixedEditor = try BaseDefinitionEditor(yaml: mixed)
        try mixedEditor.setLimit(3, forViewAt: 0)
        XCTAssertEqual(try mixedEditor.yaml(), mixed + "    limit: 3\n", "Only the added line is new; the CRLF line stays as it was.")

        var withoutFinalBreak = try BaseDefinitionEditor(yaml: "views:\r\n  - type: table\r\n    name: X")
        try withoutFinalBreak.setLimit(3, forViewAt: 0)
        XCTAssertEqual(try withoutFinalBreak.yaml(), "views:\r\n  - type: table\r\n    name: X\r\n    limit: 3\r\n")
    }

    func testCommentOnlyBaseGainsViewsAfterItsComments() throws {
        var editor = try BaseDefinitionEditor(yaml: "# Reading tracker\n")
        editor.addView(type: .cards, name: "Gallery")
        let output = try editor.yaml()
        XCTAssertTrue(output.hasPrefix("# Reading tracker\nviews:\n"), output)
        XCTAssertEqual(try BaseDefinition.parse(output).views.map(\.name), ["Table", "Gallery"])
    }

    // MARK: Helpers

    /// Runs `work` on a thread with the 512 KB stack that Swift concurrency threads have.
    private func onSmallStack<Value>(_ work: @escaping @Sendable () -> Value) -> Value {
        let resultBox = SmallStackResultBox<Value>()
        let finished = DispatchSemaphore(value: 0)
        let thread = Thread {
            resultBox.value = work()
            finished.signal()
        }
        thread.stackSize = 512 * 1_024
        thread.start()
        finished.wait()
        guard let value = resultBox.value else { preconditionFailure("The thread always stores a result before signaling.") }
        return value
    }
}

/// Written once by the worker thread before it signals, then read once after the wait.
private final class SmallStackResultBox<Value>: @unchecked Sendable {
    var value: Value?
}


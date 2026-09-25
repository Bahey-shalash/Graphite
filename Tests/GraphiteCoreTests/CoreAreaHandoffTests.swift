import XCTest
import Yams
@testable import GraphiteCore

/// Regressions for changes other groups handed to the core files: date fields, YAML
/// limits and explicit tags in frontmatter, compact nesting, link candidates, empty
/// frontmatter, paragraph blocks and formula sorting.
final class CoreAreaHandoffTests: XCTestCase {
    private let note = BaseTestRecords.record("Folder/Note.md")

    private func evaluate(_ sourceText: String) throws -> BaseValue {
        let evaluator = BaseEvaluator(formulas: [], environment: BaseTestRecords.environment(), thisRecord: nil, knownRecords: [note])
        return try evaluator.evaluate(sourceText: sourceText, for: note)
    }

    // MARK: Date fields (F417, F428)

    func testDateYearCountsYearsBeforeTheCommonEraAsMomentDoes() throws {
        XCTAssertEqual(try evaluate("date(\"0000-06-01\").year"), .number(0), "1 BCE is year 0.")
        XCTAssertEqual(try evaluate("date(\"2025-06-01\").year"), .number(2025))
        let calendar = BaseDateFormatting.displayCalendar
        let beforeCommonEra = try XCTUnwrap(calendar.date(from: DateComponents(era: 0, year: 251, month: 10, day: 19, hour: 12)))
        let beforeCommonEraMilliseconds = Int64(beforeCommonEra.timeIntervalSince1970 * 1_000)
        XCTAssertEqual(try evaluate("date(\(beforeCommonEraMilliseconds)).year"), .number(-250), "251 BCE is year -250.")
        for dateSource in ["date(\"0000-06-01\")", "date(\(beforeCommonEraMilliseconds))", "date(\"0001-01-01\")", "date(\"2025-06-01\")"] {
            XCTAssertEqual(try evaluate("\(dateSource).year"), try evaluate("number(\(dateSource).format(\"YYYY\"))"), dateSource)
        }
    }

    func testDateMillisecondIsTheWrittenMillisecond() throws {
        for millisecond in 0..<1_000 {
            let writtenMilliseconds = String(format: "%03d", millisecond)
            XCTAssertEqual(try evaluate("date(\"2025-06-01T10:00:00.\(writtenMilliseconds)Z\").millisecond"), .number(Double(millisecond)), writtenMilliseconds)
        }
    }

    // MARK: Formula list sorting (F409)

    func testListSortIsOneOrderWhateverTheInputOrder() throws {
        let orderings = [
            "[image(\"a50\"), \"a9\", \"a100\", link(\"a70\")]",
            "[\"a100\", link(\"a70\"), \"a9\", image(\"a50\")]",
            "[\"a9\", \"a100\", image(\"a50\"), link(\"a70\")]",
        ]
        let sortedTexts = try orderings.map { listText -> [String] in
            guard case .list(let elements) = try evaluate(listText + ".sort()") else { XCTFail("Not a list"); return [] }
            return elements.map(\.displayText)
        }
        XCTAssertEqual(Set(sortedTexts.map { texts in texts.joined(separator: ",") }).count, 1, "\(sortedTexts)")
        XCTAssertEqual(try evaluate("[3, number(\"nan\"), 1].sort()").displayText, try evaluate("[number(\"nan\"), 1, 3].sort()").displayText)
        guard case .list(let numbers) = try evaluate("[3, number(\"nan\"), 1].sort()") else { return XCTFail("Not a list") }
        XCTAssertEqual(Array(numbers.prefix(2)), [.number(1), .number(3)], "NaN sorts after every number.")
    }

    // MARK: Compact nesting (F18)

    func testCompactIndicatorsCountAsNesting() {
        let deepSequences = "filters:\n  " + String(repeating: "- ", count: 400) + "x"
        let deepKeys = "filters:\n  " + String(repeating: "? ", count: 400) + "x"
        let outcomes = onConcurrencySizedStack { () -> [BaseDefinitionError?] in
            [deepSequences, deepKeys].map { yaml in
                do {
                    _ = try BaseDefinition.parse(yaml)
                    return nil
                } catch {
                    return error as? BaseDefinitionError
                }
            }
        }
        XCTAssertEqual(outcomes, [.invalidYAML(BaseDefinitionError.nestedTooDeeplyReason), .invalidYAML(BaseDefinitionError.nestedTooDeeplyReason)])
        XCTAssertFalse(YAMLNesting.exceedsSafeDepth("a:\n  - - - x\n  - ? k\n    : v\n"))
        XCTAssertFalse(YAMLNesting.exceedsSafeDepth("---\n-1\n-x\n"))
    }

    // MARK: Aliases in frontmatter (F21)

    /// Anchors that each hold the previous one build a tree far deeper than its text,
    /// which crashed when the tree was released on a small stack.
    private let aliasChainFrontmatter = "aliases: [Name]\n" + (1...3_000).map { anchorIndex in "a\(anchorIndex): &a\(anchorIndex) [*a\(anchorIndex - 1)]" }
        .joined(separator: "\n").replacingOccurrences(of: "[*a0]", with: "[x]")

    /// Nine anchors, each repeating the previous one ten times: a billion values.
    private let repeatedAliasFrontmatter = "aliases: [Name]\na0: &a0 [x, x, x, x, x, x, x, x, x, x]\n" + (1...8).map { anchorIndex in
        "a\(anchorIndex): &a\(anchorIndex) [" + Array(repeating: "*a\(anchorIndex - 1)", count: 10).joined(separator: ", ") + "]"
    }.joined(separator: "\n")

    func testAliasChainsInFrontmatterAreRefusedWithoutCrashing() throws {
        let chain = aliasChainFrontmatter
        let outcome = onConcurrencySizedStack { () -> (semanticsAliases: [String]?, properties: Int?) in
            let semantics = try? MarkdownSemantics.parse("---\n" + chain + "\n---\nbody")
            return (semantics?.aliases, NoteProperties.parse(chain)?.count)
        }
        XCTAssertEqual(outcome?.semanticsAliases, [], "The note still parses; its invalid properties are ignored.")
        XCTAssertNil(outcome?.properties)
    }

    func testRepeatedAliasesInFrontmatterAreRefusedQuickly() throws {
        let startTime = Date()
        XCTAssertEqual(try MarkdownSemantics.parse("---\n" + repeatedAliasFrontmatter + "\n---\nbody").aliases, [])
        XCTAssertNil(NoteProperties.parse(repeatedAliasFrontmatter))
        XCTAssertLessThan(Date().timeIntervalSince(startTime), 5)
        XCTAssertEqual(NoteProperties.parse("base: &base shared\ncopy: *base\n")?.map(\.value), [.text("shared"), .text("shared")],
                       "A few ordinary aliases still read.")
    }

    // MARK: Explicit tags in frontmatter (F115)

    func testExplicitScalarTagsDecideThePropertyType() throws {
        let properties = try XCTUnwrap(NoteProperties.parse("id: !!str 007\ncount: !!int \"7\"\nflag: !!bool \"true\"\nplain: 007\n"))
        XCTAssertEqual(properties.map(\.value), [.text("007"), .number(7), .checkbox(true), .number(7)])
    }

    func testTaggedTextIsNeverRewrittenAsANumber() throws {
        let source = "---\nid: !!str 007\nstatus: todo\n---\nbody"
        let properties = try XCTUnwrap(NoteProperties.parse("id: !!str 007\nstatus: todo"))
        let otherPropertyChanged = properties.map { property in property.key == "status" ? NoteProperty(key: "status", value: .text("done")) : property }
        XCTAssertEqual(NoteProperties.replacingFrontmatter(in: source, with: otherPropertyChanged), "---\nid: !!str 007\nstatus: done\n---\nbody")

        let taggedPropertyChanged = properties.map { property in property.key == "id" ? NoteProperty(key: "id", value: .text("008")) : property }
        let rewritten = NoteProperties.replacingFrontmatter(in: source, with: taggedPropertyChanged)
        XCTAssertEqual(rewritten, "---\nid: \"008\"\nstatus: todo\n---\nbody")

        // A flow mapping cannot be spliced, so every property is written anew.
        let flowSource = "---\n{id: !!str 007, status: todo}\n---\nbody"
        let flowProperties = try XCTUnwrap(NoteProperties.parse("{id: !!str 007, status: todo}"))
        let flowRewritten = NoteProperties.replacingFrontmatter(in: flowSource, with: flowProperties.map { property in
            property.key == "status" ? NoteProperty(key: "status", value: .text("done")) : property
        })
        XCTAssertEqual(flowRewritten, "---\nid: \"007\"\nstatus: done\n---\nbody")
        XCTAssertEqual(NoteProperties.parse("id: \"007\"\nstatus: done")?.first?.value, .text("007"))
    }

    // MARK: Empty frontmatter in base records (F343)

    func testFrontmatterHoldingOnlyCommentsHasNoProperties() {
        XCTAssertEqual(BaseFrontmatter.entries(fromYAML: "# nothing here yet\n# still nothing"), [])
        XCTAssertNil(BaseFrontmatter.entries(fromYAML: "key: [unclosed"), "Invalid YAML is still invalid.")
        XCTAssertNil(BaseFrontmatter.entries(fromYAML: "- a list\n- at the top"), "A list is not a mapping.")
    }

    // MARK: Link candidates (F7)

    func testMarkdownLinksAlsoResolveFromTheVaultRoot() throws {
        let source = try VaultPath("Other/Note.md")
        func candidates(_ target: String) -> [String] {
            WikiLinkResolver.directCandidates(target: target, source: source, isWiki: false).map(\.rawValue)
        }
        XCTAssertEqual(Array(candidates("Folder/Sub/Target.md").prefix(2)), ["Other/Folder/Sub/Target.md", "Folder/Sub/Target.md"],
                       "Beside the note first, then from the root.")
        XCTAssertEqual(Array(candidates("Folder/Sub/Target%20Two.md").prefix(2)), ["Other/Folder/Sub/Target Two.md", "Folder/Sub/Target Two.md"])
        XCTAssertEqual(candidates("./Target.md").filter { candidate in !candidate.hasPrefix("Other/") }, [],
                       "A path starting with ./ is relative to the note only.")
        XCTAssertEqual(candidates("../Target.md").first, "Target.md")
        XCTAssertEqual(WikiLinkResolver.directCandidates(target: "Folder/Sub/Target.md", source: source, isWiki: true).map(\.rawValue), candidates("Folder/Sub/Target.md"))
    }

    // MARK: Paragraph blocks (F327)

    func testParagraphEndsAtASpacedThematicBreak() {
        for thematicBreak in ["- - -", "* * *", "_ _ _"] {
            let text = "para\n\(thematicBreak)\nafter"
            let paragraphs = NoteBlocks.blocks(in: text).filter { block in block.kind == .paragraph }.map(\.text)
            XCTAssertEqual(paragraphs, ["para", "after"], thematicBreak)
        }
    }

    // MARK: Display math in Live Preview (F13)

    func testLivePreviewMathOpenedAfterTextNeverCoversALaterHeading() {
        for note in ["- $$\n  x^2\n  $$\n\nText\n\n## Heading", "Text $$\nE=mc^2\n$$\n## Heading"] {
            let headingLocation = (note as NSString).range(of: "## Heading").location
            let mathBlocks = LivePreviewBlockScanner.blocks(in: note as NSString).filter { block in block.kind == .mathBlock }
            XCTAssertFalse(mathBlocks.contains { block in NSLocationInRange(headingLocation, block.range) }, note)
        }
        let displayMath = LivePreviewBlockScanner.blocks(in: "$$\nx^2\n$$\n## Heading" as NSString)
        XCTAssertEqual(displayMath.map(\.kind), [.mathBlock])
        XCTAssertEqual(displayMath.first?.markdown, "$$\nx^2\n$$")
        XCTAssertEqual(LivePreviewBlockScanner.blocks(in: "$$x^2$$\nText" as NSString).map(\.kind), [.mathBlock], "A one-line formula is still a block.")
    }

    // MARK: Markdown image destinations (F80)

    func testLivePreviewLeavesWebImagesAsMarkdown() {
        XCTAssertTrue(LivePreviewBlockScanner.blocks(in: "![](https://example.com/a.png)\n" as NSString).isEmpty)
        XCTAssertTrue(LivePreviewBlockScanner.blocks(in: "![photo](https://example.com/a.png \"Title\")" as NSString).isEmpty)
        guard case .embed(let embed)? = LivePreviewBlockScanner.blocks(in: "![photo](Attachments/a.png \"Title\")" as NSString).first?.kind else {
            return XCTFail("A vault image with a title is still an embed.")
        }
        XCTAssertEqual(embed.target, "Attachments/a.png")
    }

    func testMarkdownEmbedTitlesAreNotPartOfTheTarget() {
        func target(_ line: String) -> String? {
            EmbedLocator.embed(at: 1, in: line as NSString)?.target
        }
        XCTAssertEqual(target("![a](a.png \"Title\")"), "a.png")
        XCTAssertEqual(target("![a](a.png 'Title')"), "a.png")
        XCTAssertEqual(target("![a](a.png (Title))"), "a.png")
        XCTAssertEqual(target("![a](<my file.png> \"Title\")"), "my file.png")
        XCTAssertEqual(target("![a](a.png)"), "a.png")
    }

    // MARK: Nested aliases in frontmatter mappings (F66)

    func testAliasesNestingMappingsInFrontmatterAreRefusedQuickly() {
        let keys = (0..<10).map { keyIndex in "k\(keyIndex)" }
        var yaml = "title: Note\nm0: &m0 {" + keys.map { key in "\(key): x" }.joined(separator: ", ") + "}\n"
        for level in 1...7 {
            yaml += "m\(level): &m\(level) {" + keys.map { key in "\(key): *m\(level - 1)" }.joined(separator: ", ") + "}\n"
        }
        let startTime = Date()
        XCTAssertNil(NoteProperties.parse(yaml))
        XCTAssertLessThan(Date().timeIntervalSince(startTime), 5)
    }

    // MARK: Nested mappings edited from a base (F36)

    func testBaseEditingRefusesToReplaceANestedMapping() throws {
        let note = "---\nmeta:\n  author: Frank\n  year: 1965\nstatus: todo\n---\nBody"
        XCTAssertThrowsError(try BasePropertyEditing.settingProperty("meta", to: .text("{author: Frank, year: 1965}"), in: note)) { error in
            XCTAssertTrue(error.localizedDescription.contains("nested values"), error.localizedDescription)
        }
        XCTAssertEqual(try BasePropertyEditing.settingProperty("status", to: .text("done"), in: note),
                       "---\nmeta:\n  author: Frank\n  year: 1965\nstatus: done\n---\nBody", "Other properties stay editable.")
        XCTAssertEqual(try BasePropertyEditing.settingProperty("meta", to: nil, in: note), "---\nstatus: todo\n---\nBody", "Removing the property is still allowed.")
    }

    // MARK: Number spellings in a rewritten frontmatter (F71)

    func testRewrittenFrontmatterKeepsTheSpellingOfUntouchedNumbers() throws {
        let source = "---\n{code: 007, ratio: 1.10, count: 3, title: Old}\n---\nbody"
        let properties = try XCTUnwrap(NoteProperties.parse("{code: 007, ratio: 1.10, count: 3, title: Old}"))
        let edited = properties.map { property in
            switch property.key {
            case "title": NoteProperty(key: "title", value: .text("New"))
            case "count": NoteProperty(key: "count", value: .number(4))
            default: property
            }
        }
        XCTAssertEqual(NoteProperties.replacingFrontmatter(in: source, with: edited), "---\ncode: 007\nratio: 1.10\ncount: 4\ntitle: New\n---\nbody")
    }

    // MARK: Regular expressions in formulas (F134)

    func testRunawayFormulaPatternStopsWithAnError() {
        let clock = ContinuousClock()
        let startTime = clock.now
        let subject = String(repeating: "a", count: 32) + "!"
        for formula in ["/(a+)+$/.matches(\"\(subject)\")", "\"\(subject)\".replace(/(a+)+$/g, \"x\")", "\"\(subject)\".split(/(a+)+$/)"] {
            XCTAssertThrowsError(try evaluate(formula), formula) { error in
                XCTAssertTrue(error.localizedDescription.contains("took too long"), error.localizedDescription)
            }
        }
        XCTAssertLessThan(clock.now - startTime, .seconds(15))
        XCTAssertEqual(try evaluate("/b+/.matches(\"abbc\")"), .boolean(true))
        XCTAssertEqual(try evaluate("\"a-b-c\".replace(/-/g, \"+\")"), .string("a+b+c"))
        XCTAssertEqual(try evaluate("\"a-b\".replace(/-/, \"+\")"), .string("a+b"))
    }

    // MARK: Link resolution per folder (P25)

    func testLinksAreResolvedOncePerFolder() {
        let records = ["A/One.md", "A/Two.md", "B/Three.md", "Target.md"].map { path in BaseTestRecords.record(path) }
        let provider = CountingRecordProvider(records: records)
        let evaluator = BaseEvaluator(formulas: [], environment: BaseTestRecords.environment(), thisRecord: nil, provider: provider)
        let oneInA = evaluator.resolveLink("Target", from: records[0].path)
        let twoInA = evaluator.resolveLink("Target", from: records[1].path)
        XCTAssertEqual(provider.resolutionCount, 1, "Two notes in one folder share one resolution.")
        XCTAssertEqual(oneInA?.rawValue, "Target.md")
        XCTAssertEqual(twoInA?.rawValue, "Target.md")
        _ = evaluator.resolveLink("Target", from: records[2].path)
        XCTAssertEqual(provider.resolutionCount, 2, "Another folder resolves again.")
        XCTAssertEqual(evaluator.resolveLink("#Heading", from: records[1].path), records[1].path, "A heading link names its own note.")
    }

    // MARK: Helpers

    /// Runs `work` on a thread with the 512 KB stack of a Swift concurrency thread.
    private func onConcurrencySizedStack<Value>(_ work: @escaping @Sendable () -> Value) -> Value? {
        let resultBox = HandoffResultBox<Value>()
        let finished = DispatchSemaphore(value: 0)
        let thread = Thread {
            resultBox.value = work()
            finished.signal()
        }
        thread.stackSize = 512 * 1_024
        thread.start()
        finished.wait()
        return resultBox.value
    }
}

/// Written once by the worker thread before it signals the semaphore, and read only after
/// the wait, so the semaphore orders the two accesses.
private final class HandoffResultBox<Value>: @unchecked Sendable {
    var value: Value?
}

/// Counts how often the evaluator asks for a link resolution.
private final class CountingRecordProvider: BaseRecordProvider, @unchecked Sendable {
    private let recordProvider: BaseInMemoryRecordProvider
    // Guards `resolutions`, which the evaluator may reach from any thread.
    private let lock = NSLock()
    private var resolutions = 0

    init(records: [BaseFileRecord]) {
        recordProvider = BaseInMemoryRecordProvider(records: records)
    }

    var resolutionCount: Int { lock.withLock { resolutions } }

    func record(at path: VaultPath) -> BaseFileRecord? { recordProvider.record(at: path) }

    func resolveLinkTarget(_ target: String, from source: VaultPath) -> VaultPath? {
        lock.withLock { resolutions += 1 }
        return recordProvider.resolveLinkTarget(target, from: source)
    }

    func backlinks(to path: VaultPath) -> [VaultPath] { recordProvider.backlinks(to: path) }
}

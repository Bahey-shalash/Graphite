import XCTest
@testable import GraphiteCore

/// Builds records the way the index would, from frontmatter YAML.
enum BaseTestRecords {
    static let referenceDate = Date(timeIntervalSince1970: 1_758_000_000) // 2025-09-16

    static func record(_ path: String, yaml: String = "", tags: [String] = [], links: [BaseRecordLink] = [], size: Int = 1_000,
                       created: Date = referenceDate, modified: Date = referenceDate) -> BaseFileRecord {
        // Fixtures are often stored properties, built while XCTest assembles the suite, where
        // XCTFail is silently dropped. A broken fixture must stop the run rather than become an
        // empty record at the vault root, which tests of missing values would accept.
        guard let recordPath = try? VaultPath(path) else { preconditionFailure("Invalid fixture path: \(path)") }
        guard let properties = BaseFrontmatter.entries(fromYAML: yaml) else { preconditionFailure("Invalid fixture YAML for \(path):\n\(yaml)") }
        return BaseFileRecord(path: recordPath, size: size, createdDate: created, modifiedDate: modified,
                              properties: properties, tags: tags, links: links)
    }

    static func wikiLink(_ target: String, isEmbed: Bool = false) -> BaseRecordLink {
        BaseRecordLink(target: target, isEmbed: isEmbed, isWiki: true)
    }

    /// 2025-09-16 10:30 in the device time zone, so date-only arithmetic is predictable.
    static var fixedNow: Date {
        var components = DateComponents(year: 2025, month: 9, day: 16, hour: 10, minute: 30)
        components.timeZone = BaseDateFormatting.displayCalendar.timeZone
        return BaseDateFormatting.displayCalendar.date(from: components) ?? referenceDate
    }

    /// The display calendar, as the app uses. Date text is always moment's English,
    /// whatever the device language.
    static func environment(declaredTypes: [String: PropertyType] = [:]) -> BaseEvaluationEnvironment {
        BaseEvaluationEnvironment(now: fixedNow, calendar: BaseDateFormatting.displayCalendar, declaredTypes: declaredTypes)
    }
}

final class BaseEvaluatorTests: XCTestCase {
    private let book = BaseTestRecords.record("Library/Books/Dune.md", yaml: """
        title: Dune
        author: "[[Frank Herbert]]"
        pages: 412
        price: 9.5
        quantity: 3
        done: false
        status: reading
        rating: 4.5
        due: 2025-09-20
        categories:
          - "[[Books]]"
          - "[[Classics]]"
        scores: [3, 1, 2]
        tags: [book, scifi]
        """, tags: ["book", "scifi/classic"], links: [BaseTestRecords.wikiLink("Frank Herbert"), BaseTestRecords.wikiLink("cover.png", isEmbed: true)], size: 2_048)
    private let author = BaseTestRecords.record("People/Frank Herbert.md", yaml: "born: 1920-10-08\nicon: user")
    private let cover = BaseTestRecords.record("Library/Books/cover.png")

    private func evaluate(_ sourceText: String, record: BaseFileRecord? = nil, this thisRecord: BaseFileRecord? = nil,
                          formulas: [BaseFormula] = [], declaredTypes: [String: PropertyType] = [:]) throws -> BaseValue {
        let evaluator = BaseEvaluator(formulas: formulas, environment: BaseTestRecords.environment(declaredTypes: declaredTypes), thisRecord: thisRecord,
                                      knownRecords: [book, author, cover])
        return try evaluator.evaluate(sourceText: sourceText, for: record ?? book)
    }

    private func text(_ sourceText: String, record: BaseFileRecord? = nil) throws -> String {
        try evaluate(sourceText, record: record).displayText
    }

    // MARK: Operators

    func testArithmeticPrecedenceAndParentheses() throws {
        XCTAssertEqual(try evaluate("1 + 2 * 3"), .number(7))
        XCTAssertEqual(try evaluate("(1 + 2) * 3"), .number(9))
        XCTAssertEqual(try evaluate("10 % 4"), .number(2))
        XCTAssertEqual(try evaluate("-2 + 5"), .number(3))
        XCTAssertEqual(try evaluate("7 / 2"), .number(3.5))
        XCTAssertEqual(try evaluate("2 - 3 - 4"), .number(-5), "Subtraction is left-associative.")
        XCTAssertEqual(try evaluate("price * quantity"), .number(28.5))
        XCTAssertEqual(try evaluate("(price / quantity).toFixed(2)"), .string("3.17"))
    }

    func testComparisonAndBooleanOperators() throws {
        XCTAssertEqual(try evaluate("3 > 2 && !(1 == 2)"), .boolean(true))
        XCTAssertEqual(try evaluate("pages >= 412 || false"), .boolean(true))
        XCTAssertEqual(try evaluate("status != \"done\""), .boolean(true))
        XCTAssertEqual(try evaluate("\"b\" > \"a\""), .boolean(true))
        XCTAssertEqual(try evaluate("missing > 3"), .boolean(false), "Empty values never order against numbers.")
        XCTAssertEqual(try evaluate("missing == missing"), .boolean(true))
        XCTAssertEqual(try evaluate("1 === 1 && 1 !== 2"), .boolean(true), "JavaScript's strict operators are accepted.")
        XCTAssertEqual(try evaluate("done"), .boolean(false))
        XCTAssertEqual(try evaluate("!done"), .boolean(true))
    }

    func testTextConcatenationAndFormattingLikeTheDocumentation() throws {
        XCTAssertEqual(try evaluate("(pages * 2).toString() + \" min\""), .string("824 min"))
        XCTAssertEqual(try evaluate("if(price, price.toFixed(2) + \" dollars\")"), .string("9.50 dollars"))
        XCTAssertEqual(try evaluate("if(missing, missing.toFixed(2) + \" dollars\")"), .null, "A missing alternative is empty.")
        XCTAssertEqual(try evaluate("\"Pages: \" + pages"), .string("Pages: 412"))
        XCTAssertEqual(try evaluate("if(done, \"✅\", \"⏳\")"), .string("⏳"))
        XCTAssertEqual(try evaluate("if(status == \"reading\", \"📖\", if(status == \"done\", \"✅\", \"📚\"))"), .string("📖"))
    }

    // MARK: Properties

    func testPropertyReferencesInEverySpelling() throws {
        XCTAssertEqual(try evaluate("status"), .string("reading"))
        XCTAssertEqual(try evaluate("note.status"), .string("reading"))
        XCTAssertEqual(try evaluate("note[\"status\"]"), .string("reading"))
        XCTAssertEqual(try evaluate("Status"), .string("reading"), "Property names are case-insensitive.")
        XCTAssertEqual(try evaluate("missing"), .null)
        XCTAssertEqual(try evaluate("scores[0]"), .number(3))
        XCTAssertEqual(try evaluate("scores[9]"), .null)
        XCTAssertEqual(try evaluate("file.properties.pages"), .number(412))
        XCTAssertEqual(try evaluate("note.pages"), .number(412))
        guard case .link(let authorLink) = try evaluate("author") else { return XCTFail("Wikilinks in properties are links.") }
        XCTAssertEqual(authorLink.target, "Frank Herbert")
        guard case .date(let dueDate) = try evaluate("due") else { return XCTFail("YAML dates are dates.") }
        XCTAssertFalse(dueDate.hasTime)
    }

    func testFileProperties() throws {
        XCTAssertEqual(try evaluate("file.name"), .string("Dune.md"))
        XCTAssertEqual(try evaluate("file.basename"), .string("Dune"))
        XCTAssertEqual(try evaluate("file.path"), .string("Library/Books/Dune.md"))
        XCTAssertEqual(try evaluate("file.folder"), .string("Library/Books"))
        XCTAssertEqual(try evaluate("file.ext"), .string("md"))
        XCTAssertEqual(try evaluate("file.size"), .number(2_048))
        XCTAssertEqual(try evaluate("(file.size / 5).round(0)"), .number(410))
        XCTAssertEqual(try evaluate("file.tags"), .list([.string("#book"), .string("#scifi/classic")]))
        XCTAssertEqual(try evaluate("file.mtime.year"), .number(2025))
        XCTAssertEqual(try evaluate("file.links.length"), .number(4), "One body link and three links in properties.")
        XCTAssertEqual(try evaluate("file.embeds.length"), .number(1))
        XCTAssertEqual(try evaluate("file.folder", record: BaseTestRecords.record("Root.md")), .string("/"))
    }

    func testDeclaredTypesDecideHowValuesAreRead() throws {
        let record = BaseTestRecords.record("Note.md", yaml: "code: 007\ncount: \"42\"\nlabels: one\nwhen: 2025-01-02T10:15")
        XCTAssertEqual(try evaluate("code", record: record), .number(7))
        XCTAssertEqual(try evaluate("code", record: record, declaredTypes: ["code": .text]), .string("007"))
        XCTAssertEqual(try evaluate("count + 1", record: record, declaredTypes: ["count": .number]), .number(43))
        XCTAssertEqual(try evaluate("labels", record: record, declaredTypes: ["labels": .multitext]), .list([.string("one")]))
        XCTAssertEqual(try evaluate("when.hour", record: record), .number(10))
    }

    // MARK: Formulas

    func testFormulasReferenceEachOtherAndReportCycles() throws {
        let formulas = [BaseFormula(name: "total", sourceText: "price * quantity"), BaseFormula(name: "label", sourceText: "formula.total.toFixed(1) + \" total\""),
                        BaseFormula(name: "loop", sourceText: "formula.loop + 1"), BaseFormula(name: "broken", sourceText: "price *")]
        XCTAssertEqual(try evaluate("formula.label", formulas: formulas), .string("28.5 total"))
        XCTAssertEqual(try evaluate("formula[\"total\"]", formulas: formulas), .number(28.5))
        XCTAssertThrowsError(try evaluate("formula.loop", formulas: formulas)) { error in
            XCTAssertTrue(error.localizedDescription.contains("refers to itself"), error.localizedDescription)
        }
        XCTAssertThrowsError(try evaluate("formula.broken", formulas: formulas)) { error in
            XCTAssertTrue(error.localizedDescription.contains("broken"), error.localizedDescription)
        }
        XCTAssertThrowsError(try evaluate("formula.nothing", formulas: formulas)) { error in
            XCTAssertTrue(error.localizedDescription.contains("no formula named “nothing”"), error.localizedDescription)
        }
    }

    // MARK: Dates and durations

    func testDateArithmeticFromTheDocumentation() throws {
        XCTAssertEqual(try text("(date(\"2024-12-01\") + \"1M\" + \"4h\" + \"3m\").format(\"YYYY-MM-DD HH:mm:ss\")"), "2025-01-01 04:03:00")
        XCTAssertEqual(try evaluate("(date(\"2024-03-10\") - date(\"2024-03-01\")).days"), .number(9))
        XCTAssertEqual(try text("(today() + \"7d\").format(\"YYYY-MM-DD\")"), "2025-09-23")
        XCTAssertEqual(try text("(now() + \"1 day\").format(\"YYYY-MM-DD HH:mm\")"), "2025-09-17 10:30")
        XCTAssertEqual(try text("(date(\"2025-01-31\") + \"1 month\").format(\"YYYY-MM-DD\")"), "2025-03-03", "February 31 overflows into March, as in Obsidian.")
        XCTAssertEqual(try text("(today() - \"2 weeks\").format(\"YYYY-MM-DD\")"), "2025-09-02")
        XCTAssertEqual(try evaluate("file.mtime > now() - \"1 week\""), .boolean(true))
        XCTAssertEqual(try evaluate("(date(due) - today()).days"), .number(4))
        XCTAssertEqual(try evaluate("due > today()"), .boolean(true))
        XCTAssertEqual(try evaluate("due == date(\"2025-09-20\")"), .boolean(true))
        XCTAssertEqual(try evaluate("(now() - today()).hours"), .number(10.5))
        XCTAssertEqual(try text("(now() + (duration('1d') * 2)).format(\"YYYY-MM-DD\")"), "2025-09-18")
        XCTAssertEqual(try evaluate("duration(\"2h\").minutes"), .number(120))
        XCTAssertEqual(try evaluate("duration(\"P1DT2H\").hours"), .number(26))
        XCTAssertEqual(try evaluate("duration(\"1d 12h\").days"), .number(1.5))
    }

    func testDateFieldsFormattingAndRelativeTime() throws {
        XCTAssertEqual(try text("date(\"2025-05-27\").format(\"YYYY-MM-DD\")"), "2025-05-27")
        XCTAssertEqual(try text("date(\"2025-05-27\").format(\"dddd, MMMM Do YYYY\")"), "Tuesday, May 27th 2025")
        XCTAssertEqual(try text("date(\"2025-05-03 07:05:09\").format(\"ddd D MMM YY, h:mm:ss A [at] H[h]\")"), "Sat 3 May 25, 7:05:09 AM at 7h")
        XCTAssertEqual(try text("date(\"2025-12-31 23:59:59\").time()"), "23:59:59")
        XCTAssertEqual(try text("date(\"2025-12-31 23:59:59\").date().format(\"YYYY-MM-DD HH:mm:ss\")"), "2025-12-31 00:00:00")
        XCTAssertEqual(try evaluate("date(\"2025-12-31 23:59:59\").month"), .number(12))
        XCTAssertEqual(try evaluate("date(\"2025-12-31 23:59:59\").minute"), .number(59))
        XCTAssertEqual(try evaluate("now().hour"), .number(10))
        XCTAssertEqual(try text("(now() - \"3 days\").relative()"), "3 days ago")
        XCTAssertEqual(try text("(now() + \"2h\").relative()"), "in 2 hours")
        XCTAssertEqual(try text("(now() - \"20s\").relative()"), "a few seconds ago")
        XCTAssertEqual(try text("date(\"2025-01-02\")"), "2025-01-02")
        XCTAssertEqual(try evaluate("today().isEmpty()"), .boolean(false))
        XCTAssertEqual(try text("date(\"2025-06-15T08:00:00Z\").format(\"YYYY\")"), "2025")
    }

    /// Regression: names came from the device language while ordinals and AM/PM stayed
    /// English, giving "Dienstag, 27 Mai 27th 2025 12 AM" on a German iPad.
    func testFormattedDatesAreEnglishInEveryWord() throws {
        var germanCalendar = BaseDateFormatting.displayCalendar
        germanCalendar.locale = Locale(identifier: "de_DE")
        let germanEvaluator = BaseEvaluator(formulas: [], environment: BaseEvaluationEnvironment(now: BaseTestRecords.fixedNow, calendar: germanCalendar),
                                            thisRecord: nil, knownRecords: [book])
        XCTAssertEqual(try germanEvaluator.evaluate(sourceText: "date(\"2025-05-27\").format(\"dddd MMMM\")", for: book).displayText, "Tuesday May")
        XCTAssertEqual(try text("date(\"2025-05-27\").format(\"dddd, D MMMM Do YYYY h A\")"), "Tuesday, 27 May 27th 2025 12 AM")
        XCTAssertEqual(try text("date(\"2025-05-27\").format(\"ddd dd MMM\")"), "Tue Tu May")
    }

    // MARK: Functions and methods

    func testStringFunctions() throws {
        XCTAssertEqual(try evaluate("\"hello\".contains(\"ell\")"), .boolean(true))
        XCTAssertEqual(try evaluate("\"hello\".containsAll(\"h\", \"e\")"), .boolean(true))
        XCTAssertEqual(try evaluate("\"hello\".containsAny(\"x\", \"y\", \"e\")"), .boolean(true))
        XCTAssertEqual(try evaluate("\"hello\".startsWith(\"he\") && \"hello\".endsWith(\"lo\")"), .boolean(true))
        XCTAssertEqual(try evaluate("\"\".isEmpty() && !\"Hello world\".isEmpty()"), .boolean(true))
        XCTAssertEqual(try evaluate("\"hello\".length"), .number(5))
        XCTAssertEqual(try evaluate("\"Hello\".lower() + \"Hello\".upper()"), .string("helloHELLO"))
        XCTAssertEqual(try evaluate("\"hello world\".title()"), .string("Hello World"))
        XCTAssertEqual(try evaluate("\" hi \".trim()"), .string("hi"))
        XCTAssertEqual(try evaluate("\"a:b:c:d\".replace(\":\", \"-\")"), .string("a-b:c:d"))
        XCTAssertEqual(try evaluate("\"a:b:c:d\".replace(/:/, \"-\")"), .string("a-b:c:d"))
        XCTAssertEqual(try evaluate("\"a:b:c:d\".replace(/:/g, \"-\")"), .string("a-b-c-d"))
        XCTAssertEqual(try evaluate("\"John Smith\".replace(/(\\w+) (\\w+)/, \"$2, $1\")"), .string("Smith, John"))
        XCTAssertEqual(try evaluate("\"a,b,c,d\".split(\",\", 3)"), .list([.string("a"), .string("b"), .string("c")]))
        XCTAssertEqual(try evaluate("\"a1b22c\".split(/[0-9]+/)"), .list([.string("a"), .string("b"), .string("c")]))
        XCTAssertEqual(try evaluate("\"hello\".slice(1, 4)"), .string("ell"))
        XCTAssertEqual(try evaluate("\"hello\".slice(-3)"), .string("llo"))
        XCTAssertEqual(try evaluate("\"123\".repeat(2)"), .string("123123"))
        XCTAssertEqual(try evaluate("\"hello\".reverse()"), .string("olleh"))
        XCTAssertEqual(try evaluate("title.lower().contains(\"dune\")"), .boolean(true))
    }

    func testNumberFunctions() throws {
        XCTAssertEqual(try evaluate("(-5).abs()"), .number(5))
        XCTAssertEqual(try evaluate("(2.1).ceil()"), .number(3))
        XCTAssertEqual(try evaluate("(2.9).floor()"), .number(2))
        XCTAssertEqual(try evaluate("(2.5).round()"), .number(3))
        XCTAssertEqual(try evaluate("(2.3333).round(2)"), .number(2.33))
        XCTAssertEqual(try evaluate("(3.14159).toFixed(2)"), .string("3.14"))
        XCTAssertEqual(try evaluate("5.isEmpty()"), .boolean(false))
        XCTAssertEqual(try evaluate("123.toString()"), .string("123"))
        XCTAssertEqual(try evaluate("number(\"3.4\")"), .number(3.4))
        XCTAssertEqual(try evaluate("number(true) + number(false)"), .number(1))
        XCTAssertEqual(try evaluate("min(3, 1, 2) + max(3, 1, 2)"), .number(4))
        XCTAssertEqual(try evaluate("max(scores)"), .number(3))
    }

    func testListFunctions() throws {
        XCTAssertEqual(try evaluate("[1,2,3].contains(2)"), .boolean(true))
        XCTAssertEqual(try evaluate("[1,2,3].containsAll(2,3)"), .boolean(true))
        XCTAssertEqual(try evaluate("[1,2,3].containsAny(3,4)"), .boolean(true))
        XCTAssertEqual(try evaluate("[1,2,3].containsAny(4,5)"), .boolean(false))
        XCTAssertEqual(try evaluate("[1,2,3].isEmpty() || [].isEmpty()"), .boolean(true))
        XCTAssertEqual(try evaluate("[1,2,3].length"), .number(3))
        XCTAssertEqual(try evaluate("[1,2,3].join(\",\")"), .string("1,2,3"))
        XCTAssertEqual(try evaluate("[3, 1, 2].sort()"), .list([.number(1), .number(2), .number(3)]))
        XCTAssertEqual(try evaluate("[\"c\", \"a\", \"b\"].sort()"), .list([.string("a"), .string("b"), .string("c")]))
        XCTAssertEqual(try evaluate("[1,2,2,3].unique()"), .list([.number(1), .number(2), .number(3)]))
        XCTAssertEqual(try evaluate("[1,[2,3]].flat()"), .list([.number(1), .number(2), .number(3)]))
        XCTAssertEqual(try evaluate("[1,2,3,4].filter(value > 2)"), .list([.number(3), .number(4)]))
        XCTAssertEqual(try evaluate("[1,2,3,4].map(value + 1)"), .list([.number(2), .number(3), .number(4), .number(5)]))
        XCTAssertEqual(try evaluate("[5,6,7].map(index)"), .list([.number(0), .number(1), .number(2)]))
        XCTAssertEqual(try evaluate("[1,2,3].reduce(acc + value, 0)"), .number(6))
        XCTAssertEqual(try evaluate("[1,2,3].reverse()"), .list([.number(3), .number(2), .number(1)]))
        XCTAssertEqual(try evaluate("[1,2,3,4].slice(1,3)"), .list([.number(2), .number(3)]))
        XCTAssertEqual(try evaluate("[1,2,3,4].mean()"), .number(2.5))
        XCTAssertEqual(try evaluate("list(\"value\")"), .list([.string("value")]))
        XCTAssertEqual(try evaluate("list(missing)[0]"), .null)
        XCTAssertEqual(try evaluate("tags.contains(\"book\")"), .boolean(true))
        XCTAssertEqual(try evaluate("scores.filter(value >= 2).length"), .number(2), "Lambda variables shadow properties.")
    }

    func testAnyTypeFunctions() throws {
        XCTAssertEqual(try evaluate("1.isTruthy() && !0.isTruthy()"), .boolean(true))
        XCTAssertEqual(try evaluate("\"example\".isType(\"string\") && true.isType(\"boolean\") && today().isType(\"date\")"), .boolean(true))
        XCTAssertEqual(try evaluate("missing.isEmpty()"), .boolean(true))
        XCTAssertEqual(try evaluate("missing.lower()"), .null, "Methods on empty values stay empty instead of failing.")
        XCTAssertEqual(try evaluate("{}.isEmpty()"), .boolean(true))
        XCTAssertEqual(try evaluate("file.properties.keys().contains(\"title\")"), .boolean(true))
        XCTAssertEqual(try evaluate("/abc/.matches(\"abcde\")"), .boolean(true))
        XCTAssertEqual(try evaluate("/^\\d{4}$/.matches(file.basename)"), .boolean(false))
        XCTAssertEqual(try evaluate("escapeHTML(\"<b>\")"), .string("&lt;b&gt;"))
    }

    // MARK: Files and links

    func testFileFunctions() throws {
        XCTAssertEqual(try evaluate("file.hasTag(\"book\")"), .boolean(true))
        XCTAssertEqual(try evaluate("file.hasTag(\"scifi\")"), .boolean(true), "Nested tags match their parent.")
        XCTAssertEqual(try evaluate("file.hasTag(\"#SCIFI/classic\")"), .boolean(true))
        XCTAssertEqual(try evaluate("file.hasTag(\"sci\")"), .boolean(false))
        XCTAssertEqual(try evaluate("file.hasTag(\"x\", \"book\")"), .boolean(true))
        XCTAssertEqual(try evaluate("file.hasProperty(\"pages\") && !file.hasProperty(\"isbn\")"), .boolean(true))
        XCTAssertEqual(try evaluate("file.inFolder(\"Library\") && file.inFolder(\"Library/Books\")"), .boolean(true))
        XCTAssertEqual(try evaluate("file.inFolder(\"Lib\")"), .boolean(false))
        XCTAssertEqual(try evaluate("file.hasLink(\"Frank Herbert\")"), .boolean(true))
        XCTAssertEqual(try evaluate("file.hasLink(file(\"People/Frank Herbert.md\"))"), .boolean(true))
        XCTAssertEqual(try evaluate("file.hasLink(\"Books\")"), .boolean(true), "Links in properties count.")
        XCTAssertEqual(try evaluate("file.hasLink(\"Nobody\")"), .boolean(false))
        XCTAssertEqual(try evaluate("file.hasLink(this.file)", this: author), .boolean(true))
        XCTAssertEqual(try evaluate("file.asLink().asFile() == file"), .boolean(true))
        XCTAssertEqual(try evaluate("author.asFile().properties.icon"), .string("user"))
        XCTAssertEqual(try evaluate("author.asFile().born.year"), .number(1920))
        XCTAssertEqual(try evaluate("author == this", this: author), .boolean(true))
        XCTAssertEqual(try evaluate("author.linksTo(file)"), .boolean(false))
        XCTAssertEqual(try evaluate("categories.containsAny(link(\"Books\"))"), .boolean(true))
        XCTAssertEqual(try evaluate("categories.contains(\"[[Classics]]\")"), .boolean(true))
        XCTAssertEqual(try evaluate("list(author).contains(this)", this: author), .boolean(true))
        XCTAssertEqual(try evaluate("file(\"missing.md\")"), .null)
        XCTAssertEqual(try evaluate("link(\"Books\", \"Library\")").displayText, "Library")
    }

    func testThisRefersToTheEmbeddingNote() throws {
        XCTAssertEqual(try evaluate("this.file.name", this: author), .string("Frank Herbert.md"))
        XCTAssertEqual(try evaluate("this.icon", this: author), .string("user"))
        XCTAssertEqual(try evaluate("this.note.icon", this: author), .string("user"))
        XCTAssertEqual(try evaluate("this[\"icon\"]", this: author), .string("user"))
        XCTAssertEqual(try evaluate("this"), .null, "Without a context note, this is empty.")
    }

    // MARK: Errors

    func testSyntaxErrorsAreReported() {
        for sourceText in ["\"unterminated", "1 +", "(1 + 2", "price * * 2", "", "a..b", "#", "[1, 2"] {
            XCTAssertThrowsError(try BaseExpression.parse(sourceText), sourceText) { error in
                guard case .syntax = error as? BaseExpressionError else { return XCTFail("\(sourceText): \(error)") }
            }
        }
    }

    func testEvaluationErrorsAreReportedNotCrashes() {
        for sourceText in ["unknown()", "pages.lower()", "1 / 0", "5 % 0", "date(\"not a date\")", "duration(\"soon\")",
                           "[1, 2] - 3", "formula", "\"a\".repeat(-1)", "html(\"<b>\")", "status.nothing", "(2).round"] {
            XCTAssertThrowsError(try evaluate(sourceText), sourceText) { error in
                XCTAssertFalse(error.localizedDescription.isEmpty)
            }
        }
    }

    func testDeeplyNestedExpressionsFailSafely() {
        let deeplyNested = String(repeating: "(", count: 500) + "1" + String(repeating: ")", count: 500)
        XCTAssertThrowsError(try BaseExpression.parse(deeplyNested))
        XCTAssertThrowsError(try BaseExpression.parse(String(repeating: "!", count: 500) + "true"))
    }

    func testTokenizerDistinguishesDivisionFromRegularExpressions() throws {
        XCTAssertEqual(try evaluate("pages / 4 / 1"), .number(103))
        XCTAssertEqual(try evaluate("[/a/, /b/].length"), .number(2))
        XCTAssertEqual(try evaluate("'single' + \"double\""), .string("singledouble"))
        XCTAssertEqual(try evaluate("\"tab\\tquote\\\"\""), .string("tab\tquote\""))
    }
}

import XCTest
@testable import MermaidDiagrams

/// The inputs of Mermaid 12.1.0's pie specs (`pie.spec.ts` and the parser's `pie.test.ts`, ported to Pele's
/// `tests/compat/pie`), Mermaid's documentation example, and the errors.
final class PieChartParserTests: XCTestCase {
    private func pieChart(_ source: String) throws -> PieChart {
        try PieChartReading.pieChart(source)
    }

    private func slices(_ source: String) throws -> [String: Double] {
        Dictionary(uniqueKeysWithValues: try pieChart(source).slices.map { slice in (slice.label.spokenText, slice.value) })
    }

    // MARK: Mermaid's specs

    func testTheKeywordReadsWithAnySpacesAroundIt() throws {
        for source in ["pie", "  pie  ", "\tpie\t", "\n    \tpie\n    "] {
            XCTAssertEqual(try pieChart(source), PieChart(), source)
        }
    }

    func testShowDataOnTheKeywordsLineShowsTheValues() throws {
        for source in ["pie showData", "  pie  showData  ", "\tpie\tshowData\t", "\n    pie\tshowData\n    "] {
            XCTAssertTrue(try pieChart(source).showsValues, source)
        }
        XCTAssertFalse(try pieChart("pie\n\"ash\" : 1").showsValues)
    }

    func testTheTitleReadsOnTheKeywordsLineOrItsOwn() throws {
        for source in ["pie title sample title", "  pie  title sample title  ", "\tpie\ttitle sample title\t", "pie\n        \ttitle sample title\n        ",
                       "pie\n        title sample title", "pie showData title sample title", "pie showData\n        title sample title\n        "] {
            XCTAssertEqual(try pieChart(source).title, "sample title", source)
        }
    }

    func testSlicesReadWithAnySpacesAroundTheColon() throws {
        for source in ["pie\n        \"GitHub\":100\n        \"GitLab\":50", "pie\n        \"GitHub\"   :   100\n        \"GitLab\"   :   50",
                       "pie\n        \"GitHub\"\t:\t100\n        \"GitLab\"\t:\t50",
                       "pie\n        \t\"GitHub\" \t : \t 100\n        \t\"GitLab\" \t : \t  50\n        "] {
            let chart = try pieChart(source)
            XCTAssertEqual(chart.slices, [PieChartSlice(label: DiagramLabel("GitHub"), value: 100), PieChartSlice(label: DiagramLabel("GitLab"), value: 50)])
        }
    }

    func testSlicesFollowTheShowDataAndTheTitle() throws {
        let chart = try pieChart("pie showData\n        \"GitHub\": 100\n        \"GitLab\": 50")
        XCTAssertTrue(chart.showsValues)
        XCTAssertEqual(chart.slices.count, 2)
        let titled = try pieChart("pie title a 60/40 pie\n      \"ash\" : 60\n      \"bat\" : 40\n      ")
        XCTAssertEqual(titled.title, "a 60/40 pie")
        XCTAssertEqual(try slices("pie title a 60/40 pie\n \"ash\" : 60\n \"bat\" : 40"), ["ash": 60, "bat": 40])
    }

    func testCommentsAreLeft() throws {
        XCTAssertEqual(try slices("pie\n      %% comments\n      \"ash\" : 60\n      \"bat\" : 40\n      "), ["ash": 60, "bat": 40])
    }

    func testAccessibilityTitleAndDescriptionRead() throws {
        let titled = try pieChart("pie title a neat chart\n      accTitle: a neat acc title\n      \"ash\" : 60\n      \"bat\" : 40\n      ")
        XCTAssertEqual(titled.title, "a neat chart")
        XCTAssertEqual(titled.accessibilityTitle, "a neat acc title")
        let described = try pieChart("pie title a neat chart\n      accDescr: a neat description\n      \"ash\" : 60\n      \"bat\" : 40\n      ")
        XCTAssertEqual(described.accessibilityDescription, "a neat description")
        let onTheKeywordsLine = try pieChart("pie accTitle: sample wow\n        \"GitHub\": 100\n        \"GitLab\": 50")
        XCTAssertEqual(onTheKeywordsLine.accessibilityTitle, "sample wow")
        XCTAssertEqual(try pieChart("pie accDescr: sample wow\n        \"GitHub\": 100").accessibilityDescription, "sample wow")
    }

    func testAMultilineDescriptionKeepsItsLinesTrimmed() throws {
        let chart = try pieChart("pie title a neat chart\n      accDescr {\n        a neat description\n        on multiple lines\n      }\n"
                                 + "      \"ash\" : 60\n    ")
        XCTAssertEqual(chart.accessibilityDescription, "a neat description\non multiple lines")
        XCTAssertEqual(chart.slices.count, 1)
        XCTAssertEqual(try pieChart("pie accDescr {\n            sample wow\n        }\n        \"GitHub\": 100").accessibilityDescription, "sample wow")
    }

    func testDecimalsAndZeroAreValues() throws {
        XCTAssertEqual(try slices("pie\n      \"ash\" : 60.67\n      \"bat\" : 40\n      "), ["ash": 60.67, "bat": 40])
        let chart = try pieChart("""
        pie title Default text position: Animal adoption
                accTitle: simple pie char demo
                accDescr: pie chart with 3 sections: dogs, cats, rats. Most are dogs.
                 "dogs" : 0
                "rats" : 40.12
        """)
        XCTAssertEqual(chart.title, "Default text position: Animal adoption")
        XCTAssertEqual(chart.accessibilityDescription, "pie chart with 3 sections: dogs, cats, rats. Most are dogs.")
        XCTAssertEqual(chart.slices.map(\.value), [0, 40.12])
    }

    func testANegativeValueIsRefusedWithItsLabel() {
        XCTAssertEqual(PieChartReading.readError("pie\n        \"ash\" : -60.67\n        \"bat\" : 40.12\n        "),
                       .invalidSyntax(line: 2, problem: .negativeSliceValue(label: "ash")))
        XCTAssertEqual(PieChartReading.readError("pie title Animal adoption\n \"dogs\" : -60.67\n \"rats\" : 40.12"),
                       .invalidSyntax(line: 2, problem: .negativeSliceValue(label: "dogs")))
    }

    func testLabelsThatNameScriptPropertiesAreOrdinaryLabels() throws {
        let chart = try pieChart("pie title Unsafe props test\n        \"__proto__\" : 386\n        \"constructor\" : 85\n        \"prototype\" : 15")
        XCTAssertEqual(chart.slices.map(\.label.spokenText), ["__proto__", "constructor", "prototype"])
    }

    func testMermaidsDocumentationExampleReads() throws {
        let chart = try pieChart("pie title Pets adopted by volunteers\n    \"Dogs\" : 386\n    \"Cats\" : 85\n    \"Rats\" : 15\n")
        XCTAssertEqual(chart.title, "Pets adopted by volunteers")
        XCTAssertEqual(chart.slices.map(\.label.spokenText), ["Dogs", "Cats", "Rats"])
        XCTAssertEqual(chart.slices.map(\.value), [386, 85, 15])
    }

    func testMermaidsDocumentationExampleWithItsConfigurationReads() throws {
        let chart = try pieChart("""
        ---
        config:
          pie:
            textPosition: 0.5
            donutHole: 0.2
            highlightSlice: Potassium
          themeVariables:
            pieOuterStrokeWidth: "5px"
        ---
        pie showData
            title Key elements in Product X
            "Calcium" : 42.96
            "Potassium" : 50.05
            "Magnesium" : 10.01
            "Iron" :  5

        """)
        XCTAssertTrue(chart.showsValues)
        XCTAssertEqual(chart.title, "Key elements in Product X")
        XCTAssertEqual(chart.slices.map(\.value), [42.96, 50.05, 10.01, 5])
    }

    func testTheFrontMattersTitleIsTheChartsUnlessItHasItsOwn() throws {
        XCTAssertEqual(try pieChart("---\ntitle: From front matter\n---\npie\n \"A\" : 1").title, "From front matter")
        XCTAssertEqual(try pieChart("---\ntitle: From front matter\n---\npie title Own\n \"A\" : 1").title, "Own")
    }

    // MARK: Graphite's cases

    func testALabelUsedAgainKeepsItsFirstSlice() throws {
        let chart = try pieChart("pie showData\n \"A\" : 1\n \"A\" : 2\n \"B\" : 3")
        XCTAssertEqual(chart.slices.map(\.value), [1, 3])
    }

    func testLabelsTakeApostrophesEscapesAndLineBreakTags() throws {
        let chart = try pieChart("pie\n 'It\\'s' : 1\n \"Say \\\"hi\\\"\" : 2\n \"Dogs<br>and cats\" : 3\n \"&lt;none&gt;\" : 4")
        XCTAssertEqual(chart.slices.map(\.label.lines), [["It's"], ["Say \"hi\""], ["Dogs", "and cats"], ["<none>"]])
    }

    func testCommentsAndDirectivesMayFollowAStatement() throws {
        let chart = try pieChart("pie showData %% values\n title Pets %% a comment\n %%{init: {\"pie\": {\"textPosition\": 0.5}}}%%\n \"Dogs\" : 3 %% most")
        XCTAssertTrue(chart.showsValues)
        XCTAssertEqual(chart.title, "Pets")
        XCTAssertEqual(chart.slices.count, 1)
    }

    func testAnEmptyTitleIsNoTitle() throws {
        XCTAssertNil(try pieChart("pie\ntitle\n\"a\" : 1").title)
    }

    func testASliceWithoutAColonAndANumberIsReportedOnItsLine() {
        XCTAssertEqual(PieChartReading.readError("pie\n\"a\" 1"), .invalidSyntax(line: 2, problem: .expectedSliceValue))
        XCTAssertEqual(PieChartReading.readError("pie\n\"a\" :\n1"), .invalidSyntax(line: 2, problem: .expectedSliceValue))
        for value in ["1.", "007", "1.2.3", ".5", "ten"] {
            XCTAssertEqual(PieChartReading.readError("pie\n\"a\" : \(value)"), .invalidSyntax(line: 2, problem: .expectedSliceValue), value)
        }
    }

    func testTextAfterAStatementOrOutsideOneIsUnexpected() {
        XCTAssertEqual(PieChartReading.readError("pie\n\"a\" : 1 more"), .invalidSyntax(line: 2, problem: .unexpectedText("more")))
        XCTAssertEqual(PieChartReading.readError("pie\nshowData"), .invalidSyntax(line: 2, problem: .unexpectedText("showData")))
        XCTAssertEqual(PieChartReading.readError("pie\nslice : 1"), .invalidSyntax(line: 2, problem: .unexpectedText("slice : 1")))
        XCTAssertEqual(PieChartReading.readError("pie\naccTitle missing colon"), .invalidSyntax(line: 2, problem: .unexpectedText("accTitle missing colon")))
    }

    func testATitleRunsToTheEndOfItsLine() throws {
        XCTAssertEqual(try pieChart("pie title A; \"a\" : 1").title, "A; \"a\" : 1")
    }

    func testUnclosedQuotationAndDescriptionAreReportedWhereTheyOpen() {
        XCTAssertEqual(PieChartReading.readError("pie\n\"a : 1\n\"b\" : 2"), .invalidSyntax(line: 3, problem: .expectedSliceValue))
        XCTAssertEqual(PieChartReading.readError("pie\n\"never closed : 1"), .invalidSyntax(line: 2, problem: .unclosedQuotation))
        XCTAssertEqual(PieChartReading.readError("pie\naccDescr {\nlost"), .invalidSyntax(line: 2, problem: .unclosedAccessibilityDescription))
    }

    func testSlicesPastTheNodeLimitAreRefused() {
        var limits = MermaidDiagramLimits.standard
        limits.maximumNodeCount = 2
        XCTAssertNil(PieChartReading.readError("pie\n\"a\" : 1\n\"b\" : 2\n\"a\" : 3", limits: limits), "A label used again adds no slice")
        XCTAssertEqual(PieChartReading.readError("pie\n\"a\" : 1\n\"b\" : 2\n\"c\" : 3", limits: limits), .tooManyNodes(limit: 2))
    }
}

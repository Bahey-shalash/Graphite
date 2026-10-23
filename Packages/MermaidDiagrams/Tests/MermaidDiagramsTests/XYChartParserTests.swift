import XCTest
@testable import MermaidDiagrams

/// The inputs of Mermaid 12.1.0's XY chart specs (`xychart.jison.spec.ts` and `xychartDb.spec.ts`, ported to Pele's
/// `tests/compat/xychart`), read as Mermaid's database holds them, and the errors.
final class XYChartParserTests: XCTestCase {
    private func chart(_ source: String) throws -> XYChart {
        try XYChartReading.chart(source)
    }

    private func throwsError(_ source: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertNotNil(XYChartReading.readError(source), source, file: file, line: line)
    }

    private func categories(_ chart: XYChart) -> [String] {
        guard case .categories(let categories) = chart.xAxis.scale else { return [] }
        return categories.map(XYChartReading.text)
    }

    // MARK: The keyword, the title and the orientation

    func testTheKeywordAloneIsAChartWithNothingInIt() throws {
        XCTAssertEqual(try chart("xychart"), XYChart())
        XCTAssertEqual(try chart("xychart-beta"), XYChart())
    }

    func testTheTitleReadsQuotedOrAsOneWord() throws {
        XCTAssertEqual(try chart("xychart \n title \"This is a title\"").title, "This is a title")
        XCTAssertEqual(try chart("xychart \n title oneLinertitle").title, "oneLinertitle")
    }

    func testTheOrientationFollowsTheKeyword() throws {
        XCTAssertEqual(try chart("xychart vertical").orientation, .vertical)
        XCTAssertEqual(try chart("xychart        horizontal        ").orientation, .horizontal)
        throwsError("xychart abc")
    }

    // MARK: The x axis

    func testTheXAxisTitleReadsWithOrWithoutQuotationMarksAndIsTrimmed() throws {
        for source in ["xychart \nx-axis xAxisName\n", "xychart \nx-axis        xAxisName     \n"] {
            XCTAssertEqual(XYChartReading.text(try chart(source).xAxis.title), "xAxisName", source)
        }
        XCTAssertEqual(XYChartReading.text(try chart("xychart \n    x-axis \"xAxisName has space\"\n").xAxis.title), "xAxisName has space")
        XCTAssertEqual(XYChartReading.text(try chart("xychart \n   x-axis    \"  xAxisName has space   \"         \n").xAxis.title),
                       "xAxisName has space")
    }

    func testTheXAxisRangeReadsWithOrWithoutATitle() throws {
        let titled = try chart("xychart \nx-axis xAxisName    45.5   -->   33   \n")
        XCTAssertEqual(XYChartReading.text(titled.xAxis.title), "xAxisName")
        XCTAssertEqual(titled.xAxis.scale, .range(start: 45.5, end: 33))
        XCTAssertEqual(try chart("xychart \nx-axis xAxisName    45.5   -->   .34   \n").xAxis.scale, .range(start: 45.5, end: 0.34))
        let untitled = try chart("xychart \nx-axis   45.5   -->   1.34   \n")
        XCTAssertTrue(untitled.xAxis.title.isEmpty)
        XCTAssertEqual(untitled.xAxis.scale, .range(start: 45.5, end: 1.34))
        throwsError("xychart \nx-axis xAxisName    aaa   -->   33   \n")
    }

    func testTheXAxisCategoriesReadQuotedOrAsWordsJoinedWithoutTheirSpaces() throws {
        let titled = try chart("xychart \nx-axis xAxisName    [  \"cat1\"  ,   cat2a  ]   \n   ")
        XCTAssertEqual(XYChartReading.text(titled.xAxis.title), "xAxisName")
        XCTAssertEqual(categories(titled), ["cat1", "cat2a"])
        XCTAssertEqual(categories(try chart("xychart \nx-axis    [  \"cat1\"  ,   cat2a  ]   \n   ")), ["cat1", "cat2a"])
        let first = try chart("xychart \n x-axis \"this is x axis\" [category1, \"category 2\", category3]\n")
        XCTAssertEqual(XYChartReading.text(first.xAxis.title), "this is x axis")
        XCTAssertEqual(categories(first), ["category1", "category 2", "category3"])
        let second = try chart("xychart \nx-axis xAxisName    [  \"cat1  with space\"  ,   cat2 , cat3]   \n   ")
        XCTAssertEqual(categories(second), ["cat1 with space", "cat2", "cat3"], "Runs of spaces are drawn as one, as an SVG shows them")
        let third = try chart("xychart \nx-axis xAxisName    [  \"cat1  with space\"  ,   cat2 asdf , cat3]   \n   ")
        XCTAssertEqual(categories(third), ["cat1 with space", "cat2asdf", "cat3"])
    }

    func testUnbalancedCategoryBracketsAreErrors() {
        XCTAssertEqual(XYChartReading.readError("xychart \nx-axis xAxisName    [  \"cat1\"  [   cat2a  ]   \n   "),
                       .invalidSyntax(line: 2, problem: .expectedCategories))
        throwsError("xychart \nx-axis xAxisName    [  \"cat1\"  ,   cat2a ] ]   \n   ")
    }

    // MARK: The y axis

    func testTheYAxisTitleReadsWithOrWithoutQuotationMarksAndIsTrimmed() throws {
        for source in ["xychart \ny-axis yAxisName\n", "xychart \ny-axis        yAxisName     \n"] {
            XCTAssertEqual(XYChartReading.text(try chart(source).yAxis.title), "yAxisName", source)
        }
        XCTAssertEqual(XYChartReading.text(try chart("xychart \n    y-axis \"yAxisName has space\"\n").yAxis.title), "yAxisName has space")
        XCTAssertEqual(XYChartReading.text(try chart("xychart \n   y-axis    \"  yAxisName has space   \"         \n").yAxis.title),
                       "yAxisName has space")
        XCTAssertNil(try chart("xychart \ny-axis yAxisName\n").yAxis.range)
    }

    func testTheYAxisRangeReadsWithOrWithoutATitle() throws {
        let titled = try chart("xychart \ny-axis yAxisName    45.5   -->   33   \n")
        XCTAssertEqual(XYChartReading.text(titled.yAxis.title), "yAxisName")
        XCTAssertEqual(titled.yAxis.range, XYChartValueRange(start: 45.5, end: 33))
        XCTAssertEqual(try chart("xychart \ny-axis    45.5   -->   33   \n").yAxis.range, XYChartValueRange(start: 45.5, end: 33))
        XCTAssertEqual(try chart("xychart \ny-axis yAxisName    45.5   -->   .33   \n").yAxis.range, XYChartValueRange(start: 45.5, end: 0.33))
    }

    func testAYAxisRangeThatIsNotTwoNumbersIsAnError() {
        XCTAssertEqual(XYChartReading.readError("xychart \ny-axis yAxisName    45.5   -->   abc   \n"),
                       .invalidSyntax(line: 2, problem: .expectedAxisRange))
        throwsError("xychart \ny-axis yAxisName    [ 45.3,   33 ]   \n")
    }

    func testBothAxesReadTogether() throws {
        let both = try chart("xychart\nx-axis xAxisName\ny-axis yAxisName\n")
        XCTAssertEqual(XYChartReading.text(both.xAxis.title), "xAxisName")
        XCTAssertEqual(XYChartReading.text(both.yAxis.title), "yAxisName")
    }

    // MARK: Series

    func testALineReadsItsTitleAndValuesWithSigns() throws {
        let titled = try chart("xychart\nx-axis xAxisName\ny-axis yAxisName\n line lineTitle [23, 45, 56.6]")
        XCTAssertEqual(titled.series, [XYChartSeries(kind: .line, title: DiagramLabel("lineTitle"), values: [23, 45, 56.6])])
        let signed = try chart("xychart\nx-axis xAxisName\ny-axis yAxisName\n line \"lineTitle with space\"   [  +23 , -45  , 56.6 ]   ")
        XCTAssertEqual(XYChartReading.text(signed.series[0].title), "lineTitle with space")
        XCTAssertEqual(signed.series[0].values, [23, -45, 56.6])
        let untitled = try chart("xychart\nx-axis xAxisName\ny-axis yAxisName\n line [  +23 , -45  , 56.6 , .33]   ")
        XCTAssertTrue(untitled.series[0].title.isEmpty)
        XCTAssertEqual(untitled.series[0].values, [23, -45, 56.6, 0.33])
    }

    func testABarReadsItsTitleAndValuesWithSigns() throws {
        let titled = try chart("xychart\nx-axis xAxisName\ny-axis yAxisName\n bar barTitle [23, 45, 56.6, .22]")
        XCTAssertEqual(titled.series, [XYChartSeries(kind: .bar, title: DiagramLabel("barTitle"), values: [23, 45, 56.6, 0.22])])
        let signed = try chart("xychart\nx-axis xAxisName\ny-axis yAxisName\n bar \"barTitle with space\"   [  +23 , -45  , 56.6 ]   ")
        XCTAssertEqual(signed.series[0].values, [23, -45, 56.6])
        XCTAssertTrue(try chart("xychart\nx-axis xAxisName\ny-axis yAxisName\n bar   [  +23 , -45  , 56.6 ]   ").series[0].title.isEmpty)
    }

    func testSeriesValuesThatAreNotNumbersInBracketsAreErrors() {
        for keyword in ["line", "bar"] {
            let start = "xychart\nx-axis xAxisName\ny-axis yAxisName\n \(keyword) \"title with space\"   "
            let malformedValues = ["[  +23 [ -45  , 56.6 ]   ", "[  +23 , -45  ] 56.6 ]   ", "", "[ ] ", "[  +23 ,  , -45  , 56.6 ]   ",
                                   "[  +23 , -4aa5  , 56.6 ]   "]
            for values in malformedValues {
                throwsError(start + values)
            }
            XCTAssertEqual(XYChartReading.readError(start + "[ ] "), .invalidSyntax(line: 4, problem: .expectedSeriesValues), keyword)
        }
    }

    func testBarsAndLinesReadInTheirOrder() throws {
        let source = "xychart\nx-axis xAxisName\ny-axis yAxisName\n bar barTitle1 [23, 45, 56.6] \n line lineTitle1 [11, 45.5, 67, 23] \n"
            + " bar barTitle2 [13, 42, 56.89] \n line lineTitle2 [45, 99, 012]"
        let read = try chart(source)
        XCTAssertEqual(read.series.map(\.kind), [.bar, .line, .bar, .line])
        XCTAssertEqual(read.series.map { series in XYChartReading.text(series.title) }, ["barTitle1", "lineTitle1", "barTitle2", "lineTitle2"])
        XCTAssertEqual(read.series[3].values, [45, 99, 12], "012 is twelve")
    }

    func testAHorizontalChartWithEveryStatement() throws {
        let read = try chart("""

            xychart horizontal
            title "Basic xychart"
            x-axis "this is x axis" [category1, "category 2", category3]
            y-axis yaxisText 10 --> 150
         bar barTitle1 [23, 45, 56.6]
         line lineTitle1 [11, 45.5, 67, 23]
         bar barTitle2 [13, 42, 56.89]
            line lineTitle2 [45, 99, 012]
        """)
        XCTAssertEqual(read.orientation, .horizontal)
        XCTAssertEqual(read.title, "Basic xychart")
        XCTAssertEqual(read.yAxis.range, XYChartValueRange(start: 10, end: 150))
        XCTAssertEqual(XYChartReading.text(read.yAxis.title), "yaxisText")
        XCTAssertEqual(categories(read), ["category1", "category 2", "category3"])
        XCTAssertEqual(read.series[1].values, [11, 45.5, 67], "A value past the last category is left out")
    }

    // MARK: Point labels

    func testALinesPointsMayHaveLabels() throws {
        let start = "xychart\nx-axis xAxisName\ny-axis yAxisName\n "
        XCTAssertEqual(try chart(start + "line [10 \"First\", 20 \"Second\", 30 \"Third\"]").series[0].pointLabels.map(XYChartReading.text),
                       ["First", "Second", "Third"])
        let mixed = try chart(start + "line [10 \"Start\", 20, 30 \"End\"]").series[0]
        XCTAssertEqual(mixed.values, [10, 20, 30])
        XCTAssertEqual(mixed.pointLabels.map(XYChartReading.text), ["Start", "", "End"])
        XCTAssertEqual(try chart(start + "line [10 \"Hello World\", 20 \"Another Label\"]").series[0].pointLabels.map(XYChartReading.text),
                       ["Hello World", "Another Label"])
        let titled = try chart(start + "line \"My Line\" [10 \"A\", 20 \"B\"]").series[0]
        XCTAssertEqual(XYChartReading.text(titled.title), "My Line")
        XCTAssertEqual(titled.pointLabels.map(XYChartReading.text), ["A", "B"])
        let decimals = try chart(start + "line [3.8 \"Phi-3\", 7 \"Mistral\", 540 \"PaLM\"]").series[0]
        XCTAssertEqual(decimals.values, [3.8, 7, 540])
        XCTAssertTrue(try chart(start + "line [10, 20]").series[0].pointLabels.isEmpty)
    }

    func testABarsPointLabelsAreReadAndNotKept() throws {
        let bar = try chart("xychart\nx-axis xAxisName\ny-axis yAxisName\n bar [10 \"A\", 20 \"B\", 30 \"C\"]").series[0]
        XCTAssertEqual(bar.values, [10, 20, 30])
        XCTAssertTrue(bar.pointLabels.isEmpty)
    }

    // MARK: Accessibility

    func testAccessibilityTitleAndDescriptionsRead() throws {
        XCTAssertEqual(try chart("xychart\naccTitle: Accessible Title\nx-axis [Q1, Q2]\nline [1, 2]").accessibilityTitle, "Accessible Title")
        XCTAssertEqual(try chart("xychart\naccDescr: This is a description\nx-axis [Q1, Q2]\nline [1, 2]").accessibilityDescription,
                       "This is a description")
        let block = try chart("xychart\naccDescr {\n  This is a multiline\n  description\n}\nx-axis [Q1, Q2]\nline [1, 2]")
        XCTAssertEqual(block.accessibilityDescription, "This is a multiline\ndescription")
        let both = try chart("xychart\naccTitle: Sales Overview\naccDescr: Revenue report for Q1-Q4\ntitle \"Revenue Report\"\nx-axis [Q1, Q2, Q3, Q4]\n"
                             + "line [45, 67, 89, 55]")
        XCTAssertEqual(both.accessibilityTitle, "Sales Overview")
        XCTAssertEqual(both.accessibilityDescription, "Revenue report for Q1-Q4")
        XCTAssertEqual(both.title, "Revenue Report")
    }

    // MARK: Mermaid's database

    func testSeriesTitlesAreTrimmedForTheLegend() throws {
        let read = try chart("xychart\nx-axis [\"90d\", \"60d\"]\nline \" avg \" [48.1, 41.5]\nbar \" p95 \" [112.2, 75.3]")
        XCTAssertEqual(read.series.map { series in XYChartReading.text(series.title) }, ["avg", "p95"])
        XCTAssertEqual(read.series.map(\.kind), [.line, .bar])
    }

    func testValuesAreKeptForEachCategoryAndNoMore() throws {
        XCTAssertEqual(try chart("xychart\nx-axis [cat1, cat2, cat3]\nbar testBar [10, 20, 30, 40, 50]").series[0].values, [10, 20, 30])
        XCTAssertEqual(try chart("xychart\nx-axis [A, B]\nline testLine [100, 200, 300, 400]").series[0].values, [100, 200])
        XCTAssertEqual(try chart("xychart\nx-axis [X, Y, Z]\nbar exact [5, 10, 15]").series[0].values, [5, 10, 15])
        XCTAssertEqual(try chart("xychart\nx-axis [A, B, C, D]\nbar short [1, 2]").series[0].values, [1, 2, nil, nil])
    }

    func testASeriesBeforeAnyXAxisRangesItFromOneToItsNumberOfValues() throws {
        let read = try chart("xychart\nline [3, 1, 4, 1, 5]\nbar [9, 2]")
        XCTAssertEqual(read.xAxis.scale, .range(start: 1, end: 5), "The first series fixes the range")
        XCTAssertEqual(read.series[1].values, [9, 2])
        let replaced = try chart("xychart\nline [3, 1, 4]\nx-axis [a, b]")
        XCTAssertEqual(categories(replaced), ["a", "b"])
        XCTAssertEqual(replaced.series[0].values, [3, 1, 4], "A series keeps the values it had when it was written")
    }

    // MARK: The lexer's rules

    func testCommentsAndSemicolonsEndStatements() throws {
        let commented = try chart("xychart-beta\n%% comment\n  x-axis x 0 --> 1 %% trailing\n  y-axis 0 --> 1   \n  line [0.1, 0.9]   \n  bar [0.5, 0.2]")
        XCTAssertEqual(commented.xAxis.scale, .range(start: 0, end: 1))
        XCTAssertEqual(commented.yAxis.range, XYChartValueRange(start: 0, end: 1))
        XCTAssertEqual(commented.series.map(\.values), [[0.1, 0.9], [0.5, 0.2]])
        let packed = try chart("xychart;title a-b_c;x-axis 1 --> 10;y-axis \"y\" -5 --> +5.5;line [1,2];bar [.5]")
        XCTAssertEqual(packed.title, "a-b_c")
        XCTAssertEqual(packed.xAxis.scale, .range(start: 1, end: 10))
        XCTAssertEqual(packed.yAxis.range, XYChartValueRange(start: -5, end: 5.5))
        XCTAssertEqual(packed.series.map(\.values), [[1, 2], [0.5]])
    }

    func testAWordWithAKeywordInsideIsNotRead() {
        XCTAssertEqual(XYChartReading.readError("xychart\nx-axis [vertical]\nline [1]"), .invalidSyntax(line: 2, problem: .expectedCategories),
                       "`vertical` is the orientation wherever it is, as in Mermaid's grammar")
    }

    func testACharacterNoRuleReadsIsShownWhereItIs() {
        XCTAssertEqual(XYChartReading.readError("xychart\ntitle \"Sales\"\nline [1, 2] {"), .invalidSyntax(line: 3, problem: .unexpectedText("{")))
        XCTAssertEqual(XYChartReading.readError("xychart\nx-axis [café]\nbar [1]"), .invalidSyntax(line: 2, problem: .unexpectedText("é]")),
                       "A letter beyond ASCII is read only between quotation marks, as in Mermaid")
        XCTAssertEqual(XYChartReading.readError("xychart\nx-axis [\"café\"]\nbar [1]"), nil)
    }

    func testATitleWithNothingAfterItIsAnError() {
        XCTAssertEqual(XYChartReading.readError("xychart\ntitle"), .invalidSyntax(line: 2, problem: .expectedChartText))
        XCTAssertEqual(XYChartReading.readError("xychart\nline [1]\nx-axis"), .invalidSyntax(line: 3, problem: .expectedAxisRange))
    }

    func testTheCategoriesAndValuesAreBounded() {
        let limits = MermaidDiagramLimits(maximumSourceBytes: 50_000, maximumNodeCount: 4, maximumEdgeCount: 10, maximumLayoutPointCount: 100)
        XCTAssertNil(XYChartReading.readError("xychart\nx-axis [a, b]\nbar [1, 2]", limits: limits))
        XCTAssertEqual(XYChartReading.readError("xychart\nx-axis [a, b]\nbar [1, 2]\nline [3]", limits: limits), .tooManyChartValues(limit: 4))
    }
}

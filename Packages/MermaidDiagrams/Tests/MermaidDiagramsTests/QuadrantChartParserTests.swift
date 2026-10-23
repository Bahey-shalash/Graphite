import XCTest
@testable import MermaidDiagrams

/// The inputs of Mermaid 12.1.0's quadrant chart parser spec (`quadrant.jison.spec.ts`, as Pele ports it in
/// `tests/compat/quadrant`), the quadrant inputs of Pele's own rendering tests, the documentation's examples, and the
/// errors. Mermaid's spec hands its parser `QuadRantChart` in any case; the reader takes the keyword as Mermaid's
/// detector does, in its own case, so these inputs write it so.
final class QuadrantChartParserTests: XCTestCase {
    private func chart(_ source: String) throws -> QuadrantChart {
        try QuadrantChartReading.quadrantChart(source)
    }

    private func readError(_ source: String) -> MermaidDiagramReadError? {
        QuadrantChartReading.readError(source)
    }

    private func text(_ label: DiagramLabel?) -> String? {
        label?.lines.joined(separator: "\n")
    }

    // MARK: Mermaid's parser spec

    func testTheKeywordAloneReads() throws {
        XCTAssertEqual(try chart("quadrantChart"), QuadrantChart())
    }

    func testTheXAxisHasALowAndAHighText() throws {
        let plain = try chart("quadrantChart\nx-axis urgent --> not urgent")
        XCTAssertEqual([text(plain.xAxisLowLabel), text(plain.xAxisHighLabel)], ["urgent", "not urgent"])
        let spaced = try chart("quadrantChart\n       x-AxIs         Urgent     -->        Not Urgent    \n")
        XCTAssertEqual([text(spaced.xAxisLowLabel), text(spaced.xAxisHighLabel)], ["Urgent", "Not Urgent"])
        let quoted = try chart("quadrantChart\n       x-AxIs         \"Urgent(* +=[❤\"     -->        \"Not Urgent (* +=[❤\"\n    ")
        XCTAssertEqual([text(quoted.xAxisLowLabel), text(quoted.xAxisHighLabel)], ["Urgent(* +=[❤", "Not Urgent (* +=[❤"])
        let lowOnly = try chart("quadrantChart\n       x-AxIs         \"Urgent(* +=[❤\"")
        XCTAssertEqual(text(lowOnly.xAxisLowLabel), "Urgent(* +=[❤")
        XCTAssertNil(lowOnly.xAxisHighLabel)
        let arrowOnly = try chart("quadrantChart\n       x-AxIs         \"Urgent(* +=[❤\"  --> ")
        XCTAssertEqual(text(arrowOnly.xAxisLowLabel), "Urgent(* +=[❤ ⟶")
        XCTAssertNil(arrowOnly.xAxisHighLabel)
    }

    func testTheYAxisHasALowAndAHighText() throws {
        let plain = try chart("quadrantChart\ny-axis urgent --> not urgent")
        XCTAssertEqual([text(plain.yAxisLowLabel), text(plain.yAxisHighLabel)], ["urgent", "not urgent"])
        let quoted = try chart("quadrantChart\n       Y-AxIs         \"Urgent(* +=[❤\"     -->        \"Not Urgent (* +=[❤\"\n    ")
        XCTAssertEqual([text(quoted.yAxisLowLabel), text(quoted.yAxisHighLabel)], ["Urgent(* +=[❤", "Not Urgent (* +=[❤"])
        let arrowOnly = try chart("quadrantChart\n       y-AxIs         \"Urgent(* +=[❤\"  --> ")
        XCTAssertEqual(text(arrowOnly.yAxisLowLabel), "Urgent(* +=[❤ ⟶")
        XCTAssertNil(arrowOnly.yAxisHighLabel)
        XCTAssertNil(arrowOnly.xAxisLowLabel)
    }

    func testEachQuadrantHasItsText() throws {
        let plain = try chart("quadrantChart\nquadrant-1 Plan\nquadrant-2 do\nquadrant-3 delegate\nquadrant-4 delete")
        XCTAssertEqual(plain.quadrantLabels.map(text), ["Plan", "do", "delegate", "delete"])
        XCTAssertEqual(text(try chart("quadrantChart   \n     QuaDrant-1 Plan    ").quadrantLabels[0]), "Plan")
        XCTAssertEqual(text(try chart("quadrantChart   \n     QuaDrant-4 \"Delete(* +=[❤\"").quadrantLabels[3]), "Delete(* +=[❤")
        XCTAssertEqual(try chart("quadrantChart\nquadrant-2 do").quadrantLabels.map(text), [nil, "do", nil, nil])
    }

    func testATitleIsTheRestOfItsLineAsWritten() throws {
        XCTAssertEqual(try chart("quadrantChart\ntitle this is title").title, "this is title")
        XCTAssertEqual(try chart("quadrantChart   \n     TiTle this Is title    ").title, "this Is title")
        XCTAssertEqual(try chart("quadrantChart   \n     title \"this is title (* +=[❤\"").title, "\"this is title (* +=[❤\"")
    }

    func testPointsHaveTheirTextAndCoordinates() throws {
        let plain = try chart("quadrantChart\npoint1: [0.1, 0.4]")
        XCTAssertEqual(plain.points, [QuadrantChartPoint(label: DiagramLabel("point1"), xCoordinate: 0.1, yCoordinate: 0.4, className: nil,
                                                         style: QuadrantChartPointStyle())])
        let spaced = try chart("quadrantChart   \n     Point1      : [0.1, 0.4]   ")
        XCTAssertEqual(spaced.points.map(\.label.lines), [["Point1"]])
        let quoted = try chart("quadrantChart   \n     \"Point1 : (* +=[❤\": [1, 0]   ")
        XCTAssertEqual(quoted.points.map(\.label.lines), [["Point1 : (* +=[❤"]])
        XCTAssertEqual(quoted.points.map(\.xCoordinate), [1])
        XCTAssertEqual(quoted.points.map(\.yCoordinate), [0])
        XCTAssertEqual(readError("quadrantChart   \n     Point1 : [1.2, 0.4]   "), .invalidSyntax(line: 2, problem: .expectedPointCoordinates))
    }

    func testTheWholeChartReads() throws {
        let chart = try chart(Self.analytics)
        XCTAssertEqual(chart.title, "Analytics and Business Intelligence Platforms")
        XCTAssertEqual([text(chart.xAxisLowLabel), text(chart.xAxisHighLabel)], ["Completeness of Vision ❤", "x-axis-2"])
        XCTAssertEqual([text(chart.yAxisLowLabel), text(chart.yAxisHighLabel)], ["Ability to Execute", "y-axis-2"])
        XCTAssertEqual(chart.quadrantLabels.map(text), ["Leaders", "Challengers", "Niche", "Visionaries"])
        XCTAssertEqual(chart.points.map(\.label.spokenText), ["Microsoft", "Salesforce", "IBM", "Incorta"])
        XCTAssertEqual(chart.points.map(\.xCoordinate), [0.75, 0.55, 0.51, 0.20])
        XCTAssertEqual(chart.points.map(\.yCoordinate), [0.75, 0.60, 0.40, 0.30])
    }

    func testPointsKeepTheirStylesInAnyOrderAndTheirClass() throws {
        let red = QuadrantChartColor(red: 255, green: 0, blue: 0)
        let magenta = QuadrantChartColor(red: 255, green: 0, blue: 255)
        let styled = "[0.20, 0.30] radius: 10 ,color: #ff0000 ,stroke-color: #ff00ff ,stroke-width: 10px"
        let all = try chart(Self.analytics.replacingOccurrences(of: "[0.20, 0.30]", with: styled))
        XCTAssertEqual(all.points.last?.style, QuadrantChartPointStyle(radius: 10, color: red, strokeColor: magenta, strokeWidth: 10))
        let shuffled = try chart("""
        quadrantChart
          Microsoft: [0.75, 0.75] stroke-color: #ff00ff ,stroke-width: 10px, color: #ff0000, radius: 10
          Salesforce:::class1: [0.55, 0.60] radius: 10, color: #ff0000
          IBM: [0.51, 0.40] stroke-color: #ff00ff ,stroke-width: 10px
          Incorta: [0.20, 0.30] stroke-width: 10px
        """)
        XCTAssertEqual(shuffled.points.map(\.className), [nil, "class1", nil, nil])
        XCTAssertEqual(shuffled.points.map(\.style), [
            QuadrantChartPointStyle(radius: 10, color: red, strokeColor: magenta, strokeWidth: 10),
            QuadrantChartPointStyle(radius: 10, color: red),
            QuadrantChartPointStyle(strokeColor: magenta, strokeWidth: 10),
            QuadrantChartPointStyle(strokeWidth: 10),
        ])
    }

    func testAClassMayBeNamedConstructorAndAFillIsNotAPointStyle() throws {
        let chart = try chart("quadrantChart\n    classDef constructor color: #ff0000\n    Microsoft:::constructor: [0.75, 0.75]\n    ")
        XCTAssertEqual(chart.classStyles["constructor"], QuadrantChartPointStyle(color: QuadrantChartColor(red: 255, green: 0, blue: 0)))
        XCTAssertEqual(chart.points.first?.className, "constructor")
        XCTAssertEqual(readError("quadrantChart\n    classDef constructor fill:#ff0000\n"),
                       .invalidSyntax(line: 2, problem: .unsupportedPointStyle(name: "fill")))
    }

    func testChineseJapaneseKoreanEmojiAndAccentedTextRead() throws {
        let chinese = try chart("""
        quadrantChart
        title 分析象限图
        x-axis 低覆盖率 --> 高覆盖率
        y-axis 低参与度 --> 高参与度
        quadrant-1 需要扩展
        quadrant-2 需要推广
        quadrant-3 重新评估
        quadrant-4 可以改进
        产品A: [0.3, 0.6]
        产品B: [0.45, 0.23]
        """)
        XCTAssertEqual(chinese.title, "分析象限图")
        XCTAssertEqual([text(chinese.xAxisLowLabel), text(chinese.xAxisHighLabel), text(chinese.yAxisLowLabel), text(chinese.yAxisHighLabel)],
                       ["低覆盖率", "高覆盖率", "低参与度", "高参与度"])
        XCTAssertEqual(chinese.quadrantLabels.map(text), ["需要扩展", "需要推广", "重新评估", "可以改进"])
        XCTAssertEqual(chinese.points.map(\.label.spokenText), ["产品A", "产品B"])
        XCTAssertEqual(chinese.points.map(\.yCoordinate), [0.6, 0.23])
        XCTAssertEqual(text(try chart("quadrantChart\nquadrant-1 拡張が必要\nx-axis 低い --> 高い").quadrantLabels[0]), "拡張が必要")
        XCTAssertEqual(text(try chart("quadrantChart\nx-axis 낮음 --> 높음").xAxisLowLabel), "낮음")
        XCTAssertEqual(text(try chart("quadrantChart\nquadrant-2 🚀Growth").quadrantLabels[1]), "🚀Growth")
        let accented = try chart("quadrantChart\nx-axis Café --> Größe\nquadrant-1 catégoría\nquadrant-2 naïve")
        XCTAssertEqual([text(accented.xAxisLowLabel), text(accented.xAxisHighLabel)], ["Café", "Größe"])
        XCTAssertEqual(accented.quadrantLabels.prefix(2).map(text), ["catégoría", "naïve"])
    }

    // MARK: Pele's rendering tests

    func testStylesMermaidRejectsAreErrors() {
        XCTAssertEqual(readError("quadrantChart\n A: [0.1, 0.1] radius: big"),
                       .invalidSyntax(line: 2, problem: .invalidPointStyleValue(name: "radius", value: "big")))
        XCTAssertEqual(readError("quadrantChart\n A: [0.1, 0.1] color: red"),
                       .invalidSyntax(line: 2, problem: .invalidPointStyleValue(name: "color", value: "red")))
        XCTAssertEqual(readError("quadrantChart\n classDef c fill: #fff"), .invalidSyntax(line: 2, problem: .unsupportedPointStyle(name: "fill")))
        XCTAssertEqual(readError("quadrantChart\n A: [1.2, 0.4]"), .invalidSyntax(line: 2, problem: .expectedPointCoordinates))
        XCTAssertEqual(readError("quadrantChart\n A: [0.2, 0.4"), .invalidSyntax(line: 2, problem: .expectedPointCoordinates))
    }

    func testMermaidsCoordinatePatternTakesWhatIsNoNumberFromZeroToOne() throws {
        let chart = try chart("quadrantChart\n A: [0x5, 0.5]\n B: [0,5, 0.5]\n C: [0.5, 0.5]")
        XCTAssertEqual(chart.points.map(\.xCoordinate), [5, nil, 0.5])
    }

    func testTheModelHoldsAxesMarkdownClassesAndStyles() throws {
        let chart = try chart("quadrantChart\n x-axis a --> b\n quadrant-2 \"`Do`\"\n P:::k: [0.2, 0.8] radius: 3\n classDef k color: #abc")
        XCTAssertEqual([text(chart.xAxisLowLabel), text(chart.xAxisHighLabel)], ["a", "b"])
        XCTAssertEqual(text(chart.quadrantLabels[1]), "Do")
        XCTAssertEqual(chart.points, [QuadrantChartPoint(label: DiagramLabel("P"), xCoordinate: 0.2, yCoordinate: 0.8, className: "k",
                                                         style: QuadrantChartPointStyle(radius: 3))])
        XCTAssertEqual(chart.classStyles, ["k": QuadrantChartPointStyle(color: QuadrantChartColor(red: 0xAA, green: 0xBB, blue: 0xCC))])
    }

    func testMarkdownStringsLoseTheirMarkersAndBreakTagsEndLines() throws {
        let chart = try chart("quadrantChart\n quadrant-1 \"`**Bold** text`\"\n \"two<br>lines\": [0.5, 0.5]")
        XCTAssertEqual(chart.quadrantLabels[0]?.lines, ["Bold text"])
        XCTAssertEqual(chart.points.first?.label.lines, ["two", "lines"])
    }

    func testAccessibleNamesAreRead() throws {
        let chart = try chart("quadrantChart\n accTitle: Priorities\n accDescr: Four boxes\n quadrant-1 Plan")
        XCTAssertEqual(chart.accessibilityTitle, "Priorities")
        XCTAssertEqual(chart.accessibilityDescription, "Four boxes")
    }

    // MARK: Statements, errors and limits

    func testCommentsAndSemicolonsEndStatements() throws {
        let chart = try chart("quadrantChart\n %% a comment\n A: [0.1, 0.2] %% after a point\n quadrant-1 One; quadrant-2 Two\n")
        XCTAssertEqual(chart.points.count, 1)
        XCTAssertEqual(chart.quadrantLabels.prefix(2).map(text), ["One", "Two"])
    }

    func testWhatMermaidRejectsIsAnError() {
        XCTAssertEqual(readError("quadrantChart\n quadrantChart"), .invalidSyntax(line: 2, problem: .unexpectedText("quadrantChart")))
        XCTAssertEqual(readError("quadrantChart\n x-axis\n"), .invalidSyntax(line: 2, problem: .expectedAxisOrQuadrantText))
        XCTAssertEqual(readError("quadrantChart\n quadrant-1 \"never closed\n"), .invalidSyntax(line: 2, problem: .unclosedQuotation))
        XCTAssertEqual(readError("quadrantChart\n A: [0.1, 0.2] radius: 4,\n"), .invalidSyntax(line: 2, problem: .expectedPointStyle))
        XCTAssertEqual(readError("quadrantChart\n A task\n"), .invalidSyntax(line: 2, problem: .expectedPointCoordinates))
        XCTAssertEqual(readError("quadrantChart\n quadrant-1 (Plan)"), .invalidSyntax(line: 2, problem: .unexpectedText("(Plan)")))
        XCTAssertEqual(readError("quadrantChart\n Point:::: [0.1, 0.2]"), .invalidSyntax(line: 2, problem: .unexpectedText(": [0.1, 0.2]")))
    }

    func testPointsAndClassesPastTheNodeLimitAreRefused() {
        var limits = MermaidDiagramLimits.standard
        limits.maximumNodeCount = 2
        XCTAssertNil(QuadrantChartReading.readError("quadrantChart\n A: [0.1, 0.2]\n classDef k radius: 3", limits: limits))
        XCTAssertEqual(QuadrantChartReading.readError("quadrantChart\n A: [0.1, 0.2]\n B: [0.3, 0.4]\n classDef k radius: 3", limits: limits),
                       .tooManyNodes(limit: 2))
    }

    // MARK: Through the reader

    func testTheKeywordIsReadInItsOwnCaseAsMermaidsDetectorReadsIt() {
        XCTAssertEqual(readError("quadrant-1 do"), .unsupportedDiagramType(keyword: "quadrant-1"))
        XCTAssertEqual(readError("QuadRantChart\n quadrant-1 Plan"), .unsupportedDiagramType(keyword: "QuadRantChart"))
    }

    func testTheFrontMattersTitleIsTheTitleUnlessTheChartGivesOne() throws {
        XCTAssertEqual(try chart("---\ntitle: From front matter\n---\nquadrantChart\n A: [0.5, 0.5]").title, "From front matter")
        XCTAssertEqual(try chart("---\ntitle: From front matter\n---\nquadrantChart\n title Own").title, "Own")
        XCTAssertEqual(readError("---\ntitle: T\n---\nquadrantChart\n A task"), .invalidSyntax(line: 5, problem: .expectedPointCoordinates))
    }

    // MARK: Mermaid's documentation

    func testTheDocumentationsStyledExampleReads() throws {
        let chart = try chart("""
        quadrantChart
          title Reach and engagement of campaigns
          x-axis Low Reach --> High Reach
          y-axis Low Engagement --> High Engagement
          quadrant-1 We should expand
          quadrant-2 Need to promote
          quadrant-3 Re-evaluate
          quadrant-4 May be improved
          Campaign A: [0.9, 0.0] radius: 12
          Campaign B:::class1: [0.8, 0.1] color: #ff3300, radius: 10
          Campaign C: [0.7, 0.2] radius: 25, color: #00ff33, stroke-color: #10f0f0
          Campaign D: [0.6, 0.3] radius: 15, stroke-color: #00ff0f, stroke-width: 5px ,color: #ff33f0
          Campaign E:::class2: [0.5, 0.4]
          Campaign F:::class3: [0.4, 0.5] color: #0000ff
          classDef class1 color: #109060
          classDef class2 color: #908342, radius : 10, stroke-color: #310085, stroke-width: 10px
          classDef class3 color: #f00fff, radius : 10
        """)
        XCTAssertEqual(chart.points.count, 6)
        XCTAssertEqual(chart.quadrantLabels.map(text), ["We should expand", "Need to promote", "Re-evaluate", "May be improved"])
        XCTAssertEqual(chart.points[3].style, QuadrantChartPointStyle(radius: 15, color: QuadrantChartColor(red: 0xFF, green: 0x33, blue: 0xF0),
                                                                      strokeColor: QuadrantChartColor(red: 0, green: 0xFF, blue: 0x0F), strokeWidth: 5))
        XCTAssertEqual(chart.classStyles["class2"], QuadrantChartPointStyle(radius: 10, color: QuadrantChartColor(red: 0x90, green: 0x83, blue: 0x42),
                                                                            strokeColor: QuadrantChartColor(red: 0x31, green: 0, blue: 0x85), strokeWidth: 10))
        XCTAssertEqual(Set(chart.classStyles.keys), ["class1", "class2", "class3"])
    }

    private static let analytics = """
    quadrantChart
          title Analytics and Business Intelligence Platforms
          x-axis "Completeness of Vision ❤" --> "x-axis-2"
          y-axis Ability to Execute --> "y-axis-2"
          quadrant-1 Leaders
          quadrant-2 Challengers
          quadrant-3 Niche
          quadrant-4 Visionaries
          Microsoft: [0.75, 0.75]
          Salesforce: [0.55, 0.60]
          IBM: [0.51, 0.40]
          Incorta: [0.20, 0.30]
    """
}

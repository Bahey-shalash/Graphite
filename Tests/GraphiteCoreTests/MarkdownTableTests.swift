import XCTest
@testable import GraphiteCore

final class MarkdownTableTests: XCTestCase {
    // MARK: Helpers

    private func table(_ source: String, file: StaticString = #filePath, line: UInt = #line) -> MarkdownTable? {
        let parsed = MarkdownTable.parse(source)
        if parsed == nil { XCTFail("Expected a table in \(source.debugDescription)", file: file, line: line) }
        return parsed
    }

    private func sources(_ table: MarkdownTable) -> [[String]] {
        table.rows.map { row in row.map(\.source) }
    }

    /// Every cell's range must hold exactly the cell's text, or be empty for an empty cell.
    private func assertRangesMatch(_ source: String, file: StaticString = #filePath, line: UInt = #line) {
        guard let parsed = MarkdownTable.parse(source) else { return XCTFail("Not a table: \(source.debugDescription)", file: file, line: line) }
        let text = source as NSString
        for row in parsed.rows {
            for cell in row {
                XCTAssertLessThanOrEqual(NSMaxRange(cell.sourceRange), text.length, file: file, line: line)
                guard NSMaxRange(cell.sourceRange) <= text.length else { continue }
                XCTAssertEqual(text.substring(with: cell.sourceRange), cell.source, file: file, line: line)
            }
        }
    }

    // MARK: Parsing

    func testParsesATableWithOuterPipes() throws {
        let source = "| a | b |\n| --- | :-: |\n| 1 | 2 |\n"
        let parsed = try XCTUnwrap(table(source))
        XCTAssertEqual(sources(parsed), [["a", "b"], ["1", "2"]])
        XCTAssertEqual(parsed.columnCount, 2)
        XCTAssertEqual(parsed.bodyRowCount, 1)
        XCTAssertEqual(parsed.rows[0][0].sourceRange, NSRange(location: 2, length: 1))
        XCTAssertEqual(parsed.rows[0][1].sourceRange, NSRange(location: 6, length: 1))
        XCTAssertEqual(parsed.rows[1][0].sourceRange, NSRange(location: 26, length: 1))
        XCTAssertEqual(parsed.rows[1][1].sourceRange, NSRange(location: 30, length: 1))
        assertRangesMatch(source)
    }

    func testParsesATableWithoutOuterPipes() throws {
        let source = "a | b\n--|--\n1 | 2"
        let parsed = try XCTUnwrap(table(source))
        XCTAssertEqual(sources(parsed), [["a", "b"], ["1", "2"]])
        XCTAssertEqual(parsed.rows[0][1].sourceRange, NSRange(location: 4, length: 1))
        XCTAssertEqual(parsed.rows[1][0].sourceRange, NSRange(location: 12, length: 1))
        assertRangesMatch(source)
    }

    func testParsesAnIndentedTable() throws {
        let source = "   | a | b |\n   | - | - |\n   | 1 | 2 |\n"
        let parsed = try XCTUnwrap(table(source))
        XCTAssertEqual(sources(parsed), [["a", "b"], ["1", "2"]])
        XCTAssertEqual(parsed.rows[0][0].sourceRange, NSRange(location: 5, length: 1))
        assertRangesMatch(source)
    }

    func testParsesWindowsLineEndingsWithExactRanges() throws {
        let source = "| a | b |\r\n| - | - |\r\n| 1 | 2 |\r\n"
        let parsed = try XCTUnwrap(table(source))
        XCTAssertEqual(sources(parsed), [["a", "b"], ["1", "2"]])
        XCTAssertEqual(parsed.rows[0][1].sourceRange, NSRange(location: 6, length: 1))
        XCTAssertEqual(parsed.rows[1][0].sourceRange, NSRange(location: 24, length: 1))
        XCTAssertEqual(parsed.rows[1][1].sourceRange, NSRange(location: 28, length: 1))
    }

    func testParsesLoneCarriageReturnLineEndingsWithExactRanges() throws {
        let source = "| a | b |\r| - | - |\r| 1 | 2 |\r"
        let parsed = try XCTUnwrap(table(source))
        XCTAssertEqual(sources(parsed), [["a", "b"], ["1", "2"]])
        XCTAssertEqual(parsed.rows[1][0].sourceRange, NSRange(location: 22, length: 1))
        XCTAssertEqual(parsed.rows[1][1].sourceRange, NSRange(location: 26, length: 1))
    }

    func testEscapedPipeStaysInTheCell() throws {
        let source = "| a \\| b | c |\n| - | - |\n"
        let parsed = try XCTUnwrap(table(source))
        XCTAssertEqual(sources(parsed), [["a \\| b", "c"]])
        XCTAssertEqual(parsed.rows[0][0].sourceRange, NSRange(location: 2, length: 6))
        assertRangesMatch(source)
    }

    func testPipeInsideACodeSpanStillSplitsCells() throws {
        let parsed = try XCTUnwrap(table("| `a | b` | c |\n| - | - | - |\n"))
        XCTAssertEqual(sources(parsed), [["`a", "b`", "c"]])
    }

    func testParsesEmptyCellsWithInsertionPoints() throws {
        let source = "| a |\n| - |\n||\n|   |\n"
        let parsed = try XCTUnwrap(table(source))
        XCTAssertEqual(parsed.bodyRowCount, 2)
        XCTAssertEqual(parsed.rows[1], [MarkdownTable.Cell(source: "", sourceRange: NSRange(location: 13, length: 0))])
        XCTAssertEqual(parsed.rows[2], [MarkdownTable.Cell(source: "", sourceRange: NSRange(location: 17, length: 0))],
                       "Text typed into `|   |` goes after the first space.")
    }

    func testParsesRaggedRows() throws {
        let source = "| a | b | c |\n| - | - | - |\n| 1 |\n| 1 | 2 | 3 | 4 |\n"
        let parsed = try XCTUnwrap(table(source))
        XCTAssertEqual(sources(parsed), [["a", "b", "c"], ["1"], ["1", "2", "3", "4"]])
        XCTAssertEqual(parsed.columnCount, 3)
        XCTAssertEqual(parsed.alignments.count, 3)
        XCTAssertEqual(parsed.bodyRowCount, 2)
    }

    func testParsesEveryAlignment() throws {
        let parsed = try XCTUnwrap(table("| a | b | c | d |\n| --- | :--- | :---: | ---: |\n"))
        XCTAssertEqual(parsed.alignments, [.none, .left, .center, .right])
    }

    func testParsesAHeaderOnlyTable() throws {
        for source in ["| a | b |\n| - | - |", "| a | b |\n| - | - |\n"] {
            let parsed = try XCTUnwrap(table(source))
            XCTAssertEqual(parsed.bodyRowCount, 0)
            XCTAssertEqual(parsed.rows.count, 1)
        }
    }

    func testTableEndsAtABlankLine() throws {
        let parsed = try XCTUnwrap(table("| a |\n| - |\n| 1 |\n\nText | with pipe\n"))
        XCTAssertEqual(parsed.bodyRowCount, 1)
    }

    func testNonTablesReturnNil() {
        XCTAssertNil(MarkdownTable.parse(""))
        XCTAssertNil(MarkdownTable.parse("just text"))
        XCTAssertNil(MarkdownTable.parse("| a |"))
        XCTAssertNil(MarkdownTable.parse("| a | b |\nnext line"))
        XCTAssertNil(MarkdownTable.parse("a | b\n---"), "Without outer pipes the delimiter row needs a pipe too.")
        XCTAssertNil(MarkdownTable.parse("text\n---"))
        XCTAssertNil(MarkdownTable.parse("\n| - |"))
        XCTAssertNil(MarkdownTableEditing.insertingRow(atBodyIndex: 0, in: "not a table"))
        XCTAssertNil(MarkdownTableEditing.replacingCell(row: 0, column: 0, with: "x", in: ""))
    }

    func testParsesNonASCIIWithUTF16Offsets() throws {
        let source = "| é | 😀 | 日本 |\n| - | - | - |\n| x | y | z |"
        let parsed = try XCTUnwrap(table(source))
        XCTAssertEqual(sources(parsed), [["é", "😀", "日本"], ["x", "y", "z"]])
        XCTAssertEqual(parsed.rows[0][1].sourceRange, NSRange(location: 6, length: 2))
        XCTAssertEqual(parsed.rows[0][2].sourceRange, NSRange(location: 11, length: 2))
        XCTAssertEqual(parsed.rows[1][0].sourceRange, NSRange(location: 32, length: 1),
                       "The body starts after a header of 16 UTF-16 units and a delimiter row of 14, line breaks included.")
        assertRangesMatch(source)
    }

    // MARK: Replacing a cell

    func testReplacesOnlyTheCellText() {
        let source = "| a | b |\n| - | - |\n| 1 | 2 |\n"
        XCTAssertEqual(MarkdownTableEditing.replacingCell(row: 1, column: 1, with: "xyz", in: source),
                       "| a | b |\n| - | - |\n| 1 | xyz |\n")
        XCTAssertEqual(MarkdownTableEditing.replacingCell(row: 0, column: 0, with: "Header", in: source),
                       "| Header | b |\n| - | - |\n| 1 | 2 |\n")
        XCTAssertEqual(MarkdownTableEditing.replacingCell(row: 1, column: 0, with: "", in: source),
                       "| a | b |\n| - | - |\n|  | 2 |\n")
    }

    func testReplacingKeepsPaddingIndentationAndLineEndings() {
        let source = "  a   | b\r\n  --- | ---\r\n  1   | 2\r\n"
        XCTAssertEqual(MarkdownTableEditing.replacingCell(row: 1, column: 1, with: "22", in: source),
                       "  a   | b\r\n  --- | ---\r\n  1   | 22\r\n")
        XCTAssertEqual(MarkdownTableEditing.replacingCell(row: 1, column: 0, with: "x", in: source),
                       "  a   | b\r\n  --- | ---\r\n  x   | 2\r\n")
        XCTAssertEqual(MarkdownTableEditing.replacingCell(row: 1, column: 0, with: "x", in: "| a |\r| - |\r| 1 |\r"),
                       "| a |\r| - |\r| x |\r")
    }

    func testReplacingInAnEmptyCellKeepsItReadable() {
        let source = "| a |\n| - |\n||\n|   |\n| |\n"
        XCTAssertEqual(MarkdownTableEditing.replacingCell(row: 1, column: 0, with: "x", in: source),
                       "| a |\n| - |\n| x |\n|   |\n| |\n", "`||` gets a space each side.")
        XCTAssertEqual(MarkdownTableEditing.replacingCell(row: 2, column: 0, with: "x", in: source),
                       "| a |\n| - |\n||\n| x  |\n| |\n", "`|   |` gets the text after its first space.")
        XCTAssertEqual(MarkdownTableEditing.replacingCell(row: 3, column: 0, with: "x", in: source),
                       "| a |\n| - |\n||\n|   |\n| x |\n")
    }

    func testReplacingPastARaggedRowsEndAddsEmptyCells() {
        let source = "| a | b | c |\n| - | - | - |\n| 1 |\n"
        XCTAssertEqual(MarkdownTableEditing.replacingCell(row: 1, column: 1, with: "x", in: source),
                       "| a | b | c |\n| - | - | - |\n| 1 | x |\n")
        XCTAssertEqual(MarkdownTableEditing.replacingCell(row: 1, column: 2, with: "z", in: source),
                       "| a | b | c |\n| - | - | - |\n| 1 |  | z |\n")
        XCTAssertEqual(MarkdownTableEditing.replacingCell(row: 1, column: 2, with: "", in: source), source,
                       "Clearing a cell that does not exist changes nothing.")
        XCTAssertEqual(MarkdownTableEditing.replacingCell(row: 1, column: 2, with: "z", in: "a | b | c\n--|--|--\n1"),
                       "a | b | c\n--|--|--\n1 |  | z")
        XCTAssertEqual(MarkdownTableEditing.replacingCell(row: 1, column: 2, with: "z", in: "|a|b|c|\n|-|-|-|\n|1|"),
                       "|a|b|c|\n|-|-|-|\n|1|  | z |")
    }

    func testReplacingOutsideTheTableReturnsNil() {
        let source = "| a | b |\n| - | - |\n| 1 | 2 |\n"
        XCTAssertNil(MarkdownTableEditing.replacingCell(row: 2, column: 0, with: "x", in: source))
        XCTAssertNil(MarkdownTableEditing.replacingCell(row: -1, column: 0, with: "x", in: source))
        XCTAssertNil(MarkdownTableEditing.replacingCell(row: 0, column: 2, with: "x", in: source))
        XCTAssertNil(MarkdownTableEditing.replacingCell(row: 0, column: -1, with: "x", in: source))
    }

    func testReplacingEscapesPipesAndTurnsLineBreaksIntoBreakTags() {
        let source = "| a | b |\n| - | - |\n| 1 | 2 |\n"
        XCTAssertEqual(MarkdownTableEditing.replacingCell(row: 1, column: 0, with: "x|y\nz", in: source),
                       "| a | b |\n| - | - |\n| x\\|y<br>z | 2 |\n")
        XCTAssertEqual(MarkdownTableEditing.replacingCell(row: 1, column: 0, with: "x\\|y\r\nz\rw", in: source),
                       "| a | b |\n| - | - |\n| x\\|y<br>z<br>w | 2 |\n", "An escaped pipe stays; each break, CRLF included, is one tag.")
    }

    func testReplacingWithATrailingBackslashDoesNotEscapeTheNextPipe() {
        XCTAssertEqual(MarkdownTableEditing.replacingCell(row: 0, column: 0, with: "x\\", in: "| a|\n| -|\n"), "| x\\ |\n| -|\n")
    }

    func testClearingAnEdgeCellOfALineWithoutOuterPipesKeepsTheCell() throws {
        let source = "a | b\n--|--\n1 | 2"
        let clearedFirst = try XCTUnwrap(MarkdownTableEditing.replacingCell(row: 0, column: 0, with: "", in: source))
        XCTAssertEqual(clearedFirst, "|  | b\n--|--\n1 | 2")
        XCTAssertEqual(MarkdownTable.parse(clearedFirst)?.rows[0].map(\.source), ["", "b"])
        let clearedLast = try XCTUnwrap(MarkdownTableEditing.replacingCell(row: 0, column: 1, with: "", in: source))
        XCTAssertEqual(clearedLast, "a | |\n--|--\n1 | 2")
        XCTAssertEqual(MarkdownTable.parse(clearedLast)?.rows[0].map(\.source), ["a", ""])
    }

    func testReplacingWithNonASCIIText() {
        let source = "| é | 😀 | 日本 |\n| - | - | - |\n| x | y | z |"
        XCTAssertEqual(MarkdownTableEditing.replacingCell(row: 0, column: 2, with: "ü", in: source),
                       "| é | 😀 | ü |\n| - | - | - |\n| x | y | z |")
        XCTAssertEqual(MarkdownTableEditing.replacingCell(row: 1, column: 2, with: "🎉 日本", in: source),
                       "| é | 😀 | 日本 |\n| - | - | - |\n| x | y | 🎉 日本 |")
        XCTAssertEqual(MarkdownTableEditing.replacingCell(row: 1, column: 0, with: "ñ", in: source),
                       "| é | 😀 | 日本 |\n| - | - | - |\n| ñ | y | z |")
    }

    func testReplacingACellWithItsEditableTextLeavesTheSourceUnchanged() {
        let sources = [
            "| a | b |\n| - | - |\n| 1 | 2 |\n",
            "a | b\n--|--\n1 | 2",
            "  | a<br/>x | b <BR> y |\r\n  |:-:|--:|\r\n  | 1 \\| 2 ||\r\n",
            "| a | b | c |\n| - | - | - |\n| 1 |\n| 1 | 2 | 3 | 4 |\n",
            "| é | 😀 | 日本 |\n| - | - | - |\n|   | x | |\n",
            "a | b\r--|--\r1<br />2\r",
            "| a | b |\n| - | - |",
            "x | y\n--|--\n|\n||\n",
        ]
        for source in sources {
            guard let parsed = MarkdownTable.parse(source) else { XCTFail("Not a table: \(source.debugDescription)"); continue }
            for (rowIndex, row) in parsed.rows.enumerated() {
                for (columnIndex, cell) in row.enumerated() {
                    let editable = MarkdownTableEditing.editableText(ofCellSource: cell.source)
                    XCTAssertEqual(MarkdownTableEditing.replacingCell(row: rowIndex, column: columnIndex, with: editable, in: source), source,
                                   "Row \(rowIndex), column \(columnIndex) of \(source.debugDescription)")
                }
            }
        }
    }

    func testEditableTextShowsBreakTagsAsLineBreaks() {
        XCTAssertEqual(MarkdownTableEditing.editableText(ofCellSource: "a<br>b"), "a\nb")
        XCTAssertEqual(MarkdownTableEditing.editableText(ofCellSource: "a<BR>b<Br/>c<br />d"), "a\nb\nc\nd")
        XCTAssertEqual(MarkdownTableEditing.editableText(ofCellSource: "a \\| b <brx> <b>"), "a \\| b <brx> <b>")
        XCTAssertEqual(MarkdownTableEditing.editableText(ofCellSource: ""), "")
    }

    // MARK: Rows

    func testInsertsARowAtStartMiddleAndEnd() {
        let source = "| a | b |\n| - | - |\n| 1 | 2 |\n| 3 | 4 |\n"
        XCTAssertEqual(MarkdownTableEditing.insertingRow(atBodyIndex: 0, in: source),
                       "| a | b |\n| - | - |\n|  |  |\n| 1 | 2 |\n| 3 | 4 |\n")
        XCTAssertEqual(MarkdownTableEditing.insertingRow(atBodyIndex: 1, in: source),
                       "| a | b |\n| - | - |\n| 1 | 2 |\n|  |  |\n| 3 | 4 |\n")
        XCTAssertEqual(MarkdownTableEditing.insertingRow(atBodyIndex: 2, in: source),
                       "| a | b |\n| - | - |\n| 1 | 2 |\n| 3 | 4 |\n|  |  |\n")
        XCTAssertNil(MarkdownTableEditing.insertingRow(atBodyIndex: 3, in: source))
        XCTAssertNil(MarkdownTableEditing.insertingRow(atBodyIndex: -1, in: source))
    }

    func testInsertsARowIntoATableWithoutATrailingLineBreak() {
        let source = "| a | b |\n| - | - |\n| 1 | 2 |"
        XCTAssertEqual(MarkdownTableEditing.insertingRow(atBodyIndex: 0, in: source), "| a | b |\n| - | - |\n|  |  |\n| 1 | 2 |")
        XCTAssertEqual(MarkdownTableEditing.insertingRow(atBodyIndex: 1, in: source), "| a | b |\n| - | - |\n| 1 | 2 |\n|  |  |",
                       "The break goes before the appended row, so the source still ends without one.")
    }

    func testInsertsARowWithWindowsLineEndings() {
        let source = "| a | b |\r\n| - | - |\r\n| 1 | 2 |\r\n"
        XCTAssertEqual(MarkdownTableEditing.insertingRow(atBodyIndex: 0, in: source), "| a | b |\r\n| - | - |\r\n|  |  |\r\n| 1 | 2 |\r\n")
        XCTAssertEqual(MarkdownTableEditing.insertingRow(atBodyIndex: 1, in: source), "| a | b |\r\n| - | - |\r\n| 1 | 2 |\r\n|  |  |\r\n")
        let withoutFinalBreak = "| a | b |\r\n| - | - |\r\n| 1 | 2 |"
        XCTAssertEqual(MarkdownTableEditing.insertingRow(atBodyIndex: 1, in: withoutFinalBreak), "| a | b |\r\n| - | - |\r\n| 1 | 2 |\r\n|  |  |")
    }

    func testInsertsARowIntoAHeaderOnlyTable() {
        XCTAssertEqual(MarkdownTableEditing.insertingRow(atBodyIndex: 0, in: "| a | b |\n| - | - |"), "| a | b |\n| - | - |\n|  |  |")
        XCTAssertEqual(MarkdownTableEditing.insertingRow(atBodyIndex: 0, in: "| a | b |\n| - | - |\n"), "| a | b |\n| - | - |\n|  |  |\n")
    }

    func testInsertedRowCopiesTheTablesStyle() throws {
        XCTAssertEqual(MarkdownTableEditing.insertingRow(atBodyIndex: 1, in: "a | b\n--|--\n1 | 2"), "a | b\n--|--\n1 | 2\n | ")
        XCTAssertEqual(MarkdownTableEditing.insertingRow(atBodyIndex: 0, in: "  | a |\n  | - |\n"), "  | a |\n  | - |\n  |  |\n")
        let inserted = try XCTUnwrap(MarkdownTableEditing.insertingRow(atBodyIndex: 1, in: "a | b | c\n--|--|--\n1 | 2 | 3"))
        XCTAssertEqual(MarkdownTable.parse(inserted)?.bodyRowCount, 2, "The new row still counts as a body row.")
    }

    func testRemovesRows() {
        let source = "| a | b |\n| - | - |\n| 1 | 2 |\n| 3 | 4 |\n"
        XCTAssertEqual(MarkdownTableEditing.removingRow(atBodyIndex: 0, in: source), "| a | b |\n| - | - |\n| 3 | 4 |\n")
        XCTAssertEqual(MarkdownTableEditing.removingRow(atBodyIndex: 1, in: source), "| a | b |\n| - | - |\n| 1 | 2 |\n")
        XCTAssertNil(MarkdownTableEditing.removingRow(atBodyIndex: 2, in: source))
        XCTAssertNil(MarkdownTableEditing.removingRow(atBodyIndex: -1, in: source))
        XCTAssertEqual(MarkdownTableEditing.removingRow(atBodyIndex: 1, in: "| a | b |\n| - | - |\n| 1 | 2 |\n| 3 | 4 |"),
                       "| a | b |\n| - | - |\n| 1 | 2 |", "The source still ends without a line break.")
        XCTAssertEqual(MarkdownTableEditing.removingRow(atBodyIndex: 0, in: "| a | b |\r\n| - | - |\r\n| 1 | 2 |\r\n| 3 | 4 |\r\n"),
                       "| a | b |\r\n| - | - |\r\n| 3 | 4 |\r\n")
    }

    func testRemovingTheOnlyBodyRowLeavesTheHeader() throws {
        XCTAssertEqual(MarkdownTableEditing.removingRow(atBodyIndex: 0, in: "| a | b |\n| - | - |\n| 1 | 2 |\n"), "| a | b |\n| - | - |\n")
        XCTAssertEqual(MarkdownTableEditing.removingRow(atBodyIndex: 0, in: "| a | b |\n| - | - |\n| 1 | 2 |"), "| a | b |\n| - | - |")
        let remaining = try XCTUnwrap(MarkdownTableEditing.removingRow(atBodyIndex: 0, in: "| a |\n| - |\n| 1 |"))
        XCTAssertEqual(MarkdownTable.parse(remaining)?.bodyRowCount, 0)
        XCTAssertNil(MarkdownTableEditing.removingRow(atBodyIndex: 0, in: remaining))
    }

    func testMovesRowsAndRefusesAtTheEdges() {
        let source = "| a |\n| - |\n| 1 |\n| 2 |\n| 3 |\n"
        XCTAssertEqual(MarkdownTableEditing.movingRow(atBodyIndex: 0, by: 1, in: source), "| a |\n| - |\n| 2 |\n| 1 |\n| 3 |\n")
        XCTAssertEqual(MarkdownTableEditing.movingRow(atBodyIndex: 2, by: -1, in: source), "| a |\n| - |\n| 1 |\n| 3 |\n| 2 |\n")
        XCTAssertEqual(MarkdownTableEditing.movingRow(atBodyIndex: 0, by: 2, in: source), "| a |\n| - |\n| 2 |\n| 3 |\n| 1 |\n")
        XCTAssertNil(MarkdownTableEditing.movingRow(atBodyIndex: 0, by: -1, in: source))
        XCTAssertNil(MarkdownTableEditing.movingRow(atBodyIndex: 2, by: 1, in: source))
        XCTAssertNil(MarkdownTableEditing.movingRow(atBodyIndex: 3, by: -1, in: source))
        XCTAssertEqual(MarkdownTableEditing.movingRow(atBodyIndex: 1, by: 0, in: source), source)
    }

    func testMovingTheLastRowWithoutALineBreakKeepsTheEnding() {
        XCTAssertEqual(MarkdownTableEditing.movingRow(atBodyIndex: 1, by: -1, in: "| a |\n| - |\n| 1 |\n| 2 |"), "| a |\n| - |\n| 2 |\n| 1 |")
        XCTAssertEqual(MarkdownTableEditing.movingRow(atBodyIndex: 0, by: 1, in: "| a |\n| - |\n  | 1 |\n| 2 |\n"),
                       "| a |\n| - |\n| 2 |\n  | 1 |\n", "A row keeps its own indentation.")
        XCTAssertEqual(MarkdownTableEditing.movingRow(atBodyIndex: 0, by: 1, in: "| a |\r\n| - |\r\n| 1 |\r\n| 2 |"), "| a |\r\n| - |\r\n| 2 |\r\n| 1 |")
    }

    // MARK: Columns

    private let tableWithoutOuterPipes = "a | b | c\n--|--|--\n1 | 2 | 3\n4 | 5 | 6\n"

    func testInsertsAColumnIntoATableWithoutOuterPipes() throws {
        XCTAssertEqual(MarkdownTableEditing.insertingColumn(at: 1, in: tableWithoutOuterPipes),
                       "a |  | b | c\n--| --- |--|--\n1 |  | 2 | 3\n4 |  | 5 | 6\n")
        XCTAssertEqual(MarkdownTableEditing.insertingColumn(at: 0, in: tableWithoutOuterPipes),
                       "|  | a | b | c\n| --- | --|--|--\n|  | 1 | 2 | 3\n|  | 4 | 5 | 6\n")
        let appended = try XCTUnwrap(MarkdownTableEditing.insertingColumn(at: 3, in: tableWithoutOuterPipes))
        XCTAssertEqual(appended, "a | b | c |  |\n--|--|-- | ---\n1 | 2 | 3\n4 | 5 | 6\n")
        let parsed = try XCTUnwrap(MarkdownTable.parse(appended))
        XCTAssertEqual(parsed.columnCount, 4)
        XCTAssertEqual(parsed.alignments.count, 4)
        XCTAssertNil(MarkdownTableEditing.insertingColumn(at: 4, in: tableWithoutOuterPipes))
        XCTAssertNil(MarkdownTableEditing.insertingColumn(at: -1, in: tableWithoutOuterPipes))
    }

    func testInsertsAColumnIntoATableWithOuterPipes() {
        let source = "| a | b |\n| - | - |\n| 1 | 2 |"
        XCTAssertEqual(MarkdownTableEditing.insertingColumn(at: 1, in: source), "| a |  | b |\n| - | --- | - |\n| 1 |  | 2 |")
        XCTAssertEqual(MarkdownTableEditing.insertingColumn(at: 0, in: source), "|  | a | b |\n| --- | - | - |\n|  | 1 | 2 |")
        XCTAssertEqual(MarkdownTableEditing.insertingColumn(at: 2, in: source), "| a | b |  |\n| - | - | --- |\n| 1 | 2 |  |")
    }

    func testInsertingAColumnLeavesRowsThatDoNotReachItAlone() {
        let source = "| a | b | c |\r\n| - | - | - |\r\n| 1 |\r\n"
        XCTAssertEqual(MarkdownTableEditing.insertingColumn(at: 2, in: source), "| a | b |  | c |\r\n| - | - | --- | - |\r\n| 1 |\r\n")
        XCTAssertEqual(MarkdownTableEditing.insertingColumn(at: 0, in: source), "|  | a | b | c |\r\n| --- | - | - | - |\r\n|  | 1 |\r\n")
    }

    func testRemovesColumnsFromATableWithoutOuterPipes() {
        XCTAssertEqual(MarkdownTableEditing.removingColumn(at: 0, in: tableWithoutOuterPipes), "b | c\n--|--\n2 | 3\n5 | 6\n")
        XCTAssertEqual(MarkdownTableEditing.removingColumn(at: 1, in: tableWithoutOuterPipes), "a | c\n--|--\n1 | 3\n4 | 6\n")
        XCTAssertEqual(MarkdownTableEditing.removingColumn(at: 2, in: tableWithoutOuterPipes), "a | b\n--|--\n1 | 2\n4 | 5\n")
        XCTAssertNil(MarkdownTableEditing.removingColumn(at: 3, in: tableWithoutOuterPipes))
    }

    func testRemovesColumnsFromATableWithOuterPipes() {
        let source = "| a | b | c |\n| - | - | - |\n| 1 | 2 | 3 |"
        XCTAssertEqual(MarkdownTableEditing.removingColumn(at: 0, in: source), "| b | c |\n| - | - |\n| 2 | 3 |")
        XCTAssertEqual(MarkdownTableEditing.removingColumn(at: 1, in: source), "| a | c |\n| - | - |\n| 1 | 3 |")
        XCTAssertEqual(MarkdownTableEditing.removingColumn(at: 2, in: source), "| a | b |\n| - | - |\n| 1 | 2 |")
    }

    func testRemovingTheOnlyColumnReturnsNil() {
        XCTAssertNil(MarkdownTableEditing.removingColumn(at: 0, in: "| a |\n| - |\n| 1 |\n"))
    }

    func testRemovingAColumnKeepsAnEmptyNeighbourAsACell() throws {
        let removedFirst = try XCTUnwrap(MarkdownTableEditing.removingColumn(at: 0, in: "a | | c\n--|--|--\n1 | | 3"))
        XCTAssertEqual(removedFirst, "| | c\n--|--\n| | 3")
        XCTAssertEqual(MarkdownTable.parse(removedFirst).map { sources($0) }, [["", "c"], ["", "3"]])
        let removedLast = try XCTUnwrap(MarkdownTableEditing.removingColumn(at: 2, in: "a | | c\n--|--|--\n1 | | 3"))
        XCTAssertEqual(removedLast, "a | |\n--|--\n1 | |")
        XCTAssertEqual(MarkdownTable.parse(removedLast).map { sources($0) }, [["a", ""], ["1", ""]])
    }

    func testRemovingAColumnFromRaggedRows() {
        let source = "| a | b | c |\n| - | - | - |\n| 1 |\n"
        XCTAssertEqual(MarkdownTableEditing.removingColumn(at: 2, in: source), "| a | b |\n| - | - |\n| 1 |\n", "A row without the cell is left alone.")
        XCTAssertEqual(MarkdownTableEditing.removingColumn(at: 1, in: source), "| a | c |\n| - | - |\n| 1 |\n")
        XCTAssertEqual(MarkdownTableEditing.removingColumn(at: 0, in: source), "| b | c |\n| - | - |\n|\n",
                       "The row's only cell goes; the lone pipe stays a row.")
    }

    func testMovesColumnsAndTheirAlignments() throws {
        let source = "a | b | c\n--|:-:|--\n1 | 2 | 3\n"
        let movedRight = try XCTUnwrap(MarkdownTableEditing.movingColumn(at: 0, by: 1, in: source))
        XCTAssertEqual(movedRight, "b | a | c\n:-:|--|--\n2 | 1 | 3\n")
        XCTAssertEqual(MarkdownTable.parse(movedRight)?.alignments, [.center, .none, .none])
        XCTAssertEqual(MarkdownTableEditing.movingColumn(at: 2, by: -2, in: source), "c | a | b\n--|--|:-:\n3 | 1 | 2\n")
        XCTAssertEqual(MarkdownTableEditing.movingColumn(at: 1, by: -1, in: source), "b | a | c\n:-:|--|--\n2 | 1 | 3\n")
        XCTAssertNil(MarkdownTableEditing.movingColumn(at: 0, by: -1, in: source))
        XCTAssertNil(MarkdownTableEditing.movingColumn(at: 2, by: 1, in: source))
        XCTAssertNil(MarkdownTableEditing.movingColumn(at: 3, by: -1, in: source))
        XCTAssertEqual(MarkdownTableEditing.movingColumn(at: 1, by: 0, in: source), source)
    }

    func testMovingAColumnKeepsPaddingInPlace() {
        let source = "| a   | bbb |\n| --- | --- |\n| 1   | 2   |\n"
        XCTAssertEqual(MarkdownTableEditing.movingColumn(at: 0, by: 1, in: source), "| bbb   | a |\n| --- | --- |\n| 2   | 1   |\n",
                       "Each cell's spacing stays at its position; only the text moves.")
    }

    func testMovingAColumnWithShortRowsTreatsMissingCellsAsEmpty() {
        let source = "| a | b |\n| - | - |\n| 1 |\n"
        XCTAssertEqual(MarkdownTableEditing.movingColumn(at: 0, by: 1, in: source), "| b | a |\n| - | - |\n|  | 1 |\n",
                       "The short row's text moves to the second column, after an empty first cell.")
        XCTAssertEqual(MarkdownTableEditing.movingColumn(at: 1, by: -1, in: source), "| b | a |\n| - | - |\n|  | 1 |\n")
        let threeColumns = "| a | b | c |\n| - | - | - |\n| 1 |\n"
        XCTAssertEqual(MarkdownTableEditing.movingColumn(at: 1, by: 1, in: threeColumns), "| a | c | b |\n| - | - | - |\n| 1 |\n",
                       "A short row with nothing in the moved columns is left as written.")
    }

    func testColumnEditsWithNonASCIIText() {
        let source = "| é | 😀 | 日本 |\n| - | - | - |\n| x | y | z |"
        XCTAssertEqual(MarkdownTableEditing.movingColumn(at: 1, by: 1, in: source), "| é | 日本 | 😀 |\n| - | - | - |\n| x | z | y |")
        XCTAssertEqual(MarkdownTableEditing.removingColumn(at: 1, in: source), "| é | 日本 |\n| - | - |\n| x | z |")
        XCTAssertEqual(MarkdownTableEditing.insertingColumn(at: 2, in: source), "| é | 😀 |  | 日本 |\n| - | - | --- | - |\n| x | y |  | z |")
    }

    // MARK: Alignment

    func testSettingAlignmentKeepsTheDelimiterWidth() {
        let source = "| a | b |\n| ----- | --- |\n| 1 | 2 |\n"
        XCTAssertEqual(MarkdownTableEditing.settingAlignment(.center, ofColumn: 0, in: source), "| a | b |\n| :---: | --- |\n| 1 | 2 |\n")
        XCTAssertEqual(MarkdownTableEditing.settingAlignment(.left, ofColumn: 0, in: source), "| a | b |\n| :---- | --- |\n| 1 | 2 |\n")
        XCTAssertEqual(MarkdownTableEditing.settingAlignment(.right, ofColumn: 0, in: source), "| a | b |\n| ----: | --- |\n| 1 | 2 |\n")
        XCTAssertEqual(MarkdownTableEditing.settingAlignment(.center, ofColumn: 1, in: source), "| a | b |\n| ----- | :---: |\n| 1 | 2 |\n",
                       "A delimiter of three dashes grows to keep three dashes beside the colons.")
    }

    func testSettingAlignmentBackToNoneAndOnShortDelimiters() {
        XCTAssertEqual(MarkdownTableEditing.settingAlignment(.none, ofColumn: 0, in: "| a |\n| :---: |\n"), "| a |\n| ----- |\n")
        XCTAssertEqual(MarkdownTableEditing.settingAlignment(.left, ofColumn: 0, in: "| a |\n| :---: |\n"), "| a |\n| :---- |\n")
        XCTAssertEqual(MarkdownTableEditing.settingAlignment(.right, ofColumn: 1, in: "a | b\n--|--"), "a | b\n--|---:")
        XCTAssertEqual(MarkdownTableEditing.settingAlignment(.center, ofColumn: 1, in: "| a | b |\n| - |\n"), "| a | b |\n| - | :---: |\n")
    }

    func testSettingTheAlignmentAColumnAlreadyHasChangesNothing() {
        let source = "| a | b |\n| :-- | --: |\n"
        XCTAssertEqual(MarkdownTableEditing.settingAlignment(.left, ofColumn: 0, in: source), source)
        XCTAssertEqual(MarkdownTableEditing.settingAlignment(.right, ofColumn: 1, in: source), source)
        XCTAssertEqual(MarkdownTableEditing.settingAlignment(.none, ofColumn: 1, in: "| a | b |\n| - |\n"), "| a | b |\n| - |\n")
    }

    func testSettingAlignmentOutsideTheTableReturnsNil() {
        XCTAssertNil(MarkdownTableEditing.settingAlignment(.left, ofColumn: 2, in: "| a | b |\n| - | - |\n"))
        XCTAssertNil(MarkdownTableEditing.settingAlignment(.left, ofColumn: -1, in: "| a | b |\n| - | - |\n"))
        XCTAssertNil(MarkdownTableEditing.settingAlignment(.left, ofColumn: 0, in: "text"))
    }

    func testSettingAlignmentKeepsTheRestOfTheSourceWithWindowsLineEndings() {
        XCTAssertEqual(MarkdownTableEditing.settingAlignment(.center, ofColumn: 1, in: "  a | b\r\n  --|-----\r\n  1 | 2\r\n"),
                       "  a | b\r\n  --|:---:\r\n  1 | 2\r\n")
    }
}

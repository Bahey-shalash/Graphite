import XCTest
@testable import GraphiteCore

/// Tasks of reading view in Core: where a block's lines are in the note, how a task is
/// marked with its place, and the edit a tap on its checkbox makes.
final class ReadingTaskTests: XCTestCase {
    // MARK: Offsets through replaced text

    func testOffsetsAreTracedThroughRemovalsAndReplacements() {
        let original = "0123456789abcdef"
        // "234" removed, "78" replaced by "XYZW", "c" removed.
        let offsets = ReplacedTextOffsets(replacements: [(NSRange(location: 12, length: 1), 0), (NSRange(location: 2, length: 3), 0), (NSRange(location: 7, length: 2), 4)])
        let result = "0156XYZW9abdef"
        for (resultOffset, originalOffset) in [(0, 0), (1, 1), (2, 5), (3, 6), (4, 7), (8, 9), (9, 10), (10, 11), (11, 13), (13, 15), (14, 16)] as [(Int, Int)] {
            XCTAssertEqual(offsets.originalOffset(of: resultOffset), originalOffset, "offset \(resultOffset)")
            if resultOffset < 14, resultOffset != 4 {
                XCTAssertEqual((result as NSString).character(at: resultOffset), (original as NSString).character(at: originalOffset))
            }
        }
        XCTAssertNil(offsets.originalOffset(of: 5), "Inside the replacement, the original has no such character.")
        XCTAssertNil(offsets.originalOffset(of: 7))
    }

    func testOffsetAfterRangesRemovedNextToEachOtherIsAfterBoth() {
        let offsets = ReplacedTextOffsets(replacements: [(NSRange(location: 2, length: 2), 0), (NSRange(location: 4, length: 3), 0)])
        XCTAssertEqual(offsets.originalOffset(of: 1), 1)
        XCTAssertEqual(offsets.originalOffset(of: 2), 7)
        XCTAssertEqual(ReplacedTextOffsets(replacements: []).originalOffset(of: 42), 42)
    }

    // MARK: Where a block's lines are in the note

    /// The lines of every Markdown run, callout bodies included, with the text the body
    /// has from each line's offset to the end of that line.
    private func linesWithSourceText(of blocks: [NotePreviewDocument.LocatedBlock], in body: String) -> [(line: String, sourceText: String)] {
        let source = body as NSString
        return blocks.flatMap { located -> [(line: String, sourceText: String)] in
            guard case .markdown(let markdown) = located.block else { return linesWithSourceText(of: located.body, in: body) }
            let lines = markdown.components(separatedBy: "\n")
            XCTAssertEqual(lines.count, located.lineStartOffsets.count)
            return zip(lines, located.lineStartOffsets).map { line, offset in
                let lineEnd = source.range(of: "\n", range: NSRange(location: offset, length: source.length - offset)).location
                var sourceText = source.substring(with: NSRange(location: offset, length: (lineEnd == NSNotFound ? source.length : lineEnd) - offset))
                if sourceText.hasSuffix("\r") { sourceText.removeLast() }
                return (line, sourceText)
            }
        }
    }

    func testEveryLineOfAMarkdownRunKnowsWhereItStartsInTheBody() {
        let body = "First\r\n- [ ] one\r\n\r\n# Heading\r\n- [ ] two\r\n```\r\n- [ ] code\r\n```\r\n$$\r\nx\r\n$$\r\n- [ ] three\r\n> [!note] Title\r\n> - [ ] in a callout\r\n>- [ ] without a space\r\n> > [!tip]\r\n> > - [ ] nested\r\nLast"
        let lines = linesWithSourceText(of: NotePreviewDocument.locatedBlocks(from: body), in: body)
        XCTAssertEqual(lines.map(\.line), ["First", "- [ ] one", "", "- [ ] two", "```", "- [ ] code", "```", "- [ ] three",
                                           "- [ ] in a callout", "- [ ] without a space", "- [ ] nested", "Last"])
        for line in lines { XCTAssertEqual(line.line, line.sourceText) }
        XCTAssertEqual(NotePreviewDocument.locatedBlocks(from: body).map(\.block), NotePreviewDocument.blocks(from: body))
    }

    func testLinesAfterARemovedCommentKeepTheirPlaceInTheBody() {
        let body = "- [ ] before\n%%hidden\n- [ ] in the comment\n%%\n- [ ] after %%note%% more\n- [ ] last"
        let lines = linesWithSourceText(of: NotePreviewDocument.locatedBlocks(from: body), in: body)
        XCTAssertEqual(lines.map(\.line), ["- [ ] before", "", "- [ ] after  more", "- [ ] last"])
        XCTAssertEqual(lines.map(\.sourceText), ["- [ ] before", "", "- [ ] after %%note%% more", "- [ ] last"])
    }

    // MARK: Marking tasks with their place

    /// The tasks `preparedForReading` marks in a block made of `body`'s lines, found in
    /// `body` as the reading view finds them.
    private func markedTasks(inBody body: String) -> [ReadingTasks.MarkedTask] {
        NotePreviewDocument.locatedBlocks(from: body).flatMap { located -> [ReadingTasks.MarkedTask] in
            guard case .markdown(let markdown) = located.block else { return [] }
            let prepared = ObsidianInlineMarkup.preparedForReading(markdown, colorsEnabled: true, paletteHexByName: [:]) { lineIndex, status in
                ReadingTasks.location(ofTaskStartingAt: located.lineStartOffsets[lineIndex], status: status, in: body)
            }
            let scalars = prepared.unicodeScalars
            var tasks: [ReadingTasks.MarkedTask] = []
            var position = scalars.startIndex
            while position < scalars.endIndex {
                if let marked = ReadingTasks.markedTask(at: position, in: scalars) {
                    tasks.append(marked.task)
                    position = marked.end
                } else {
                    position = scalars.index(after: position)
                }
            }
            return tasks
        }
    }

    func testMarkedTasksCarryTheOffsetOfTheirStatusCharacter() {
        let body = "- [ ] a\n* [x] b\n\t+ [/] c\n12. [-] d\n3) [ ] e\n> - [?] quoted\n- [x]\n```\n- [ ] code\n```\n- not [ ] a task\n[ ] no list\n- [] empty\n- [xx] two\n- [ ]no space"
        let tasks = markedTasks(inBody: body)
        XCTAssertEqual(tasks.map { task in String(Character(task.status)) }, [" ", "x", "/", "-", " ", "?", "x"])
        let source = body as NSString
        XCTAssertEqual(tasks.compactMap(\.location).count, tasks.count)
        for (task, line) in zip(tasks, ["- [ ] a", "* [x] b", "\t+ [/] c", "12. [-] d", "3) [ ] e", "> - [?] quoted", "- [x]"]) {
            let statusOffset = try? XCTUnwrap(task.location?.statusOffset)
            let lineRange = source.range(of: line)
            XCTAssertEqual(statusOffset, lineRange.location + (line as NSString).range(of: "[").location + 1, line)
        }
    }

    func testTasksAfterADisplayFormulaWrittenOverSeveralLinesKeepTheirOwnLines() {
        let body = "- [ ] first\n- $$\n  a \\\\\n  - [ ] not a task, inside the formula\n  $$\n- [ ] second\n- [ ] third"
        let tasks = markedTasks(inBody: body)
        let source = body as NSString
        XCTAssertEqual(tasks.compactMap(\.location).map(\.statusOffset),
                       ["- [ ] first", "- [ ] second", "- [ ] third"].map { line in source.range(of: line).location + 3 })
    }

    func testTasksAreNotGivenAPlaceOnceACommentHasJoinedLines() {
        // In a block of a note comments are gone before it is split; text handed over with
        // one that spans lines no longer has the lines its tasks are known by.
        let markdown = "- [ ] first %%hidden\nstill hidden%%\n- [ ] second"
        var askedLineIndices: [Int] = []
        let prepared = ObsidianInlineMarkup.preparedForReading(markdown, colorsEnabled: true, paletteHexByName: [:]) { lineIndex, _ in
            askedLineIndices.append(lineIndex)
            return ReadingTasks.Location(statusOffset: 3, lineChecksum: 0)
        }
        XCTAssertEqual(askedLineIndices, [])
        let unchecked = String(ObsidianInlineMarkup.uncheckedTaskMarker)
        XCTAssertEqual(prepared, "- \(unchecked)32 first \n- \(unchecked)32 second")
    }

    func testMarkedTaskIsReadBackWithItsStatusAndPlace() {
        let tasks = [ReadingTasks.MarkedTask(status: " ", location: nil),
                     ReadingTasks.MarkedTask(status: "x", location: ReadingTasks.Location(statusOffset: 0, lineChecksum: 0)),
                     ReadingTasks.MarkedTask(status: "7", location: ReadingTasks.Location(statusOffset: 8_388_608, lineChecksum: .max)),
                     ReadingTasks.MarkedTask(status: "\u{1F525}", location: ReadingTasks.Location(statusOffset: 12, lineChecksum: 99))]
        for task in tasks {
            let text = "- " + ReadingTasks.markedText(for: task) + " text 123"
            let scalars = text.unicodeScalars
            let start = scalars.index(scalars.startIndex, offsetBy: 2)
            let marked = ReadingTasks.markedTask(at: start, in: scalars)
            XCTAssertEqual(marked?.task, task)
            XCTAssertEqual(marked.map { marked in String(scalars[marked.end...]) }, " text 123")
            XCTAssertTrue(scalars[start...].dropFirst().prefix { scalar in scalar != " " }.allSatisfy { scalar in
                ReadingTasks.isTaskMarker(scalar) || ("0"..."9").contains(Character(scalar))
            }, "Only markers and digits, which Markdown leaves alone.")
        }
    }

    func testDamagedMarkedTaskIsReadAsFarAsItIsWhole() {
        let marker = String(ObsidianInlineMarkup.checkedTaskMarker)
        func task(in text: String) -> ReadingTasks.MarkedTask? { ReadingTasks.markedTask(at: text.unicodeScalars.startIndex, in: text.unicodeScalars)?.task }
        XCTAssertNil(task(in: marker), "A marker without a status is no task.")
        XCTAssertNil(task(in: marker + "x"))
        XCTAssertNil(task(in: "120"))
        XCTAssertNil(task(in: marker + "99999999999999999999999"), "A number too large to be a code point.")
        XCTAssertNil(task(in: marker + "55296"), "A surrogate is no character.")
        XCTAssertEqual(task(in: marker + "120" + marker), ReadingTasks.MarkedTask(status: "x", location: nil))
        XCTAssertEqual(task(in: marker + "120" + marker + "15"), ReadingTasks.MarkedTask(status: "x", location: nil))
        XCTAssertEqual(task(in: marker + "120" + marker + "15" + marker + "99999999999"), ReadingTasks.MarkedTask(status: "x", location: nil))
        XCTAssertEqual(task(in: marker + "120" + marker + "15" + marker + "7"),
                       ReadingTasks.MarkedTask(status: "x", location: ReadingTasks.Location(statusOffset: 15, lineChecksum: 7)))
    }

    // MARK: The edit a tap makes

    /// The text after a tap on the checkbox of the task on the line that starts with `linePrefix`.
    private func ticking(taskOnLineStarting linePrefix: String, in text: String, status: Unicode.Scalar) throws -> String {
        let source = text as NSString
        let lineStart = source.range(of: linePrefix).location
        let location = try XCTUnwrap(ReadingTasks.location(ofTaskStartingAt: lineStart, status: status, in: text))
        let edit = try XCTUnwrap(ReadingTasks.togglingEdit(at: location, in: text, selection: NSRange(location: 0, length: 0)))
        return source.replacingCharacters(in: edit.range, with: edit.replacement)
    }

    func testTapTicksAnOpenTaskAndClearsEveryOtherStatus() throws {
        let text = "- [ ] open\r\n- [x] done\r\n- [X] capital\r\n- [/] half\r\n- [-] dropped\r\n"
        XCTAssertEqual(try ticking(taskOnLineStarting: "- [ ] open", in: text, status: " "), "- [x] open\r\n- [x] done\r\n- [X] capital\r\n- [/] half\r\n- [-] dropped\r\n")
        XCTAssertEqual(try ticking(taskOnLineStarting: "- [x] done", in: text, status: "x"), "- [ ] open\r\n- [ ] done\r\n- [X] capital\r\n- [/] half\r\n- [-] dropped\r\n")
        XCTAssertEqual(try ticking(taskOnLineStarting: "- [X] capital", in: text, status: "X"), "- [ ] open\r\n- [x] done\r\n- [ ] capital\r\n- [/] half\r\n- [-] dropped\r\n")
        XCTAssertEqual(try ticking(taskOnLineStarting: "- [/] half", in: text, status: "/"), "- [ ] open\r\n- [x] done\r\n- [X] capital\r\n- [ ] half\r\n- [-] dropped\r\n")
        XCTAssertEqual(try ticking(taskOnLineStarting: "- [-] dropped", in: text, status: "-"), "- [ ] open\r\n- [x] done\r\n- [X] capital\r\n- [/] half\r\n- [ ] dropped\r\n")
    }

    func testStatusOutsideTheBasicMultilingualPlaneIsOneCharacter() throws {
        let text = "- [\u{1F525}] hot\n- [ ] next"
        XCTAssertEqual(try ticking(taskOnLineStarting: "- [\u{1F525}]", in: text, status: "\u{1F525}"), "- [ ] hot\n- [ ] next")
        let location = try XCTUnwrap(ReadingTasks.location(ofTaskStartingAt: 0, status: "\u{1F525}", in: text))
        // A cursor after the status moves with the text; one before it stays.
        let afterStatus = try XCTUnwrap(ReadingTasks.togglingEdit(at: location, in: text, selection: NSRange(location: 8, length: 3)))
        XCTAssertEqual(afterStatus.selectionAfter, NSRange(location: 7, length: 3))
        let aroundStatus = try XCTUnwrap(ReadingTasks.togglingEdit(at: location, in: text, selection: NSRange(location: 1, length: 9)))
        XCTAssertEqual(aroundStatus.selectionAfter, NSRange(location: 1, length: 8))
    }

    func testSelectionStaysWhereItIsWhenOneUnitReplacesAnother() throws {
        let text = "- [ ] open\nnext line"
        let location = try XCTUnwrap(ReadingTasks.location(ofTaskStartingAt: 0, status: " ", in: text))
        for selection in [NSRange(location: 0, length: 0), NSRange(location: 3, length: 1), NSRange(location: 2, length: 10), NSRange(location: 15, length: 0)] {
            XCTAssertEqual(ReadingTasks.togglingEdit(at: location, in: text, selection: selection)?.selectionAfter, selection)
        }
    }

    func testTapOnAnOlderTextChangesNothingOnceTheLineIsAnother() throws {
        let text = "- [ ] first\n- [ ] second\n"
        let location = try XCTUnwrap(ReadingTasks.location(ofTaskStartingAt: 12, status: " ", in: text))
        // The same place after a line of the same length was put first holds another task.
        XCTAssertNil(ReadingTasks.togglingEdit(at: location, in: "- [ ] added\n- [ ] first\n- [ ] second\n", selection: NSRange(location: 0, length: 0)))
        XCTAssertNil(ReadingTasks.togglingEdit(at: location, in: "- [ ] first\n- [ ] secon\n", selection: NSRange(location: 0, length: 0)))
        XCTAssertNil(ReadingTasks.togglingEdit(at: location, in: "- [ ] first\n", selection: NSRange(location: 0, length: 0)))
        XCTAssertNil(ReadingTasks.togglingEdit(at: location, in: "", selection: NSRange(location: 0, length: 0)))
        XCTAssertNil(ReadingTasks.togglingEdit(at: ReadingTasks.Location(statusOffset: 0, lineChecksum: location.lineChecksum), in: text, selection: NSRange(location: 0, length: 0)))
        // A task ticked since, which leaves its line's other characters as they were, is still that task.
        let ticked = try XCTUnwrap(ReadingTasks.togglingEdit(at: location, in: "- [x] first\n- [x] second\n", selection: NSRange(location: 0, length: 0)))
        XCTAssertEqual(ticked.range, NSRange(location: 15, length: 1))
        XCTAssertEqual(ticked.replacement, " ")
    }

    func testLocationNeedsTheStatusTheTaskWasDrawnWith() {
        XCTAssertNil(ReadingTasks.location(ofTaskStartingAt: 0, status: "x", in: "- [ ] open"))
        XCTAssertNil(ReadingTasks.location(ofTaskStartingAt: 0, status: " ", in: "plain [ ] text"))
        XCTAssertNil(ReadingTasks.location(ofTaskStartingAt: 2, status: " ", in: "- [ ] not from the middle of its marker"))
        XCTAssertNil(ReadingTasks.location(ofTaskStartingAt: 99, status: " ", in: "- [ ] open"))
        XCTAssertNotNil(ReadingTasks.location(ofTaskStartingAt: 2, status: " ", in: "> - [ ] after the quote marker of a callout"))
    }

    // MARK: Parts of an embedded note

    func testEmbeddedPartsKnowWhereTheyStartInTheNote() {
        let body = "Intro\r\n\r\n## One\r\n- [ ] a\r\n\r\n## Two\r\n- [ ] b ^task\r\n\r\nTail"
        let source = body as NSString
        let section = NoteBlocks.locatedEmbeddedPart(of: body, subpath: "Two")
        XCTAssertEqual(section?.location, source.range(of: "## Two").location)
        XCTAssertEqual(section?.text, "## Two\r\n- [ ] b ^task\r\n\r\nTail")
        let block = NoteBlocks.locatedEmbeddedPart(of: body, subpath: "^task")
        XCTAssertEqual(block?.location, source.range(of: "- [ ] b").location)
        XCTAssertEqual(block?.text, "- [ ] b")
        XCTAssertEqual(NoteBlocks.locatedEmbeddedPart(of: body, subpath: nil)?.location, 0)
        XCTAssertNil(NoteBlocks.locatedEmbeddedPart(of: body, subpath: "Missing"))
        XCTAssertEqual(NoteBlocks.embeddedPart(of: body, subpath: "Two"), section?.text)
    }

    func testFootnotePreparationKnowsWhereItsTextWasInTheNote() {
        let text = "Claim[^a] here.\n[^a]: The note.\n    continued\n- [ ] task[^a]\n"
        let prepared = Footnotes.preparedForReadingKeepingOffsets(text) { number in "<\(number)>" }
        XCTAssertEqual(prepared.text, "Claim<1> here.\n- [ ] task<1>\n")
        XCTAssertEqual(prepared.text, Footnotes.preparedForReading(text) { number in "<\(number)>" }.text)
        let taskLineStart = (prepared.text as NSString).range(of: "- [ ] task").location
        XCTAssertEqual(prepared.offsets.originalOffset(of: taskLineStart), (text as NSString).range(of: "- [ ] task").location)
    }
}

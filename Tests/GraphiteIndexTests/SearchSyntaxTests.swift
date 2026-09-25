import XCTest
@testable import GraphiteIndex
import GraphiteCore

final class SearchSyntaxTests: XCTestCase {
    private var directory: URL!
    private var index: VaultIndex!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        index = try VaultIndex(databaseURL: directory.appendingPathComponent("index.sqlite"))
        try await index.update([
            IndexedFile(path: try VaultPath("Exams/Midterm.md"), size: 1, modified: Date(timeIntervalSince1970: 100),
                        markdown: "# Midterm\nThe exam covers sampling. #2026-exam\n- [ ] review chapter 3\n- [x] book room"),
            IndexedFile(path: try VaultPath("Notes/Work.md"), size: 1, modified: Date(timeIntervalSince1970: 300),
                        markdown: "work meeting notes\nmeeting later\n\n## Other\nwork again"),
            IndexedFile(path: try VaultPath("Notes/Meetup.md"), size: 1, modified: Date(timeIntervalSince1970: 200),
                        markdown: "---\nstatus: draft\nduration: 3\n---\nmeetup personal"),
            IndexedFile(path: try VaultPath("Media/photo.jpg"), size: 1, modified: Date(timeIntervalSince1970: 50), markdown: nil),
        ], generation: "test")
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func paths(_ query: String) async throws -> [String] {
        try await index.search(query).results.map(\.path.rawValue).sorted()
    }

    func testExclusionOrAndPhrases() async throws {
        let excluded = try await paths("-exam")
        XCTAssertEqual(excluded, ["Media/photo.jpg", "Notes/Meetup.md", "Notes/Work.md"])
        let either = try await paths("meeting OR meetup")
        XCTAssertEqual(either, ["Notes/Meetup.md", "Notes/Work.md"])
        let meetingWithoutWork = try await paths("meeting -work")
        XCTAssertEqual(meetingWithoutWork, [])
        let phrase = try await paths("\"work meeting\"")
        XCTAssertEqual(phrase, ["Notes/Work.md"])
        let reversedPhrase = try await paths("\"meeting work\"")
        XCTAssertEqual(reversedPhrase, [])
        let grouped = try await paths("(meetup OR exam) -personal")
        XCTAssertEqual(grouped, ["Exams/Midterm.md"])
    }

    func testFileAndPathAndTagOperators() async throws {
        let inFolder = try await paths("path:Exams")
        XCTAssertEqual(inFolder, ["Exams/Midterm.md"])
        let byExtension = try await paths("file:.jpg")
        XCTAssertEqual(byExtension, ["Media/photo.jpg"])
        let tagged = try await paths("tag:#2026-exam")
        XCTAssertEqual(tagged, ["Exams/Midterm.md"])
        let notNested = try await paths("tag:2026")
        XCTAssertEqual(notNested, [])
        let bareTag = try await paths("#2026-exam")
        XCTAssertEqual(bareTag, ["Exams/Midterm.md"])
    }

    func testLineSectionAndTaskOperators() async throws {
        let sameLine = try await paths("line:(meeting later)")
        XCTAssertEqual(sameLine, ["Notes/Work.md"])
        let differentLines = try await paths("line:(notes later)")
        XCTAssertEqual(differentLines, [])
        let sameSection = try await paths("section:(notes later)")
        XCTAssertEqual(sameSection, ["Notes/Work.md"])
        let otherSection = try await paths("section:(later again)")
        XCTAssertEqual(otherSection, [])
        let openTask = try await paths("task-todo:review")
        XCTAssertEqual(openTask, ["Exams/Midterm.md"])
        let doneReview = try await paths("task-done:review")
        XCTAssertEqual(doneReview, [])
        let doneBooking = try await paths("task-done:book")
        XCTAssertEqual(doneBooking, ["Exams/Midterm.md"])
        let noLineWithout = try await paths("-line:(meeting)")
        XCTAssertEqual(noLineWithout, ["Exams/Midterm.md", "Media/photo.jpg", "Notes/Meetup.md"])
    }

    func testPropertiesRegularExpressionsAndCase() async throws {
        let draft = try await paths("[status:draft]")
        XCTAssertEqual(draft, ["Notes/Meetup.md"])
        let hasStatus = try await paths("[status]")
        XCTAssertEqual(hasStatus, ["Notes/Meetup.md"])
        let short = try await paths("[duration:<5]")
        XCTAssertEqual(short, ["Notes/Meetup.md"])
        let long = try await paths("[duration:>5]")
        XCTAssertEqual(long, [])
        let regularExpression = try await paths("/sampl\\w+/")
        XCTAssertEqual(regularExpression, ["Exams/Midterm.md"])
        let exactCase = try await paths("match-case:Midterm")
        XCTAssertEqual(exactCase, ["Exams/Midterm.md"])
        let wrongCase = try await paths("match-case:midterm")
        XCTAssertEqual(wrongCase, [])
        let propertyText = try await paths("draft")
        XCTAssertEqual(propertyText, ["Notes/Meetup.md"], "Property values are searchable text.")
    }

    func testMatchesAreHighlightedAtTheirPositionInTheFile() async throws {
        let samplingResults = try await index.search("sampling").results
        let result = try XCTUnwrap(samplingResults.first)
        let match = try XCTUnwrap(result.matches.first)
        XCTAssertEqual(match.excerpt, "The exam covers sampling. #2026-exam")
        let highlighted = try XCTUnwrap(match.highlightedRanges.first)
        XCTAssertEqual((match.excerpt as NSString).substring(with: NSRange(location: highlighted.lowerBound, length: highlighted.count)), "sampling")
        let note = "# Midterm\nThe exam covers sampling. #2026-exam\n- [ ] review chapter 3\n- [x] book room" as NSString
        XCTAssertEqual(note.substring(with: NSRange(location: match.location, length: match.length)), "sampling")
        let meetingResults = try await index.search("meeting").results
        let several = try XCTUnwrap(meetingResults.first { result in result.path.name == "Work.md" })
        XCTAssertEqual(several.matchCount, 2)
    }

    func testPagesContinueAndSortOrdersApply() async throws {
        let bulkFiles = try (1...120).map { number in
            IndexedFile(path: try VaultPath(String(format: "Bulk/Item %03d.md", number)), size: 1, modified: Date(timeIntervalSince1970: Double(1_000 + number)), markdown: "common text")
        }
        try await index.update(bulkFiles, generation: "bulk")
        let firstPage = try await index.search("common")
        XCTAssertEqual(firstPage.results.count, 50)
        XCTAssertEqual(firstPage.results.first?.path.name, "Item 001.md")
        let secondPage = try await index.search("common", after: firstPage.continuation)
        let thirdPage = try await index.search("common", after: secondPage.continuation)
        XCTAssertEqual(secondPage.results.first?.path.name, "Item 051.md")
        XCTAssertEqual(thirdPage.results.count, 20)
        XCTAssertNil(thirdPage.continuation)
        let newest = try await index.search("common", sortOrder: .modifiedNewestFirst)
        XCTAssertEqual(newest.results.first?.path.name, "Item 120.md")
        let checkedPages = try await index.search("line:(common text)", limit: 30)
        XCTAssertEqual(checkedPages.results.count, 30)
        XCTAssertNotNil(checkedPages.continuation)
    }
}

final class QuickSwitcherTests: XCTestCase {
    func testFuzzyNamesAliasesAndPaths() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let index = try VaultIndex(databaseURL: directory.appendingPathComponent("index.sqlite"))
        try await index.update([
            IndexedFile(path: try VaultPath("Courses/Signals/Lecture notes.md"), size: 1, modified: .now, markdown: "---\naliases: [Fourier basics]\n---\nx"),
            IndexedFile(path: try VaultPath("Balance sheet.md"), size: 1, modified: .now, markdown: "x"),
            IndexedFile(path: try VaultPath("Slides/Lecture 3.pdf"), size: 1, modified: .now, markdown: nil),
        ], generation: "test")
        let byInitials = try await index.quickSwitcherMatches(for: "ln")
        XCTAssertEqual(byInitials.first?.path.name, "Lecture notes.md", "Word starts beat scattered letters.")
        let pdf = try await index.quickSwitcherMatches(for: "lec 3")
        XCTAssertEqual(pdf.first?.path.name, "Lecture 3.pdf")
        let alias = try await index.quickSwitcherMatches(for: "fourier")
        XCTAssertEqual(alias.first?.alias, "Fourier basics")
        XCTAssertEqual(alias.first?.path.name, "Lecture notes.md")
        let byPath = try await index.quickSwitcherMatches(for: "signals/lec")
        XCTAssertEqual(byPath.map(\.path.name), ["Lecture notes.md"])
        let nothing = try await index.quickSwitcherMatches(for: "zzz")
        XCTAssertTrue(nothing.isEmpty)
    }
}

final class TagSuggestionTests: XCTestCase {
    func testTagsAreCountedAndFilteredByText() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let index = try VaultIndex(databaseURL: directory.appendingPathComponent("index.sqlite"))
        try await index.update([
            IndexedFile(path: try VaultPath("A.md"), size: 1, modified: .now, markdown: "#lecture #inbox/todo"),
            IndexedFile(path: try VaultPath("B.md"), size: 1, modified: .now, markdown: "#lecture #exam"),
            IndexedFile(path: try VaultPath("C.md"), size: 1, modified: .now, markdown: "#Lecture"),
        ], generation: "test")
        let lecture = try await index.tags(matching: "lec")
        XCTAssertEqual(lecture.count, 1)
        XCTAssertEqual(lecture.first?.fileCount, 3)
        let all = try await index.tags(matching: "")
        XCTAssertEqual(all.map(\.tag.localizedLowercase), ["lecture", "exam", "inbox/todo"])
    }
}

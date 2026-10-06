import XCTest
@testable import GraphiteIndex
@testable import GraphiteCore

/// Canvases in the index and in renames: a note on a canvas lists the canvas among its
/// backlinks, and moving a note rewrites exactly the file cards and text-card links
/// that name it, byte for byte.
final class CanvasLinkTests: XCTestCase {
    private var vault: URL!
    private var index: VaultIndex!
    private var operations: VaultFileOperations!

    /// A canvas in Obsidian's layout, with a file card for the note, one for a heading of
    /// it, a picture, a group background, text cards that link to the note, a key
    /// Graphite does not know, and a card for another note of the same name elsewhere.
    private let board = "{\n\t\"nodes\":[\n"
        + "\t\t{\"id\":\"a000000000000001\",\"type\":\"file\",\"file\":\"Courses/Lecture.md\",\"x\":0,\"y\":0,\"width\":400,\"height\":400},\n"
        + "\t\t{\"id\":\"a000000000000002\",\"type\":\"file\",\"file\":\"Courses/Lecture.md\",\"subpath\":\"#Summary\",\"x\":500,\"y\":0,\"width\":400,\"height\":400,\"plugin\":{\"keep\":true}},\n"
        + "\t\t{\"id\":\"a000000000000003\",\"type\":\"text\",\"text\":\"See [[Lecture]] and [the notes](Courses/Lecture.md).\\nAlso [[Other]].\",\"x\":0,\"y\":500,\"width\":400,\"height\":100},\n"
        + "\t\t{\"id\":\"a000000000000004\",\"type\":\"file\",\"file\":\"Pictures/diagram 100%.png\",\"x\":500,\"y\":500,\"width\":400,\"height\":300},\n"
        + "\t\t{\"id\":\"a000000000000005\",\"type\":\"group\",\"x\":-20,\"y\":-20,\"width\":1000,\"height\":900,\"background\":\"Pictures/diagram 100%.png\",\"backgroundStyle\":\"cover\"},\n"
        + "\t\t{\"id\":\"a000000000000006\",\"type\":\"file\",\"file\":\"Archive/Old lecture.md\",\"x\":1000,\"y\":0,\"width\":400,\"height\":400}\n"
        + "\t],\n\t\"edges\":[\n"
        + "\t\t{\"id\":\"e000000000000001\",\"fromNode\":\"a000000000000001\",\"fromSide\":\"right\",\"toNode\":\"a000000000000002\",\"toSide\":\"left\"}\n"
        + "\t]\n}"

    override func setUp() async throws {
        vault = FileManager.default.temporaryDirectory.appendingPathComponent("CanvasVault-\(UUID().uuidString)")
        for folder in ["Courses", "Pictures", "Boards", "Archive"] {
            try FileManager.default.createDirectory(at: vault.appendingPathComponent(folder), withIntermediateDirectories: true)
        }
        try write("Courses/Lecture.md", "# Lecture\n\n## Summary\n\nText.\n")
        try write("Archive/Old lecture.md", "old")
        try write("Other.md", "other")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: vault.appendingPathComponent("Pictures/diagram 100%.png"))
        try write("Boards/Study.canvas", board)
        try write("Boards/Broken.canvas", "{\"nodes\":[{\"id\":\"x\",\"type\":\"file\",\"file\":\"Courses/Lecture.md\"")
        try write("Linking.md", "A link to [[Courses/Lecture]].")
        index = try VaultIndex(databaseURL: vault.appendingPathExtension("cache").appendingPathComponent("index.sqlite"))
        _ = try await index.reconcile(root: vault)
        operations = VaultFileOperations(store: VaultStore(root: vault), index: index)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: vault)
        try? FileManager.default.removeItem(at: vault.appendingPathExtension("cache"))
    }

    private func write(_ relativePath: String, _ text: String) throws {
        try Data(text.utf8).write(to: vault.appendingPathComponent(relativePath))
    }

    private func read(_ relativePath: String) throws -> String {
        try String(contentsOf: vault.appendingPathComponent(relativePath), encoding: .utf8)
    }

    func testANoteOnACanvasListsTheCanvasAmongItsBacklinks() async throws {
        let backlinks = try await index.backlinks(to: VaultPath("Courses/Lecture.md"))
        XCTAssertEqual(Set(backlinks.map(\.rawValue)), ["Boards/Study.canvas", "Linking.md"])
        let pictureBacklinks = try await index.backlinks(to: VaultPath("Pictures/diagram 100%.png"))
        XCTAssertEqual(pictureBacklinks.map(\.rawValue), ["Boards/Study.canvas"], "A file card's path is kept exactly, a percent sign included.")
        let archiveBacklinks = try await index.backlinks(to: VaultPath("Archive/Old lecture.md"))
        XCTAssertEqual(archiveBacklinks.map(\.rawValue), ["Boards/Study.canvas"])
        let otherBacklinks = try await index.backlinks(to: VaultPath("Other.md"))
        XCTAssertEqual(otherBacklinks.map(\.rawValue), ["Boards/Study.canvas"], "Links in text cards count too.")
        let linkingNotes = try await index.linkingNotes(to: VaultPath("Courses/Lecture.md"))
        XCTAssertEqual(linkingNotes.map(\.rawValue).sorted(), ["Boards/Study.canvas", "Linking.md"])
    }

    func testAFileCardNamesItsFileByTheWholePathNotANoteBesideTheCanvas() async throws {
        // A note named like the card's file, but beside the canvas, is not what the card shows.
        try write("Boards/Lecture.md", "beside")
        try write("Boards/Only cards.canvas", #"{"nodes":[{"id":"n","type":"file","file":"Courses/Lecture.md","x":0,"y":0,"width":10,"height":10}]}"#)
        try await index.refresh(paths: [VaultPath("Boards/Lecture.md"), VaultPath("Boards/Only cards.canvas")], root: vault)
        let besideBacklinks = try await index.backlinks(to: VaultPath("Boards/Lecture.md"))
        XCTAssertFalse(besideBacklinks.contains(try VaultPath("Boards/Only cards.canvas")))
        let namedBacklinks = try await index.backlinks(to: VaultPath("Courses/Lecture.md"))
        XCTAssertTrue(namedBacklinks.contains(try VaultPath("Boards/Only cards.canvas")))
    }

    func testCanvasesAreNotSearchedAsText() async throws {
        let page = try await index.search("content:\"periodic\"")
        XCTAssertTrue(page.results.isEmpty)
        let named = try await index.search("Study")
        XCTAssertEqual(named.results.map(\.path.rawValue), ["Boards/Study.canvas"], "A canvas is still found by its name.")
    }

    func testRenamingANoteRewritesExactlyItsFileCardsAndTextCardLinks() async throws {
        let plan = try await operations.linkUpdates(forMoving: VaultPath("Courses/Lecture.md"), to: VaultPath("Courses/Week 1/Fourier.md"))
        let canvasUpdate = try XCTUnwrap(plan.updates.first { update in update.path.rawValue == "Boards/Study.canvas" })
        XCTAssertEqual(canvasUpdate.changedLinkCount, 4, "Two file cards and two links in a text card")
        let report = try await operations.move(VaultPath("Courses/Lecture.md"), to: VaultPath("Courses/Week 1/Fourier.md"), applying: plan)
        XCTAssertTrue(report.updatedNotes.contains(try VaultPath("Boards/Study.canvas")))
        let expected = board
            .replacingOccurrences(of: "\"file\":\"Courses/Lecture.md\"", with: "\"file\":\"Courses/Week 1/Fourier.md\"")
            .replacingOccurrences(of: "See [[Lecture]] and [the notes](Courses/Lecture.md).", with: "See [[Fourier]] and [the notes](Courses/Week%201/Fourier.md).")
        XCTAssertEqual(try read("Boards/Study.canvas"), expected, "Only the file cards and the links change; the card for the other note, the unknown key and the layout stay.")
        XCTAssertEqual(try read("Boards/Broken.canvas"), "{\"nodes\":[{\"id\":\"x\",\"type\":\"file\",\"file\":\"Courses/Lecture.md\"",
                       "A damaged canvas names nothing the index knows of, and is left as it was.")
    }

    func testACanvasDamagedSinceItWasReadIsReportedAndLeftAlone() async throws {
        let damaged = board.replacingOccurrences(of: "\t]\n}", with: "")
        try write("Boards/Study.canvas", damaged)
        let plan = try await operations.linkUpdates(forMoving: VaultPath("Courses/Lecture.md"), to: VaultPath("Courses/Renamed.md"))
        let report = try await operations.move(VaultPath("Courses/Lecture.md"), to: VaultPath("Courses/Renamed.md"), applying: plan)
        XCTAssertEqual(report.failures[try VaultPath("Boards/Study.canvas")], .linksNotLocated)
        XCTAssertEqual(try read("Boards/Study.canvas"), damaged)
        XCTAssertEqual(try read("Linking.md"), "A link to [[Courses/Renamed]].", "The notes that can be updated still are.")
    }

    func testMovingAFolderRewritesCardsForEveryFileInIt() async throws {
        let plan = try await operations.linkUpdates(forMoving: VaultPath("Pictures"), to: VaultPath("Media/Pictures"))
        _ = try await operations.move(VaultPath("Pictures"), to: VaultPath("Media/Pictures"), applying: plan)
        XCTAssertEqual(try read("Boards/Study.canvas"), board.replacingOccurrences(of: "Pictures/diagram 100%.png", with: "Media/Pictures/diagram 100%.png"),
                       "The picture card and the group's background follow the folder.")
    }

    func testMovingTheCanvasItselfKeepsItsFileCards() async throws {
        let plan = try await operations.linkUpdates(forMoving: VaultPath("Boards/Study.canvas"), to: VaultPath("Study.canvas"))
        _ = try await operations.move(VaultPath("Boards/Study.canvas"), to: VaultPath("Study.canvas"), applying: plan)
        XCTAssertEqual(try read("Study.canvas"), board, "File cards name files from the vault's root, so a moved canvas needs no change.")
    }

    func testARenameTheCanvasDoesNotMentionLeavesItByteForByte() async throws {
        let plan = try await operations.linkUpdates(forMoving: VaultPath("Linking.md"), to: VaultPath("Linked.md"))
        XCTAssertFalse(plan.updates.contains { update in update.path.rawValue == "Boards/Study.canvas" })
        _ = try await operations.move(VaultPath("Linking.md"), to: VaultPath("Linked.md"), applying: plan)
        XCTAssertEqual(try read("Boards/Study.canvas"), board)
    }

    func testACanvasWithAByteOrderMarkAndWindowsLineEndingsKeepsThemWhenUpdated() async throws {
        let windowsBoard = "\u{FEFF}{\r\n  \"nodes\": [\r\n    {\"id\": \"n\", \"type\": \"file\", \"file\": \"Other.md\", \"x\": 0, \"y\": 0, \"width\": 10, \"height\": 10}\r\n  ]\r\n}\r\n"
        try write("Boards/Windows.canvas", windowsBoard)
        try await index.refresh(paths: [VaultPath("Boards/Windows.canvas")], root: vault)
        let plan = try await operations.linkUpdates(forMoving: VaultPath("Other.md"), to: VaultPath("Renamed.md"))
        _ = try await operations.move(VaultPath("Other.md"), to: VaultPath("Renamed.md"), applying: plan)
        let written = try Data(contentsOf: vault.appendingPathComponent("Boards/Windows.canvas"))
        XCTAssertEqual(written, Data(windowsBoard.replacingOccurrences(of: "\"Other.md\"", with: "\"Renamed.md\"").utf8))
        XCTAssertTrue(written.starts(with: [0xEF, 0xBB, 0xBF]))
    }
}

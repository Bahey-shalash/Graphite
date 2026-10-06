import XCTest
import CoreGraphics
@testable import GraphiteCore

/// Every edit must change only the bytes of what it names, and undo must give the file
/// back byte for byte.
final class CanvasEditingTests: XCTestCase {
    /// Applies `changes` and returns the new file's text, checking on the way that the
    /// undo patch restores the original bytes and that redoing gives the edit again.
    @discardableResult
    private func edited(_ text: String, _ changes: [CanvasChange], file sourceFile: StaticString = #filePath, line: UInt = #line) throws -> String {
        let original = try CanvasFixtures.file(text)
        let result = try original.applying(changes)
        let undone = try result.file.applying(result.undoPatch)
        XCTAssertEqual(String(decoding: undone.file.data, as: UTF8.self), text, "Undo restores the file byte for byte", file: sourceFile, line: line)
        let redone = try undone.file.applying(undone.undoPatch)
        XCTAssertEqual(redone.file.data, result.file.data, "Redo gives the edit again", file: sourceFile, line: line)
        return String(decoding: result.file.data, as: UTF8.self)
    }

    // MARK: Nothing changed

    func testAnEditThatChangesNothingKeepsEveryByte() throws {
        let text = "{ \"nodes\" : [ {\"id\":\"a\",\"type\":\"text\",\"text\":\"\\u0041\\/b\",\"x\":10.0,\"y\":-2e1,\"width\":250,\"height\":60,\"color\":\"1\"} ],\n \"edges\":[{\"id\":\"e\",\"fromNode\":\"a\",\"toNode\":\"a\",\"toEnd\":\"arrow\",\"label\":\"l\"}] }"
        let file = try CanvasFixtures.file(text)
        let result = try file.applying([
            .setFrames(["a": CGRect(x: 10, y: -20, width: 250, height: 60)]),
            .setText("A/b", nodeIdentifier: "a"),
            .setNodeColor(.preset(1), nodeIdentifiers: ["a"]),
            .setEdgeLabel("l", edgeIdentifier: "e"),
            .setEdgeEnds(fromEnd: .none, toEnd: .arrow, edgeIdentifiers: ["e"]),
            .setEdgeColor(nil, edgeIdentifiers: ["e"]),
            .moveToFront(nodeIdentifiers: ["a"]),
            .remove(nodeIdentifiers: [], edgeIdentifiers: []),
            .add(nodes: [], edges: []),
        ])
        XCTAssertEqual(String(decoding: result.file.data, as: UTF8.self), text,
                       "Numbers written as 10.0 or -2e1, escapes such as \\u0041 and an explicit default end stay as written when their meaning does not change.")
        XCTAssertTrue(result.undoPatch.isEmpty)
    }

    // MARK: Moving and resizing

    func testMovingACardChangesOnlyItsPosition() throws {
        let moved = try edited(CanvasFixtures.obsidianBoard, [.setFrames(["0f1e2d3c4b5a6978": CGRect(x: -400, y: -260, width: 320, height: 200)])])
        XCTAssertEqual(moved, CanvasFixtures.obsidianBoard.replacingOccurrences(of: "\"x\":-380,\"y\":-260,\"width\":320,\"height\":200}", with: "\"x\":-400,\"y\":-260,\"width\":320,\"height\":200}"))
        XCTAssertEqual(moved.utf8.count, CanvasFixtures.obsidianBoard.utf8.count)
    }

    func testResizingWritesWholePixelsAndKeepsUnknownKeysAndLayout() throws {
        let text = "{\r\n  \"nodes\": [\r\n    {\r\n      \"id\": \"a\",\r\n      \"x\": 0,\r\n      \"y\": 0,\r\n      \"width\": 100,\r\n      \"plugin\": {\"keep\": [1, 2]},\r\n      \"height\": 50,\r\n      \"type\": \"text\",\r\n      \"text\": \"t\"\r\n    }\r\n  ]\r\n}\r\n"
        let resized = try edited(text, [.setFrames(["a": CGRect(x: 0.4, y: -0.6, width: 119.5, height: 50.2)])])
        XCTAssertEqual(resized, text.replacingOccurrences(of: "\"y\": 0,", with: "\"y\": -1,").replacingOccurrences(of: "\"width\": 100,", with: "\"width\": 120,"))
    }

    func testMovingManyCardsOfALargeBoardLeavesTheOthersUntouched() throws {
        let cardCount = 5_000
        let text = CanvasFixtures.largeBoard(cardCount: cardCount)
        let file = try CanvasFixtures.file(text)
        var frames: [String: CGRect] = [:]
        for cardIndex in stride(from: 0, to: cardCount, by: 5) {
            frames[CanvasFixtures.identifier(cardIndex)] = file.nodes[cardIndex].frame.offsetBy(dx: 7, dy: -13)
        }
        let start = ContinuousClock.now
        let result = try file.applying([.setFrames(frames)])
        let elapsed = ContinuousClock.now - start
        print("Canvas measurement: moved \(frames.count) of \(cardCount) cards in \(elapsed)")
        let originalLines = text.components(separatedBy: "\n"), editedLines = String(decoding: result.file.data, as: UTF8.self).components(separatedBy: "\n")
        XCTAssertEqual(originalLines.count, editedLines.count)
        for (lineIndex, originalLine) in originalLines.enumerated() {
            let cardIndex = lineIndex - 2
            if (0..<cardCount).contains(cardIndex), cardIndex % 5 == 0 {
                XCTAssertNotEqual(editedLines[lineIndex], originalLine)
            } else if editedLines[lineIndex] != originalLine {
                return XCTFail("Line \(lineIndex) changed though its card did not move")
            }
        }
        XCTAssertEqual(result.file.nodes[10].frame, file.nodes[10].frame.offsetBy(dx: 7, dy: -13))
        XCTAssertEqual(try result.file.applying(result.undoPatch).file.data, file.data)
    }

    // MARK: Adding

    func testFirstCardOfAnEmptyCanvasIsWrittenAsObsidianWritesIt() throws {
        let card = CanvasNode(id: "0123456789abcdef", content: .text("Hello \"you\"\nline\ttab \\ é 😀"), frame: CGRect(x: -125, y: -30, width: 250, height: 60))
        let expected = "{\n\t\"nodes\":[\n\t\t{\"id\":\"0123456789abcdef\",\"type\":\"text\",\"text\":\"Hello \\\"you\\\"\\nline\\ttab \\\\ é 😀\",\"x\":-125,\"y\":-30,\"width\":250,\"height\":60}\n\t]\n}"
        XCTAssertEqual(try edited("{}", [.add(nodes: [card], edges: [])]), expected)
        XCTAssertEqual(try CanvasFile(data: Data()).applying([.add(nodes: [card], edges: [])]).file.data, Data(expected.utf8), "A file with nothing in it becomes a canvas.")
        XCTAssertEqual(try CanvasFixtures.file(expected).nodes, [card])
    }

    func testAddedCardsAndConnectionsFollowTheLayoutOfTheFile() throws {
        let note = CanvasNode(id: "aaaaaaaaaaaaaaaa", content: .file(path: "Notes/A B.md", subpath: "#Heading"), frame: CGRect(x: 0, y: 0, width: 400, height: 400), color: .preset(2))
        let link = CanvasNode(id: "bbbbbbbbbbbbbbbb", content: .link(address: "https://example.com/?q=1"), frame: CGRect(x: 500, y: 0, width: 300, height: 200))
        let group = CanvasNode(id: "cccccccccccccccc", content: .group(label: "Group", background: nil, backgroundStyle: .cover), frame: CGRect(x: -20, y: -20, width: 900, height: 500),
                               color: .custom(red: 1, green: 2, blue: 3))
        let edge = CanvasEdge(id: "dddddddddddddddd", fromNode: "aaaaaaaaaaaaaaaa", toNode: "bbbbbbbbbbbbbbbb", fromSide: .right, toSide: .left, fromEnd: .arrow, toEnd: .none, color: .preset(5), label: "to")
        let noteText = ##"{"id":"aaaaaaaaaaaaaaaa","type":"file","file":"Notes/A B.md","subpath":"#Heading","x":0,"y":0,"width":400,"height":400,"color":"2"}"##
        let linkText = #"{"id":"bbbbbbbbbbbbbbbb","type":"link","url":"https://example.com/?q=1","x":500,"y":0,"width":300,"height":200}"#
        let groupText = ##"{"id":"cccccccccccccccc","type":"group","x":-20,"y":-20,"width":900,"height":500,"color":"#010203","label":"Group"}"##
        let edgeText = #"{"id":"dddddddddddddddd","fromNode":"aaaaaaaaaaaaaaaa","fromSide":"right","fromEnd":"arrow","toNode":"bbbbbbbbbbbbbbbb","toSide":"left","toEnd":"none","color":"5","label":"to"}"#
        let changes: [CanvasChange] = [.add(nodes: [note, link, group], edges: [edge])]

        // Obsidian's layout: appended on their own lines.
        let obsidian = try edited(CanvasFixtures.specificationSample, changes)
        XCTAssertEqual(obsidian, CanvasFixtures.specificationSample
            .replacingOccurrences(of: "\"height\":400}\n\t],", with: "\"height\":400},\n\t\t\(noteText),\n\t\t\(linkText),\n\t\t\(groupText)\n\t],")
            .replacingOccurrences(of: "\"toSide\":\"left\"}\n\t]", with: "\"toSide\":\"left\"},\n\t\t\(edgeText)\n\t]"))

        // One line, no spaces.
        XCTAssertEqual(try edited(#"{"nodes":[{"id":"x","type":"text","text":"","x":0,"y":0,"width":1,"height":1}],"edges":[]}"#, changes),
                       #"{"nodes":[{"id":"x","type":"text","text":"","x":0,"y":0,"width":1,"height":1},"# + noteText + "," + linkText + "," + groupText + #"],"edges":["# + edgeText + "]}")

        // Two-space indentation and Windows line endings, with empty lists.
        XCTAssertEqual(try edited("{\r\n  \"nodes\": [],\r\n  \"edges\": []\r\n}\r\n", [.add(nodes: [link], edges: [edge])]),
                       "{\r\n  \"nodes\": [\r\n    \(linkText)\r\n  ],\r\n  \"edges\": [\r\n    \(edgeText)\r\n  ]\r\n}\r\n")

        // Lists that are missing are added after the keys that are there, in their style.
        XCTAssertEqual(try edited("{\n  \"future\": {\"a\": 1}\n}", [.add(nodes: [link], edges: [edge])]),
                       "{\n  \"future\": {\"a\": 1},\n  \"nodes\": [\n    \(linkText)\n  ],\n  \"edges\": [\n    \(edgeText)\n  ]\n}")
        XCTAssertEqual(try edited(#"{"nodes":null,"edges":[]}"#, [.add(nodes: [link], edges: [])]), #"{"nodes":["# + linkText + #"],"edges":[]}"#)
    }

    func testNewIdentifiersAreSixteenHexadecimalDigitsAndUnused() throws {
        let file = try CanvasFixtures.file(CanvasFixtures.obsidianBoard)
        var seen: Set<String> = []
        for _ in 0..<200 {
            let identifier = file.newIdentifier(avoiding: seen)
            XCTAssertEqual(identifier.count, 16)
            XCTAssertTrue(identifier.allSatisfy { character in character.isHexDigit && !character.isUppercase }, identifier)
            XCTAssertNil(file.node(named: identifier))
            XCTAssertTrue(seen.insert(identifier).inserted)
        }
        struct RepeatingGenerator: RandomNumberGenerator {
            var values: [UInt64]
            mutating func next() -> UInt64 { values.count > 1 ? values.removeFirst() : values[0] }
        }
        var generator = RepeatingGenerator(values: [0xa1b2c3d4e5f60718, 0xe1e1e1e1e1e1e1e1, 0x5, 0x2a])
        XCTAssertEqual(file.newIdentifier(avoiding: ["0000000000000005"], using: &generator), "000000000000002a",
                       "Identifiers of cards and connections already in the file, and those just handed out, are passed over.")
    }

    // MARK: Editing values

    func testTextColorsLabelsAndEndsChangeOnlyTheirOwnValues() throws {
        let board = CanvasFixtures.obsidianBoard
        XCTAssertEqual(try edited(board, [.setText("New *text*\nsecond \"line\"", nodeIdentifier: "0f1e2d3c4b5a6978")]),
                       board.replacingOccurrences(of: "\"text\":\"# Fourier series\\n\\nA periodic signal is a sum of **sinusoids**.\"", with: "\"text\":\"New *text*\\nsecond \\\"line\\\"\""))
        // A color that is there is replaced, one that is not is added last, and none removes it.
        XCTAssertEqual(try edited(board, [.setNodeColor(.preset(2), nodeIdentifiers: ["a1b2c3d4e5f60718"])]), board.replacingOccurrences(of: "\"color\":\"4\"", with: "\"color\":\"2\""))
        XCTAssertEqual(try edited(board, [.setNodeColor(.custom(red: 0, green: 128, blue: 255), nodeIdentifiers: ["99aabbccddeeff00"])]),
                       board.replacingOccurrences(of: "\"width\":320,\"height\":180}", with: "\"width\":320,\"height\":180,\"color\":\"#0080ff\"}"))
        XCTAssertEqual(try edited(board, [.setNodeColor(nil, nodeIdentifiers: ["1122334455667788", "99aabbccddeeff00"])]), board.replacingOccurrences(of: ",\"color\":\"#ff8800\"", with: ""))
        XCTAssertEqual(try edited(board, [.setEdgeColor(.preset(6), edgeIdentifiers: ["e1e1e1e1e1e1e1e1", "e2e2e2e2e2e2e2e2"])]),
                       board.replacingOccurrences(of: "\"label\":\"proved in\"}", with: "\"label\":\"proved in\",\"color\":\"6\"}").replacingOccurrences(of: "\"color\":\"1\"}", with: "\"color\":\"6\"}"))
        XCTAssertEqual(try edited(board, [.setGroupLabel("Week 4", nodeIdentifier: "a1b2c3d4e5f60718")]), board.replacingOccurrences(of: "\"label\":\"Week 3\"", with: "\"label\":\"Week 4\""))
        XCTAssertEqual(try edited(board, [.setGroupLabel("", nodeIdentifier: "a1b2c3d4e5f60718")]), board.replacingOccurrences(of: ",\"label\":\"Week 3\"", with: ""))
        XCTAssertEqual(try edited(board, [.setEdgeLabel("", edgeIdentifier: "e1e1e1e1e1e1e1e1")]), board.replacingOccurrences(of: ",\"label\":\"proved in\"", with: ""))
        XCTAssertEqual(try edited(board, [.setEdgeLabel("see", edgeIdentifier: "e2e2e2e2e2e2e2e2")]), board.replacingOccurrences(of: "\"color\":\"1\"}", with: "\"color\":\"1\",\"label\":\"see\"}"))
        // Ends: the defaults are left out, as Obsidian leaves them out.
        XCTAssertEqual(try edited(board, [.setEdgeEnds(fromEnd: .arrow, toEnd: .arrow, edgeIdentifiers: ["e1e1e1e1e1e1e1e1"])]),
                       board.replacingOccurrences(of: "\"label\":\"proved in\"}", with: "\"label\":\"proved in\",\"fromEnd\":\"arrow\"}"))
        XCTAssertEqual(try edited(board, [.setEdgeEnds(fromEnd: .none, toEnd: .arrow, edgeIdentifiers: ["e2e2e2e2e2e2e2e2"])]),
                       board.replacingOccurrences(of: ",\"fromEnd\":\"arrow\"", with: "").replacingOccurrences(of: ",\"toEnd\":\"none\"", with: ""))
        XCTAssertEqual(try edited(board, [.setEdgeEnds(fromEnd: .arrow, toEnd: .arrow, edgeIdentifiers: ["e2e2e2e2e2e2e2e2"])]), board.replacingOccurrences(of: ",\"toEnd\":\"none\"", with: ""))
    }

    func testKeysAreAddedInTheObjectsOwnStyle() throws {
        let pretty = "{\n  \"nodes\": [\n    {\n      \"id\": \"a\",\n      \"type\": \"group\",\n      \"x\": 0,\n      \"y\": 0,\n      \"width\": 10,\n      \"height\": 10\n    }\n  ]\n}\n"
        XCTAssertEqual(try edited(pretty, [.setGroupLabel("L", nodeIdentifier: "a"), .setNodeColor(.preset(3), nodeIdentifiers: ["a"])]),
                       pretty.replacingOccurrences(of: "\"height\": 10\n", with: "\"height\": 10,\n      \"label\": \"L\",\n      \"color\": \"3\"\n"))
        XCTAssertEqual(try edited(pretty, [.setNodeColor(.preset(3), nodeIdentifiers: ["a"]), .setNodeColor(nil, nodeIdentifiers: ["a"])]), pretty,
                       "Adding a key and removing it again gives the file back.")
    }

    func testEditingOneOfTwoKeysWrittenTwiceChangesTheOneThatCounts() throws {
        let text = #"{"nodes":[{"id":"n","type":"text","text":"first","text":"last","x":0,"y":0,"width":1,"height":1}]}"#
        XCTAssertEqual(try edited(text, [.setText("new", nodeIdentifier: "n")]), text.replacingOccurrences(of: "\"last\"", with: "\"new\""))
    }

    // MARK: Removing

    func testRemovingCardsTakesTheirConnectionsAndKeepsTheOtherLines() throws {
        let board = CanvasFixtures.obsidianBoard
        // The middle card, and the connection that ends at it.
        XCTAssertEqual(try edited(board, [.remove(nodeIdentifiers: ["1122334455667788"], edgeIdentifiers: [])]),
                       board.replacingOccurrences(of: ",\n\t\t{\"id\":\"1122334455667788\",\"type\":\"file\",\"file\":\"Courses/Signals/Lecture 3.md\",\"subpath\":\"#Convergence\",\"x\":0,\"y\":-260,\"width\":400,\"height\":400,\"color\":\"#ff8800\"}", with: "")
                           .replacingOccurrences(of: "\t\t{\"id\":\"e1e1e1e1e1e1e1e1\",\"fromNode\":\"0f1e2d3c4b5a6978\",\"fromSide\":\"right\",\"toNode\":\"1122334455667788\",\"toSide\":\"left\",\"label\":\"proved in\"},\n", with: ""))
        // The first and the last card, and one connection by name.
        let withoutEnds = try edited(board, [.remove(nodeIdentifiers: ["a1b2c3d4e5f60718", "deadbeefcafef00d"], edgeIdentifiers: ["e2e2e2e2e2e2e2e2"])])
        XCTAssertEqual(withoutEnds, board
            .replacingOccurrences(of: "\t\t{\"id\":\"a1b2c3d4e5f60718\",\"type\":\"group\",\"x\":-420,\"y\":-320,\"width\":900,\"height\":560,\"color\":\"4\",\"label\":\"Week 3\"},\n", with: "")
            .replacingOccurrences(of: ",\n\t\t{\"id\":\"deadbeefcafef00d\",\"type\":\"link\",\"url\":\"https://en.wikipedia.org/wiki/Fourier_series\",\"x\":520,\"y\":-260,\"width\":360,\"height\":240}", with: "")
            .replacingOccurrences(of: ",\n\t\t{\"id\":\"e2e2e2e2e2e2e2e2\",\"fromNode\":\"99aabbccddeeff00\",\"fromSide\":\"top\",\"fromEnd\":\"arrow\",\"toNode\":\"0f1e2d3c4b5a6978\",\"toSide\":\"bottom\",\"toEnd\":\"none\",\"color\":\"1\"}", with: ""))
        // Everything.
        let everyCard = Set(try CanvasFixtures.file(board).nodes.map(\.id))
        XCTAssertEqual(try edited(board, [.remove(nodeIdentifiers: everyCard, edgeIdentifiers: [])]), "{\n\t\"nodes\":[],\n\t\"edges\":[]\n}")
    }

    func testRemovingKeepsEntriesGraphiteCannotShow() throws {
        let text = #"{"nodes":[{"id":"a","type":"text","text":"","x":0,"y":0,"width":1,"height":1}, {"broken":true} ,{"id":"b","type":"text","text":"","x":0,"y":0,"width":1,"height":1}],"edges":[{"id":"e","fromNode":"a","toNode":"b"},{"id":"kept","fromNode":"b","toNode":"b"},{"odd":1}],"other":[1,2]}"#
        XCTAssertEqual(try edited(text, [.remove(nodeIdentifiers: ["a"], edgeIdentifiers: [])]),
                       #"{"nodes":[{"broken":true} ,{"id":"b","type":"text","text":"","x":0,"y":0,"width":1,"height":1}],"edges":[{"id":"kept","fromNode":"b","toNode":"b"},{"odd":1}],"other":[1,2]}"#)
        XCTAssertThrowsError(try CanvasFixtures.file(text).applying([.remove(nodeIdentifiers: ["gone"], edgeIdentifiers: [])])) { error in
            XCTAssertEqual(error as? CanvasFileError, .missingItem)
        }
    }

    // MARK: Order and copies

    func testBringingToFrontAndSendingToBackMoveWholeEntries() throws {
        let text = "{\n\t\"nodes\":[\n\t\t{\"id\":\"a\",\"x\":0,\"y\":0,\"width\":1,\"height\":1,\"type\":\"text\",\"text\":\"A\"},\n\t\t{\"id\":\"b\",\"x\":0,\"y\":0,\"width\":1,\"height\":1,\"type\":\"text\",\"text\":\"B\",\"extra\":{\"k\":[1]}},\n\t\t{\"id\":\"c\",\"x\":0,\"y\":0,\"width\":1,\"height\":1,\"type\":\"text\",\"text\":\"C\"},\n\t\t{\"id\":\"d\",\"x\":0,\"y\":0,\"width\":1,\"height\":1,\"type\":\"text\",\"text\":\"D\"}\n\t]\n}"
        func lines(_ order: String) -> String {
            let cardLines = ["a": "{\"id\":\"a\",\"x\":0,\"y\":0,\"width\":1,\"height\":1,\"type\":\"text\",\"text\":\"A\"}",
                             "b": "{\"id\":\"b\",\"x\":0,\"y\":0,\"width\":1,\"height\":1,\"type\":\"text\",\"text\":\"B\",\"extra\":{\"k\":[1]}}",
                             "c": "{\"id\":\"c\",\"x\":0,\"y\":0,\"width\":1,\"height\":1,\"type\":\"text\",\"text\":\"C\"}",
                             "d": "{\"id\":\"d\",\"x\":0,\"y\":0,\"width\":1,\"height\":1,\"type\":\"text\",\"text\":\"D\"}"]
            return "{\n\t\"nodes\":[\n\t\t" + order.map { name in cardLines[String(name)] ?? "" }.joined(separator: ",\n\t\t") + "\n\t]\n}"
        }
        XCTAssertEqual(text, lines("abcd"))
        XCTAssertEqual(try edited(text, [.moveToFront(nodeIdentifiers: ["b"])]), lines("acdb"))
        XCTAssertEqual(try edited(text, [.moveToFront(nodeIdentifiers: ["a", "c"])]), lines("bdac"))
        XCTAssertEqual(try edited(text, [.moveToBack(nodeIdentifiers: ["d"])]), lines("dabc"))
        XCTAssertEqual(try edited(text, [.moveToBack(nodeIdentifiers: ["b", "d"])]), lines("bdac"))
        XCTAssertEqual(try edited(text, [.moveToFront(nodeIdentifiers: ["d"])]), text, "The top card is already in front.")
        XCTAssertEqual(try CanvasFixtures.file(lines("acdb")).nodes.map(\.id), ["a", "c", "d", "b"], "The last card in the file is drawn on top.")
    }

    func testACopyKeepsEverythingWrittenInTheCard() throws {
        let text = #"{"nodes":[{"id":"a","type":"mindmap","x":10,"y":20,"width":100,"height":50,"children":[{"n":1}],"color":"3"},{"id":"b","type":"text","text":"B","x":200,"y":20,"width":100,"height":50}],"edges":[{"id":"e","fromNode":"a","toNode":"b","plugin":"keep","label":"l"}]}"#
        let copied = try edited(text, [.duplicate(nodes: [CanvasNodeCopy(sourceIdentifier: "a", newIdentifier: "1111111111111111", origin: CGPoint(x: 30, y: 40)),
                                                        CanvasNodeCopy(sourceIdentifier: "b", newIdentifier: "2222222222222222", origin: CGPoint(x: 220, y: 40))],
                                                edges: [CanvasEdgeCopy(sourceIdentifier: "e", newIdentifier: "3333333333333333", fromNode: "1111111111111111", toNode: "2222222222222222")])])
        XCTAssertEqual(copied, #"{"nodes":[{"id":"a","type":"mindmap","x":10,"y":20,"width":100,"height":50,"children":[{"n":1}],"color":"3"},{"id":"b","type":"text","text":"B","x":200,"y":20,"width":100,"height":50},{"id":"1111111111111111","type":"mindmap","x":30,"y":40,"width":100,"height":50,"children":[{"n":1}],"color":"3"},{"id":"2222222222222222","type":"text","text":"B","x":220,"y":40,"width":100,"height":50}],"edges":[{"id":"e","fromNode":"a","toNode":"b","plugin":"keep","label":"l"},{"id":"3333333333333333","fromNode":"1111111111111111","toNode":"2222222222222222","plugin":"keep","label":"l"}]}"#)
        XCTAssertThrowsError(try CanvasFixtures.file(text).applying([.add(nodes: [CanvasNode(id: "new", content: .unknown(type: "mindmap"), frame: CGRect(x: 0, y: 0, width: 1, height: 1))], edges: [])]),
                             "A card of a type Graphite does not know can be copied, not made from nothing.")
    }

    // MARK: Sequences

    func testALongSequenceOfEditsUndoesToTheOriginalBytesStepByStep() throws {
        let original = try CanvasFixtures.file(CanvasFixtures.obsidianBoard)
        var file = original
        var undoPatches: [CanvasPatch] = []
        var texts: [Data] = [file.data]
        let steps: [[CanvasChange]] = [
            [.add(nodes: [CanvasNode(id: "f00dfacef00dface", content: .text("new"), frame: CGRect(x: 1000, y: 0, width: 250, height: 60))], edges: [])],
            [.add(nodes: [], edges: [CanvasEdge(id: "abcdabcdabcdabcd", fromNode: "f00dfacef00dface", toNode: "deadbeefcafef00d", fromSide: .left, toSide: .right)])],
            [.setFrames(["f00dfacef00dface": CGRect(x: 1040, y: 20, width: 300, height: 100), "a1b2c3d4e5f60718": CGRect(x: -440, y: -340, width: 900, height: 560)])],
            [.setText("# Edited", nodeIdentifier: "f00dfacef00dface"), .setNodeColor(.preset(5), nodeIdentifiers: ["f00dfacef00dface", "0f1e2d3c4b5a6978"])],
            [.moveToBack(nodeIdentifiers: ["f00dfacef00dface"]), .setEdgeEnds(fromEnd: .arrow, toEnd: .none, edgeIdentifiers: ["abcdabcdabcdabcd"])],
            [.remove(nodeIdentifiers: ["0f1e2d3c4b5a6978"], edgeIdentifiers: [])],
            [.remove(nodeIdentifiers: ["f00dfacef00dface", "99aabbccddeeff00", "deadbeefcafef00d", "1122334455667788", "a1b2c3d4e5f60718"], edgeIdentifiers: [])],
        ]
        for changes in steps {
            let result = try file.applying(changes)
            file = result.file
            undoPatches.append(result.undoPatch)
            texts.append(file.data)
        }
        XCTAssertEqual(String(decoding: file.data, as: UTF8.self), "{\n\t\"nodes\":[],\n\t\"edges\":[]\n}")
        for stepIndex in steps.indices.reversed() {
            file = try file.applying(undoPatches[stepIndex]).file
            XCTAssertEqual(file.data, texts[stepIndex], "Undoing step \(stepIndex + 1)")
        }
        XCTAssertEqual(file.data, original.data)
        XCTAssertEqual(file.nodes, original.nodes)
        XCTAssertEqual(file.edges, original.edges)
    }

    func testAPatchForAnotherVersionIsRefusedNotMisapplied() throws {
        let file = try CanvasFixtures.file(CanvasFixtures.obsidianBoard)
        let result = try file.applying([.add(nodes: [CanvasNode(id: "f00dfacef00dface", content: .text("new"), frame: CGRect(x: 0, y: 0, width: 250, height: 60))], edges: [])])
        XCTAssertThrowsError(try CanvasFixtures.file("{}").applying(result.undoPatch)) { error in XCTAssertEqual(error as? CanvasFileError, .editNotApplied) }
    }
}

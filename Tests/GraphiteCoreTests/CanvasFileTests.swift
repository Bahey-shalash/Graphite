import XCTest
import CoreGraphics
@testable import GraphiteCore

/// Canvas files used by the canvas tests, written the way the JSON Canvas repository and
/// Obsidian write them.
enum CanvasFixtures {
    /// `sample.canvas` from the JSON Canvas repository, byte for byte.
    static let specificationSample = "{\n\t\"nodes\":[\n"
        + "\t\t{\"id\":\"754a8ef995f366bc\",\"type\":\"group\",\"x\":-300,\"y\":-460,\"width\":610,\"height\":200,\"label\":\"JSON Canvas\"},\n"
        + "\t\t{\"id\":\"8132d4d894c80022\",\"type\":\"file\",\"file\":\"readme.md\",\"x\":-280,\"y\":-200,\"width\":570,\"height\":560,\"color\":\"6\"},\n"
        + "\t\t{\"id\":\"7efdbbe0c4742315\",\"type\":\"file\",\"file\":\"_site/logo.svg\",\"x\":-280,\"y\":-440,\"width\":217,\"height\":80},\n"
        + "\t\t{\"id\":\"59e896bc8da20699\",\"type\":\"text\",\"text\":\"Learn more:\\n\\n- [Apps](/docs/apps.md)\\n- [Spec](spec/1.0.md)\\n- [Github](https://github.com/obsidianmd/jsoncanvas)\",\"x\":40,\"y\":-440,\"width\":250,\"height\":160},\n"
        + "\t\t{\"id\":\"0ba565e7f30e0652\",\"type\":\"file\",\"file\":\"spec/1.0.md\",\"x\":360,\"y\":-400,\"width\":400,\"height\":400}\n"
        + "\t],\n\t\"edges\":[\n"
        + "\t\t{\"id\":\"6fa11ab87f90b8af\",\"fromNode\":\"7efdbbe0c4742315\",\"fromSide\":\"right\",\"toNode\":\"59e896bc8da20699\",\"toSide\":\"left\"}\n"
        + "\t]\n}"

    /// A study board as Obsidian saves one: every card type, a heading subpath, preset and
    /// custom colors, a label, and both arrow ends.
    static let obsidianBoard = "{\n\t\"nodes\":[\n"
        + "\t\t{\"id\":\"a1b2c3d4e5f60718\",\"type\":\"group\",\"x\":-420,\"y\":-320,\"width\":900,\"height\":560,\"color\":\"4\",\"label\":\"Week 3\"},\n"
        + "\t\t{\"id\":\"0f1e2d3c4b5a6978\",\"type\":\"text\",\"text\":\"# Fourier series\\n\\nA periodic signal is a sum of **sinusoids**.\",\"x\":-380,\"y\":-260,\"width\":320,\"height\":200},\n"
        + "\t\t{\"id\":\"1122334455667788\",\"type\":\"file\",\"file\":\"Courses/Signals/Lecture 3.md\",\"subpath\":\"#Convergence\",\"x\":0,\"y\":-260,\"width\":400,\"height\":400,\"color\":\"#ff8800\"},\n"
        + "\t\t{\"id\":\"99aabbccddeeff00\",\"type\":\"file\",\"file\":\"Attachments/spectrum.png\",\"x\":-380,\"y\":-20,\"width\":320,\"height\":180},\n"
        + "\t\t{\"id\":\"deadbeefcafef00d\",\"type\":\"link\",\"url\":\"https://en.wikipedia.org/wiki/Fourier_series\",\"x\":520,\"y\":-260,\"width\":360,\"height\":240}\n"
        + "\t],\n\t\"edges\":[\n"
        + "\t\t{\"id\":\"e1e1e1e1e1e1e1e1\",\"fromNode\":\"0f1e2d3c4b5a6978\",\"fromSide\":\"right\",\"toNode\":\"1122334455667788\",\"toSide\":\"left\",\"label\":\"proved in\"},\n"
        + "\t\t{\"id\":\"e2e2e2e2e2e2e2e2\",\"fromNode\":\"99aabbccddeeff00\",\"fromSide\":\"top\",\"fromEnd\":\"arrow\",\"toNode\":\"0f1e2d3c4b5a6978\",\"toSide\":\"bottom\",\"toEnd\":\"none\",\"color\":\"1\"}\n"
        + "\t]\n}"

    /// A board in Obsidian's layout with `cardCount` text cards in a grid, each joined to
    /// the next.
    static func largeBoard(cardCount: Int) -> String {
        var lines: [String] = []
        for cardIndex in 0..<cardCount {
            let column = cardIndex % 100, row = cardIndex / 100
            lines.append("\t\t{\"id\":\"\(identifier(cardIndex))\",\"type\":\"text\",\"text\":\"Card \(cardIndex)\\n\\nwith **Markdown** and a [[Link \(cardIndex)]]\",\"x\":\(column * 300),\"y\":\(row * 200),\"width\":260,\"height\":140}")
        }
        var edgeLines: [String] = []
        for cardIndex in 0..<max(cardCount - 1, 0) {
            edgeLines.append("\t\t{\"id\":\"\(identifier(cardCount + cardIndex))\",\"fromNode\":\"\(identifier(cardIndex))\",\"fromSide\":\"right\",\"toNode\":\"\(identifier(cardIndex + 1))\",\"toSide\":\"left\"}")
        }
        return "{\n\t\"nodes\":[\n" + lines.joined(separator: ",\n") + "\n\t],\n\t\"edges\":[\n" + edgeLines.joined(separator: ",\n") + "\n\t]\n}"
    }

    static func identifier(_ number: Int) -> String { String(format: "%016x", number) }

    static func file(_ text: String) throws -> CanvasFile { try CanvasFile(data: Data(text.utf8)) }
}

final class CanvasFileTests: XCTestCase {
    func testReadsTheSpecificationSample() throws {
        let file = try CanvasFixtures.file(CanvasFixtures.specificationSample)
        XCTAssertEqual(file.nodes.map(\.id), ["754a8ef995f366bc", "8132d4d894c80022", "7efdbbe0c4742315", "59e896bc8da20699", "0ba565e7f30e0652"],
                       "Cards keep the file's order, which is their stacking order.")
        XCTAssertEqual(file.nodes[0].content, .group(label: "JSON Canvas", background: nil, backgroundStyle: .cover))
        XCTAssertEqual(file.nodes[0].frame, CGRect(x: -300, y: -460, width: 610, height: 200))
        XCTAssertEqual(file.nodes[1].content, .file(path: "readme.md", subpath: nil))
        XCTAssertEqual(file.nodes[1].color, .preset(6))
        XCTAssertEqual(file.nodes[3].content, .text("Learn more:\n\n- [Apps](/docs/apps.md)\n- [Spec](spec/1.0.md)\n- [Github](https://github.com/obsidianmd/jsoncanvas)"))
        XCTAssertNil(file.nodes[3].color)
        XCTAssertEqual(file.edges, [CanvasEdge(id: "6fa11ab87f90b8af", fromNode: "7efdbbe0c4742315", toNode: "59e896bc8da20699", fromSide: .right, toSide: .left,
                                               fromEnd: .none, toEnd: .arrow)],
                       "A connection without ends has the specification's defaults: none at its start, an arrow at its end.")
        XCTAssertEqual(file.unreadableNodeCount, 0)
        XCTAssertEqual(file.data, Data(CanvasFixtures.specificationSample.utf8), "Reading keeps the file's bytes.")
    }

    func testReadsEveryAttributeTheSpecificationDefines() throws {
        let file = try CanvasFixtures.file(CanvasFixtures.obsidianBoard)
        XCTAssertEqual(file.nodes.count, 5)
        XCTAssertEqual(file.nodes[0].color, .preset(4))
        XCTAssertEqual(file.nodes[2].content, .file(path: "Courses/Signals/Lecture 3.md", subpath: "#Convergence"))
        XCTAssertEqual(file.nodes[2].color, .custom(red: 0xFF, green: 0x88, blue: 0x00))
        XCTAssertEqual(file.nodes[4].content, .link(address: "https://en.wikipedia.org/wiki/Fourier_series"))
        XCTAssertEqual(file.edges[0].label, "proved in")
        XCTAssertEqual(file.edges[1], CanvasEdge(id: "e2e2e2e2e2e2e2e2", fromNode: "99aabbccddeeff00", toNode: "0f1e2d3c4b5a6978", fromSide: .top, toSide: .bottom,
                                                 fromEnd: .arrow, toEnd: .none, color: .preset(1)))
        XCTAssertEqual(file.node(named: "1122334455667788")?.frame, CGRect(x: 0, y: -260, width: 400, height: 400))

        let groupWithBackground = try CanvasFixtures.file(#"{"nodes":[{"id":"g","type":"group","x":0,"y":0,"width":10,"height":10,"background":"Art/paper.png","backgroundStyle":"repeat"}]}"#)
        XCTAssertEqual(groupWithBackground.nodes[0].content, .group(label: nil, background: "Art/paper.png", backgroundStyle: .repeat))
    }

    func testColorsReadPresetsAndHexadecimalOnly() {
        XCTAssertEqual(CanvasColor(text: "1"), .preset(1))
        XCTAssertEqual(CanvasColor(text: "6"), .preset(6))
        XCTAssertEqual(CanvasColor(text: "#FF0000"), .custom(red: 255, green: 0, blue: 0))
        XCTAssertEqual(CanvasColor(text: "#0af"), .custom(red: 0x00, green: 0xAA, blue: 0xFF))
        for unknown in ["0", "7", "12", "+1", "red", "#12", "#gggggg", "ff0000", ""] {
            XCTAssertNil(CanvasColor(text: unknown), "“\(unknown)” is not a canvas color")
        }
        XCTAssertEqual(CanvasColor.custom(red: 255, green: 136, blue: 0).text, "#ff8800")
        XCTAssertEqual(CanvasColor.preset(3).text, "3")
        XCTAssertEqual(CanvasColor.presets.map(\.name), ["Red", "Orange", "Yellow", "Green", "Cyan", "Purple"])
    }

    func testUnknownKeysAndTypesAreShownAsFarAsUnderstoodAndMalformedEntriesAreCounted() throws {
        let text = """
            {"version":"9.9","nodes":[
              {"id":"known","type":"text","text":"hi","x":1,"y":2,"width":30,"height":40,"styleAttributes":{"shape":"pill"},"color":"banana"},
              {"id":"future","type":"mindmap","x":0,"y":0,"width":100,"height":100,"children":[1,[2,{"deep":null}]]},
              {"id":"no-geometry","type":"text","text":"lost"},
              {"type":"text","text":"no id","x":0,"y":0,"width":1,"height":1},
              {"id":"text-size","type":"text","x":"12","y":0,"width":10,"height":10},
              {"id":"flat","type":"text","x":0,"y":0,"width":0,"height":10},
              {"id":"far","type":"text","x":1e30,"y":0,"width":10,"height":10},
              "not an object", 7, null,
              {"id":"untyped","x":5.5,"y":-6.25,"width":10,"height":10}
            ],"edges":[
              {"id":"ok","fromNode":"known","toNode":"future","fromSide":"diagonal","toEnd":"circle","plugin":true},
              {"id":"dangling","fromNode":"known","toNode":"nowhere"},
              {"fromNode":"known","toNode":"future"},
              {"id":"no-target","fromNode":"known"}
            ],"metadata":{"frontmatter":{}}}
            """
        let file = try CanvasFixtures.file(text)
        XCTAssertEqual(file.nodes.map(\.id), ["known", "future", "untyped"])
        XCTAssertNil(file.nodes[0].color, "A color Graphite cannot read shows as no color.")
        XCTAssertEqual(file.nodes[1].content, .unknown(type: "mindmap"))
        XCTAssertEqual(file.nodes[2].content, .unknown(type: ""))
        XCTAssertEqual(file.nodes[2].frame, CGRect(x: 5.5, y: -6.25, width: 10, height: 10), "Positions with fractions are read as written.")
        XCTAssertEqual(file.unreadableNodeCount, 8)
        XCTAssertEqual(file.edges.map(\.id), ["ok", "dangling"])
        XCTAssertNil(file.edges[0].fromSide, "An unknown side lets the app choose.")
        XCTAssertEqual(file.edges[0].toEnd, .arrow, "An unknown end reads as the default.")
        XCTAssertEqual(file.unreadableEdgeCount, 2)
        XCTAssertNil(file.node(named: "nowhere"))
    }

    func testFilesWithWindowsLineEndingsByteOrderMarkAndUnusualWhitespaceAreRead() throws {
        let text = "\u{FEFF}{\r\n  \"edges\" :\t[ ] ,\r\n  \"nodes\"  : [\r\n\r\n    { \"height\" : 60 ,\"width\":250 , \"y\" : -30, \"x\":-125 ,\"text\" : \"a\\tb\" , \"type\":\"text\", \"id\":\"n1\" }\r\n  ]\r\n}\r\n\r\n"
        let file = try CanvasFixtures.file(text)
        XCTAssertEqual(file.nodes, [CanvasNode(id: "n1", content: .text("a\tb"), frame: CGRect(x: -125, y: -30, width: 250, height: 60))])
        XCTAssertEqual(file.edges, [])
        XCTAssertEqual(file.data, Data(text.utf8))
    }

    func testEscapesAreDecoded() throws {
        let file = try CanvasFixtures.file(#"{"nodes":[{"id":"n","type":"text","text":"q\" b\\ s\/ \b\f\n\r\t \u00e9 \uD83D\uDE00 \ud83d lone","x":0,"y":0,"width":1,"height":1}]}"#)
        XCTAssertEqual(file.nodes[0].content, .text("q\" b\\ s/ \u{8}\u{C}\n\r\t é 😀 \u{FFFD} lone"))
    }

    func testAKeyWrittenTwiceCountsOnce() throws {
        let file = try CanvasFixtures.file(#"{"nodes":[{"id":"n","type":"text","text":"first","text":"last","x":0,"y":0,"width":1,"height":1}]}"#)
        XCTAssertEqual(file.nodes[0].content, .text("last"), "As JavaScript reads it, the last value counts.")
    }

    func testCardsSharingAnIdentifierAreAllShown() throws {
        let file = try CanvasFixtures.file(#"{"nodes":[{"id":"a","type":"text","text":"1","x":0,"y":0,"width":10,"height":10},{"id":"a","type":"text","text":"2","x":50,"y":0,"width":10,"height":10}],"edges":[{"id":"e","fromNode":"a","toNode":"a"},{"id":"e","fromNode":"a","toNode":"a"}]}"#)
        XCTAssertEqual(file.nodes.count, 2)
        XCTAssertEqual(Set(file.nodes.map(\.id)).count, 2, "Each shown card has its own key.")
        XCTAssertEqual(file.nodes.map(\.identifierInFile), ["a", "a"])
        XCTAssertEqual(file.node(named: "a")?.content, .text("1"), "A connection attaches to the first card with the name.")
        XCTAssertEqual(Set(file.edges.map(\.id)).count, 2)
    }

    func testEmptyCanvasesOpen() throws {
        for text in ["{}", "", "  \n", "{\"nodes\":[],\"edges\":[]}", "{\"nodes\":null}"] {
            let file = try CanvasFixtures.file(text)
            XCTAssertTrue(file.nodes.isEmpty && file.edges.isEmpty, "“\(text)” is an empty canvas")
        }
    }

    func testDamagedFilesAreRefusedWithAMessageThatSaysTheFileIsUntouched() {
        let damaged: [(text: String, expected: CanvasFileError?)] = [
            ("{\"nodes\":[{\"id\":\"a\"", nil),
            ("{\"nodes\":[{\"id\":\"a\",}]}", nil),
            ("{\"nodes\":[]} trailing", nil),
            ("{\"nodes\":[],}", nil),
            ("{'nodes':[]}", nil),
            ("{\"nodes\":[{\"id\":\"a\",\"text\":\"line\nbreak\"}]}", nil),
            ("{\"nodes\":[{\"id\":\"a\",\"text\":\"\\q\"}]}", nil),
            ("{\"nodes\":[{\"x\":01}]}", nil),
            ("{\"nodes\":[{\"x\":1.}]}", nil),
            ("{\"nodes\":[{\"x\":tru}]}", nil),
            ("[]", .notAnObject),
            ("\"canvas\"", .notAnObject),
            ("{\"nodes\":{}}", .listIsNotAnArray(listName: "nodes")),
            ("{\"edges\":\"none\"}", .listIsNotAnArray(listName: "edges")),
        ]
        for (text, expected) in damaged {
            XCTAssertThrowsError(try CanvasFixtures.file(text), "“\(text)” should be refused") { error in
                guard let canvasError = error as? CanvasFileError else { return XCTFail("Unexpected error \(error)") }
                if let expected { XCTAssertEqual(canvasError, expected) } else if case .invalidJSON = canvasError {} else { XCTFail("“\(text)” gave \(canvasError)") }
                XCTAssertTrue(canvasError.localizedDescription.contains("left the file as it is"), canvasError.localizedDescription)
            }
        }
        XCTAssertThrowsError(try CanvasFile(data: Data([0x7B, 0x22, 0xFF, 0xFE, 0x22, 0x3A, 0x31, 0x7D]))) { error in
            XCTAssertEqual(error as? CanvasFileError, .notUTF8)
        }
    }

    func testSizesAndCountsOfUntrustedFilesAreBounded() throws {
        XCTAssertThrowsError(try CanvasFile(data: Data(repeating: 0x20, count: CanvasFile.maximumSourceBytes + 1))) { error in
            XCTAssertEqual(error as? CanvasFileError, .oversized)
        }
        let deeplyNested = "{\"nodes\":[],\"extra\":" + String(repeating: "[", count: 100_000) + String(repeating: "]", count: 100_000) + "}"
        XCTAssertThrowsError(try CanvasFixtures.file(deeplyNested)) { error in
            XCTAssertEqual(error as? CanvasFileError, .nestedTooDeeply, "Deep nesting must be refused before it can exhaust the stack.")
        }
        let nestedWithinLimit = "{\"nodes\":[],\"extra\":" + String(repeating: "[", count: 40) + String(repeating: "]", count: 40) + "}"
        XCTAssertNoThrow(try CanvasFixtures.file(nestedWithinLimit))
        let tooManyCards = "{\"nodes\":[" + Array(repeating: "0", count: CanvasFile.maximumNodeCount + 1).joined(separator: ",") + "]}"
        XCTAssertThrowsError(try CanvasFixtures.file(tooManyCards)) { error in XCTAssertEqual(error as? CanvasFileError, .tooManyCards) }
        let tooManyConnections = "{\"edges\":[" + Array(repeating: "0", count: CanvasFile.maximumEdgeCount + 1).joined(separator: ",") + "]}"
        XCTAssertThrowsError(try CanvasFixtures.file(tooManyConnections)) { error in XCTAssertEqual(error as? CanvasFileError, .tooManyConnections) }
    }

    func testAVeryLargeBoardIsReadCompletely() throws {
        let cardCount = 20_000
        let data = Data(CanvasFixtures.largeBoard(cardCount: cardCount).utf8)
        let start = ContinuousClock.now
        let file = try CanvasFile(data: data)
        let elapsed = ContinuousClock.now - start
        XCTAssertEqual(file.nodes.count, cardCount)
        XCTAssertEqual(file.edges.count, cardCount - 1)
        XCTAssertEqual(file.nodes[19_999].frame, CGRect(x: 99 * 300, y: 199 * 200, width: 260, height: 140))
        XCTAssertEqual(file.nodes[12_345].content, .text("Card 12345\n\nwith **Markdown** and a [[Link 12345]]"))
        print("Canvas measurement: read \(cardCount) cards and \(cardCount - 1) connections (\(data.count / 1024) KB) in \(elapsed)")
    }
}

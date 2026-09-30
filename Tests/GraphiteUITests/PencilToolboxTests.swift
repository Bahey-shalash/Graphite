import XCTest
@testable import GraphiteUI

/// The state of the fixed Pencil tool bar.
@MainActor
final class PencilToolboxTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() async throws {
        suiteName = "PencilToolboxTests-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    func testStartsWithAPenAndMediumWidths() {
        let toolbox = PencilToolbox(defaults: defaults)
        XCTAssertEqual(toolbox.toolInUse, .pen)
        XCTAssertTrue(toolbox.erasesWholeStrokes)
        XCTAssertFalse(toolbox.isRulerActive)
        for kind in PencilToolKind.allCases where kind.drawsInk {
            XCTAssertEqual(kind.widthChoices.count, 3)
            XCTAssertEqual(toolbox.width(of: kind), kind.widthChoices[1])
            XCTAssertEqual(toolbox.colorHex(of: kind), kind.defaultColorHex)
        }
        XCTAssertTrue(PencilToolKind.eraser.widthChoices.isEmpty)
        XCTAssertFalse(PencilToolKind.lasso.drawsInk)
    }

    func testEachToolKeepsItsOwnColorAndWidth() {
        let toolbox = PencilToolbox(defaults: defaults)
        toolbox.chooseColor(hex: "#E93147")
        toolbox.chooseWidth(PencilToolKind.pen.widthChoices[2])
        toolbox.toolInUse = .highlighter
        toolbox.chooseColor(hex: "#08b94e")
        XCTAssertEqual(toolbox.colorHex(of: .pen), "#e93147", "Colors are kept in one spelling.")
        XCTAssertEqual(toolbox.width(of: .pen), PencilToolKind.pen.widthChoices[2])
        XCTAssertEqual(toolbox.colorHex(of: .highlighter), "#08b94e")
        XCTAssertEqual(toolbox.width(of: .highlighter), PencilToolKind.highlighter.widthChoices[1])
        XCTAssertEqual(toolbox.colorHex(of: .pencil), PencilToolKind.pencil.defaultColorHex)

        // A width the tool does not offer, and a color that is none, change nothing.
        toolbox.chooseWidth(123)
        XCTAssertEqual(toolbox.width(of: .highlighter), PencilToolKind.highlighter.widthChoices[1])
        toolbox.chooseColor(hex: "not a color")
        XCTAssertEqual(toolbox.colorHex(of: .highlighter), "#08b94e")
    }

    func testChoosingAColorWithTheEraserInUseTakesUpThePen() {
        let toolbox = PencilToolbox(defaults: defaults)
        toolbox.toolInUse = .eraser
        toolbox.chooseColor(hex: "#086ddd")
        XCTAssertEqual(toolbox.toolInUse, .pen)
        XCTAssertEqual(toolbox.colorHex(of: .pen), "#086ddd")
        toolbox.toolInUse = .lasso
        toolbox.chooseWidth(PencilToolKind.pen.widthChoices[0])
        XCTAssertEqual(toolbox.width(of: .pen), PencilToolKind.pen.widthChoices[1], "The lasso has no width to choose.")
    }

    func testStateIsKeptBetweenLaunchesAndDamagedStateFallsBack() throws {
        let toolbox = PencilToolbox(defaults: defaults)
        toolbox.toolInUse = .pencil
        toolbox.chooseColor(hex: "#7852ee")
        toolbox.chooseWidth(PencilToolKind.pencil.widthChoices[0])
        toolbox.erasesWholeStrokes = false
        toolbox.isRulerActive = true

        let relaunched = PencilToolbox(defaults: defaults)
        XCTAssertEqual(relaunched.toolInUse, .pencil)
        XCTAssertEqual(relaunched.colorHex(of: .pencil), "#7852ee")
        XCTAssertEqual(relaunched.width(of: .pencil), PencilToolKind.pencil.widthChoices[0])
        XCTAssertFalse(relaunched.erasesWholeStrokes)
        XCTAssertFalse(relaunched.isRulerActive, "The ruler is put away with the app.")

        // Widths and colors another build would not offer fall back to the defaults.
        let damaged = #"{"toolInUse":"pen","colorHexes":{"pen":"purple"},"widths":{"pen":99},"erasesWholeStrokes":true}"#
        defaults.set(Data(damaged.utf8), forKey: PencilToolbox.storageKey)
        let recovered = PencilToolbox(defaults: defaults)
        XCTAssertEqual(recovered.colorHex(of: .pen), PencilToolKind.pen.defaultColorHex)
        XCTAssertEqual(recovered.width(of: .pen), PencilToolKind.pen.widthChoices[1])
        defaults.set(Data("not JSON".utf8), forKey: PencilToolbox.storageKey)
        XCTAssertEqual(PencilToolbox(defaults: defaults).toolInUse, .pen)
    }

    func testSelectionChangesExactlyWhenTheToolDoes() {
        let toolbox = PencilToolbox(defaults: defaults)
        let penSelection = toolbox.selection
        XCTAssertEqual(toolbox.selection, penSelection)
        toolbox.chooseWidth(PencilToolKind.pen.widthChoices[0])
        XCTAssertNotEqual(toolbox.selection, penSelection)
        let fineSelection = toolbox.selection
        toolbox.isRulerActive = true
        XCTAssertNotEqual(toolbox.selection, fineSelection)
        XCTAssertEqual(PencilToolbarStyle(rawValue: "fixed"), .fixed)
        XCTAssertEqual(PencilToolbarStyle.allCases.map(\.title), ["Floating palette", "Fixed bar"])
    }
}

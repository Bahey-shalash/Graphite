import XCTest
import GraphiteCore
import GraphiteApple
@testable import GraphiteUI
import GraphiteTestSupport

/// What `ReadAloudController` keeps on the device: how mathematics is said and the reading
/// order of PDF pages, under these names.
@MainActor
final class ReadAloudControllerPreferenceKeysTests: XCTestCase {
    private var preferences: UserDefaults!

    override func setUp() async throws {
        preferences = try IsolatedDeviceState.make(prefix: "ReadAloudControllerPreferenceKeysTests", for: self).preferences
    }

    override func tearDown() async throws {
        preferences = nil
    }

    private func makeController() -> ReadAloudController {
        ReadAloudController(session: ReadAloudSession(speech: PenTestSpeech(), preferences: preferences), preferences: preferences)
    }

    func testAnEmptyStoreSaysMathematicsConciselyAndReadsPDFPagesInLayoutOrder() {
        let controller = makeController()

        XCTAssertEqual(controller.mathematicalStyle, .concise)
        XCTAssertEqual(controller.pdfReadingOrder, .layout)
    }

    func testTheMathematicalStyleIsStoredAsItsRawValueAndReadBack() {
        XCTAssertEqual(MathematicalSpeechStyle.allCases.map(\.rawValue), ["concise", "detailed"])
        let controller = makeController()

        controller.chooseMathematicalStyle(.detailed)

        XCTAssertEqual(preferences.string(forKey: "readAloudMathematicalStyle"), "detailed")
        XCTAssertEqual(makeController().mathematicalStyle, .detailed)
        preferences.set("verbose", forKey: "readAloudMathematicalStyle")
        XCTAssertEqual(makeController().mathematicalStyle, .concise)
    }

    func testThePDFReadingOrderIsStoredAsItsRawValueAndReadBack() {
        XCTAssertEqual(PDFReadingOrder.allCases.map(\.rawValue), ["layout", "file"])
        let controller = makeController()

        controller.choosePDFReadingOrder(.file)

        XCTAssertEqual(preferences.string(forKey: "readAloudPDFReadingOrder"), "file")
        XCTAssertEqual(makeController().pdfReadingOrder, .file)
        preferences.set("reversed", forKey: "readAloudPDFReadingOrder")
        XCTAssertEqual(makeController().pdfReadingOrder, .layout)
    }

    func testTheFloatingPlayersCornerIsKeptByTheseRawValues() {
        XCTAssertEqual(ReadAloudPlayerPosition.allCases.map(\.rawValue), ["topLeading", "top", "topTrailing", "bottomLeading", "bottom", "bottomTrailing"])
    }
}

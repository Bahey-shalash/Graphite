import XCTest
import GraphiteCore
@testable import GraphiteUI

/// The callouts a person expanded or collapsed are remembered per note, for the session only,
/// under `ReadAloudFolding.calloutKey`; the callout's own marker is the starting point.
@MainActor
final class CalloutFoldStoreTests: XCTestCase {
    func testAnEntryIsKeptPerNotePath() {
        let store = CalloutFoldStore()
        let key = ReadAloudFolding.calloutKey(type: "NOTE", title: " Title ")
        store.setExpanded(true, notePath: "Lectures/One.md", key: key)
        XCTAssertEqual(store.expansion(for: "Lectures/One.md"), ["note|Title": true])
        XCTAssertEqual(store.expansion(for: "Lectures/Two.md"), [:])
        XCTAssertTrue(store.isExpanded(notePath: "Lectures/One.md", key: key, initially: false))
        XCTAssertFalse(store.isExpanded(notePath: "Lectures/Two.md", key: key, initially: false))
    }

    func testWithoutAnEntryTheMarkerDecidesAndAnEntryWins() {
        let store = CalloutFoldStore()
        XCTAssertTrue(store.isExpanded(notePath: "A.md", key: "note|Title", initially: true))
        XCTAssertFalse(store.isExpanded(notePath: "A.md", key: "note|Title", initially: false))
        store.setExpanded(false, notePath: "A.md", key: "note|Title")
        XCTAssertFalse(store.isExpanded(notePath: "A.md", key: "note|Title", initially: true), "A collapsed entry beats a '+' marker.")
        store.setExpanded(true, notePath: "A.md", key: "note|Title")
        XCTAssertTrue(store.isExpanded(notePath: "A.md", key: "note|Title", initially: false), "An expanded entry beats a '-' marker.")
    }

    func testANewStoreStartsEmptyBecauseNothingIsSavedBetweenSessions() {
        let store = CalloutFoldStore()
        store.setExpanded(true, notePath: "A.md", key: "note|Title")
        XCTAssertEqual(CalloutFoldStore().expansion(for: "A.md"), [:])
    }

    func testTheStoresExpansionDrivesReadAloudsHiddenRanges() {
        let store = CalloutFoldStore()
        let text = "> [!NOTE]-  Title \n> body\n"
        XCTAssertEqual(ReadAloudFolding.hiddenRanges(in: text, foldedKeys: [], calloutExpansion: store.expansion(for: "A.md")).count, 1)
        store.setExpanded(true, notePath: "A.md", key: ReadAloudFolding.calloutKey(type: "note", title: "Title"))
        XCTAssertEqual(ReadAloudFolding.hiddenRanges(in: text, foldedKeys: [], calloutExpansion: store.expansion(for: "A.md")), [])
    }
}

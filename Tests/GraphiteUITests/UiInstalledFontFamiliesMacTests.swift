#if os(macOS)
import AppKit
import XCTest
@testable import GraphiteUI

/// The Mac finds a vault's font family by asking for that family alone, as the whole list of
/// installed families would answer: ignoring case, in the system's spelling.
@MainActor
final class UiInstalledFontFamiliesMacTests: XCTestCase {
    func testAFamilyIsFoundIgnoringCaseInTheSystemsSpelling() {
        InstalledFontFamilies.refresh()
        XCTAssertEqual(InstalledFontFamilies.family(named: "helvetica neue"), "Helvetica Neue")
        XCTAssertEqual(InstalledFontFamilies.family(named: "HELVETICA NEUE"), "Helvetica Neue")
        XCTAssertNil(InstalledFontFamilies.family(named: "No Such Family In Graphite"))
        // The system font's private faces are not offered.
        XCTAssertNil(InstalledFontFamilies.family(named: ".AppleSystemUIFont"))
    }

    /// The same answers come from the whole list, once the font settings have listed it.
    func testTheListAndTheSingleFamilyAgree() {
        InstalledFontFamilies.refresh()
        let single = ["Helvetica Neue", "menlo", "Missing Family"].map { name in InstalledFontFamilies.family(named: name) }
        _ = InstalledFontFamilies.all
        let listed = ["Helvetica Neue", "menlo", "Missing Family"].map { name in InstalledFontFamilies.family(named: name) }
        XCTAssertEqual(single, listed)
        InstalledFontFamilies.refresh()
    }
}
#endif

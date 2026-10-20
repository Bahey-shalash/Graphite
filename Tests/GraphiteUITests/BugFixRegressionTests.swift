import XCTest
import PDFKit
import SwiftUI
import GraphiteApple
@testable import GraphiteCore
@testable import GraphiteUI
import GraphiteTestSupport

/// Edge cases found in a review of the whole app, each of which went wrong before.
@MainActor
final class BugFixRegressionTests: XCTestCase {
    // MARK: Font sizes

    /// A plugin's `baseFontSize` of 1e20, or a pinch's scale near 1e18, stopped the app:
    /// a number past `Int`'s range was made whole before it was clamped.
    func testHugeFontSizesAreClampedInsteadOfStoppingTheApp() {
        XCTAssertEqual(NoteFontSize.clamped(1e20), NoteFontSize.adjustableRange.upperBound)
        XCTAssertEqual(NoteFontSize.clamped(-1e20), NoteFontSize.adjustableRange.lowerBound)
        XCTAssertEqual(NoteFontSize.clamped(Double.nan), NoteFontSize.defaultSize)
        XCTAssertEqual(NoteFontSize.size(afterPinchingBy: 1e18, from: 16), NoteFontSize.adjustableRange.upperBound)
    }

    // MARK: Read Aloud's places

    private func makeNavigator() throws -> (ReadAloudNavigator, UserDefaults) {
        let preferences = try IsolatedDeviceState.make(prefix: "BugFixRegressionTests", for: self).preferences
        let session = ReadAloudSession(speech: PenTestSpeech(), preferences: preferences)
        let reader = ReadAloudController(session: session, preferences: preferences)
        return (ReadAloudNavigator(reader: reader, preferences: preferences), preferences)
    }

    /// Once 300 places were kept, a new one dropped the place of the note first in the
    /// alphabet, however recently it was read, instead of the place kept longest ago.
    func testTheLeastRecentlyKeptPlaceIsForgottenFirst() throws {
        let (navigator, _) = try makeNavigator()
        navigator.remember(7, for: "Algebra.md")
        for noteNumber in 1...299 { navigator.remember(noteNumber, for: "Note \(noteNumber).md") }
        navigator.remember(8, for: "Algebra.md")
        navigator.remember(1, for: "Zoology.md")
        XCTAssertEqual(navigator.rememberedLocation(for: "Algebra.md"), 8, "Read again just now, so kept")
        XCTAssertNil(navigator.rememberedLocation(for: "Note 1.md"), "Kept longest ago, so forgotten")
        XCTAssertEqual(navigator.rememberedLocation(for: "Zoology.md"), 1)
    }

    /// A PDF is read under its file's location; it was left out of the history and the
    /// queue, and a queued PDF did not come back to its page.
    func testAPDFReadByItsFileLocationIsKnownByItsPlaceInTheVault() throws {
        let (navigator, _) = try makeNavigator()
        let vault = FileManager.default.temporaryDirectory.appendingPathComponent("Vault-\(UUID().uuidString)")
        navigator.vaultRoot = { vault }
        let location = vault.appendingPathComponent("Lectures/Week 1.pdf")
        XCTAssertEqual(navigator.vaultPath(ofSource: location.path), try VaultPath("Lectures/Week 1.pdf"))
        XCTAssertEqual(navigator.vaultPath(ofSource: "Notes/Plan.md"), try VaultPath("Notes/Plan.md"))
        XCTAssertNil(navigator.vaultPath(ofSource: "/Elsewhere/Other.pdf"))
        navigator.remember(4, for: location.path)
        XCTAssertEqual(navigator.rememberedLocation(for: try VaultPath("Lectures/Week 1.pdf")), 4)
    }

    // MARK: Properties

    /// Obsidian takes `Tags` and `tags` for one property; adding the second made two keys.
    func testAPropertyNameDifferingOnlyInCaseIsTaken() {
        var editing = PropertyListEditing()
        let parsed = [NoteProperty(key: "tags", value: .list(["a"]))]
        XCTAssertNil(editing.adding("Tags", parsedProperties: parsed))
        XCTAssertNotNil(editing.adding("Status", parsedProperties: parsed))
    }

    // MARK: The Mac's PDF view

    /// Switching tabs made the Mac's PDF view again at the top of the current page at best;
    /// it now comes back to the same place on the page, as the iPad does.
    func testTheMacPDFViewComesBackToItsPlaceOnThePage() async throws {
        let directory = try TemporaryVault.make(prefix: "MacPlace", for: self).root
        let location = try PerformanceBenchmarkTests.makeLecturePDF(at: directory.appendingPathComponent("Lecture.pdf"), pageCount: 20)
        let session = try await PDFSession.open(location)
        session.keptPlace = PDFPagePlace(pageIndex: 7, fractionFromTop: 0.5)
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 600, height: 800), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.contentView = nil; window.close() }
        window.contentView = NSHostingView(rootView: GraphitePDFView(session: session, input: PDFAnnotationInput(isEnabled: false, drawsWithFinger: false, showsToolPicker: false)))
        var place: PDFPagePlace?
        for _ in 0..<200 {
            window.contentView?.layoutSubtreeIfNeeded()
            place = session.livePlace?()
            if place != nil { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        let shownPlace = try XCTUnwrap(place, "The view tells where it is once laid out")
        XCTAssertEqual(shownPlace.pageIndex, 7)
        XCTAssertEqual(shownPlace.fractionFromTop, 0.5, accuracy: 0.1)
    }
}

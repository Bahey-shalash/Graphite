#if os(macOS)
import AppKit
import XCTest
@testable import GraphiteUI

/// The Mac note editor tells the session where the note is scrolled when the session asks
/// for the place to remember: closing a tab, switching vault or leaving the app.
@MainActor
final class MacMarkdownEditorRememberedPlaceTests: XCTestCase {
    private var fixture: MacMarkdownEditorFixture?

    override func tearDown() async throws {
        fixture?.tearDown()
        fixture = nil
        try await super.tearDown()
    }

    private static let text = (0..<300).map { index in "Line \(index)" }.joined(separator: "\n")

    private func characterLocation(ofLine index: Int) -> Int {
        (Self.text as NSString).range(of: "Line \(index)\n").location
    }

    func testPlaceToRememberIsTheLineAtTheTopOfTheEditorScrolledSinceItWasShown() async throws {
        let fixture = try await MacMarkdownEditorFixture(text: Self.text)
        self.fixture = fixture
        fixture.coordinator.resume(fixture.scrollView)
        fixture.scrollToTop(ofCharacter: characterLocation(ofLine: 150))

        let place = fixture.session.placeToRemember()

        XCTAssertEqual(place.topLocation, characterLocation(ofLine: 150))
    }

    func testPlaceToRememberFollowsTheEditorBackToTheTopOfTheNote() async throws {
        let fixture = try await MacMarkdownEditorFixture(text: Self.text)
        self.fixture = fixture
        fixture.coordinator.resume(fixture.scrollView)
        fixture.scrollToTop(ofCharacter: characterLocation(ofLine: 150))
        _ = fixture.session.placeToRemember()
        fixture.scrollToTop(ofCharacter: 0)

        XCTAssertEqual(fixture.session.placeToRemember().topLocation, 0)
    }

    func testPlaceToRememberIgnoresAJumpThatHasNotLandedYet() async throws {
        let fixture = try await MacMarkdownEditorFixture(text: Self.text)
        self.fixture = fixture
        fixture.coordinator.resume(fixture.scrollView)
        fixture.scrollToTop(ofCharacter: characterLocation(ofLine: 150))
        _ = fixture.session.placeToRemember()
        fixture.coordinator.pendingJump = .topOfCharacter(characterLocation(ofLine: 20))
        fixture.scrollToTop(ofCharacter: 0)

        XCTAssertEqual(fixture.session.placeToRemember().topLocation, characterLocation(ofLine: 150),
                       "A view still on its way to the jump's target keeps the place stored before it.")
    }

    func testSuspendedEditorStopsAnsweringForTheSession() async throws {
        let fixture = try await MacMarkdownEditorFixture(text: Self.text)
        self.fixture = fixture
        fixture.coordinator.resume(fixture.scrollView)
        fixture.scrollToTop(ofCharacter: characterLocation(ofLine: 150))

        fixture.coordinator.suspend(fixture.scrollView)

        XCTAssertNil(fixture.session.recordEditorPlace)
        XCTAssertEqual(fixture.session.placeToRemember().topLocation, characterLocation(ofLine: 150),
                       "Suspending stores the place the editor left.")
    }
}
#endif

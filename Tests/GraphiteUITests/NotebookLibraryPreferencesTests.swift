import XCTest
import GraphiteTestSupport
@testable import GraphiteUI

@MainActor
final class NotebookLibraryPreferencesTests: XCTestCase {
    private lazy var deviceState = try? IsolatedDeviceState.make(prefix: "NotebookLibraryPreferencesTests", for: self)

    private func makeDefaults() throws -> UserDefaults {
        try XCTUnwrap(deviceState).preferences
    }

    func testStartsAsTheObsidianListOfferingNotesFirst() throws {
        let preferences = NotebookLibraryPreferences(defaults: try makeDefaults())
        XCTAssertEqual(preferences.presentation, .list)
        XCTAssertEqual(preferences.firstCreatedKind, .note)
    }

    func testTheLibraryOffersNotebooksFirst() throws {
        let preferences = NotebookLibraryPreferences(defaults: try makeDefaults())
        preferences.presentation = .library
        XCTAssertEqual(preferences.firstCreatedKind, .notebook)
    }

    func testThePresentationSurvivesARestart() throws {
        let defaults = try makeDefaults()
        NotebookLibraryPreferences(defaults: defaults).presentation = .library
        XCTAssertEqual(NotebookLibraryPreferences(defaults: defaults).presentation, .library)
    }
}

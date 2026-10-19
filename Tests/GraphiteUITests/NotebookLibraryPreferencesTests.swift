import XCTest
import GraphiteTestSupport
@testable import GraphiteUI

@MainActor
final class NotebookLibraryPreferencesTests: XCTestCase {
    private lazy var deviceState = try? IsolatedDeviceState.make(prefix: "NotebookLibraryPreferencesTests", for: self)

    private func makeDefaults() throws -> UserDefaults {
        try XCTUnwrap(deviceState).preferences
    }

    func testStartsAsTheObsidianListWithNoAnswer() throws {
        let preferences = NotebookLibraryPreferences(defaults: try makeDefaults())
        XCTAssertEqual(preferences.presentation, .list)
        XCTAssertNil(preferences.noteTakingStyle)
        XCTAssertEqual(preferences.firstCreatedKind, .note)
    }

    func testAnsweringPencilShowsTheLibraryAndOffersNotebooksFirst() throws {
        let preferences = NotebookLibraryPreferences(defaults: try makeDefaults())
        preferences.choose(.pencil)
        XCTAssertEqual(preferences.presentation, .library)
        XCTAssertEqual(preferences.firstCreatedKind, .notebook)
    }

    func testAnsweringKeyboardKeepsTheListAndOffersNotesFirst() throws {
        let preferences = NotebookLibraryPreferences(defaults: try makeDefaults())
        preferences.choose(.keyboard)
        XCTAssertEqual(preferences.presentation, .list)
        XCTAssertEqual(preferences.firstCreatedKind, .note)
    }

    func testChoicesSurviveARestart() throws {
        let defaults = try makeDefaults()
        let preferences = NotebookLibraryPreferences(defaults: defaults)
        preferences.choose(.both)
        preferences.presentation = .list
        let reopened = NotebookLibraryPreferences(defaults: defaults)
        XCTAssertEqual(reopened.noteTakingStyle, .both)
        XCTAssertEqual(reopened.presentation, .list)
        XCTAssertEqual(reopened.firstCreatedKind, .notebook)
    }

    func testTheLibraryWithoutAnAnswerOffersNotebooksFirst() throws {
        let preferences = NotebookLibraryPreferences(defaults: try makeDefaults())
        preferences.presentation = .library
        XCTAssertEqual(preferences.firstCreatedKind, .notebook)
    }
}

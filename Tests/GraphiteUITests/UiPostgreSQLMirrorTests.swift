import XCTest
import GraphitePostgreSQLMirror
@testable import GraphiteUI

/// The PostgreSQL Mirror core plugin's preferences: off until turned on, and its server kept
/// on this device.
@MainActor
final class UiPostgreSQLMirrorTests: XCTestCase {
    func testTheMirrorStaysOffOnADeviceThatAlreadyStoredItsPluginList() throws {
        let suiteName = "GraphitePostgreSQLMirrorPreferences-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        // A device that turned the graph off before the mirror existed.
        defaults.set(["graph"], forKey: "GraphiteDisabledCorePlugins")
        let preferences = GraphitePreferences(defaults: defaults)
        XCTAssertFalse(preferences.isEnabled(.postgreSQLMirror))
        XCTAssertFalse(preferences.isEnabled(.graph))
        XCTAssertTrue(preferences.isEnabled(.map))

        preferences.setEnabled(.postgreSQLMirror, true)
        preferences.postgreSQLMirrorConfiguration = PostgreSQLMirrorConfiguration(host: "db.example.org", databaseName: "notes", userName: "felix")
        let readAgain = GraphitePreferences(defaults: defaults)
        XCTAssertTrue(readAgain.isEnabled(.postgreSQLMirror))
        XCTAssertEqual(readAgain.postgreSQLMirrorConfiguration, PostgreSQLMirrorConfiguration(host: "db.example.org", databaseName: "notes", userName: "felix"))
        XCTAssertEqual(defaults.stringArray(forKey: "GraphiteDisabledCorePlugins"), ["graph"], "The other plugins' list is left as it was.")
        readAgain.setEnabled(.postgreSQLMirror, false)
        XCTAssertFalse(GraphitePreferences(defaults: defaults).isEnabled(.postgreSQLMirror))
    }
}

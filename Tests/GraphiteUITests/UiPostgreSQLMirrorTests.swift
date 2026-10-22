import XCTest
import GraphitePostgreSQLMirror
@testable import GraphiteUI

/// The PostgreSQL Mirror core plugin: off until turned on, its server kept on this device, and
/// its failures worded by the controller of its copies.
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

    func testAFailureNamesTheServerAndWhatItAnsweredOrSaysWhatToDo() {
        let server = "db.example.org:5432"
        let refusal = PostgreSQLMirrorError.connectionRefused(server: server, message: "password authentication failed")
        XCTAssertEqual(PostgreSQLMirrorController.message(for: refusal),
                       "db.example.org:5432 refused the connection: password authentication failed")
        XCTAssertEqual(PostgreSQLMirrorController.message(for: PostgreSQLMirrorError.unreachable(server: server, reason: "timed out")),
                       "Graphite could not reach db.example.org:5432: timed out. "
                       + "Check the address and the port, and that the server accepts connections from this device.")
        XCTAssertEqual(PostgreSQLMirrorController.message(for: PostgreSQLMirrorError.copyRefused(message: "cannot drop view my_places")),
                       "The server refused the copy: cannot drop view my_places")
        struct KeychainRefusal: LocalizedError { var errorDescription: String? { "The keychain did not keep the password (-25308)." } }
        struct Silence: Error {}
        XCTAssertEqual(PostgreSQLMirrorController.message(for: KeychainRefusal()), "The keychain did not keep the password (-25308).")
        XCTAssertEqual(PostgreSQLMirrorController.message(for: Silence()), "The copy to PostgreSQL failed. Try again with Copy Now.")
    }
}

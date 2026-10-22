import XCTest
import GraphiteCore
import GraphiteIndex
import GraphitePostgreSQLMirror
import PostgresNIO
@testable import GraphiteUI
import GraphiteTestSupport

/// The PostgreSQL Mirror core plugin in the workspace: off until turned on, then a copy of the
/// open vault that follows its changes. The copies need a server
/// (`PostgreSQLTestServer`); the preferences do not.
@MainActor
final class UiPostgreSQLMirrorTests: XCTestCase {
    /// Preferences, vault list and indexes of their own, removed after each test.
    private var device: IsolatedWorkspaceDevice!
    private var testedConfiguration: PostgreSQLMirrorConfiguration?
    private var testedPassword = ""

    override func setUp() async throws {
        device = try IsolatedWorkspaceDevice.make(for: self)
    }

    override func tearDown() async throws {
        if let testedConfiguration {
            var logger = Logger(label: "UiPostgreSQLMirrorTests")
            logger.logLevel = .critical
            let connection = try await PostgresConnection.connect(
                configuration: PostgresConnection.Configuration(host: testedConfiguration.host, port: testedConfiguration.port, username: testedConfiguration.userName,
                                                                password: testedPassword, database: testedConfiguration.databaseName, tls: .disable),
                id: 4, logger: logger)
            _ = try? await connection.query(PostgresQuery(unsafeSQL: "DROP SCHEMA IF EXISTS \"\(testedConfiguration.schemaName)\" CASCADE"), logger: logger)
            try? await connection.close()
        }
    }

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

    func testTurningTheMirrorOnCopiesTheOpenVaultAndASaveIsCopiedAfterward() async throws {
        let configuration = try serverConfiguration()
        let vault = try makeVault(files: ["Paris.md": "---\ncoordinates: [48.8566, 2.3522]\n---\n# Paris\n"])
        let clock = ManualClock()
        let workspace = device.makeWorkspace(clock: clock)
        let password = testedPassword
        workspace.postgreSQLMirror.readPassword = { password }
        try await workspace.openFolderAsVault(vault)
        try await waitUntil { workspace.hasCompletedIndexScan }

        // Set up but off: nothing is copied.
        workspace.preferences.postgreSQLMirrorConfiguration = configuration
        workspace.copyToPostgreSQLMirrorNow()
        XCTAssertEqual(workspace.postgreSQLMirror.status, .idle)

        // Turned on as Settings does: the open vault is copied at once.
        workspace.setCorePluginEnabled(.postgreSQLMirror, true)
        try await waitUntil { Self.copiedNoteCount(workspace) == 1 }

        // A note written and taken in by the index, as a save is, is copied once changes settle.
        try Data("---\ncoordinates: [45.764, 4.8357]\n---\n# Lyon\n".utf8).write(to: vault.appendingPathComponent("Lyon.md"))
        workspace.refreshIndex(for: [try VaultPath("Lyon.md")])
        try await waitUntil { workspace.postgreSQLMirror.isCopyScheduled }
        // Time moves on until the copy, which waits for the vault to be still, has run.
        try await waitUntil(timeoutSeconds: 30) {
            clock.advance(by: PostgreSQLMirrorController.settleDelay)
            return Self.copiedNoteCount(workspace) == 2
        }

        // Turned off, the mirror stops following the vault.
        workspace.setCorePluginEnabled(.postgreSQLMirror, false)
        try Data("# Marseille\n".utf8).write(to: vault.appendingPathComponent("Marseille.md"))
        let versionBeforeMarseille = workspace.indexVersion
        workspace.refreshIndex(for: [try VaultPath("Marseille.md")])
        try await waitUntil { workspace.indexVersion > versionBeforeMarseille }
        XCTAssertFalse(workspace.postgreSQLMirror.isCopyScheduled, "Off, a change schedules no copy.")
        XCTAssertEqual(Self.copiedNoteCount(workspace), 2)
    }

    func testAnUnreachableServerIsReportedAndAutomaticCopiesWait() async throws {
        let configuration = try serverConfiguration()
        let vault = try makeVault(files: ["Paris.md": "# Paris\n"])
        let workspace = device.makeWorkspace()
        workspace.postgreSQLMirror.readPassword = { "not the password" }
        try await workspace.openFolderAsVault(vault)
        try await waitUntil { workspace.hasCompletedIndexScan }
        workspace.preferences.postgreSQLMirrorConfiguration = configuration
        workspace.preferences.setEnabled(.postgreSQLMirror, true)
        workspace.copyToPostgreSQLMirrorNow()
        try await waitUntil {
            if case .failed = workspace.postgreSQLMirror.status { return true }
            return false
        }
        guard case .failed(let message, _) = workspace.postgreSQLMirror.status else { return }
        XCTAssertTrue(message.contains("password authentication failed"), message)
    }

    func testAChangeWaitsTheSettleDelayAndAFailureHoldsAutomaticCopiesForTheRetryDelay() async throws {
        let configuration = try serverConfiguration()
        let vault = try makeVault(files: ["Paris.md": "# Paris\n"])
        let index = try VaultIndex(databaseURL: try TemporaryVault.make(prefix: "MirrorClockIndex", for: self).root.appendingPathComponent("index.sqlite"))
        _ = try await index.reconcile(root: vault)
        let source = PostgreSQLMirrorSource(vaultName: "Clock", index: index, store: VaultStore(root: vault), vaultRoot: vault,
                                                           configuration: configuration)
        let clock = ManualClock()
        let mirror = PostgreSQLMirrorController(clock: clock)
        mirror.readPassword = { "not the password" }

        mirror.schedule(source)
        try await clock.awaitPendingSleepers()
        clock.advance(by: PostgreSQLMirrorController.settleDelay - .seconds(1))
        XCTAssertEqual(mirror.status, .idle, "A run of saves makes one copy, once the vault has been still for the delay.")
        clock.advance(by: .seconds(1))
        try await waitUntil("the copy to fail") {
            if case .failed = mirror.status { return true }
            return false
        }

        mirror.schedule(source)
        XCTAssertFalse(mirror.isCopyScheduled, "Right after a failure, a change does not try the server again.")
        clock.advance(by: PostgreSQLMirrorController.retryDelay)
        mirror.schedule(source)
        XCTAssertTrue(mirror.isCopyScheduled, "A minute later it does.")
        mirror.stop()
    }

    // MARK: Helpers

    private func serverConfiguration() throws -> PostgreSQLMirrorConfiguration {
        let server = try PostgreSQLTestServer.require()
        let configuration = PostgreSQLMirrorConfiguration(host: server.host, port: server.port, databaseName: server.databaseName,
                                                          userName: server.userName, schemaName: "graphite_ui_test_" + UUID().uuidString.prefix(8).lowercased(),
                                                          transportSecurity: .off)
        testedConfiguration = configuration
        testedPassword = server.password
        return configuration
    }

    private static func copiedNoteCount(_ workspace: WorkspaceModel) -> Int? {
        guard case .copied(let report, _) = workspace.postgreSQLMirror.status else { return nil }
        return report.copiedNoteCount
    }

    private func makeVault(files: [String: String]) throws -> URL {
        try TemporaryVault.make(prefix: "MirrorWorkspace", files: files, for: self).root
    }
}

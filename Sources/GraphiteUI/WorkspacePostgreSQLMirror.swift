import Foundation
import Observation
import GraphiteCore
import GraphiteApple
import GraphitePostgreSQLMirror

/// The PostgreSQL Mirror core plugin for the open vault: a copy starts a few seconds after the
/// index takes in changes, one copy runs at a time, and the settings page shows what the last
/// one did. The copy itself runs off the main thread, in the mirror's and the index's actors.
@MainActor @Observable
final class PostgreSQLMirrorController {
    enum Status: Equatable {
        case idle
        case copying
        case copied(PostgreSQLMirrorReport, finishedAt: Date)
        case failed(String, finishedAt: Date)
    }

    /// How long a copy waits after the index changes, so a run of saves makes one copy.
    static let settleDelay: Duration = .seconds(5)
    /// After a failed copy, how long automatic copies wait before trying the server again;
    /// Copy Now does not wait.
    static let retryDelay: Duration = .seconds(60)

    private(set) var status: Status = .idle
    /// The copies' delays and timings are counted on it.
    private let clock: any ApplicationClock
    /// Reads the password when a copy starts, off the main thread; tests give their own.
    @ObservationIgnored var readPassword: @Sendable () -> String = { PostgreSQLPasswordStore().password() }
    /// Keeps the password in the keychain, or forgets it when it is empty; tests give their own.
    @ObservationIgnored var savePassword: (String) throws -> Void = { password in try PostgreSQLPasswordStore().setPassword(password) }
    @ObservationIgnored private var mirror: PostgreSQLMirror?
    @ObservationIgnored private var mirrorSettings: (configuration: PostgreSQLMirrorConfiguration, password: String)?
    @ObservationIgnored private var scheduledCopy: Task<Void, Never>?
    @ObservationIgnored private var runningCopy: Task<Void, Never>?
    /// A copy asked for while one runs; it starts when that one ends.
    @ObservationIgnored private var pendingCopy: (source: PostgreSQLMirrorSource, rechecksDatabase: Bool)?
    @ObservationIgnored private var automaticCopiesResumeAt: Duration?

    init(clock: any ApplicationClock) {
        self.clock = clock
    }

    /// Whether a copy waits for the vault to be still for `settleDelay`.
    var isCopyScheduled: Bool { scheduledCopy != nil }

    /// Starts a copy after `settleDelay`, replacing a copy scheduled earlier.
    func schedule(_ source: PostgreSQLMirrorSource) {
        if let automaticCopiesResumeAt, clock.now < automaticCopiesResumeAt { return }
        scheduledCopy?.cancel()
        scheduledCopy = Task { [clock] in
            do { try await clock.sleep(for: Self.settleDelay) } catch { return } // Replaced by a later change, or stopped.
            scheduledCopy = nil
            start(source, rechecksDatabase: false)
        }
    }

    /// Starts a copy now, or as soon as the running one ends, comparing with the database even
    /// when nothing changed in the index.
    func copyNow(_ source: PostgreSQLMirrorSource) {
        scheduledCopy?.cancel()
        automaticCopiesResumeAt = nil
        start(source, rechecksDatabase: true)
    }

    /// Stops copying: the vault closed or the plugin was turned off. A copy in progress is
    /// cancelled, and its transaction is rolled back.
    func stop() {
        scheduledCopy?.cancel()
        runningCopy?.cancel()
        scheduledCopy = nil
        runningCopy = nil
        pendingCopy = nil
        if status == .copying { status = .idle }
    }

    private func start(_ source: PostgreSQLMirrorSource, rechecksDatabase: Bool) {
        guard runningCopy == nil else {
            pendingCopy = (source, rechecksDatabase || pendingCopy?.rechecksDatabase == true)
            return
        }
        status = .copying
        let readPassword = readPassword
        runningCopy = Task {
            do {
                // The keychain and the vault's small settings files are read off the main thread.
                let password = await Task.detached(priority: .utility) { readPassword() }.value
                let placePropertyNames = await Task.detached(priority: .utility) { PlacedNote.propertyNames(vaultRoot: source.vaultRoot) }.value
                let declaredPropertyTypes = await source.store.propertyTypes()
                let vault = MirroredVault(name: source.vaultName, declaredPropertyTypes: declaredPropertyTypes, placePropertyNames: placePropertyNames)
                let report = try await mirror(for: source.configuration, password: password).copy(vault, from: source.index, rechecksDatabase: rechecksDatabase)
                guard !Task.isCancelled else { return }
                status = .copied(report, finishedAt: .now)
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                status = .failed(Self.message(for: error), finishedAt: .now)
                automaticCopiesResumeAt = clock.now + Self.retryDelay
            }
            runningCopy = nil
            if let pendingCopy {
                self.pendingCopy = nil
                start(pendingCopy.source, rechecksDatabase: pendingCopy.rechecksDatabase)
            }
        }
    }

    /// The server these settings reach, for the settings page's connection test.
    func describeServer(configuration: PostgreSQLMirrorConfiguration, password: String) async throws -> PostgreSQLServerDescription {
        try await PostgreSQLMirror(configuration: configuration, password: password, clock: clock).describeServer()
    }

    /// What the settings page says when a copy, a connection test or saving the password failed:
    /// the server and what it answered, and what to do next.
    static func message(for error: any Error) -> String {
        switch error as? PostgreSQLMirrorError {
        case .connectionRefused(let server, let message):
            "\(server) refused the connection: \(message)"
        case .encryptionUnavailable(let server):
            "\(server) does not offer encryption. Choose another Encryption setting, or turn encryption on in the server."
        case .unreachable(let server, let reason):
            "Graphite could not reach \(server): \(reason). Check the address and the port, and that the server accepts connections from this device."
        case .copyRefused(let message):
            "The server refused the copy: \(message)"
        case .copyStopped(let reason):
            "The copy stopped: \(reason)."
        case nil:
            (error as? LocalizedError)?.errorDescription ?? "The copy to PostgreSQL failed. Try again with Copy Now."
        }
    }

    /// The mirror for these settings: the same one while they stay the same, so it keeps what
    /// it knows about the vault and the database between copies.
    private func mirror(for configuration: PostgreSQLMirrorConfiguration, password: String) -> PostgreSQLMirror {
        if let mirror, let mirrorSettings, mirrorSettings.configuration == configuration, mirrorSettings.password == password { return mirror }
        let newMirror = PostgreSQLMirror(configuration: configuration, password: password, clock: clock)
        mirror = newMirror
        mirrorSettings = (configuration, password)
        return newMirror
    }
}

/// The PostgreSQL Mirror core plugin.
extension WorkspaceModel {
    /// What a copy of the open vault needs, or nil when there is nothing to copy yet: the
    /// plugin is off or not set up, no vault is open, or the index has not read the whole
    /// vault (a note it does not hold yet would be deleted from the database).
    private var postgreSQLMirrorSource: PostgreSQLMirrorSource? {
        guard preferences.isEnabled(.postgreSQLMirror), preferences.postgreSQLMirrorConfiguration.missingSetting == nil, hasCompletedIndexScan,
              let index, let store, let root = folderAccess?.root, let currentVaultIdentifier,
              let vault = vaultLibrary.vault(withIdentifier: currentVaultIdentifier) else { return nil }
        return PostgreSQLMirrorSource(vaultName: vault.name, index: index, store: store, vaultRoot: root,
                                                     configuration: preferences.postgreSQLMirrorConfiguration)
    }

    /// After the index takes in changes.
    func schedulePostgreSQLMirrorCopy() {
        guard let source = postgreSQLMirrorSource else { return }
        postgreSQLMirror.schedule(source)
    }

    /// Copy Now, and after the settings change or the plugin is turned on.
    func copyToPostgreSQLMirrorNow() {
        guard let source = postgreSQLMirrorSource else { return }
        postgreSQLMirror.copyNow(source)
    }
}

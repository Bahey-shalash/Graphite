import Foundation
import GraphiteCore
import GraphiteIndex

/// What a window hears about the index of its vault, which every window on that vault shares.
enum VaultIndexEvent: Sendable {
    /// A scan of the whole vault started, asked for by this window or another.
    case scanStarted
    /// A scan ended; `isAnotherScanQueued` when a scan asked for meanwhile runs next.
    case scanFinished(IndexingReport, isAnotherScanQueued: Bool)
    /// A scan stopped before its end, as when the index is emptied for a rebuild.
    case scanCancelled
    case scanFailed(any Error)
    /// Every entry was removed for a rebuild: the index is incomplete until the next scan
    /// ends, so a link followed meanwhile must not create a note that exists.
    case emptied
}

/// Whether a scan asked for must read the vault again, or may stand on one that already
/// ended or is running.
enum VaultIndexScanRequest {
    /// A window opening the vault: another window's finished or running scan serves it.
    case unlessScanned
    /// Something changed that a scan which started earlier may have missed.
    case always
}

/// One index per vault for the whole process (decision 12 of
/// `Docs/solid/rewrite-foundations.md`). Two windows on one vault used to open the vault's
/// cache file twice, failing each other's writes ("database is locked") and pruning each
/// other's rows on rescan. Now they share one `VaultIndex`, an actor and so the file's single
/// writer, and one scan at a time; the index closes when the last window on its vault ends
/// its lease. Two vaults in two windows keep an index each.
@MainActor
final class VaultIndexRegistry {
    /// One vault's index and its scans, while a window has the vault open.
    private final class SharedIndex {
        let opening: Task<VaultIndex, any Error>
        /// The folder scans read: the latest a window opened the vault at.
        var root: URL
        var listeners: [UUID: AsyncStream<VaultIndexEvent>.Continuation] = [:]
        var runningScan: Task<Void, Never>?
        var isScanQueued = false
        /// The last finished scan's report; nil before one finished or once the index is emptied.
        var lastReport: IndexingReport?

        init(root: URL, opening: Task<VaultIndex, any Error>) {
            self.root = root
            self.opening = opening
        }
    }

    private let cachesFolder: URL?
    private var sharedIndexes: [UUID: SharedIndex] = [:]

    /// Indexes kept in `cachesFolder`, or in the system's Caches folder when nil.
    init(cachesFolder: URL?) {
        self.cachesFolder = cachesFolder
    }

    /// Whether a window has the vault open, so its index must stay.
    func isOpen(_ vaultIdentifier: UUID) -> Bool { sharedIndexes[vaultIdentifier] != nil }

    /// The index of the vault `vaultIdentifier` at `root`, opened unless a window has it open.
    func lease(forVault vaultIdentifier: UUID, root: URL) async throws -> VaultIndexLease {
        let shared = sharedIndexes[vaultIdentifier] ?? open(vaultIdentifier, root: root)
        shared.root = root
        let (events, continuation) = AsyncStream.makeStream(of: VaultIndexEvent.self)
        let leaseIdentifier = UUID()
        // Counted before the wait, so a window that closes meanwhile does not close the index.
        shared.listeners[leaseIdentifier] = continuation
        do {
            let index = try await shared.opening.value
            return VaultIndexLease(identifier: leaseIdentifier, vaultIdentifier: vaultIdentifier, index: index, events: events, registry: self)
        } catch {
            continuation.finish()
            shared.listeners[leaseIdentifier] = nil
            // A failed opening is not kept: the next window to open the vault tries again.
            if sharedIndexes[vaultIdentifier] === shared { sharedIndexes[vaultIdentifier] = nil }
            throw error
        }
    }

    private func open(_ vaultIdentifier: UUID, root: URL) -> SharedIndex {
        let cachesFolder = cachesFolder
        let shared = SharedIndex(root: root, opening: Task.detached(priority: .utility) {
            let location = try VaultIndex.cacheURL(forVault: vaultIdentifier, legacyRoot: root, in: cachesFolder)
            return try VaultIndex(databaseURL: location)
        })
        sharedIndexes[vaultIdentifier] = shared
        return shared
    }

    fileprivate func requestScan(_ request: VaultIndexScanRequest, for lease: VaultIndexLease) {
        guard let shared = sharedIndexes[lease.vaultIdentifier], shared.listeners[lease.identifier] != nil else { return }
        if shared.runningScan != nil {
            // The running scan may have read past what prompted the request.
            if request == .always { shared.isScanQueued = true }
            return
        }
        if request == .unlessScanned, let lastReport = shared.lastReport {
            shared.listeners[lease.identifier]?.yield(.scanFinished(lastReport, isAnotherScanQueued: false))
            return
        }
        startScan(of: shared, index: lease.index)
    }

    private func startScan(of shared: SharedIndex, index: VaultIndex) {
        shared.isScanQueued = false
        broadcast(.scanStarted, to: shared)
        let root = shared.root
        // Below the editor's priority, so a scan does not compete with typing and scrolling.
        shared.runningScan = Task(priority: .utility) { [weak self, weak shared] in
            let outcome: Result<IndexingReport, any Error>
            do { outcome = .success(try await index.reconcile(root: root)) } catch { outcome = .failure(error) }
            guard let self, let shared else { return }
            self.scanDidEnd(of: shared, index: index, with: outcome)
        }
    }

    private func scanDidEnd(of shared: SharedIndex, index: VaultIndex, with outcome: Result<IndexingReport, any Error>) {
        shared.runningScan = nil
        // The last window on the vault closed meanwhile.
        guard !shared.listeners.isEmpty else { return }
        switch outcome {
        case .success(let report):
            shared.lastReport = report
            broadcast(.scanFinished(report, isAnotherScanQueued: shared.isScanQueued), to: shared)
        case .failure(let error) where error is CancellationError:
            broadcast(.scanCancelled, to: shared)
        case .failure(let error):
            broadcast(.scanFailed(error), to: shared)
        }
        if shared.isScanQueued { startScan(of: shared, index: index) }
    }

    /// Empties the index and scans the vault again, for every window on it. A scan running
    /// is stopped first: it would count entries the removal deletes.
    fileprivate func rebuild(for lease: VaultIndexLease) async throws {
        guard let shared = sharedIndexes[lease.vaultIdentifier] else { return }
        let previousReport = shared.lastReport
        shared.lastReport = nil
        shared.isScanQueued = false
        broadcast(.emptied, to: shared)
        if let runningScan = shared.runningScan {
            runningScan.cancel()
            await runningScan.value
        }
        do {
            try await lease.index.removeAllEntries()
        } catch {
            // The removal is one transaction, so the index is as it was.
            if let previousReport, shared.runningScan == nil {
                shared.lastReport = previousReport
                broadcast(.scanFinished(previousReport, isAnotherScanQueued: false), to: shared)
            }
            throw error
        }
        guard !shared.listeners.isEmpty, shared.runningScan == nil else { return }
        startScan(of: shared, index: lease.index)
    }

    fileprivate func endLease(_ lease: VaultIndexLease) {
        guard let shared = sharedIndexes[lease.vaultIdentifier],
              let continuation = shared.listeners.removeValue(forKey: lease.identifier) else { return }
        continuation.finish()
        guard shared.listeners.isEmpty else { return }
        // The last window on the vault: its scan stops and the index closes once the
        // windows let go of it.
        shared.runningScan?.cancel()
        sharedIndexes[lease.vaultIdentifier] = nil
    }

    private func broadcast(_ event: VaultIndexEvent, to shared: SharedIndex) {
        for continuation in shared.listeners.values { continuation.yield(event) }
    }
}

/// One window's hold on its vault's shared index: the index, the events of its scans, and
/// the scans and rebuilds the window asks for. Ending it, or letting it go, lets the index
/// close when no other window holds it.
@MainActor
final class VaultIndexLease {
    fileprivate let identifier: UUID
    let vaultIdentifier: UUID
    let index: VaultIndex
    /// Every scan's start and end, and the rebuild's emptying, whichever window asked.
    let events: AsyncStream<VaultIndexEvent>
    private weak var registry: VaultIndexRegistry?

    fileprivate init(identifier: UUID, vaultIdentifier: UUID, index: VaultIndex, events: AsyncStream<VaultIndexEvent>, registry: VaultIndexRegistry) {
        self.identifier = identifier
        self.vaultIdentifier = vaultIdentifier
        self.index = index
        self.events = events
        self.registry = registry
    }

    isolated deinit {
        registry?.endLease(self)
    }

    func requestScan(_ request: VaultIndexScanRequest) {
        registry?.requestScan(request, for: self)
    }

    func rebuild() async throws {
        try await registry?.rebuild(for: self)
    }

    func end() {
        registry?.endLease(self)
    }
}

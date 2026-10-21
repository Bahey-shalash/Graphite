import Foundation
import Observation
import GraphiteCore

/// How many items each folder tile on screen holds, as the Files app says it under a folder's
/// name. Counted one folder at a time off the main actor, only for tiles on screen, and
/// forgotten when a tile scrolls away. A new vault gets a new instance.
@MainActor @Observable
final class LibraryFolderItemCounts {
    /// Counts the items of a folder, off the main actor; nil when it cannot be read.
    typealias Counter = @Sendable (VaultPath) async -> Int?

    /// The counts of the folders on screen.
    private(set) var counts: [VaultPath: Int] = [:]

    @ObservationIgnored private let countItems: Counter
    /// How many tiles of each folder are on screen. SwiftUI shows a rebuilt grid's tile before
    /// it removes the old one, so a folder's count goes only when its last tile does.
    @ObservationIgnored private var visibleTileCounts: [VaultPath: Int] = [:]
    /// Folders on screen whose count waits its turn, oldest first.
    @ObservationIgnored private var waitingFolders: [VaultPath] = []
    /// Counts the waiting folders one at a time; nil while none waits.
    @ObservationIgnored private var worker: Task<Void, Never>?

    init(countItems: @escaping Counter) {
        self.countItems = countItems
    }

    func tileAppeared(_ folder: VaultPath) {
        visibleTileCounts[folder, default: 0] += 1
        enqueue(folder)
    }

    func tileDisappeared(_ folder: VaultPath) {
        let remainingTiles = max(visibleTileCounts[folder, default: 0] - 1, 0)
        visibleTileCounts[folder] = remainingTiles == 0 ? nil : remainingTiles
        guard remainingTiles == 0 else { return }
        counts[folder] = nil
        waitingFolders.removeAll { waitingFolder in waitingFolder == folder }
    }

    /// Counts the folders on screen again after the listing changed; the old numbers stay until the new ones are known.
    func refreshVisibleFolders() {
        for folder in visibleTileCounts.keys.sorted() { enqueue(folder) }
    }

    /// Stops counting and forgets every count, as when the vault or the folder shown changes.
    func cancelAll() {
        worker?.cancel()
        worker = nil
        waitingFolders = []
        visibleTileCounts = [:]
        counts = [:]
    }

    private func enqueue(_ folder: VaultPath) {
        if !waitingFolders.contains(folder) { waitingFolders.append(folder) }
        guard worker == nil else { return }
        worker = Task { [weak self] in await self?.countWaitingFolders() }
    }

    private func countWaitingFolders() async {
        while !waitingFolders.isEmpty {
            let folder = waitingFolders.removeFirst()
            guard visibleTileCounts[folder] != nil else { continue }
            let count = await countItems(folder)
            guard !Task.isCancelled else { return }
            if visibleTileCounts[folder] != nil, let count { counts[folder] = count }
        }
        worker = nil
    }
}

import Foundation
import ShareInbox

/// The app's end of the share inbox: reads and removes items off the main actor, lets one
/// delivery run at a time, and remembers which failures the person was already told about in
/// this run, so an item that keeps failing is not announced each time Graphite comes back.
@MainActor
final class SharedItemReceiver {
    /// A draft the share extension has not committed after this long was abandoned.
    nonisolated static let abandonedDraftAgeSeconds: TimeInterval = 3_600

    let inbox: ShareInbox
    private enum PassState { case idle, running, runningWithAnotherRequested }
    private var passState = PassState.idle
    /// The failure last reported for each item's folder.
    private var reportedFailures: [URL: String] = [:]

    init(inbox: ShareInbox) {
        self.inbox = inbox
    }

    /// Runs `receive`, one pass at a time: a request during a pass (the vault that was
    /// reopening at launch is open now) runs one more pass after it, rather than a second
    /// pass beside it.
    func receiveInPasses(_ receive: () async -> Void) async {
        guard passState == .idle else {
            passState = .runningWithAnotherRequested
            return
        }
        repeat {
            passState = .running
            await receive()
        } while passState == .runningWithAnotherRequested
        passState = .idle
    }

    /// The inbox's items, oldest first, after clearing drafts abandoned before `now`.
    func pendingEntries(now: Date) async throws -> [ShareInboxEntry] {
        let inbox = inbox
        return try await Task.detached(priority: .utility) {
            try inbox.removeAbandonedDrafts(startedBefore: now.addingTimeInterval(-Self.abandonedDraftAgeSeconds))
            return try inbox.pendingItems()
        }.value
    }

    func removeDeliveredItem(_ item: PendingSharedItem) async throws {
        let inbox = inbox
        try await Task.detached(priority: .utility) { try inbox.removeDeliveredItem(item) }.value
        reportedFailures[item.folder] = nil
    }

    /// Whether `message` about the item in `folder` is news to the person in this run.
    func isNewFailure(_ message: String, ofItemIn folder: URL) -> Bool {
        guard reportedFailures[folder] != message else { return false }
        reportedFailures[folder] = message
        return true
    }
}

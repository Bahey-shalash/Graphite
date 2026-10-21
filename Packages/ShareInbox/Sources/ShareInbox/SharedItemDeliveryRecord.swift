import Foundation

/// What the app has already done with an item, `delivery.json` in the item's folder. A
/// delivery that stops halfway (the app is closed, a vault is unavailable) starts again from
/// here, so no attachment is copied twice and no note is written twice.
public struct SharedItemDeliveryRecord: Codable, Equatable, Sendable {
    /// The vault the progress below belongs to. Progress in another vault is not reused.
    public var vaultIdentifier: UUID?
    /// Each attachment already copied, by its file name in the item, to its path in the vault.
    public var deliveredAttachmentPaths: [String: String]
    /// The note written or appended to; the item is finished once this is set.
    public var notePath: String?
    public var failureCount: Int
    /// What went wrong the last time, as the app worded it for the person.
    public var lastFailureDescription: String?
    public var lastAttemptDate: Date?

    public init(vaultIdentifier: UUID? = nil, deliveredAttachmentPaths: [String: String] = [:], notePath: String? = nil, failureCount: Int = 0,
                lastFailureDescription: String? = nil, lastAttemptDate: Date? = nil) {
        self.vaultIdentifier = vaultIdentifier
        self.deliveredAttachmentPaths = deliveredAttachmentPaths
        self.notePath = notePath
        self.failureCount = failureCount
        self.lastFailureDescription = lastFailureDescription
        self.lastAttemptDate = lastAttemptDate
    }

    /// The progress that applies to a delivery into `vaultIdentifier`: this record, or an
    /// empty one with the failure history kept when the progress was made in another vault.
    public func progress(forVault vaultIdentifier: UUID) -> SharedItemDeliveryRecord {
        guard self.vaultIdentifier != vaultIdentifier else { return self }
        return SharedItemDeliveryRecord(vaultIdentifier: vaultIdentifier, failureCount: failureCount,
                                        lastFailureDescription: lastFailureDescription, lastAttemptDate: lastAttemptDate)
    }
}

import XCTest
@testable import ShareInbox

final class SharedItemDeliveryRecordTests: XCTestCase {
    func testProgressInTheSameVaultIsKept() {
        let vaultIdentifier = UUID()
        let record = SharedItemDeliveryRecord(vaultIdentifier: vaultIdentifier, deliveredAttachmentPaths: ["A.png": "A.png"], notePath: "Note.md")
        XCTAssertEqual(record.progress(forVault: vaultIdentifier), record)
    }

    func testProgressInAnotherVaultStartsOverAndKeepsTheFailureHistory() {
        let record = SharedItemDeliveryRecord(vaultIdentifier: UUID(), deliveredAttachmentPaths: ["A.png": "A.png"], notePath: "Note.md",
                                              failureCount: 2, lastFailureDescription: "Unavailable", lastAttemptDate: Date(timeIntervalSince1970: 5))
        let otherVault = UUID()
        XCTAssertEqual(record.progress(forVault: otherVault),
                       SharedItemDeliveryRecord(vaultIdentifier: otherVault, failureCount: 2, lastFailureDescription: "Unavailable",
                                                lastAttemptDate: Date(timeIntervalSince1970: 5)))
    }
}

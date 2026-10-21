import XCTest
import ShareInbox
import GraphiteTestSupport
@testable import GraphiteCore

final class SharedItemDeliveryTests: XCTestCase {
    /// 2026-10-14 17:46:40 UTC, 19:46:40 in Zurich.
    private let sharedDate = Date(timeIntervalSince1970: 1_792_000_000)
    private let zurich = TimeZone(identifier: "Europe/Zurich") ?? .gmt
    private let vaultIdentifier = UUID()
    private let maximumNoteBytes = 1_048_576

    private struct Share {
        let vault: TemporaryVault
        let inbox: ShareInbox
        let store: VaultStore
    }

    private func makeShare(files: [String: String] = [:]) throws -> Share {
        let vault = try TemporaryVault.make(prefix: "SharedItemDelivery", files: files, for: self)
        let container = try TemporaryVault.make(prefix: "ShareContainer", for: self)
        return Share(vault: vault, inbox: ShareInbox(containerFolder: container.root), store: VaultStore(root: vault.root))
    }

    /// Commits an item as the share extension does and returns it as the app finds it.
    private func share(_ text: String, title: String = "Lecture 4", destination: SharedItemDestination = .newNote,
                       attachments: [String: String] = [:], in share: Share) throws -> PendingSharedItem {
        let draft = try share.inbox.makeDraft()
        var fileNames: [String] = []
        for (fileName, contents) in attachments.sorted(by: { first, second in first.key < second.key }) {
            fileNames.append(try draft.addAttachment(contents: Data(contents.utf8), preferredFileName: fileName))
        }
        try draft.commit(noteText: text, manifest: SharedItemManifest(identifier: draft.identifier, createdDate: sharedDate, vaultIdentifier: vaultIdentifier,
                                                                      vaultName: "Physics", destination: destination, title: title, attachmentFileNames: fileNames))
        return try pendingItem(withIdentifier: draft.identifier, in: share)
    }

    private func pendingItem(withIdentifier identifier: UUID, in share: Share) throws -> PendingSharedItem {
        let items = try share.inbox.pendingItems().compactMap { entry -> PendingSharedItem? in
            if case .item(let item) = entry, item.manifest.identifier == identifier { return item }
            return nil
        }
        return try XCTUnwrap(items.first)
    }

    private func deliver(_ item: PendingSharedItem, in share: Share) async throws -> SharedItemDeliveryOutcome {
        let delivery = SharedItemDelivery(store: share.store, inbox: share.inbox, vaultIdentifier: vaultIdentifier, timeZone: zurich, maximumNoteBytes: maximumNoteBytes)
        return try await delivery.deliver(item, now: sharedDate, embedText: { attachment, note, settings in
            AttachmentResolver().embed(attachment: attachment, note: note, settings: settings, isNameUniqueInVault: false)
        }, appendToExistingNote: SharedItemDelivery.appendingInFile(store: share.store, maximumNoteBytes: maximumNoteBytes))
    }

    private static let folderSettings = #"{"newFileLocation":"folder","newFileFolderPath":"Inbox","attachmentFolderPath":"Attachments"}"#

    func testANewNoteGoesToTheNewNoteFolderWithItsTextAndTheEmbedsOfItsFiles() async throws {
        let share = try makeShare(files: [".obsidian/app.json": Self.folderSettings])
        let item = try self.share("[Paper](https://example.com/paper)", attachments: ["Board.jpeg": "jpeg bytes"], in: share)
        let outcome = try await deliver(item, in: share)
        XCTAssertEqual(outcome, SharedItemDeliveryOutcome(notePath: try VaultPath("Inbox/Lecture 4.md"), attachmentPaths: [try VaultPath("Attachments/Board.jpeg")],
                                                          destination: .newNote))
        XCTAssertEqual(try share.vault.readText(at: "Inbox/Lecture 4.md"), "[Paper](https://example.com/paper)\n\n![[Attachments/Board.jpeg]]\n")
        XCTAssertEqual(try share.vault.readText(at: "Attachments/Board.jpeg"), "jpeg bytes")
    }

    func testTakenNamesGiveTheNoteAndItsFileTheNextFreeNames() async throws {
        let share = try makeShare(files: [".obsidian/app.json": Self.folderSettings, "Inbox/Lecture 4.md": "Mine", "Attachments/Board.jpeg": "older"])
        let outcome = try await deliver(try self.share("Text", attachments: ["Board.jpeg": "newer"], in: share), in: share)
        XCTAssertEqual(outcome.notePath.rawValue, "Inbox/Lecture 4 1.md")
        XCTAssertEqual(outcome.attachmentPaths.map(\.rawValue), ["Attachments/Board 1.jpeg"])
        XCTAssertEqual(try share.vault.readText(at: "Inbox/Lecture 4.md"), "Mine")
        XCTAssertEqual(try share.vault.readText(at: "Attachments/Board.jpeg"), "older")
    }

    func testATitleNoNoteNameMayHoldIsMadeIntoOne() async throws {
        let share = try makeShare()
        let outcome = try await deliver(try self.share("Text", title: "Q&A: [draft] #1", in: share), in: share)
        XCTAssertEqual(outcome.notePath.rawValue, "Q&A draft 1.md")
    }

    func testTheDailyNoteOfTheDaySharedIsCreatedFromItsTemplateThenAddedTo() async throws {
        let share = try makeShare(files: [".obsidian/daily-notes.json": #"{"folder":"Daily","template":"Templates/Daily"}"#,
                                          "Templates/Daily.md": "# {{date:dddd D MMMM}}\n"])
        let outcome = try await deliver(try self.share("Shared thought", destination: .dailyNote, in: share), in: share)
        XCTAssertEqual(outcome.notePath.rawValue, "Daily/2026-10-14.md")
        XCTAssertEqual(try share.vault.readText(at: "Daily/2026-10-14.md"), "# Wednesday 14 October\n\nShared thought\n")
    }

    func testAnExistingDailyNoteKeepsItsTextAndLineEndingsAndGetsTheItemAtItsEnd() async throws {
        let share = try makeShare(files: ["2026-10-14.md": "Morning\r\nPlan"])
        _ = try await deliver(try self.share("Line one\nLine two", destination: .dailyNote, in: share), in: share)
        XCTAssertEqual(try share.vault.readText(at: "2026-10-14.md"), "Morning\r\nPlan\r\n\r\nLine one\r\nLine two\r\n")
    }

    func testADailyNoteWithAByteOrderMarkKeepsIt() async throws {
        let share = try makeShare()
        try share.vault.writeFile("2026-10-14.md", data: Data([0xEF, 0xBB, 0xBF]) + Data("Plan\n".utf8))
        _ = try await deliver(try self.share("Shared", destination: .dailyNote, in: share), in: share)
        XCTAssertEqual(try Data(contentsOf: share.vault.location(of: "2026-10-14.md")), Data([0xEF, 0xBB, 0xBF]) + Data("Plan\n\nShared\n".utf8))
    }

    func testUnreadableDailyNoteSettingsRefuseTheItemAndCountTheFailure() async throws {
        let share = try makeShare()
        try share.vault.createFolder(".obsidian/daily-notes.json")
        let item = try self.share("Shared", destination: .dailyNote, in: share)
        do {
            _ = try await deliver(item, in: share)
            XCTFail("Unreadable Daily notes settings refuse the item.")
        } catch {}
        let kept = try pendingItem(withIdentifier: item.manifest.identifier, in: share)
        XCTAssertEqual(kept.deliveryRecord?.failureCount, 1)
        XCTAssertEqual(kept.deliveryRecord?.lastAttemptDate, sharedDate)
        XCTAssertFalse(share.vault.fileExists(at: "2026-10-14.md"))
    }

    func testADeliveryThatStoppedStartsAgainWithoutCopyingAFileTwice() async throws {
        let share = try makeShare(files: [".obsidian/daily-notes.json": #"{"template":"Daily template"}"#])
        let item = try self.share("Shared", destination: .dailyNote, attachments: ["Board.jpeg": "bytes"], in: share)
        do {
            _ = try await deliver(item, in: share)
            XCTFail("A missing template stops the delivery.")
        } catch DailyNoteCreation.Failure.templateMissing(let templatePath) {
            XCTAssertEqual(templatePath.rawValue, "Daily template.md")
        }
        XCTAssertTrue(share.vault.fileExists(at: "Board.jpeg"), "The file copied before the stop stays in the vault.")
        try share.vault.writeFile("Daily template.md", text: "")
        let outcome = try await deliver(try pendingItem(withIdentifier: item.manifest.identifier, in: share), in: share)
        XCTAssertEqual(outcome.attachmentPaths.map(\.rawValue), ["Board.jpeg"])
        XCTAssertFalse(share.vault.fileExists(at: "Board 1.jpeg"), "The file is not copied a second time.")
        XCTAssertEqual(try share.vault.readText(at: "2026-10-14.md"), "Shared\n\n![[Board.jpeg]]\n")
    }

    func testAnItemDeliveredBeforeIsNotWrittenAgain() async throws {
        let share = try makeShare(files: ["2026-10-14.md": "Plan\n"])
        let item = try self.share("Shared", destination: .dailyNote, in: share)
        let firstOutcome = try await deliver(item, in: share)
        let secondOutcome = try await deliver(try pendingItem(withIdentifier: item.manifest.identifier, in: share), in: share)
        XCTAssertEqual(secondOutcome, firstOutcome)
        XCTAssertEqual(try share.vault.readText(at: "2026-10-14.md"), "Plan\n\nShared\n")
    }

    func testProgressMadeInAnotherVaultIsNotReused() async throws {
        let share = try makeShare()
        let item = try self.share("Shared", in: share)
        try share.inbox.saveDeliveryRecord(SharedItemDeliveryRecord(vaultIdentifier: UUID(), notePath: "Elsewhere.md"), for: item)
        let outcome = try await deliver(try pendingItem(withIdentifier: item.manifest.identifier, in: share), in: share)
        XCTAssertEqual(outcome.notePath.rawValue, "Lecture 4.md")
        XCTAssertTrue(share.vault.fileExists(at: "Lecture 4.md"))
    }

    func testADestinationThisBuildDoesNotKnowIsRefusedAndKept() async throws {
        let share = try makeShare()
        let item = try self.share("Shared", destination: .unknown("canvas"), in: share)
        do {
            _ = try await deliver(item, in: share)
            XCTFail("An unknown destination is refused.")
        } catch SharedItemDeliveryFailure.unknownDestination(let rawValue) {
            XCTAssertEqual(rawValue, "canvas")
        }
        XCTAssertEqual(try share.inbox.pendingItems().count, 1)
    }
}

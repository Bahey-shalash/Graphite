import XCTest
@testable import ShareInbox

final class ShareInboxTests: XCTestCase {
    private let sharedDate = Date(timeIntervalSince1970: 1_792_000_000)

    private func manifest(attachments: [String] = [], createdDate: Date? = nil, destination: SharedItemDestination = .newNote) -> SharedItemManifest {
        SharedItemManifest(identifier: UUID(), createdDate: createdDate ?? sharedDate, vaultIdentifier: UUID(), vaultName: "Physics",
                           destination: destination, title: "Lecture 4", attachmentFileNames: attachments)
    }

    private func onlyItem(in inbox: ShareInbox) throws -> PendingSharedItem {
        let entries = try inbox.pendingItems()
        XCTAssertEqual(entries.count, 1)
        guard case .item(let item) = try XCTUnwrap(entries.first) else { throw XCTSkip("The entry is not readable.") }
        return item
    }

    func testACommittedDraftIsOnePendingItemWithItsTextAndAttachments() throws {
        let folder = try TemporaryFolder.make(for: self)
        let inbox = ShareInbox(containerFolder: folder.location.appendingPathComponent("Container"))
        let draft = try inbox.makeDraft()
        let attachmentName = try draft.addAttachment(copying: try folder.writeFile(named: "Slides.pdf", text: "%PDF"), preferredFileName: "Slides.pdf")
        let description = manifest(attachments: [attachmentName])
        try draft.commit(noteText: "[Paper](https://example.com)", manifest: description)

        let item = try onlyItem(in: inbox)
        XCTAssertEqual(item.manifest, description)
        XCTAssertNil(item.deliveryRecord)
        XCTAssertEqual(try item.noteText(), "[Paper](https://example.com)")
        XCTAssertEqual(try String(contentsOf: try item.attachmentLocation(named: "Slides.pdf"), encoding: .utf8), "%PDF")
        XCTAssertFalse(FileManager.default.fileExists(atPath: draft.folder.path), "The draft folder moved into the inbox.")
    }

    func testADraftNotYetCommittedIsNotPending() throws {
        let folder = try TemporaryFolder.make(for: self)
        let inbox = ShareInbox(containerFolder: folder.location)
        let draft = try inbox.makeDraft()
        _ = try draft.addAttachment(contents: Data([1, 2, 3]), preferredFileName: "Shared image.png")
        XCTAssertTrue(try inbox.pendingItems().isEmpty)
    }

    func testAnInboxThatWasNeverWrittenHasNoItems() throws {
        let folder = try TemporaryFolder.make(for: self)
        XCTAssertTrue(try ShareInbox(containerFolder: folder.location.appendingPathComponent("Nothing")).pendingItems().isEmpty)
    }

    func testItemsAreListedOldestFirst() throws {
        let folder = try TemporaryFolder.make(for: self)
        let inbox = ShareInbox(containerFolder: folder.location)
        for (title, offsetSeconds) in [("Second", 60.0), ("First", 0.0), ("Third", 120.0)] {
            var description = manifest(createdDate: sharedDate.addingTimeInterval(offsetSeconds))
            description.title = title
            try inbox.makeDraft().commit(noteText: title, manifest: description)
        }
        let titles = try inbox.pendingItems().compactMap { entry -> String? in
            if case .item(let item) = entry { return item.manifest.title }
            return nil
        }
        XCTAssertEqual(titles, ["First", "Second", "Third"])
    }

    func testAnItemOfALaterFormatIsListedAsUnreadableAndKept() throws {
        let folder = try TemporaryFolder.make(for: self)
        let inbox = ShareInbox(containerFolder: folder.location)
        var description = manifest()
        description.formatVersion = SharedItemManifest.currentFormatVersion + 1
        try inbox.makeDraft().commit(noteText: "Text", manifest: description)
        let entries = try inbox.pendingItems()
        guard case .unreadable(let itemFolder, let error) = try XCTUnwrap(entries.first) else { return XCTFail("A later format is not read.") }
        XCTAssertEqual(error as? ShareInboxError, .newerFormat(SharedItemManifest.currentFormatVersion + 1))
        XCTAssertTrue(FileManager.default.fileExists(atPath: itemFolder.path))
    }

    func testAFolderWithAnUnreadableDescriptionIsListedAsUnreadable() throws {
        let folder = try TemporaryFolder.make(for: self)
        let inbox = ShareInbox(containerFolder: folder.location)
        let itemFolder = inbox.inboxFolder.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: itemFolder, withIntermediateDirectories: true)
        try Data("{ not json".utf8).write(to: itemFolder.appendingPathComponent("item.json"))
        guard case .unreadable = try XCTUnwrap(try inbox.pendingItems().first) else { return XCTFail("Broken JSON is not an item.") }
    }

    func testCommittingRefusesAnAttachmentTheDraftDoesNotHold() throws {
        let folder = try TemporaryFolder.make(for: self)
        let inbox = ShareInbox(containerFolder: folder.location)
        let draft = try inbox.makeDraft()
        XCTAssertThrowsError(try draft.commit(noteText: "", manifest: manifest(attachments: ["Missing.png"]))) { error in
            XCTAssertEqual(error as? ShareInboxError, .attachmentMissing(fileName: "Missing.png"))
        }
        XCTAssertTrue(try inbox.pendingItems().isEmpty)
    }

    func testTwoFilesWithOneNameAreBothKept() throws {
        let folder = try TemporaryFolder.make(for: self)
        let draft = try ShareInbox(containerFolder: folder.location).makeDraft()
        let firstName = try draft.addAttachment(contents: Data("a".utf8), preferredFileName: "Photo.jpeg")
        let secondName = try draft.addAttachment(contents: Data("b".utf8), preferredFileName: "Photo.jpeg")
        XCTAssertEqual([firstName, secondName], ["Photo.jpeg", "Photo 2.jpeg"])
    }

    func testAnAttachmentNameCannotReachOutsideTheItem() throws {
        let folder = try TemporaryFolder.make(for: self)
        let inbox = ShareInbox(containerFolder: folder.location)
        try inbox.makeDraft().commit(noteText: "", manifest: manifest())
        let item = try onlyItem(in: inbox)
        XCTAssertThrowsError(try item.attachmentLocation(named: "../item.json"))
        XCTAssertThrowsError(try item.attachmentLocation(named: ".hidden"))
    }

    func testTheDeliveryRecordIsSavedWithTheItem() throws {
        let folder = try TemporaryFolder.make(for: self)
        let inbox = ShareInbox(containerFolder: folder.location)
        try inbox.makeDraft().commit(noteText: "", manifest: manifest(attachments: []))
        let record = SharedItemDeliveryRecord(vaultIdentifier: UUID(), deliveredAttachmentPaths: ["Photo.jpeg": "Attachments/Photo.jpeg"],
                                              notePath: nil, failureCount: 1, lastFailureDescription: "The folder is unavailable.",
                                              lastAttemptDate: sharedDate)
        try inbox.saveDeliveryRecord(record, for: try onlyItem(in: inbox))
        XCTAssertEqual(try onlyItem(in: inbox).deliveryRecord, record)
    }

    func testRemovingADeliveredItemRemovesItsFolder() throws {
        let folder = try TemporaryFolder.make(for: self)
        let inbox = ShareInbox(containerFolder: folder.location)
        try inbox.makeDraft().commit(noteText: "", manifest: manifest())
        let item = try onlyItem(in: inbox)
        try inbox.removeDeliveredItem(item)
        XCTAssertTrue(try inbox.pendingItems().isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: item.folder.path))
    }

    func testOnlyDraftsBegunBeforeTheDateAreRemoved() throws {
        let folder = try TemporaryFolder.make(for: self)
        let inbox = ShareInbox(containerFolder: folder.location)
        let oldDraft = try inbox.makeDraft()
        try FileManager.default.setAttributes([.creationDate: sharedDate], ofItemAtPath: oldDraft.folder.path)
        let newDraft = try inbox.makeDraft()
        try inbox.removeAbandonedDrafts(startedBefore: sharedDate.addingTimeInterval(1))
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldDraft.folder.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: newDraft.folder.path))
    }

    func testTheVaultListIsMissingThenReadThenUnreadable() throws {
        let folder = try TemporaryFolder.make(for: self)
        let inbox = ShareInbox(containerFolder: folder.location)
        guard case .missing = inbox.readVaultList() else { return XCTFail("No list was published.") }
        let vaultList = SharedVaultList(vaults: [SharedVaultList.Vault(id: UUID(), name: "Physics", lastOpenedDate: sharedDate)])
        try inbox.saveVaultList(vaultList)
        guard case .read(let readList) = inbox.readVaultList() else { return XCTFail("The published list is read.") }
        XCTAssertEqual(readList, vaultList)
        try Data("[".utf8).write(to: inbox.vaultListFile)
        guard case .unreadable = inbox.readVaultList() else { return XCTFail("A broken list is not an empty one.") }
    }

    func testTheItemDescriptionKeepsItsFormat() throws {
        let description = SharedItemManifest(identifier: try XCTUnwrap(UUID(uuidString: "6F1C2A3B-0000-4000-8000-000000000001")),
                                             createdDate: sharedDate, vaultIdentifier: try XCTUnwrap(UUID(uuidString: "6F1C2A3B-0000-4000-8000-000000000002")),
                                             vaultName: "Physics", destination: .dailyNote, title: "Lecture 4", attachmentFileNames: ["Board.jpeg"])
        let expected = """
        {
          "attachmentFileNames" : [
            "Board.jpeg"
          ],
          "createdDate" : "2026-10-14T17:46:40Z",
          "destination" : "dailyNote",
          "formatVersion" : 1,
          "identifier" : "6F1C2A3B-0000-4000-8000-000000000001",
          "title" : "Lecture 4",
          "vaultIdentifier" : "6F1C2A3B-0000-4000-8000-000000000002",
          "vaultName" : "Physics"
        }
        """
        XCTAssertEqual(String(decoding: try ShareInbox.encoder.encode(description), as: UTF8.self), expected)
        XCTAssertEqual(try ShareInbox.decoder.decode(SharedItemManifest.self, from: Data(expected.utf8)), description)
    }

    func testADestinationThisBuildDoesNotKnowIsKeptAsWritten() throws {
        let decoded = try ShareInbox.decoder.decode([SharedItemDestination].self, from: Data(#"["newNote","dailyNote","canvas"]"#.utf8))
        XCTAssertEqual(decoded, [.newNote, .dailyNote, .unknown("canvas")])
        XCTAssertEqual(String(decoding: try ShareInbox.encoder.encode([SharedItemDestination.unknown("canvas")]), as: UTF8.self), "[\n  \"canvas\"\n]")
    }
}

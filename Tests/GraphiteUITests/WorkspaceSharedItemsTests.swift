import XCTest
import ShareInbox
import GraphiteCore
@testable import GraphiteUI
import GraphiteTestSupport

/// What was shared to Graphite reaching a vault when the app becomes active
/// (`WorkspaceSharedItems.swift`): the item leaves the inbox only once it is in the vault.
@MainActor
final class WorkspaceSharedItemsTests: XCTestCase {
    private let sharedDate = Date(timeIntervalSince1970: 1_792_000_000)
    private var device: IsolatedWorkspaceDevice!
    private var inbox: ShareInbox!

    override func setUp() async throws {
        device = try IsolatedWorkspaceDevice.make(for: self)
        inbox = ShareInbox(containerFolder: try TemporaryVault.make(prefix: "ShareContainer", for: self).root)
    }

    private func dailyNoteName() -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let components = calendar.dateComponents([.year, .month, .day], from: sharedDate)
        return String(format: "%04d-%02d-%02d.md", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    @discardableResult
    private func share(_ text: String, title: String = "Shared page", destination: SharedItemDestination = .newNote, toVault vaultIdentifier: UUID?,
                       attachment: (name: String, contents: String)? = nil) throws -> UUID {
        let draft = try inbox.makeDraft()
        let fileNames = try attachment.map { attachment in [try draft.addAttachment(contents: Data(attachment.contents.utf8), preferredFileName: attachment.name)] } ?? []
        try draft.commit(noteText: text, manifest: SharedItemManifest(identifier: draft.identifier, createdDate: sharedDate, vaultIdentifier: vaultIdentifier,
                                                                      vaultName: "Chosen", destination: destination, title: title, attachmentFileNames: fileNames))
        return draft.identifier
    }

    private func openWorkspace(files: [String: String] = [:], prefix: String = "SharedItemsVault") async throws -> (WorkspaceModel, TemporaryVault) {
        let vault = try TemporaryVault.make(prefix: prefix, files: files, for: self)
        let workspace = device.makeWorkspace(shareInbox: inbox)
        try await workspace.openFolderAsVault(vault.root)
        return (workspace, vault)
    }

    func testASharedPageBecomesANoteInTheOpenVaultLeavesTheInboxAndOpens() async throws {
        let (workspace, vault) = try await openWorkspace()
        try share("[Swift](https://swift.org)", toVault: workspace.currentVaultIdentifier, attachment: ("Diagram.png", "png"))

        await workspace.receiveSharedItems(at: sharedDate)

        XCTAssertEqual(try vault.readText(at: "Shared page.md"), "[Swift](https://swift.org)\n\n![[Diagram.png]]\n")
        XCTAssertEqual(try vault.readText(at: "Diagram.png"), "png")
        XCTAssertTrue(try inbox.pendingItems().isEmpty)
        XCTAssertEqual(workspace.selection, try VaultPath("Shared page.md"))
        XCTAssertEqual(workspace.notice, "Added what you shared to “Shared page”.")
        XCTAssertNil(workspace.errorMessage)
    }

    func testTextSharedToTheDailyNoteOpenInATabGoesThroughItsEditorAndIsSaved() async throws {
        let dailyNote = dailyNoteName()
        let (workspace, vault) = try await openWorkspace(files: [dailyNote: "Plan\n"])
        await workspace.open(try VaultPath(dailyNote))
        let session = try XCTUnwrap(workspace.markdownSession)
        try share("A thought", destination: .dailyNote, toVault: workspace.currentVaultIdentifier)

        await workspace.receiveSharedItems(at: sharedDate)

        XCTAssertEqual(session.text, "Plan\n\nA thought\n")
        XCTAssertEqual(try vault.readText(at: dailyNote), "Plan\n\nA thought\n")
        XCTAssertFalse(session.hasUnsavedChanges)
        XCTAssertTrue(try inbox.pendingItems().isEmpty)
    }

    func testAnItemThatFailsStaysInTheInboxAndIsReportedOncePerRun() async throws {
        let (workspace, vault) = try await openWorkspace()
        try vault.createFolder(".obsidian/daily-notes.json")
        try share("A thought", title: "Thought", destination: .dailyNote, toVault: workspace.currentVaultIdentifier)

        await workspace.receiveSharedItems(at: sharedDate)
        let message = try XCTUnwrap(workspace.errorMessage)
        XCTAssertTrue(message.hasPrefix("“Thought”, shared to Graphite, couldn't be added to “Chosen”."), message)
        XCTAssertTrue(message.hasSuffix("It stays in the share inbox and is tried again the next time Graphite opens."), message)
        workspace.errorMessage = nil

        await workspace.receiveSharedItems(at: sharedDate)
        XCTAssertNil(workspace.errorMessage, "The same failure is not announced again in this run.")
        guard case .item(let item) = try XCTUnwrap(try inbox.pendingItems().first) else { return XCTFail("The item stays.") }
        XCTAssertEqual(item.deliveryRecord?.failureCount, 2)
    }

    func testAnItemForAnotherKnownVaultGoesThereWithoutLeavingTheOpenOne() async throws {
        let (workspace, chosenVault) = try await openWorkspace(prefix: "ChosenVault")
        let chosenIdentifier = try XCTUnwrap(workspace.currentVaultIdentifier)
        let otherVault = try TemporaryVault.make(prefix: "OpenVault", for: self)
        try await workspace.openFolderAsVault(otherVault.root)
        try share("Text", toVault: chosenIdentifier)

        await workspace.receiveSharedItems(at: sharedDate)

        XCTAssertEqual(try chosenVault.readText(at: "Shared page.md"), "Text\n")
        XCTAssertFalse(otherVault.fileExists(at: "Shared page.md"))
        XCTAssertNotEqual(workspace.currentVaultIdentifier, chosenIdentifier, "The open vault stays open.")
        XCTAssertEqual(workspace.notice, "Added a shared item to “\(chosenVault.root.lastPathComponent)”.")
        XCTAssertNil(workspace.selection)
    }

    func testAnItemWhoseVaultLeftTheListGoesToTheOpenVaultAndSaysSo() async throws {
        let (workspace, vault) = try await openWorkspace()
        try share("Text", toVault: UUID())

        await workspace.receiveSharedItems(at: sharedDate)

        XCTAssertEqual(try vault.readText(at: "Shared page.md"), "Text\n")
        XCTAssertEqual(workspace.notice?.contains("no longer in Graphite's vault list"), true)
    }

    func testItemsWaitWhileNoVaultIsOpen() async throws {
        let workspace = device.makeWorkspace(shareInbox: inbox)
        try share("Text", toVault: nil)

        await workspace.receiveSharedItems(at: sharedDate)

        XCTAssertEqual(try inbox.pendingItems().count, 1)
        XCTAssertNil(workspace.errorMessage)
    }

    func testTheVaultListIsPublishedForTheShareSheet() async throws {
        let (workspace, vault) = try await openWorkspace()
        let identifier = try XCTUnwrap(workspace.currentVaultIdentifier)
        try await waitUntil("the vault list is published") {
            if case .read(let vaultList) = self.inbox.readVaultList() { return vaultList.vaults.map(\.id) == [identifier] }
            return false
        }
        guard case .read(let vaultList) = inbox.readVaultList() else { return XCTFail("The list is readable.") }
        XCTAssertEqual(vaultList.vaults.first?.name, vault.root.lastPathComponent)
    }
}

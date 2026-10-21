import Foundation
import Observation
import ShareInbox

/// Where the share sheet puts what was shared.
enum ShareDestinationChoice: Hashable, CaseIterable {
    case newNote
    case dailyNote

    var destination: SharedItemDestination {
        switch self {
        case .newNote: .newNote
        case .dailyNote: .dailyNote
        }
    }
}

/// A file of the share, as the sheet lists it.
struct SharedAttachmentPreview: Identifiable, Hashable {
    let fileName: String
    let location: URL
    let isImage: Bool

    var id: String { fileName }
}

/// The share sheet's state: the title, the text and files shared, where they go, and the
/// draft in the share inbox they are copied into. Saving commits the draft; the app moves
/// it into the vault the next time it opens.
@MainActor @Observable
final class ShareComposeModel {
    enum Phase: Equatable {
        case loading
        case ready
        /// Nothing can be saved, for the reason given.
        case unavailable(String)
    }

    var title = ""
    var noteText = ""
    var destination = ShareDestinationChoice.newNote
    var chosenVaultIdentifier: UUID?
    private(set) var attachments: [SharedAttachmentPreview] = []
    private(set) var vaults: [SharedVaultList.Vault] = []
    private(set) var phase = Phase.loading
    /// Something shared that could not be read, said under the content.
    private(set) var loadingProblem: String?

    @ObservationIgnored private let inbox: ShareInbox?
    @ObservationIgnored private var draft: SharedItemDraft?

    init(inbox: ShareInbox?) {
        self.inbox = inbox
    }

    var chosenVaultName: String? {
        vaults.first { vault in vault.id == chosenVaultIdentifier }?.name
    }

    var canSave: Bool {
        phase == .ready && (!noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty)
    }

    /// Reads the vault list and every shared item into a new draft.
    func load(_ extensionItems: [NSExtensionItem], sharedAt date: Date) async {
        guard let inbox else {
            phase = .unavailable("Graphite can't receive shared items on this device: its shared folder is missing. Reinstalling Graphite restores it.")
            return
        }
        readVaultList(from: inbox)
        do {
            let draft = try inbox.makeDraft()
            self.draft = draft
            let contents = try await loadContents(of: extensionItems, into: draft, sharedAt: date)
            await apply(contents, pageTitle: extensionItems.lazy.compactMap { item in (item.attributedTitle ?? item.attributedContentText)?.string }.first)
            phase = .ready
        } catch {
            phase = .unavailable("Graphite couldn't prepare what you shared. " + error.localizedDescription)
        }
    }

    /// Commits the draft to the inbox.
    func save(sharedAt date: Date) throws {
        guard let draft, canSave else { return }
        let manifest = SharedItemManifest(identifier: draft.identifier, createdDate: date, vaultIdentifier: chosenVaultIdentifier, vaultName: chosenVaultName,
                                          destination: destination.destination, title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                                          attachmentFileNames: attachments.map(\.fileName))
        try draft.commit(noteText: noteText, manifest: manifest)
        self.draft = nil
    }

    /// Removes the draft and the files copied into it.
    func discard() {
        try? draft?.discard() // a draft left behind is removed by the app after an hour
        draft = nil
    }

    private func readVaultList(from inbox: ShareInbox) {
        switch inbox.readVaultList() {
        case .read(let vaultList):
            vaults = vaultList.sortedByName
            chosenVaultIdentifier = vaultList.mostRecentlyOpened?.id
        case .missing:
            vaults = []
        case .unreadable:
            vaults = []
            loadingProblem = "Graphite's vault list can't be read; what you share goes to the vault open in Graphite."
        }
    }

    private func loadContents(of extensionItems: [NSExtensionItem], into draft: SharedItemDraft, sharedAt date: Date) async throws -> [SharedContent] {
        var contents: [SharedContent] = []
        var unreadableCount = 0
        for provider in extensionItems.flatMap({ item in item.attachments ?? [] }) {
            do {
                if let content = try await SharedContentLoader.load(provider, into: draft, sharedAt: date) { contents.append(content) }
            } catch {
                unreadableCount += 1
            }
        }
        if unreadableCount > 0 {
            loadingProblem = unreadableCount == 1 ? "One shared item couldn't be read and is left out." : "\(unreadableCount) shared items couldn't be read and are left out."
        }
        return contents
    }

    private func apply(_ contents: [SharedContent], pageTitle: String?) async {
        var textParts: [String] = []
        var firstPageTitle: String?
        var firstText: String?
        // Safari shares a page as two addresses (with and without its last slash): one link is written.
        var sharedPages: Set<String> = []
        for content in contents {
            switch content {
            case .text(let text):
                textParts.append(text)
                firstText = firstText ?? text
            case .link(let address, _):
                guard sharedPages.insert(SharedContentMarkdown.pageIdentity(of: address)).inserted else { continue }
                let linkTitle = await SharedContentLoader.pageTitle(of: address, givenTitle: pageTitle)
                firstPageTitle = firstPageTitle ?? linkTitle
                textParts.append(SharedContentMarkdown.link(title: linkTitle, address: address))
            case .file(let fileName, let isImage):
                guard let draft else { continue }
                attachments.append(SharedAttachmentPreview(fileName: fileName, location: draft.attachmentLocation(named: fileName), isImage: isImage))
            }
        }
        noteText = SharedContentMarkdown.combinedText(textParts)
        let firstFileStem = attachments.first.map { attachment in (attachment.fileName as NSString).deletingPathExtension }
        title = SharedContentMarkdown.suggestedTitle(from: [firstPageTitle, firstText, firstFileStem]) ?? ""
    }
}

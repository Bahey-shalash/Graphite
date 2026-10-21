import Foundation
import ShareInbox

/// Where a shared item went in the vault.
public struct SharedItemDeliveryOutcome: Equatable, Sendable {
    /// The new note, or the daily note the item was added to.
    public let notePath: VaultPath
    public let attachmentPaths: [VaultPath]
    public let destination: SharedItemDestination
}

/// Why a shared item was not delivered, beyond the vault's and the inbox's own errors.
public enum SharedItemDeliveryFailure: Error, Equatable {
    /// The item asks for a destination this build does not know; it waits for a newer build.
    case unknownDestination(String)
}

/// Puts one item of the share inbox into a vault, through the vault's store and settings:
/// its files into the vault's attachment folder for the note, under free names (`uniquePath`,
/// written `.absent`), then the note, a new one in the "Default location for new notes" or
/// the end of the daily note of the day it was shared. The item itself is not removed here.
///
/// Every step that changed the vault is saved in the item's `delivery.json` before the next
/// one, so a delivery that stops (the app closes, a folder goes offline, a write conflicts)
/// starts again where it stopped and never copies a file or writes the note twice.
public struct SharedItemDelivery: Sendable {
    /// The embed for an attachment in a note, by the vault's link settings.
    public typealias EmbedText = @Sendable (_ attachment: VaultPath, _ note: VaultPath, _ settings: ObsidianSettings) async -> String
    /// Adds text at the end of a note that exists: the note's open editor when there is one,
    /// else the file (`appendingInFile`).
    public typealias NoteAppending = @Sendable (_ note: VaultPath, _ block: String) async throws -> Void

    /// How often a name taken between choosing it and writing is replaced by the next free one.
    static let maximumNameAttempts = 20

    private let store: VaultStore
    private let inbox: ShareInbox
    private let vaultIdentifier: UUID
    private let timeZone: TimeZone
    /// The largest daily note template read, and the largest note appended to.
    private let maximumNoteBytes: Int

    public init(store: VaultStore, inbox: ShareInbox, vaultIdentifier: UUID, timeZone: TimeZone, maximumNoteBytes: Int) {
        self.store = store
        self.inbox = inbox
        self.vaultIdentifier = vaultIdentifier
        self.timeZone = timeZone
        self.maximumNoteBytes = maximumNoteBytes
    }

    /// Delivers `item` and returns where it went. A failure is counted in the item's record,
    /// with the time `now`, and thrown; the item stays for the next attempt.
    public func deliver(_ item: PendingSharedItem, now: Date, embedText: EmbedText, appendToExistingNote: NoteAppending) async throws -> SharedItemDeliveryOutcome {
        var record = (item.deliveryRecord ?? SharedItemDeliveryRecord()).progress(forVault: vaultIdentifier)
        do {
            return try await deliver(item, record: &record, embedText: embedText, appendToExistingNote: appendToExistingNote)
        } catch {
            record.failureCount += 1
            record.lastFailureDescription = String(describing: error)
            record.lastAttemptDate = now
            try? inbox.saveDeliveryRecord(record, for: item) // the failure thrown below is what matters; an unsaved record only loses its count
            throw error
        }
    }

    /// Appends through the vault's files: the note is read, checked to be UTF-8 text (a
    /// byte order mark is kept) and written back only if no one changed it in between.
    public static func appendingInFile(store: VaultStore, maximumNoteBytes: Int) -> NoteAppending {
        { note, block in
            let snapshot = try await store.read(note, maximumBytes: maximumNoteBytes)
            let byteOrderMark = Data([0xEF, 0xBB, 0xBF])
            let hasByteOrderMark = snapshot.data.starts(with: byteOrderMark)
            guard let existingText = String(data: hasByteOrderMark ? snapshot.data.dropFirst(byteOrderMark.count) : snapshot.data, encoding: .utf8) else {
                throw GraphiteError.invalidFile(note.name)
            }
            let changedText = existingText + SharedNoteComposition.suffixAppending(block, to: existingText)
            _ = try await store.save((hasByteOrderMark ? byteOrderMark : Data()) + Data(changedText.utf8), at: note, expecting: .revision(snapshot.revision))
        }
    }

    // MARK: Stages

    private func deliver(_ item: PendingSharedItem, record: inout SharedItemDeliveryRecord, embedText: EmbedText,
                         appendToExistingNote: NoteAppending) async throws -> SharedItemDeliveryOutcome {
        let destination = item.manifest.destination
        if let recordedNote = record.notePath {
            return SharedItemDeliveryOutcome(notePath: try VaultPath(recordedNote), attachmentPaths: try recordedAttachments(of: item, in: record),
                                             destination: destination)
        }
        let settings = try await store.settings()
        let sharedText = try item.noteText()
        let plannedNote = try await plannedNotePath(for: item.manifest, settings: settings)
        var attachmentPaths: [VaultPath] = []
        for fileName in item.manifest.attachmentFileNames {
            attachmentPaths.append(try await deliverAttachment(named: fileName, of: item, forNote: plannedNote, settings: settings, record: &record))
        }
        var embeds: [String] = []
        for attachmentPath in attachmentPaths { embeds.append(await embedText(attachmentPath, plannedNote, settings)) }
        let text = SharedNoteComposition.noteText(sharedText: sharedText, embeds: embeds)
        let notePath = try await writeNote(text, at: plannedNote, of: item.manifest, appendToExistingNote: appendToExistingNote)
        record.notePath = notePath.rawValue
        try inbox.saveDeliveryRecord(record, for: item)
        return SharedItemDeliveryOutcome(notePath: notePath, attachmentPaths: attachmentPaths, destination: destination)
    }

    /// Where the note goes: a free name in the new-note folder, or the daily note's path.
    /// A new note's name may still be taken before it is written; it then gets the next free
    /// name in the same folder, so links to its attachments stay right.
    private func plannedNotePath(for manifest: SharedItemManifest, settings: ObsidianSettings) async throws -> VaultPath {
        switch manifest.destination {
        case .newNote:
            let directory = try settings.newNoteLocation.directory(currentFile: nil)
            return try await store.uniquePath(directory: directory, stem: SharedNoteComposition.noteStem(fromTitle: manifest.title), extension: "md")
        case .dailyNote:
            return try await store.dailyNoteSettings().notePath(for: manifest.createdDate, timeZone: timeZone)
        case .unknown(let rawValue):
            throw SharedItemDeliveryFailure.unknownDestination(rawValue)
        }
    }

    private func deliverAttachment(named fileName: String, of item: PendingSharedItem, forNote note: VaultPath, settings: ObsidianSettings,
                                   record: inout SharedItemDeliveryRecord) async throws -> VaultPath {
        if let recordedPath = record.deliveredAttachmentPaths[fileName], let path = try? VaultPath(recordedPath), // an unreadable record copies again
           try await store.regularFileExists(path) {
            return path
        }
        let source = try item.attachmentLocation(named: fileName)
        let directory = try AttachmentResolver().directory(for: settings.attachmentLocation, note: note)
        try await store.createDirectory(directory)
        let fileExtension = (fileName as NSString).pathExtension
        let stem = (fileName as NSString).deletingPathExtension
        let path = try await underFreeName(in: directory, stem: stem, fileExtension: fileExtension) { destination in
            _ = try store.writer.copy(from: source, to: try destination.url(in: store.root), expecting: .absent)
        }
        record.deliveredAttachmentPaths[fileName] = path.rawValue
        try inbox.saveDeliveryRecord(record, for: item)
        return path
    }

    private func writeNote(_ text: String, at plannedPath: VaultPath, of manifest: SharedItemManifest,
                           appendToExistingNote: NoteAppending) async throws -> VaultPath {
        let title = manifest.title, date = manifest.createdDate
        switch manifest.destination {
        case .newNote:
            try await store.createDirectory(plannedPath.parent)
            // The free name now, in the planned folder: the embeds only depend on the folder.
            let stem = SharedNoteComposition.noteStem(fromTitle: title)
            return try await underFreeName(in: plannedPath.parent, stem: stem, fileExtension: "md") { path in
                _ = try await store.save(Data(text.utf8), at: path, expecting: .absent)
            }
        case .dailyNote:
            let settings = try await store.dailyNoteSettings()
            let timeFormat = (try? await store.templateSettings())?.timeFormat ?? TemplateSettings().timeFormat // as the app: the default while unreadable
            try await DailyNoteCreation.createIfMissing(plannedPath, for: date, settings: settings, timeFormat: timeFormat,
                                                        maximumTemplateBytes: maximumNoteBytes, timeZone: timeZone, store: store)
            try await appendToExistingNote(plannedPath, text)
            return plannedPath
        case .unknown(let rawValue):
            throw SharedItemDeliveryFailure.unknownDestination(rawValue)
        }
    }

    /// Writes with `write` at the first free name for `stem`, and at the next one when
    /// another writer took it first (`GraphiteError.conflict`), up to `maximumNameAttempts`.
    private func underFreeName(in directory: VaultPath, stem: String, fileExtension: String,
                               write: (VaultPath) async throws -> Void) async throws -> VaultPath {
        var attemptCount = 0
        while true {
            let path = try await store.uniquePath(directory: directory, stem: stem, extension: fileExtension)
            do {
                try await write(path)
                return path
            } catch GraphiteError.conflict where attemptCount + 1 < Self.maximumNameAttempts {
                attemptCount += 1
            }
        }
    }

    private func recordedAttachments(of item: PendingSharedItem, in record: SharedItemDeliveryRecord) throws -> [VaultPath] {
        try item.manifest.attachmentFileNames.compactMap { fileName in try record.deliveredAttachmentPaths[fileName].map(VaultPath.init) }
    }
}

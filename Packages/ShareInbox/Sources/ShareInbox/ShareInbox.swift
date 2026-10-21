import Foundation

/// The folder, in a container the app and its share extension both reach (an App Group),
/// where the extension leaves shared items and the app picks them up:
///
/// ```
/// <container>/Share Inbox/<item identifier>/item.json        SharedItemManifest
///                                          /Note.md          the shared text, as Markdown
///                                          /Attachments/...  the shared files
///                                          /delivery.json    SharedItemDeliveryRecord, once the app tried
/// <container>/Share Inbox/.drafts/<identifier>/              an item still being written by the extension
/// <container>/Known Vaults.json                              SharedVaultList, written by the app
/// ```
///
/// An item is written in full under `.drafts` and then renamed into the inbox, so the app
/// never sees half of one. The app removes an item only after it reached a vault.
public struct ShareInbox: Sendable {
    static let inboxFolderName = "Share Inbox"
    static let draftsFolderName = ".drafts"
    static let manifestFileName = "item.json"
    static let noteFileName = "Note.md"
    static let attachmentsFolderName = "Attachments"
    static let deliveryRecordFileName = "delivery.json"
    static let vaultListFileName = "Known Vaults.json"
    /// The largest `item.json`, `delivery.json` or vault list read; they hold a few names.
    static let maximumDescriptionBytes = 1_048_576
    /// The largest `Note.md` read: shared text is a passage or a page, not a book.
    public static let maximumNoteBytes = 8_388_608

    public let containerFolder: URL

    public init(containerFolder: URL) {
        self.containerFolder = containerFolder
    }

    /// The App Group container named `identifier`, or nil when this process has no such
    /// group in its entitlements.
    public static func applicationGroupContainer(identifier: String) -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }

    var inboxFolder: URL { containerFolder.appendingPathComponent(Self.inboxFolderName, isDirectory: true) }
    var draftsFolder: URL { inboxFolder.appendingPathComponent(Self.draftsFolderName, isDirectory: true) }
    var vaultListFile: URL { containerFolder.appendingPathComponent(Self.vaultListFileName, isDirectory: false) }

    // MARK: The share extension's side

    /// A new, empty item under `.drafts`, which becomes visible to the app when committed.
    public func makeDraft() throws -> SharedItemDraft {
        let identifier = UUID()
        let folder = draftsFolder.appendingPathComponent(identifier.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder.appendingPathComponent(Self.attachmentsFolderName, isDirectory: true),
                                                withIntermediateDirectories: true)
        return SharedItemDraft(identifier: identifier, folder: folder, inboxFolder: inboxFolder)
    }

    /// The vaults the app published, or why there are none to offer.
    public func readVaultList() -> SharedVaultListReading {
        guard FileManager.default.fileExists(atPath: vaultListFile.path) else { return .missing }
        do {
            return .read(try Self.decoder.decode(SharedVaultList.self, from: Self.readBounded(vaultListFile, maximumBytes: Self.maximumDescriptionBytes)))
        } catch {
            return .unreadable(error)
        }
    }

    // MARK: The app's side

    /// Publishes the vaults the share sheet offers, replacing the file in one step.
    public func saveVaultList(_ vaultList: SharedVaultList) throws {
        try FileManager.default.createDirectory(at: containerFolder, withIntermediateDirectories: true)
        try Self.encoder.encode(vaultList).write(to: vaultListFile, options: .atomic)
    }

    /// The committed items, oldest first. Each is readable or says why it is not; a missing
    /// inbox folder means none were ever shared.
    public func pendingItems() throws -> [ShareInboxEntry] {
        guard FileManager.default.fileExists(atPath: inboxFolder.path) else { return [] }
        let folders = try FileManager.default.contentsOfDirectory(at: inboxFolder, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
        let entries = folders.filter { folder in (try? folder.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true } // a stray file is no item
            .map(Self.entry(in:))
        return entries.sorted { first, second in
            (first.createdDate ?? .distantPast, first.folder.lastPathComponent) < (second.createdDate ?? .distantPast, second.folder.lastPathComponent)
        }
    }

    /// Saves what a delivery did so far, in one step, for the next attempt to start from.
    public func saveDeliveryRecord(_ record: SharedItemDeliveryRecord, for item: PendingSharedItem) throws {
        try Self.encoder.encode(record).write(to: item.folder.appendingPathComponent(Self.deliveryRecordFileName), options: .atomic)
    }

    /// Removes an item the app has delivered, with its copies of the shared files.
    public func removeDeliveredItem(_ item: PendingSharedItem) throws {
        try FileManager.default.removeItem(at: item.folder)
    }

    /// Removes drafts begun before `date`: an extension that was closed while writing one
    /// never commits it, and nothing else reads it.
    public func removeAbandonedDrafts(startedBefore date: Date) throws {
        guard FileManager.default.fileExists(atPath: draftsFolder.path) else { return }
        let drafts = try FileManager.default.contentsOfDirectory(at: draftsFolder, includingPropertiesForKeys: [.creationDateKey])
        for draft in drafts {
            let creationDate = try draft.resourceValues(forKeys: [.creationDateKey]).creationDate ?? .distantPast
            if creationDate < date { try FileManager.default.removeItem(at: draft) }
        }
    }

    // MARK: Reading and writing descriptions

    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    /// The file's bytes, refused when it is larger than `maximumBytes`.
    static func readBounded(_ file: URL, maximumBytes: Int) throws -> Data {
        let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= maximumBytes else { throw ShareInboxError.fileTooLarge(fileName: file.lastPathComponent, maximumBytes: maximumBytes) }
        return try Data(contentsOf: file)
    }

    private static func entry(in folder: URL) -> ShareInboxEntry {
        do {
            let manifest = try decoder.decode(SharedItemManifest.self,
                                               from: readBounded(folder.appendingPathComponent(manifestFileName), maximumBytes: maximumDescriptionBytes))
            guard manifest.formatVersion <= SharedItemManifest.currentFormatVersion else {
                return .unreadable(folder: folder, error: ShareInboxError.newerFormat(manifest.formatVersion))
            }
            let recordFile = folder.appendingPathComponent(deliveryRecordFileName)
            let record = FileManager.default.fileExists(atPath: recordFile.path)
                ? try decoder.decode(SharedItemDeliveryRecord.self, from: readBounded(recordFile, maximumBytes: maximumDescriptionBytes))
                : nil
            return .item(PendingSharedItem(folder: folder, manifest: manifest, deliveryRecord: record))
        } catch {
            return .unreadable(folder: folder, error: error)
        }
    }
}

/// Why the inbox refused a file or an item.
public enum ShareInboxError: Error, Equatable {
    case fileTooLarge(fileName: String, maximumBytes: Int)
    /// The item was written by a later version, which this build cannot read.
    case newerFormat(Int)
    case noteNotUTF8
    /// An attachment the item lists is not in its folder.
    case attachmentMissing(fileName: String)
}

/// One folder of the inbox: an item, or a folder that cannot be read as one.
public enum ShareInboxEntry: Sendable {
    case item(PendingSharedItem)
    case unreadable(folder: URL, error: any Error)

    public var folder: URL {
        switch self {
        case .item(let item): item.folder
        case .unreadable(let folder, _): folder
        }
    }

    var createdDate: Date? {
        if case .item(let item) = self { return item.manifest.createdDate }
        return nil
    }
}

/// A committed item waiting for the app.
public struct PendingSharedItem: Sendable {
    public let folder: URL
    public let manifest: SharedItemManifest
    /// What an earlier delivery did, nil when none was tried.
    public let deliveryRecord: SharedItemDeliveryRecord?

    /// The shared text, as the extension wrote it.
    public func noteText() throws -> String {
        let data = try ShareInbox.readBounded(folder.appendingPathComponent(ShareInbox.noteFileName), maximumBytes: ShareInbox.maximumNoteBytes)
        guard let text = String(data: data, encoding: .utf8) else { throw ShareInboxError.noteNotUTF8 }
        return text
    }

    /// Where the attachment named `fileName` is, after checking it is there.
    public func attachmentLocation(named fileName: String) throws -> URL {
        let location = folder.appendingPathComponent(ShareInbox.attachmentsFolderName, isDirectory: true).appendingPathComponent(fileName, isDirectory: false)
        guard SharedAttachmentName.isPlainFileName(fileName), FileManager.default.fileExists(atPath: location.path) else {
            throw ShareInboxError.attachmentMissing(fileName: fileName)
        }
        return location
    }
}

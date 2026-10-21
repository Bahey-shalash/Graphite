import Foundation

/// An item the share extension is still writing, in the inbox's `.drafts` folder. Shared
/// files are copied in as they load; `commit` adds the text and the description and moves
/// the whole folder into the inbox in one rename; `discard` removes it.
public struct SharedItemDraft: Sendable {
    public let identifier: UUID
    public let folder: URL
    let inboxFolder: URL

    var attachmentsFolder: URL { folder.appendingPathComponent(ShareInbox.attachmentsFolderName, isDirectory: true) }

    /// Copies a shared file in, under `preferredFileName` or, when that is taken by an
    /// earlier file of this item, the same name numbered. Returns the name it was given.
    public func addAttachment(copying source: URL, preferredFileName: String) throws -> String {
        let fileName = try freeFileName(for: preferredFileName)
        try FileManager.default.copyItem(at: source, to: attachmentsFolder.appendingPathComponent(fileName, isDirectory: false))
        return fileName
    }

    /// Writes shared bytes (an image given as data) as a file, named as `addAttachment(copying:)` names one.
    public func addAttachment(contents: Data, preferredFileName: String) throws -> String {
        let fileName = try freeFileName(for: preferredFileName)
        try contents.write(to: attachmentsFolder.appendingPathComponent(fileName, isDirectory: false), options: .withoutOverwriting)
        return fileName
    }

    /// Where an attachment of this draft is, for its preview.
    public func attachmentLocation(named fileName: String) -> URL {
        attachmentsFolder.appendingPathComponent(fileName, isDirectory: false)
    }

    /// Writes the text and the description, then moves the item into the inbox. The
    /// manifest lists only attachments that are in the folder.
    public func commit(noteText: String, manifest: SharedItemManifest) throws {
        for fileName in manifest.attachmentFileNames where !FileManager.default.fileExists(atPath: attachmentLocation(named: fileName).path) {
            throw ShareInboxError.attachmentMissing(fileName: fileName)
        }
        try Data(noteText.utf8).write(to: folder.appendingPathComponent(ShareInbox.noteFileName), options: .atomic)
        try ShareInbox.encoder.encode(manifest).write(to: folder.appendingPathComponent(ShareInbox.manifestFileName), options: .atomic)
        try FileManager.default.createDirectory(at: inboxFolder, withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: folder, to: inboxFolder.appendingPathComponent(identifier.uuidString, isDirectory: true))
    }

    /// Removes the draft and everything copied into it.
    public func discard() throws {
        try FileManager.default.removeItem(at: folder)
    }

    private func freeFileName(for preferredFileName: String) throws -> String {
        let fileName = SharedAttachmentName.plainFileName(preferredFileName)
        let existingNames = Set(try FileManager.default.contentsOfDirectory(atPath: attachmentsFolder.path))
        return SharedAttachmentName.freeName(for: fileName, avoiding: existingNames)
    }
}

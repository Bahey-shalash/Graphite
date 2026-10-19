import Foundation

/// Where a notebook created from inside a note lives, and what the note gets.
public enum NotebookPlacement: Equatable, Sendable {
    /// Saved where the note's attachments go, and embedded at the cursor so it is written
    /// on in place, as a drawing is.
    case embeddedInNote
    /// Saved as its own file in a folder, where the library shows it as a notebook; the
    /// note gets a link to it, or an embed.
    case inFolder(VaultPath, insertsEmbed: Bool)

    /// What goes into the note, from the embed the vault's link settings write for the
    /// new PDF (`![[Name.pdf]]` or `![Name](Name.pdf)`). A link is the embed without its `!`.
    public func insertedText(fromEmbed embedText: String) -> String {
        switch self {
        case .embeddedInNote, .inFolder(_, insertsEmbed: true): embedText
        case .inFolder(_, insertsEmbed: false): embedText.hasPrefix("!") ? String(embedText.dropFirst()) : embedText
        }
    }
}

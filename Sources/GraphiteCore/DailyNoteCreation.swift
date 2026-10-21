import Foundation

/// Creates a daily note that does not exist yet, from the Daily notes template, as Obsidian
/// does. Opening the daily note and sharing to it both create it here.
public enum DailyNoteCreation {
    public enum Failure: Error, Equatable {
        /// The template the Daily notes settings name is not in the vault.
        case templateMissing(VaultPath)
    }

    /// Writes the daily note of `date` at `path` unless a file is there: empty, or the
    /// template with its variables filled in for the note's own day, not today.
    /// - Returns: Whether the note was created.
    @discardableResult
    public static func createIfMissing(_ path: VaultPath, for date: Date, settings: DailyNoteSettings, timeFormat: String,
                                       maximumTemplateBytes: Int, timeZone: TimeZone, store: VaultStore) async throws -> Bool {
        guard try await !store.fileExists(path) else { return false }
        var content = ""
        if let templatePath = settings.templatePath {
            guard try await store.fileExists(templatePath) else { throw Failure.templateMissing(templatePath) }
            let snapshot = try await store.read(templatePath, maximumBytes: maximumTemplateBytes)
            // A template that is not UTF-8 text fills nothing in, as Obsidian creates an empty note then.
            let templateText = String(data: snapshot.data, encoding: .utf8) ?? ""
            content = TemplateRenderer.render(templateText, title: path.stem, date: date, dateFormat: settings.format, timeFormat: timeFormat, timeZone: timeZone)
        }
        try await store.createDirectory(path.parent)
        _ = try await store.save(Data(content.utf8), at: path, expecting: .absent)
        return true
    }
}

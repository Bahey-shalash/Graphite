import Foundation

/// Keeps a copy of a file dropped from another app while it is imported. The system removes
/// the file it hands over as soon as the drop's handler returns, and importing takes longer.
public enum DroppedFileStaging {
    /// What a file is called when its app suggests no name.
    public static let unnamedFileStem = "Dropped File"

    /// A copy of `file` in a folder of its own, so two dropped files of one name do not meet.
    /// The copy is named `suggestedName` when there is one, else the file's own name, else
    /// `unnamedFileStem`; a name without an extension gets `fileExtension`, and a hidden name (the
    /// system's temporary name for an item with none) counts as none.
    public static func stage(_ file: URL, namedAfter suggestedName: String? = nil, fileExtension: String? = nil) throws -> (copy: URL, folder: URL) {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("GraphiteDroppedFiles", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let copy = folder.appendingPathComponent(fileName(suggestedName: suggestedName, fileName: file.lastPathComponent, fileExtension: fileExtension ?? file.pathExtension))
        do {
            try FileManager.default.copyItem(at: file, to: copy)
        } catch {
            try? FileManager.default.removeItem(at: folder) // Nothing was kept; a leftover empty folder is only clutter.
            throw error
        }
        return (copy, folder)
    }

    /// The name a staged copy gets; see `stage`.
    static func fileName(suggestedName: String?, fileName: String, fileExtension: String) -> String {
        let candidates = [suggestedName, fileName].compactMap { $0 }.filter { name in !name.isEmpty && !name.hasPrefix(".") && !name.contains("/") }
        let name = candidates.first ?? unnamedFileStem
        guard !fileExtension.isEmpty, (name as NSString).pathExtension.isEmpty else { return name }
        return name + "." + fileExtension
    }

    /// Removes the staged copies once their import has finished or failed.
    public static func discard(_ folders: [URL]) {
        for folder in folders {
            try? FileManager.default.removeItem(at: folder) // A copy that cannot be removed is in the system's temporary folder, which it cleans.
        }
    }
}

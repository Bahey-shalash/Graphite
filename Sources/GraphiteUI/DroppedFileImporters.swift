import Foundation
import GraphiteCore

/// An importer for one kind of file dropped on the library or chosen with Import: it takes the
/// files of its types instead of the plain copy into the folder. A new format (a notebook of
/// another app, say) adds one entry to `DroppedFileImporters.registered`.
struct FileTypeImporter {
    /// The lowercased file extensions this importer takes.
    let fileExtensions: Set<String>
    /// Imports the files into the folder; reports a failure itself.
    let importFiles: @MainActor ([URL], VaultPath) async -> Void
}

enum DroppedFileImporters {
    /// The importers asked before the plain copy, in order; the first whose types include a file's takes it.
    static let registered: [FileTypeImporter] = []

    /// Which files each importer takes, and the files left for the plain copy.
    static func route(_ sources: [URL], through importers: [FileTypeImporter]) -> (routed: [(importer: FileTypeImporter, files: [URL])], remaining: [URL]) {
        var filesByImporter: [Int: [URL]] = [:]
        var remaining: [URL] = []
        for source in sources {
            let fileExtension = source.pathExtension.lowercased()
            if let position = importers.firstIndex(where: { importer in importer.fileExtensions.contains(fileExtension) }) {
                filesByImporter[position, default: []].append(source)
            } else {
                remaining.append(source)
            }
        }
        let routed = filesByImporter.keys.sorted().map { position in (importer: importers[position], files: filesByImporter[position] ?? []) }
        return (routed, remaining)
    }
}

/// The name an imported file gets: its own, except that text files become notes, which is what
/// Obsidian opens.
enum ImportedFileName {
    private static let noteExtensions: Set<String> = ["txt", "text", "markdown", "mdown", "mkd"]

    static func fileExtension(forSourceExtension sourceExtension: String) -> String {
        noteExtensions.contains(sourceExtension.lowercased()) ? "md" : sourceExtension
    }
}

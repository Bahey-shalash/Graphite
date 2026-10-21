import Foundation
import GraphiteCore

/// What a notebook import needs of the open vault: a free name in a folder, a folder made, where a vault path is on disk,
/// the writer that puts files in place, and a way to say which files it wrote. Made by the workspace from its store.
struct NotebookImportVault: Sendable {
    /// A path in the folder that nothing occupies: "Name.ext", else "Name 1.ext"…; an empty extension names a folder.
    let freePath: @Sendable (_ folder: VaultPath, _ stem: String, _ fileExtension: String) async throws -> VaultPath
    /// Makes the folder and the folders above it; a folder that exists is kept.
    let makeFolder: @Sendable (VaultPath) async throws -> Void
    let location: @Sendable (VaultPath) throws -> URL
    let fileWriter: AtomicFileWriter
    /// Called on the main actor after each notebook, with the files it wrote, so they show while the import goes on.
    let filesDidChange: @MainActor @Sendable ([VaultPath]) async -> Void
}

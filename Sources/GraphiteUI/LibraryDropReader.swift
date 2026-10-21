import Foundation
import UniformTypeIdentifiers
import GraphiteCore
import GraphiteApple

/// A file dropped from another app (Files, the Finder, Photos, Safari, Mail), ready to be
/// copied into the vault. The source is never moved or changed.
struct DroppedFile: Equatable {
    let location: URL
    /// The folder holding a staged copy, which is removed once the import ends; nil for the
    /// original file, which stays where it is.
    let stagingFolder: URL?
}

/// Files dropped from other apps, waiting to be imported.
struct DroppedFileBatch {
    let files: [DroppedFile]

    var locations: [URL] { files.map(\.location) }

    /// Removes the staged copies; the originals are not touched.
    func discard() {
        DroppedFileStaging.discard(files.compactMap(\.stagingFolder))
    }
}

/// What one item of a drop is.
enum LibraryDropSource: Equatable {
    /// A vault path, as `VaultItemTransfer` carries it: an item dragged from the library or the sidebar.
    case vaultItem(String)
    case file(DroppedFile)
}

/// Reads what a drop carries from its item providers. The item providers are the system's own
/// answer to what each dragged item can be, so this decides by their types:
/// - a vault item of Graphite (it moves; it also offers its file to other apps, which this ignores);
/// - a file address, as the Finder offers files (taken in place, never copied twice);
/// - a file by its own type, as Files, Photos and Mail offer them (copied to a staging folder
///   under the name the app suggests);
/// - not a web address, and not text without a file name: dropping a link or a selection
///   creates nothing.
/// Item providers are not `Sendable`, so reading stays on the main actor; the loading itself
/// runs on the system's queues.
@MainActor
enum LibraryDropReader {
    /// What a drop may carry at all; the providers are examined after this.
    static let acceptedTypes: [UTType] = [.item]

    /// Whether any provider holds something `read` can use, so a drop of a link only is refused at once.
    static func canRead(_ providers: [NSItemProvider]) -> Bool {
        providers.contains { provider in isVaultItem(provider) || isFileAddress(provider) || importableType(of: provider) != nil }
    }

    static func read(_ providers: [NSItemProvider]) async -> [LibraryDropSource] {
        var sources: [LibraryDropSource] = []
        for provider in providers {
            if isVaultItem(provider) {
                if let path = await vaultPath(of: provider) { sources.append(.vaultItem(path)) }
            } else if isFileAddress(provider) {
                if let location = await fileAddress(of: provider) { sources.append(.file(DroppedFile(location: location, stagingFolder: nil))) }
            } else if let type = importableType(of: provider) {
                if let file = await stagedFile(of: provider, type: type) { sources.append(.file(file)) }
            }
        }
        return sources
    }

    // MARK: Deciding

    private static func isVaultItem(_ provider: NSItemProvider) -> Bool {
        provider.hasItemConformingToTypeIdentifier(UTType.graphiteVaultItem.identifier)
    }

    private static func isFileAddress(_ provider: NSItemProvider) -> Bool {
        provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
    }

    /// The type to import a file by: data or a folder that is not an address, and not text unless
    /// the provider names a file (a dragged selection of text has no name).
    static func importableType(of provider: NSItemProvider) -> UTType? {
        provider.registeredContentTypes.first { type in
            guard !type.conforms(to: .url) else { return false }
            if type.conforms(to: .text) { return provider.suggestedName != nil }
            return type.conforms(to: .data) || type.conforms(to: .directory) || type.conforms(to: .package)
        }
    }

    // MARK: Loading

    private static func vaultPath(of provider: NSItemProvider) async -> String? {
        await withCheckedContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: UTType.graphiteVaultItem.identifier) { data, _ in
                // A drag whose item cannot be read moves nothing.
                continuation.resume(returning: data.flatMap { encoded in try? JSONDecoder().decode(VaultItemTransfer.self, from: encoded).path })
            }
        }
    }

    private static func fileAddress(of provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                // An address that cannot be read imports nothing.
                if let location = item as? URL { continuation.resume(returning: location.isFileURL ? location : nil) }
                else if let data = item as? Data, let location = URL(dataRepresentation: data, relativeTo: nil) { continuation.resume(returning: location.isFileURL ? location : nil) }
                else { continuation.resume(returning: nil) }
            }
        }
    }

    /// A copy of the provided file under the name its app suggests, with the extension its type has.
    private static func stagedFile(of provider: NSItemProvider, type: UTType) async -> DroppedFile? {
        let suggestedName = provider.suggestedName
        return await withCheckedContinuation { continuation in
            _ = provider.loadFileRepresentation(forTypeIdentifier: type.identifier) { location, _ in
                // The system removes its file when this handler returns, so the copy is made here.
                guard let location, let staged = try? DroppedFileStaging.stage(location, namedAfter: suggestedName, fileExtension: type.preferredFilenameExtension) else { // A file that cannot be copied imports nothing.
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: DroppedFile(location: staged.copy, stagingFolder: staged.folder))
            }
        }
    }
}

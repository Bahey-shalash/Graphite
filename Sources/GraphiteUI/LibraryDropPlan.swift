import GraphiteCore

/// What a drop on the library, on a folder tile or on the back button does: the vault items
/// that move into the folder and the files from other apps that are copied into it.
struct LibraryDropPlan: Equatable {
    let movedPaths: [VaultPath]
    let droppedFiles: [DroppedFile]

    var isEmpty: Bool { movedPaths.isEmpty && droppedFiles.isEmpty }

    static func make(from droppedSources: [LibraryDropSource], into folder: VaultPath) -> LibraryDropPlan {
        var draggedPaths: [VaultPath] = []
        var files: [DroppedFile] = []
        for source in droppedSources {
            switch source {
            case .vaultItem(let rawPath):
                if let path = try? VaultPath(rawPath) { draggedPaths.append(path) } // A dragged name no vault path can hold moves nothing.
            case .file(let file):
                files.append(file)
            }
        }
        return LibraryDropPlan(movedPaths: movablePaths(draggedPaths, into: folder), droppedFiles: files)
    }

    /// The dragged items that really move into `folder`, in the order dragged. Left out: an
    /// item already in the folder, the folder itself or one of its ancestors (a folder cannot
    /// go into itself or its own subfolder), an item named twice, and an item inside another
    /// dragged folder, which moves with that folder.
    static func movablePaths(_ draggedPaths: [VaultPath], into folder: VaultPath) -> [VaultPath] {
        var seenPaths: Set<VaultPath> = []
        return draggedPaths.filter { path in
            guard !path.rawValue.isEmpty, path.parent != folder, !folder.isInside(path), seenPaths.insert(path).inserted else { return false }
            return !draggedPaths.contains { other in other != path && path.isInside(other) }
        }
    }
}

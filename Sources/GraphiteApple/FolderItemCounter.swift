import Foundation
import GraphiteCore

/// Counts the items a folder of the vault shows, for the library's folder tiles.
public struct FolderItemCounter: Sendable {
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    /// How many items a folder shows: its visible children, not counting symbolic links. Read
    /// without their attributes, so it is cheap beside `VaultStore.children(of:)`.
    public func childCount(of directory: VaultPath) throws -> Int {
        let url = try directory.url(in: root)
        let children = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isSymbolicLinkKey], options: [.skipsHiddenFiles])
        return children.filter { child in
            (try? child.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true // An unreadable child counts as listed.
        }.count
    }
}

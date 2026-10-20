import Foundation

/// Which files the library shows; folders are always shown.
public enum LibraryFilter: String, CaseIterable, Sendable, Identifiable {
    case all, notebooks, notes, pictures, boards

    public var id: String { rawValue }

    public func includes(_ kind: DocumentKind) -> Bool {
        switch self {
        case .all: true
        case .notebooks: kind == .pdf
        case .notes: kind == .markdown
        case .pictures: kind == .image
        case .boards: kind == .canvas || kind == .base
        }
    }
}

/// What the library shows of one folder's listing, in order.
public enum LibraryListing {
    /// Folders first, then the files the filter lets through, each in the vault's sort order.
    public static func items(of entries: [VaultEntry], filter: LibraryFilter, sortOrder: FileSortOrder) -> [VaultEntry] {
        sortOrder.sorted(entries.filter { entry in entry.isDirectory || filter.includes(entry.kind) })
    }
}

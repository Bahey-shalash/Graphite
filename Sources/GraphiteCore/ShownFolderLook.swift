import Foundation

/// What a folder tile shows, decided from Graphite's stored style and Finder's own look.
public enum ShownFolderLook: Equatable, Sendable {
    /// A folder like any other.
    case plain
    /// A look Graphite draws: chosen in Graphite and not shown, or not shown the same, by Finder.
    case drawnByGraphite(FolderStyle)
    /// A look Finder draws exactly, so the Mac shows the system's own icon of the folder.
    /// The style is the same look for drawing where that icon is not available.
    case drawnByFinder(FolderStyle)

    /// The look in Graphite's terms; nil for a plain folder.
    public var style: FolderStyle? {
        switch self {
        case .plain: nil
        case .drawnByGraphite(let style), .drawnByFinder(let style): style
        }
    }

    /// Finder's look comes first when it changed after Graphite wrote the style, or when
    /// only Finder has one; Graphite's stored style comes first while Finder agrees with it
    /// or shows nothing, as on a device or vault where Finder's metadata does not reach.
    public static func resolve(stored: FolderStyle?, finder: FinderFolderLook) -> ShownFolderLook {
        guard finder.isCustomized else { return stored.map(ShownFolderLook.drawnByGraphite) ?? .plain }
        guard let stored, finder.agrees(with: stored) else { return .drawnByFinder(finder.style) }
        return stored.isDrawnTheSameByFinder ? .drawnByFinder(stored) : .drawnByGraphite(stored)
    }
}

extension FolderStyle {
    /// Whether Finder draws this look exactly as Graphite does: a symbol or emoji on a folder
    /// without a color or in a tag color, a picture as the whole icon, or a picture on a folder
    /// without a color (Finder's custom icon is drawn on the system's own folder). A color
    /// alone is only a tag dot in Finder.
    public var isDrawnTheSameByFinder: Bool {
        switch mark {
        case nil: false
        case .picture(let picture) where picture.layout == .wholeIcon: true
        case .picture: color == nil
        case .symbol, .emoji: color.map { color in FinderTagColor(folderColor: color) != nil } ?? true
        }
    }
}

extension FinderFolderLook {
    /// Whether Finder shows what Graphite last wrote for `style`: the same mark, and the
    /// same color where a tag can hold it.
    func agrees(with style: FolderStyle) -> Bool {
        let marksAgree = style.picture != nil ? showsCustomIconFile : mark == style.mark
        guard marksAgree else { return false }
        guard let styleColor = style.color else { return color == nil }
        guard let tagColor = FinderTagColor(folderColor: styleColor) else { return true }
        return tagColor == color
    }
}

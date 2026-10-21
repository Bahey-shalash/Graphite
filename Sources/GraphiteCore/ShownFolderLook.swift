import Foundation

/// What a folder tile shows, decided from Graphite's stored style and the folder's own
/// attributes, which Finder and the Files app draw. The attributes are the one source of what
/// a folder looks like: once Graphite's style is written there, every app shows the same.
public enum ShownFolderLook: Equatable, Sendable {
    /// A folder like any other.
    case plain
    /// A look the system cannot draw from the folder's attributes: a picture where Finder's
    /// custom icon cannot be written (iOS), or a style not written yet.
    case drawnByGraphite(FolderStyle)
    /// A look the folder's attributes hold, so the tile is the system's own icon of the folder.
    /// The style is the same look in Graphite's terms.
    case drawnByFinder(FolderStyle)

    /// The look in Graphite's terms; nil for a plain folder.
    public var style: FolderStyle? {
        switch self {
        case .plain: nil
        case .drawnByGraphite(let style), .drawnByFinder(let style): style
        }
    }

    /// The attributes' look when Graphite's style agrees with it or there is none; Graphite's
    /// style while the attributes are still plain (its write is pending); the attributes'
    /// look when they changed after Graphite's style, as Finder's is then the newer.
    public static func resolve(stored: FolderStyle?, finder: FinderFolderLook, canWritePictures: Bool) -> ShownFolderLook {
        let finderShows = FolderLookRepresentation(finder)
        guard let stored else { return finderShows.isPlain ? .plain : .drawnByFinder(finder.style) }
        if FolderLookRepresentation(stored, canWritePictures: canWritePictures) == finderShows {
            return stored.picture != nil && !canWritePictures ? .drawnByGraphite(stored) : .drawnByFinder(stored)
        }
        return finderShows.isPlain ? .drawnByGraphite(stored) : .drawnByFinder(finder.style)
    }
}

/// What a folder's attributes show, compared between Graphite's style and the folder: a tag
/// color, a symbol or emoji, and Finder's custom icon.
public struct FolderLookRepresentation: Equatable, Sendable {
    public let color: FinderTagColor?
    /// A symbol or emoji; a picture is `hasCustomIcon`.
    public let mark: FolderMark?
    public let hasCustomIcon: Bool

    public var isPlain: Bool { color == nil && mark == nil && !hasCustomIcon }

    public init(_ finder: FinderFolderLook) {
        color = finder.color
        mark = finder.mark
        hasCustomIcon = finder.showsCustomIconFile
    }

    /// What Graphite writes for a style: its color as the nearest tag color, its symbol or
    /// emoji, and its picture as Finder's custom icon where that can be written.
    public init(_ style: FolderStyle, canWritePictures: Bool) {
        color = style.color.flatMap(FinderTagColor.init(nearestTo:))
        switch style.mark {
        case .symbol, .emoji: mark = style.mark
        case .picture, nil: mark = nil
        }
        hasCustomIcon = style.picture != nil && canWritePictures
    }
}

/// What the library does for a folder whose style and attributes differ, when it lists it.
public enum FolderLookReconciliation: Equatable, Sendable {
    case none
    /// The attributes are plain: Graphite's style is written to them, as when it was chosen.
    case writeAttributes(FolderStyle)
    /// The attributes changed after Graphite's style (in Finder, Files or another app): the
    /// style follows them, so both copies say the same.
    case adoptFinderLook(FolderStyle?)

    public static func action(stored: FolderStyle?, finder: FinderFolderLook, canWritePictures: Bool) -> FolderLookReconciliation {
        guard let stored else { return .none }
        let finderShows = FolderLookRepresentation(finder)
        if FolderLookRepresentation(stored, canWritePictures: canWritePictures) == finderShows { return .none }
        if finderShows.isPlain { return .writeAttributes(stored) }
        var adopted = finder.style
        // A picture Finder still shows as its custom icon stays the folder's picture.
        if finderShows.hasCustomIcon, finderShows.mark == nil, let picture = stored.picture { adopted.mark = .picture(picture) }
        return .adoptFinderLook(adopted.isPlain ? nil : adopted)
    }
}

extension FinderTagColor {
    /// The tag color closest to a folder color, for writing a color no tag has: by hue, or gray
    /// for a color with little saturation. Nil for a color this build does not know.
    public init?(nearestTo folderColor: FolderColor) {
        if let exact = FinderTagColor(folderColor: folderColor) {
            self = exact
            return
        }
        switch folderColor {
        case .pink: self = .red
        case .indigo: self = .purple
        case .teal: self = .blue
        case .custom(let red, let green, let blue): self = Self.nearest(red: red, green: green, blue: blue)
        case .unknown, .blue, .green, .yellow, .orange, .red, .purple, .gray: return nil
        }
    }

    private static func nearest(red: UInt8, green: UInt8, blue: UInt8) -> FinderTagColor {
        let components = [Double(red), Double(green), Double(blue)].map { component in component / 255 }
        let maximum = components.max() ?? 0, minimum = components.min() ?? 0
        let saturation = maximum == 0 ? 0 : (maximum - minimum) / maximum
        // Grays, and colors too dark to tell, read as gray.
        guard saturation >= 0.2, maximum >= 0.15 else { return .gray }
        let delta = maximum - minimum
        var hueSixths: Double
        if maximum == components[0] { hueSixths = (components[1] - components[2]) / delta }
        else if maximum == components[1] { hueSixths = 2 + (components[2] - components[0]) / delta }
        else { hueSixths = 4 + (components[0] - components[1]) / delta }
        if hueSixths < 0 { hueSixths += 6 }
        switch hueSixths * 60 {
        case ..<15, 330...: return .red
        case ..<45: return .orange
        case ..<70: return .yellow
        case ..<170: return .green
        case ..<260: return .blue
        default: return .purple
        }
    }
}

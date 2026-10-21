import Foundation

/// What Graphite writes so that Finder shows a folder's style: the folder's tags with one
/// color tag for the style's color, written with its color number as Finder writes it (the
/// system's tag API looks colors up in the person's own tag list, which may lack them), and the icon attribute with the custom-icon flag for its
/// symbol or emoji. Decided here, written by the Mac's adapter.
public struct FinderFolderLookChange: Equatable, Sendable {
    /// The folder's tags in order, as stored; the color tag goes last, as Finder tints by the last.
    public let tags: [FinderTag]
    /// Nil removes the attribute.
    public let iconAttributeData: Data?
    public let setsCustomIconFlag: Bool
    public let customIconFile: CustomIconFileChange

    /// Finder's custom icon file, `Icon\r`, and what happens to it.
    public enum CustomIconFileChange: Equatable, Sendable {
        case keep
        /// Written from the folder's picture, drawn as its layout says.
        case write(FolderPicture)
        /// A look chosen in Graphite replaces a picture set before, in Finder or in Graphite.
        case remove
    }

    /// The change for `style` on a folder that shows `current`. Tags named after a tag
    /// color are the color tags Finder and Graphite add; they are replaced, and every other
    /// tag is kept. `colorTagNames` are the system's names of the color tags.
    public static func change(for style: FolderStyle?, from current: FinderFolderLook,
                              colorTagNames: [FinderTagColor: String]) -> FinderFolderLookChange {
        let knownColorNames = Set(colorTagNames.values).union(FinderTagColor.allCases.map(\.defaultTagName))
        var tags = current.tags.filter { tag in !knownColorNames.contains(tag.name) }
        // A color no tag has is written as the nearest tag color, so every app shows the same.
        if let tagColor = style?.color.flatMap(FinderTagColor.init(nearestTo:)) {
            tags.append(FinderTag(name: colorTagNames[tagColor] ?? tagColor.defaultTagName, color: tagColor))
        }
        let mark = style?.mark
        let customIconFile: CustomIconFileChange = if let picture = style?.picture { .write(picture) }
            else if current.hasCustomIconFile { .remove } else { .keep }
        return FinderFolderLookChange(tags: tags, iconAttributeData: mark.flatMap(FinderFolderLook.iconAttributeData(for:)),
                                      setsCustomIconFlag: mark != nil, customIconFile: customIconFile)
    }

    /// The color label Finder keeps beside the tags: the last colored tag's.
    public var labelColor: FinderTagColor? { tags.last { tag in tag.color != nil }?.color }
}

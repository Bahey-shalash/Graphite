import Foundation

/// What VoiceOver reads for a library tile: a file as its name, kind and date; a folder as its
/// name, its look and how many items it holds. The favorite state is spoken as the tile's value,
/// and being chosen by the selection trait, so no label repeats either.
enum LibraryTileSpokenLabel {
    static func file(name: String, kind: String, modifiedText: String) -> String {
        "\(name), \(kind), \(modifiedText)"
    }

    /// `lookDescription` is the folder's color and symbol as `FolderStyle.spokenDescription` words it; nil for a plain folder.
    static func folder(name: String, lookDescription: String?, itemCount: Int?) -> String {
        var parts = [name, "Folder"]
        if let lookDescription, !lookDescription.isEmpty { parts.append(lookDescription) }
        if let itemCount { parts.append(itemCountText(itemCount)) }
        return parts.joined(separator: ", ")
    }

    /// "12 items", "1 item", as under a folder's name in the Files app.
    static func itemCountText(_ count: Int) -> String {
        count == 1 ? "1 item" : "\(count) items"
    }
}

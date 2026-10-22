import Foundation

/// A link a plugin asked Graphite to preview (Obsidian's `hover-link` and `link-hover`), as
/// the plugin runtime names it.
public struct CommunityPluginHoveredLink: Decodable, Equatable, Sendable {
    /// Obsidian's link text, written as a Wikilink's target is: `Note`, `Folder/Note.md#Heading`.
    public let linktext: String
    /// The note the link starts from; empty when the plugin names none.
    public let sourcePath: String

    public init(linktext: String, sourcePath: String) {
        self.linktext = linktext
        self.sourcePath = sourcePath
    }

    /// The note the link resolves from: the vault's root when the plugin names none, or a
    /// path that is not a vault path, as Obsidian resolves it from the root then.
    public var sourceNote: VaultPath {
        sourcePath.isEmpty ? .root : (try? VaultPath(sourcePath)) ?? .root // Not a vault path: resolved as none.
    }
}

/// A frame a web page measured (`getBoundingClientRect`), in points from the top left of the
/// web view showing it.
public struct CommunityPluginMeasuredRect: Decodable, Equatable, Sendable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double
}

/// The runtime's answer to a hover a copy of a block or view forwarded: the link a plugin asked
/// to preview there meanwhile, if any.
public struct CommunityPluginCopyHoverAnswer: Decodable, Equatable, Sendable {
    public let linkHover: CommunityPluginHoveredLink?
}

/// What a copy's own script says of the pointer: the element it moved onto (`rect`, for a
/// hover the copy forwards), or the internal link the plugin drew under it (`linktext`, nil
/// once it left the link).
public struct CommunityPluginCopyPointer: Decodable, Equatable, Sendable {
    public let rect: CommunityPluginMeasuredRect?
    public let linktext: String?
}

/// `hoverLink.show`: a plugin asked to preview a link in the view shown live, beside an
/// element measured in the runtime's page.
public struct CommunityPluginLiveLinkHover: Decodable, Equatable, Sendable {
    /// Names the hover, which `hoverLink.end` names when the pointer leaves the element.
    public let hoverNumber: Int
    /// The live view's leaf.
    public let leafIdentifier: String
    public let linktext: String
    public let sourcePath: String
    public let rect: CommunityPluginMeasuredRect

    public var link: CommunityPluginHoveredLink { CommunityPluginHoveredLink(linktext: linktext, sourcePath: sourcePath) }
}

/// Messages from the plugin runtime as WebKit hands them over: dictionaries of JSON values.
public enum CommunityPluginRuntimeMessage {
    /// `body` decoded as `Message`; nil when it does not have that shape.
    public static func decoded<Message: Decodable>(_ type: Message.Type, from body: Any) -> Message? {
        guard JSONSerialization.isValidJSONObject(body) else { return nil }
        guard let data = try? JSONSerialization.data(withJSONObject: body) else { return nil } // A valid JSON object always encodes.
        return try? JSONDecoder().decode(type, from: data) // A message of another shape is not this one.
    }
}

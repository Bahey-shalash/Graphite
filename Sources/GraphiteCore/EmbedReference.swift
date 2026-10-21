import Foundation

/// An embed such as `![[Drawing.png|400]]` or `![](Drawing.png)` in note source.
public struct EmbedReference: Equatable, Sendable {
    public let target: String
    public let isWiki: Bool
    /// Obsidian's display size from `![[image.png|400]]` or `|400x300`.
    public let displaySize: EmbedDisplaySize?
    public let range: NSRange
    /// The width given for the image, in points, before fitting any height.
    public var displayWidth: Double? { displaySize?.width }
}

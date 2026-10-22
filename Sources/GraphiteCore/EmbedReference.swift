import Foundation

/// An embed such as `![[Drawing.png|400]]` or `![](Drawing.png)` in note source.
public struct EmbedReference: Equatable, Sendable {
    public let target: String
    public let isWiki: Bool
    /// Obsidian's display size from `![[image.png|400]]` or `|400x300`.
    public let displaySize: EmbedDisplaySize?
    public let range: NSRange

    public init(target: String, isWiki: Bool, displaySize: EmbedDisplaySize?, range: NSRange) {
        self.target = target
        self.isWiki = isWiki
        self.displaySize = displaySize
        self.range = range
    }

    /// The width given for the image, in points, before fitting any height.
    public var displayWidth: Double? { displaySize?.width }
    /// Whether the embed is a web image (`![](https://…)`), which is not a vault file. Only
    /// the destination counts, not a title written after it.
    var isRemoteImage: Bool {
        let destination = target.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? target
        return !isWiki && URL(string: destination)?.scheme != nil
    }
}

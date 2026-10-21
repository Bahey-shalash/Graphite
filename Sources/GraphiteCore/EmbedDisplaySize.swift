import Foundation

/// Obsidian's image size: `400` or `400x300` after the last `|` of an embed's label, as in
/// `![[image.png|400]]`, `![[image.png|Caption|400x300]]`, or `![Caption|400](image.png)`.
public struct EmbedDisplaySize: Hashable, Sendable {
    /// In points.
    public let width: Double
    /// In points; nil when only the width is given, so the image keeps its shape.
    public let height: Double?

    public init(width: Double, height: Double?) {
        self.width = width; self.height = height
    }

    private static let maximumPoints = 10_000.0

    public static func parse(label: String) -> EmbedDisplaySize? {
        let sizeText = (label.split(separator: "|", omittingEmptySubsequences: false).last.map(String.init) ?? label).trimmingCharacters(in: .whitespaces)
        let dimensions = sizeText.split(separator: "x", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        guard let width = points(dimensions[0]) else { return nil }
        guard dimensions.count == 2 else { return EmbedDisplaySize(width: width, height: nil) }
        guard let height = points(dimensions[1]) else { return nil }
        return EmbedDisplaySize(width: width, height: height)
    }

    private static func points(_ text: String) -> Double? {
        // Digits only: "1e3" or "Infinity" would be read as numbers by `Double`.
        guard !text.isEmpty, text.allSatisfy(\.isASCII), text.allSatisfy({ character in character.isNumber || character == "." }),
              let value = Double(text), value > 0, value <= maximumPoints else { return nil }
        return value
    }

    /// The width to draw an image of `aspectRatio` (width over height) at, so that it fits
    /// both given dimensions without being stretched.
    public func fittedWidth(aspectRatio: Double) -> Double {
        guard let height, aspectRatio > 0 else { return width }
        return min(width, height * aspectRatio)
    }
}

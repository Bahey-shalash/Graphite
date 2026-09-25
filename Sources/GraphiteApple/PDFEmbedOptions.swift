import Foundation

/// Options Obsidian reads from a PDF embed's fragment, such as `![[slides.pdf#page=3]]`,
/// `![[slides.pdf#height=400]]` or `![[slides.pdf#page=3&height=400]]`.
public struct PDFEmbedOptions: Sendable, Equatable {
    /// One-based, as written in the note. Nil opens the first page.
    public let startPageNumber: Int?
    /// Viewer height in points. Nil uses the viewer's default height.
    public let height: Double?

    public static let minimumHeight = 160.0
    public static let maximumHeight = 4_000.0

    public init(startPageNumber: Int? = nil, height: Double? = nil) {
        self.startPageNumber = startPageNumber.flatMap { pageNumber in pageNumber >= 1 ? pageNumber : nil }
        self.height = height.flatMap { requestedHeight in
            requestedHeight.isFinite && requestedHeight > 0 ? min(max(requestedHeight, Self.minimumHeight), Self.maximumHeight) : nil
        }
    }

    /// Reads the options from the part of a link after `#`, such as `page=3` in
    /// `Lecture 5.pdf#page=3`. Unknown keys are ignored, as Obsidian ignores them.
    /// A value that is malformed or out of range is skipped, so it never erases an
    /// earlier valid value for the same key; among valid values the last one wins.
    public init(fragment: String) {
        var pageNumber: Int?
        var height: Double?
        for parameter in fragment.split(separator: "&") {
            let keyAndValue = parameter.split(separator: "=", maxSplits: 1).map { part in part.trimmingCharacters(in: .whitespaces) }
            guard keyAndValue.count == 2 else { continue }
            let valueText = keyAndValue[1]
            switch keyAndValue[0].lowercased() {
            case "page":
                if let parsedPageNumber = Int(valueText), parsedPageNumber >= 1 { pageNumber = parsedPageNumber }
            case "height":
                if let parsedHeight = Self.plainDecimal(valueText), parsedHeight > 0 { height = parsedHeight }
            default: continue
            }
        }
        self.init(startPageNumber: pageNumber, height: height)
    }

    /// Digits with an optional fraction, such as `400` or `320.5`. `Double(_:)` would
    /// also read `0x10`, `1e3`, `inf` and `nan`, which are not heights anyone writes.
    private static func plainDecimal(_ text: String) -> Double? {
        let parts = text.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        guard let wholePart = parts.first, !wholePart.isEmpty,
              parts.allSatisfy({ part in part.allSatisfy { character in character.isASCII && character.isNumber } }),
              parts.count == 1 || !parts[1].isEmpty else { return nil }
        return Double(text)
    }
}

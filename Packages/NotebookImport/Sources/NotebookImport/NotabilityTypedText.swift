import Foundation

/// The note's typed text (`richText.attributedString`): one body laid out from the document's top left, in runs.
public struct NotabilityTypedText: Sendable, Equatable {
    public let text: String
    public let runs: [NotabilityTextRun]

    public init(text: String, runs: [NotabilityTextRun]) {
        self.text = text
        self.runs = runs
    }
}

/// A run of typed text with its attributes. Its range counts UTF-16 units, as `NSRange` does.
public struct NotabilityTextRun: Sendable, Equatable {
    public let utf16Location: Int
    public let utf16Length: Int
    /// The font's name; bold and italic are font names, not attributes.
    public let fontName: String?
    /// The font size in document units.
    public let fontSize: Double?
    /// Nil when the run stores no colour or one that is not four components (reported as `textRunColorNotReadable`).
    public let color: NotebookImportColor?
    public let isUnderlined: Bool
    public let isStruckThrough: Bool
    public let lineSpacing: Double?
    public let baselineOffset: Double?

    public init(utf16Location: Int, utf16Length: Int, fontName: String?, fontSize: Double?, color: NotebookImportColor?, isUnderlined: Bool,
                isStruckThrough: Bool, lineSpacing: Double?, baselineOffset: Double?) {
        self.utf16Location = utf16Location
        self.utf16Length = utf16Length
        self.fontName = fontName
        self.fontSize = fontSize
        self.color = color
        self.isUnderlined = isUnderlined
        self.isStruckThrough = isStruckThrough
        self.lineSpacing = lineSpacing
        self.baselineOffset = baselineOffset
    }
}

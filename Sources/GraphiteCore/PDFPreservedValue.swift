import Foundation

/// A value of a PDF dictionary entry Graphite does not use itself, kept so that writing an
/// annotation again gives it back: another application's keys on a text box it made
/// (`PDFTextBox.preservedEntries`).
public indirect enum PDFPreservedValue: Sendable, Hashable {
    /// A PDF name, without its slash.
    case name(String)
    case text(String)
    case integer(Int)
    case real(Double)
    case boolean(Bool)
    case array([PDFPreservedValue])
    case dictionary([String: PDFPreservedValue])

    /// Bounds what is kept of one annotation: entries, nesting and text, so a damaged or
    /// hostile file cannot make a box hold more than a page of text.
    public static let maximumEntryCount = 64
    public static let maximumNesting = 8
    public static let maximumTextUTF16Count = 65_536
}

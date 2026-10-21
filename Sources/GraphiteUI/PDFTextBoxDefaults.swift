import Foundation
import GraphiteCore

/// The look a new text box starts with: the look last given to a box, on this device, as
/// Goodnotes and Notability keep the last text style. A box changed through its format
/// popover, or the text tool's options on the fixed bar, sets it; typing does not.
struct PDFTextBoxDefaults: Codable, Equatable {
    var attributes: PDFTextAttributes
    var boxStyle: PDFTextBoxStyle

    static let preferenceKey = "GraphitePDFTextBoxStyle"
    /// The width a new box is made, in points of the page.
    static let newBoxWidthPoints: Double = 260
    /// The narrowest a new box is made near the page's edge.
    static let narrowestNewBoxWidthPoints: Double = 80
    /// The room a new box leaves before the page's edge.
    static let pageMarginPoints: Double = 12

    static let original = PDFTextBoxDefaults(attributes: PDFTextAttributes(fontFamily: PDFTextAttributes.defaultFontFamily,
                                                                           fontSize: PDFTextAttributes.defaultFontSize, color: .black),
                                             boxStyle: .plain)

    /// The look kept in `defaults`; the original look when none is kept, or one this build
    /// cannot read, which stays as it is until a box is formatted again.
    static func stored(in defaults: UserDefaults) -> PDFTextBoxDefaults {
        stored(decoding: defaults.data(forKey: preferenceKey))
    }

    /// The look kept as `data`, the value under `preferenceKey`.
    static func stored(decoding data: Data?) -> PDFTextBoxDefaults {
        guard let data, let stored = try? JSONDecoder().decode(PDFTextBoxDefaults.self, from: data) else { return original } // Unreadable: the original look.
        // Brought inside the limits a box has, as a file of another build may hold others.
        let attributes = PDFTextAttributes(fontFamily: stored.attributes.fontFamily, fontSize: stored.attributes.fontSize, color: stored.attributes.color,
                                           isBold: stored.attributes.isBold, isItalic: stored.attributes.isItalic, isUnderlined: stored.attributes.isUnderlined)
        let style = stored.boxStyle
        return PDFTextBoxDefaults(attributes: attributes,
                                  boxStyle: PDFTextBoxStyle(alignment: style.alignment, lineSpacing: style.lineSpacing, fillColor: style.fillColor,
                                                            borderColor: style.borderColor, borderWidth: style.borderWidth, padding: style.padding))
    }

    func store(in defaults: UserDefaults) {
        // A look that cannot be encoded is not kept; the next box starts with the one kept before.
        guard let encoded else { return }
        defaults.set(encoded, forKey: Self.preferenceKey)
    }

    /// The value kept under `preferenceKey`.
    var encoded: Data? {
        try? JSONEncoder().encode(self) // Encoding plain values fails only for values a box never holds.
    }

    /// The look of a box, as the next new box takes it: its text's first look, without a link.
    init(box: PDFTextBox) {
        var attributes = box.leadingAttributes
        attributes.link = nil
        self.init(attributes: attributes, boxStyle: box.style)
    }

    init(attributes: PDFTextAttributes, boxStyle: PDFTextBoxStyle) {
        self.attributes = attributes
        self.boxStyle = boxStyle
    }
}

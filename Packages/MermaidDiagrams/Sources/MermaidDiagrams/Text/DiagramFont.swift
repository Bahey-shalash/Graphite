import CoreGraphics
import CoreText

/// The font a diagram's text is measured and drawn in: the system's text font, or a font by its PostScript name.
public struct DiagramFont: Equatable, Sendable {
    /// The PostScript name, or nil for the system's text font.
    public let postScriptName: String?
    public let size: CGFloat

    public init(postScriptName: String?, size: CGFloat) {
        self.postScriptName = postScriptName
        self.size = size
    }

    /// The same font at another size.
    func resized(to size: CGFloat) -> DiagramFont {
        DiagramFont(postScriptName: postScriptName, size: size)
    }

    /// The Core Text font. A name no installed font has gives Core Text's fallback, as text drawn with it would.
    func makeCoreTextFont() -> CTFont {
        if let postScriptName { return CTFontCreateWithName(postScriptName as CFString, size, nil) }
        return CTFontCreateUIFontForLanguage(.system, size, nil) ?? CTFontCreateWithName("Helvetica" as CFString, size, nil)
    }
}

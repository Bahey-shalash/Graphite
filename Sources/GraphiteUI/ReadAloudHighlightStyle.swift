import SwiftUI
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// The one color of the word being read, in notes, the reading view, PDFs and the transcript.
/// Blue rather than yellow, so it is never mistaken for a ==highlight== in the note, and
/// stronger in dark appearance and with Increase Contrast. Text stays fully legible on it:
/// black on the light fill and white on the dark fill both measure above 10:1.
enum ReadAloudHighlightStyle {
    #if canImport(UIKit)
    static let fill = UIColor { traits in
        let isDark = traits.userInterfaceStyle == .dark
        let isHighContrast = traits.accessibilityContrast == .high
        return UIColor.systemBlue.withAlphaComponent(isDark ? (isHighContrast ? 0.55 : 0.4) : (isHighContrast ? 0.36 : 0.24))
    }
    #else
    static let fill = NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua, .accessibilityHighContrastDarkAqua, .accessibilityHighContrastAqua])
        switch isDark {
        case .darkAqua: return NSColor.systemBlue.withAlphaComponent(0.4)
        case .accessibilityHighContrastDarkAqua: return NSColor.systemBlue.withAlphaComponent(0.55)
        case .accessibilityHighContrastAqua: return NSColor.systemBlue.withAlphaComponent(0.36)
        default: return NSColor.systemBlue.withAlphaComponent(0.24)
        }
    }
    #endif

    static var color: Color { Color(fill) }
}

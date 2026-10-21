#if os(macOS)
import Foundation

/// How AppKit draws Graphite's large views on the Mac.
///
/// AppKit hands the drawing of any view larger than 768 by 768 pixels that draws itself, such
/// as the note editor's text view, to Core Animation's Metal renderer. Starting that renderer
/// reserves about 170 MB of graphics memory for a second, every time a note opens: opening a
/// one-line note took Graphite from 77 MB to a 272 MB peak. With the renderer turned off the
/// same note peaks at 94 MB, and scrolling a long note costs no more processor time.
/// (Measured 2026-10-21 on macOS 27 with a Release build; Docs/Coverage.md, "Small core".)
public enum MacViewDrawing {
    /// The AppKit default that allows the Metal renderer. AppKit reads it once, at the first
    /// view it draws, and ignores a value that is not a Boolean.
    static let metalRendererDefaultsKey = "NSViewCanUseGPUAcceleration"

    /// Draws large views on the processor, as AppKit draws small ones. Call it before the
    /// first window shows; a value someone set with `defaults write` still wins.
    public static func drawLargeViewsWithoutTheMetalRenderer(in defaults: UserDefaults = .standard) {
        defaults.register(defaults: [metalRendererDefaultsKey: false])
    }
}
#endif

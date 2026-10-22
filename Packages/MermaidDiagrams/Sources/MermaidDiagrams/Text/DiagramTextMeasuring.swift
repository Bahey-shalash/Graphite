import CoreGraphics

/// Measures lines of a diagram's text in one font and size.
///
/// A protocol because the layout has two measurers: Core Text's in use (`CoreTextDiagramTextMeasurer`), and one of
/// fixed widths in tests, so that what a test asserts does not depend on the fonts a machine has.
public protocol DiagramTextMeasuring {
    /// The font's size, in points.
    var fontSize: CGFloat { get }
    /// The distance between two lines' baselines, in points.
    var lineHeight: CGFloat { get }
    /// The width of `text` on one line, in points.
    func width(of text: String) -> CGFloat
}

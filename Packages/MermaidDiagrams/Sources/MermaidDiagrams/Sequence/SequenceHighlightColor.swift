/// The color a `rect` block shades its messages with, as its line writes it in CSS (`rgb(191, 223, 255)`,
/// `rgba(0, 0, 255, .1)`, `#bfdfff`, `hsl(…)` or a color name), in sRGB components from 0 to 1.
public struct SequenceHighlightColor: Equatable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double
    public let alpha: Double

    init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }
}

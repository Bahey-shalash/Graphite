import Foundation

/// Keeps an accent color readable on a dark background. The accent is one color chosen
/// in light appearance; text and symbols drawn in a dark ink blue would nearly vanish on
/// black, so in dark appearance the color is lightened just enough to read, keeping its hue.
public enum AccentLegibility {
    /// The contrast WCAG asks of text against its background.
    public static let minimumTextContrast = 4.5
    /// Relative luminance of the elevated dark background (`#1C1C1E`), the lightest surface
    /// dark appearance puts text on.
    static let darkBackgroundLuminance = 0.0116

    /// WCAG relative luminance of an sRGB color with components from 0 to 1.
    public static func relativeLuminance(red: Double, green: Double, blue: Double) -> Double {
        func linear(_ component: Double) -> Double {
            let clamped = min(max(component, 0), 1)
            return clamped <= 0.04045 ? clamped / 12.92 : pow((clamped + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    public static func contrastOnDarkBackground(red: Double, green: Double, blue: Double) -> Double {
        (relativeLuminance(red: red, green: green, blue: blue) + 0.05) / (darkBackgroundLuminance + 0.05)
    }

    /// The color mixed with white by the smallest amount that reaches the text contrast on
    /// a dark background; unchanged when it already reads there.
    public static func lightenedForDarkBackground(red: Double, green: Double, blue: Double) -> (red: Double, green: Double, blue: Double) {
        func mixed(_ whiteFraction: Double) -> (red: Double, green: Double, blue: Double) {
            (red + (1 - red) * whiteFraction, green + (1 - green) * whiteFraction, blue + (1 - blue) * whiteFraction)
        }
        func reads(_ color: (red: Double, green: Double, blue: Double)) -> Bool {
            contrastOnDarkBackground(red: color.red, green: color.green, blue: color.blue) >= minimumTextContrast
        }
        guard !reads((red, green, blue)) else { return (red, green, blue) }
        var lowerFraction = 0.0, upperFraction = 1.0
        for _ in 0..<24 {
            let middleFraction = (lowerFraction + upperFraction) / 2
            if reads(mixed(middleFraction)) { upperFraction = middleFraction } else { lowerFraction = middleFraction }
        }
        return mixed(upperFraction)
    }
}

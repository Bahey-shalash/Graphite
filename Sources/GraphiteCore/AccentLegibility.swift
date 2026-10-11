import Foundation

/// Keeps an accent color readable as text in both appearances. The accent is one color
/// chosen by the user; a dark ink blue would nearly vanish on black and a light amber on
/// white, so each appearance moves the color just enough to read, keeping its hue: toward
/// white in dark appearance and toward black in light appearance.
public enum AccentLegibility {
    /// The contrast WCAG asks of text against its background.
    public static let minimumTextContrast = 4.5
    /// The contrast Apple suggests for custom text colors, used when Increase Contrast is on.
    public static let increasedTextContrast = 7.0
    /// Relative luminance of the elevated dark background (`#1C1C1E`), the lightest surface
    /// dark appearance puts text on.
    public static let darkBackgroundLuminance = relativeLuminance(red: 28.0 / 255, green: 28.0 / 255, blue: 30.0 / 255)
    /// Relative luminance of the grouped light background (`#F2F2F7`), the darkest surface
    /// light appearance puts text on.
    public static let lightBackgroundLuminance = relativeLuminance(red: 242.0 / 255, green: 242.0 / 255, blue: 247.0 / 255)

    /// WCAG relative luminance of an sRGB color with components from 0 to 1.
    public static func relativeLuminance(red: Double, green: Double, blue: Double) -> Double {
        func linear(_ component: Double) -> Double {
            let clamped = min(max(component, 0), 1)
            return clamped <= 0.04045 ? clamped / 12.92 : pow((clamped + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    /// WCAG contrast ratio between two relative luminances, in either order.
    public static func contrast(betweenLuminance firstLuminance: Double, and secondLuminance: Double) -> Double {
        (max(firstLuminance, secondLuminance) + 0.05) / (min(firstLuminance, secondLuminance) + 0.05)
    }

    public static func contrastOnDarkBackground(red: Double, green: Double, blue: Double) -> Double {
        contrast(betweenLuminance: relativeLuminance(red: red, green: green, blue: blue), and: darkBackgroundLuminance)
    }

    public static func contrastOnLightBackground(red: Double, green: Double, blue: Double) -> Double {
        contrast(betweenLuminance: relativeLuminance(red: red, green: green, blue: blue), and: lightBackgroundLuminance)
    }

    /// The color mixed with white by the smallest amount that reaches the text contrast
    /// (`targetContrast`) on a dark background; unchanged when it already reads there.
    public static func lightenedForDarkBackground(red: Double, green: Double, blue: Double,
                                                  targetContrast: Double = minimumTextContrast) -> (red: Double, green: Double, blue: Double) {
        smallestMix(of: (red, green, blue), toward: 1) { color in
            contrastOnDarkBackground(red: color.red, green: color.green, blue: color.blue) >= targetContrast
        }
    }

    /// The color mixed with black by the smallest amount that reaches the text contrast on
    /// a light background of the given luminance (the grouped light background unless
    /// another is named); unchanged when it already reads there.
    public static func darkenedForLightBackground(red: Double, green: Double, blue: Double,
                                                  backgroundLuminance: Double = lightBackgroundLuminance,
                                                  targetContrast: Double = minimumTextContrast) -> (red: Double, green: Double, blue: Double) {
        smallestMix(of: (red, green, blue), toward: 0) { color in
            contrast(betweenLuminance: relativeLuminance(red: color.red, green: color.green, blue: color.blue), and: backgroundLuminance)
                >= targetContrast
        }
    }

    /// The color darkened just enough to read as text on a light tint of itself: the color
    /// at `tintOpacity` over white, as a callout's title sits on its callout.
    public static func darkenedForOwnTint(red: Double, green: Double, blue: Double, tintOpacity: Double,
                                          targetContrast: Double = minimumTextContrast) -> (red: Double, green: Double, blue: Double) {
        func tinted(_ component: Double) -> Double { component * tintOpacity + (1 - tintOpacity) }
        let tintLuminance = relativeLuminance(red: tinted(red), green: tinted(green), blue: tinted(blue))
        return darkenedForLightBackground(red: red, green: green, blue: blue, backgroundLuminance: tintLuminance, targetContrast: targetContrast)
    }

    /// The smallest mix of `color` with a gray of `target` (0 black, 1 white) that `reads`,
    /// found by bisection; the color itself when it already reads.
    private static func smallestMix(of color: (red: Double, green: Double, blue: Double), toward target: Double,
                                    reads: ((red: Double, green: Double, blue: Double)) -> Bool) -> (red: Double, green: Double, blue: Double) {
        func mixed(_ targetFraction: Double) -> (red: Double, green: Double, blue: Double) {
            (color.red + (target - color.red) * targetFraction, color.green + (target - color.green) * targetFraction,
             color.blue + (target - color.blue) * targetFraction)
        }
        guard !reads(color) else { return color }
        var lowerFraction = 0.0, upperFraction = 1.0
        for _ in 0..<24 {
            let middleFraction = (lowerFraction + upperFraction) / 2
            if reads(mixed(middleFraction)) { upperFraction = middleFraction } else { lowerFraction = middleFraction }
        }
        return mixed(upperFraction)
    }
}

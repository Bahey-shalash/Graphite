/// Writes a number as JavaScript's `String(number)` does, as Pele writes a chart's numbers: the fewest digits that
/// read back as the same double, without a fraction for a whole number (`100`, not `100.0`), in plain digits from
/// 10⁻⁶ up to 10²¹ and with an exponent outside them (`1e-7`, `1.5e+21`).
enum JavaScriptNumberText {
    /// The furthest right of its digits the decimal point is in a number JavaScript writes in plain digits: 10²⁰ is
    /// plain, 10²¹ is not.
    private static let largestPlainPointPosition = 21
    /// The furthest left of its digits the decimal point is in a number JavaScript writes in plain digits: 0.000001
    /// is plain, 1e-7 is not.
    private static let smallestPlainPointPosition = -5

    static func text(_ number: Double) -> String {
        guard number.isFinite else { return number.isNaN ? "NaN" : (number > 0 ? "Infinity" : "-Infinity") }
        guard number != 0 else { return "0" }
        let sign = number < 0 ? "-" : ""
        let (digits, pointPosition) = shortestDigits(of: number.magnitude)
        let digitCount = digits.count
        if digitCount <= pointPosition, pointPosition <= largestPlainPointPosition {
            return sign + digits + String(repeating: "0", count: pointPosition - digitCount)
        }
        if pointPosition > 0, pointPosition <= largestPlainPointPosition {
            return sign + String(digits.prefix(pointPosition)) + "." + String(digits.dropFirst(pointPosition))
        }
        if pointPosition >= smallestPlainPointPosition, pointPosition <= 0 {
            return sign + "0." + String(repeating: "0", count: -pointPosition) + digits
        }
        let exponent = pointPosition - 1
        let mantissa = digitCount == 1 ? digits : String(digits.prefix(1)) + "." + String(digits.dropFirst())
        return sign + mantissa + "e" + (exponent >= 0 ? "+" : "-") + String(exponent.magnitude)
    }

    /// The shortest digits of a positive double that read back as it, without leading or trailing zeros, and where
    /// the decimal point goes among them: `0.00125` is `125` with the point at -2, `1500` is `15` at 4.
    private static func shortestDigits(of magnitude: Double) -> (digits: String, pointPosition: Int) {
        // Swift's description is the shortest form that reads back as the same double, as JavaScript's is.
        let written = magnitude.description
        let parts = written.split(separator: "e", maxSplits: 1)
        let exponent = parts.count == 2 ? Int(parts[1]) ?? 0 : 0
        let mantissa = parts[0].split(separator: ".", maxSplits: 1)
        let integerDigits = mantissa[0]
        let allDigits = Substring(integerDigits + (mantissa.count == 2 ? mantissa[1] : ""))
        let leadingZeroCount = allDigits.prefix { character in character == "0" }.count
        let significant = allDigits.dropFirst(leadingZeroCount)
        let trimmed = significant.prefix(significant.count - significant.reversed().prefix { character in character == "0" }.count)
        return (String(trimmed), integerDigits.count + exponent - leadingZeroCount)
    }
}

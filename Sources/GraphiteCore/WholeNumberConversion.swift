import Foundation

extension Int {
    /// The whole part of `number`, clamped to ±Int.max; nil for NaN. Numbers from notes
    /// and formulas are untrusted (`1e300`, `.inf`), and `Int(_:)` traps on them. The
    /// range is symmetric so that negating the result or taking `abs` never traps either.
    init?(clampingWholePartOf number: Double) {
        guard !number.isNaN else { return nil }
        let wholePart = number.rounded(.towardZero)
        // Double(Int.max) rounds up to 2^63, so every whole part strictly between the
        // bounds converts exactly.
        if wholePart >= Double(Int.max) { self = .max }
        else if wholePart <= -Double(Int.max) { self = -.max }
        else { self = Int(wholePart) }
    }
}

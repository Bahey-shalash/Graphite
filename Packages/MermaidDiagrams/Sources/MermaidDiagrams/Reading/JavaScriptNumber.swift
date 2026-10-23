/// Reads text as JavaScript's `Number(text)` does, for the diagrams whose values Mermaid reads that way (a user
/// journey's scores): the spaces and line breaks at either end are ignored, nothing at all is 0, and what is left must
/// be a decimal number (`5`, `-2.5`, `.5`, `3.`, `1e3`, `Infinity` with an optional sign) or a whole number in
/// hexadecimal, octal or binary (`0x1F`, `0o17`, `0b101`, without a sign). Anything else is not a number.
enum JavaScriptNumber {
    /// The number `text` stands for, or nil when JavaScript reads it as `NaN`.
    static func value(of text: Substring) -> Double? {
        let trimmed = trimmed(text.unicodeScalars)
        guard !trimmed.isEmpty else { return 0 }
        if let radixValue = radixIntegerValue(trimmed) { return radixValue }
        let unsigned = trimmed.first == "+" || trimmed.first == "-" ? trimmed.dropFirst() : trimmed
        if unsigned.elementsEqual("Infinity".unicodeScalars) { return trimmed.first == "-" ? -.infinity : .infinity }
        guard isUnsignedDecimal(unsigned) else { return nil }
        return Double(Substring(trimmed))
    }

    /// `scalars` without JavaScript's white space and line terminators at either end.
    private static func trimmed(_ scalars: Substring.UnicodeScalarView) -> Substring.UnicodeScalarView {
        var slice = scalars
        while let first = slice.first, isWhiteSpace(first) { slice = slice.dropFirst() }
        while let last = slice.last, isWhiteSpace(last) { slice = slice.dropLast() }
        return slice
    }

    /// JavaScript's white space (tab, vertical tab, form feed, the byte order mark and every space separator) and
    /// line terminators (line feed, carriage return, line and paragraph separators).
    private static func isWhiteSpace(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x09...0x0D, 0x20, 0xA0, 0x1680, 0x2000...0x200A, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000, 0xFEFF: true
        default: false
        }
    }

    /// `0x`, `0o` or `0b` in either case followed by at least one digit of that base, and nothing else, as a number.
    private static func radixIntegerValue(_ scalars: Substring.UnicodeScalarView) -> Double? {
        guard !scalars.dropFirst(2).isEmpty, scalars.first == "0", let marker = scalars.dropFirst().first else { return nil }
        let radix: Int
        switch marker {
        case "x", "X": radix = 16
        case "o", "O": radix = 8
        case "b", "B": radix = 2
        default: return nil
        }
        var value = 0.0
        for scalar in scalars.dropFirst(2) {
            guard let digit = asciiDigitValue(scalar), digit < radix else { return nil }
            value = value * Double(radix) + Double(digit)
        }
        return value
    }

    /// The value of an ASCII digit or letter from `a` to `f` in either case, or nil.
    private static func asciiDigitValue(_ scalar: Unicode.Scalar) -> Int? {
        switch scalar {
        case "0"..."9": Int(scalar.value - Unicode.Scalar("0").value)
        case "a"..."f": Int(scalar.value - Unicode.Scalar("a").value) + 10
        case "A"..."F": Int(scalar.value - Unicode.Scalar("A").value) + 10
        default: nil
        }
    }

    /// Digits with an optional fraction (`3.`, `3.5`) or a fraction alone (`.5`), then an optional exponent (`e-3`).
    private static func isUnsignedDecimal(_ scalars: Substring.UnicodeScalarView) -> Bool {
        var rest = scalars
        let integerDigitCount = dropDigits(&rest)
        var fractionDigitCount = 0
        if rest.first == "." {
            rest = rest.dropFirst()
            fractionDigitCount = dropDigits(&rest)
        }
        guard integerDigitCount + fractionDigitCount > 0 else { return false }
        if rest.first == "e" || rest.first == "E" {
            rest = rest.dropFirst()
            if rest.first == "+" || rest.first == "-" { rest = rest.dropFirst() }
            guard dropDigits(&rest) > 0 else { return false }
        }
        return rest.isEmpty
    }

    /// Drops the ASCII digits at the start of `scalars` and returns how many there were.
    private static func dropDigits(_ scalars: inout Substring.UnicodeScalarView) -> Int {
        var count = 0
        while let first = scalars.first, ("0"..."9").contains(first) {
            scalars = scalars.dropFirst()
            count += 1
        }
        return count
    }
}

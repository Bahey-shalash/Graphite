/// Reads a number as JavaScript's `parseFloat` does, as Mermaid reads a Sankey diagram's values: whitespace at the
/// start is skipped, then the longest decimal number there is read (a sign, digits with a fraction and an exponent,
/// or `Infinity`), and whatever follows it is left (`12 kg` is 12). Nil where JavaScript gives `NaN`: no number starts
/// the text.
enum JavaScriptNumberReading {
    /// The number at the start of `bytes`, UTF-8 text.
    static func parseFloat(_ bytes: ArraySlice<UInt8>) -> Double? {
        var position = JavaScriptWhitespace.endOfRun(in: bytes, from: bytes.startIndex)
        let start = position
        if position < bytes.endIndex, bytes[position] == UInt8(ascii: "+") || bytes[position] == MermaidByte.hyphen { position += 1 }
        if bytes[position...].starts(with: infinity) {
            return bytes[start] == MermaidByte.hyphen ? -.infinity : .infinity
        }
        let integerEnd = endOfDigits(in: bytes, from: position)
        var end = integerEnd
        var hasDigits = integerEnd > position
        if end < bytes.endIndex, bytes[end] == MermaidByte.period {
            let fractionEnd = endOfDigits(in: bytes, from: end + 1)
            hasDigits = hasDigits || fractionEnd > end + 1
            end = fractionEnd
        }
        guard hasDigits else { return nil }
        end = endOfExponent(in: bytes, from: end)
        return Double(String(decoding: bytes[start..<end], as: UTF8.self))
    }

    /// The end of `e` or `E`, a sign and digits at `position`, or `position` when no whole exponent is there.
    private static func endOfExponent(in bytes: ArraySlice<UInt8>, from position: Int) -> Int {
        guard position < bytes.endIndex, bytes[position] == UInt8(ascii: "e") || bytes[position] == UInt8(ascii: "E") else { return position }
        var digitsStart = position + 1
        if digitsStart < bytes.endIndex, bytes[digitsStart] == UInt8(ascii: "+") || bytes[digitsStart] == MermaidByte.hyphen { digitsStart += 1 }
        let end = endOfDigits(in: bytes, from: digitsStart)
        return end > digitsStart ? end : position
    }

    private static func endOfDigits(in bytes: ArraySlice<UInt8>, from position: Int) -> Int {
        var end = position
        while end < bytes.endIndex, MermaidByte.isDigit(bytes[end]) { end += 1 }
        return end
    }

    private static let infinity = Array("Infinity".utf8)
}

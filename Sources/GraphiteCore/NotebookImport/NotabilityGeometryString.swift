import Foundation

/// The numbers of a geometry string such as `{-13.6, 1815.0}` or `{{0, 0}, {520, 304}}`, found as the reference
/// reader finds them: each match of `-?\d+(?:\.\d+)?(?:e-?\d+)?` (ASCII digits) in order, so a malformed string
/// gives the same numbers in both readers.
enum NotabilityGeometryString {
    private static let minus = UInt8(ascii: "-")
    private static let decimalPoint = UInt8(ascii: ".")
    private static let exponentMarker = UInt8(ascii: "e")

    static func numbers(in text: String) -> [Double] {
        let characters = Array(text.utf8)
        var numbers: [Double] = []
        var position = 0
        while position < characters.count {
            guard let end = numberEnd(in: characters, from: position) else {
                position += 1
                continue
            }
            if let number = Double(String(decoding: characters[position..<end], as: UTF8.self)) { numbers.append(number) }
            position = end
        }
        return numbers
    }

    /// Where a number that starts here ends; nil when none starts here.
    private static func numberEnd(in characters: [UInt8], from start: Int) -> Int? {
        var position = start
        if characters[position] == minus { position += 1 }
        guard let integerEnd = digitsEnd(in: characters, from: position) else { return nil }
        position = integerEnd
        if position < characters.count, characters[position] == decimalPoint,
           let fractionEnd = digitsEnd(in: characters, from: position + 1) {
            position = fractionEnd
        }
        if position < characters.count, characters[position] == exponentMarker {
            var exponentStart = position + 1
            if exponentStart < characters.count, characters[exponentStart] == minus { exponentStart += 1 }
            if let exponentEnd = digitsEnd(in: characters, from: exponentStart) { position = exponentEnd }
        }
        return position
    }

    /// The end of a run of at least one ASCII digit that starts here; nil when no digit is here.
    private static func digitsEnd(in characters: [UInt8], from start: Int) -> Int? {
        var position = start
        while position < characters.count, (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(characters[position]) { position += 1 }
        return position > start ? position : nil
    }
}

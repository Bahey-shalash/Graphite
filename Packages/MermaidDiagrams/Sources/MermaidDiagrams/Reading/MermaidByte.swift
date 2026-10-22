/// The bytes of Mermaid's syntax, and the classes of bytes its readers test.
enum MermaidByte {
    static let newline = UInt8(ascii: "\n")
    static let carriageReturn = UInt8(ascii: "\r")
    static let space = UInt8(ascii: " ")
    static let tab = UInt8(ascii: "\t")
    static let semicolon = UInt8(ascii: ";")
    static let colon = UInt8(ascii: ":")
    static let comma = UInt8(ascii: ",")
    static let hyphen = UInt8(ascii: "-")
    static let equals = UInt8(ascii: "=")
    static let period = UInt8(ascii: ".")
    static let tilde = UInt8(ascii: "~")
    static let lessThan = UInt8(ascii: "<")
    static let greaterThan = UInt8(ascii: ">")
    static let letterO = UInt8(ascii: "o")
    static let letterX = UInt8(ascii: "x")
    static let verticalBar = UInt8(ascii: "|")
    static let ampersand = UInt8(ascii: "&")
    static let atSign = UInt8(ascii: "@")
    static let quotationMark = UInt8(ascii: "\"")
    static let graveAccent = UInt8(ascii: "`")
    static let percent = UInt8(ascii: "%")
    static let openingBracket = UInt8(ascii: "[")
    static let closingBracket = UInt8(ascii: "]")
    static let openingBrace = UInt8(ascii: "{")
    static let closingBrace = UInt8(ascii: "}")
    static let underscore = UInt8(ascii: "_")

    static func isSpace(_ byte: UInt8) -> Bool {
        byte == space || byte == tab
    }

    /// A space, a tab, a carriage return or a line break.
    static func isWhitespace(_ byte: UInt8) -> Bool {
        isSpace(byte) || byte == newline || byte == carriageReturn
    }

    static func isLetter(_ byte: UInt8) -> Bool {
        (byte >= UInt8(ascii: "a") && byte <= UInt8(ascii: "z")) || (byte >= UInt8(ascii: "A") && byte <= UInt8(ascii: "Z"))
    }

    static func isDigit(_ byte: UInt8) -> Bool {
        byte >= UInt8(ascii: "0") && byte <= UInt8(ascii: "9")
    }

    /// A letter, a digit, an underscore, or any byte of a character beyond ASCII, so that `Étape_2` is an identifier.
    static func isIdentifierByte(_ byte: UInt8) -> Bool {
        isLetter(byte) || isDigit(byte) || byte == underscore || byte >= 0x80
    }

    static func lowercased(_ byte: UInt8) -> UInt8 {
        byte >= UInt8(ascii: "A") && byte <= UInt8(ascii: "Z") ? byte + 32 : byte
    }

    /// Whether a statement ends at this byte: a line break, a semicolon or a carriage return.
    static func endsStatement(_ byte: UInt8) -> Bool {
        byte == newline || byte == semicolon || byte == carriageReturn
    }
}

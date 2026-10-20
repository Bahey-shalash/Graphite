import Foundation

/// One tag of an XML document, read as an XML parser reads it, for counting how deep a property list's arrays and
/// dictionaries nest before Foundation parses it.
struct XMLTag {
    private static let tagEnd = UInt8(ascii: ">")
    private static let slash = UInt8(ascii: "/")
    private static let exclamation = UInt8(ascii: "!")
    private static let question = UInt8(ascii: "?")
    private static let containerNames = [Array("array".utf8), Array("dict".utf8)]
    private static let commentOpening = Array("<!--".utf8)
    private static let commentEnd = Array("-->".utf8)
    private static let characterDataOpening = Array("<![CDATA[".utf8)
    private static let characterDataEnd = Array("]]>".utf8)

    /// Just past the tag.
    let end: Int
    let isContainer: Bool
    let isClosing: Bool
    let isSelfClosing: Bool

    /// The tag whose `<` is at `opening`; nil when the document ends inside it.
    init?(in bytes: ArraySlice<UInt8>, openingAt opening: Int) {
        let rest = bytes[opening...]
        if rest.starts(with: Self.commentOpening) {
            guard let commentEnd = Self.end(of: Self.commentEnd, in: rest) else { return nil }
            self.init(end: commentEnd, isContainer: false, isClosing: false, isSelfClosing: false)
        } else if rest.starts(with: Self.characterDataOpening) {
            guard let dataEnd = Self.end(of: Self.characterDataEnd, in: rest) else { return nil }
            self.init(end: dataEnd, isContainer: false, isClosing: false, isSelfClosing: false)
        } else {
            guard let close = rest.firstIndex(of: Self.tagEnd) else { return nil }
            let inside = bytes[(opening + 1)..<close]
            let isClosing = inside.first == Self.slash
            let isMarkup = inside.first == Self.exclamation || inside.first == Self.question
            let name = inside.drop { byte in byte == Self.slash }.prefix { byte in byte != Self.slash && !Self.isWhitespace(byte) }
            self.init(end: close + 1, isContainer: !isMarkup && Self.containerNames.contains { container in name.elementsEqual(container) },
                      isClosing: isClosing, isSelfClosing: inside.last == Self.slash)
        }
    }

    private init(end: Int, isContainer: Bool, isClosing: Bool, isSelfClosing: Bool) {
        self.end = end
        self.isContainer = isContainer
        self.isClosing = isClosing
        self.isSelfClosing = isSelfClosing
    }

    private static func end(of terminator: [UInt8], in bytes: ArraySlice<UInt8>) -> Int? {
        var position = bytes.startIndex
        while let candidate = bytes[position...].firstIndex(of: terminator[0]) {
            if bytes[candidate...].starts(with: terminator) { return candidate + terminator.count }
            position = candidate + 1
        }
        return nil
    }

    private static func isWhitespace(_ byte: UInt8) -> Bool {
        byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D
    }
}

/// The characters Mermaid's Sankey grammar reads as a field's text, over UTF-8 bytes: RFC 4180's `TEXTDATA` (the
/// printable ASCII characters but the quotation mark and the comma) extended to Unicode without control characters,
/// surrogates and the two noncharacters U+FFFE and U+FFFF, as Pele's lexer reads them.
enum SankeyCharacter {
    /// The length in bytes of the text character at `position`, or zero for any other character or past the end.
    static func textDataLength(in bytes: [UInt8], at position: Int) -> Int {
        guard position < bytes.count else { return 0 }
        let lead = bytes[position]
        if lead < 0x80 { return lead >= 0x20 && lead <= 0x7E && lead != MermaidByte.quotationMark && lead != MermaidByte.comma ? 1 : 0 }
        guard let (scalar, length) = scalar(in: bytes, at: position) else { return 0 }
        let isText = (0xA0...0xD7FF).contains(scalar) || (0xE000...0xFFFD).contains(scalar) || (0x1_0000...0x10_FFFF).contains(scalar)
        return isText ? length : 0
    }

    /// The scalar a UTF-8 sequence of two to four bytes at `position` encodes, and its length.
    private static func scalar(in bytes: [UInt8], at position: Int) -> (UInt32, Int)? {
        let lead = bytes[position]
        let length = lead >= 0xF0 ? 4 : lead >= 0xE0 ? 3 : lead >= 0xC0 ? 2 : 0
        guard length > 0, position + length <= bytes.count else { return nil }
        var scalar = UInt32(lead) & (0xFF >> (length + 1))
        for offset in 1..<length { scalar = scalar << 6 | UInt32(bytes[position + offset] & 0x3F) }
        return (scalar, length)
    }
}

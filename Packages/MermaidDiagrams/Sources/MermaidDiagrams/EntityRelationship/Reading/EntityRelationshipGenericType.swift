/// Mermaid writes a generic type's angle brackets as `~` (`List~int~`, `Map~K,V~`): each pair is read as `<` and `>`,
/// from the outside in. Where commas separate parts, two parts that each hold a single `~` form one pair across
/// the comma, as Mermaid's reading does; a `~` left without a pair stays.
enum EntityRelationshipGenericType {
    static func angleBracketed(_ text: String) -> String {
        guard text.contains("~") else { return text }
        var parts: [String] = []
        var pendingSingleTilde: String?
        for part in text.split(separator: ",", omittingEmptySubsequences: false).map(String.init) {
            if let previous = pendingSingleTilde, tildeCount(part) == 1 {
                parts.append(previous + "," + part)
                pendingSingleTilde = nil
            } else {
                if let previous = pendingSingleTilde { parts.append(previous) }
                pendingSingleTilde = tildeCount(part) == 1 ? part : nil
                if pendingSingleTilde == nil { parts.append(part) }
            }
        }
        if let previous = pendingSingleTilde { parts.append(previous) }
        return parts.map(pairedFromTheOutsideIn).joined(separator: ",")
    }

    /// `~` paired first with last, second with the one before last; with an odd count, a leading `~` is left alone.
    private static func pairedFromTheOutsideIn(_ part: String) -> String {
        var characters = Array(part)
        var tildePositions = characters.indices.filter { index in characters[index] == "~" }
        guard tildePositions.count > 1 else { return part }
        if !tildePositions.count.isMultiple(of: 2), characters.first == "~" { tildePositions.removeFirst() }
        var low = 0
        var high = tildePositions.count - 1
        while low < high {
            characters[tildePositions[low]] = "<"
            characters[tildePositions[high]] = ">"
            low += 1
            high -= 1
        }
        return String(characters)
    }

    private static func tildeCount(_ part: String) -> Int {
        part.utf8.reduce(0) { count, byte in byte == UInt8(ascii: "~") ? count + 1 : count }
    }
}

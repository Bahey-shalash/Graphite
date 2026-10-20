import Foundation

/// Why a property list file could not be read as plain values.
public enum PropertyListDocumentError: Error, Hashable, Sendable {
    case binary(BinaryPropertyListError)
    /// Foundation's parser refused the XML property list.
    case xmlNotReadable
    case nestingTooDeep(limit: Int)
    /// A value of a kind property lists do not hold.
    case valueKindUnknown
}

/// A property list file read as plain values, binary or XML. A binary list is read by `BinaryPropertyList`. An XML
/// list is parsed by Foundation, whose parser recurses once per level, so its tags are scanned first (`XMLTag`) and a
/// list whose arrays and dictionaries nest deeper than the limit is refused before it is parsed. XML lists hold no
/// UIDs, so nothing is lost to the opaque objects Foundation makes of them.
public enum PropertyListDocument {
    private static let binaryMagicPrefix = Array("bplist".utf8)
    private static let tagStart = UInt8(ascii: "<")

    /// `maximumValueCount` bounds a binary list, whose shared members can expand far past its size; an XML list names
    /// no shared members, so its values are bounded by its bytes.
    public static func plainValue(of bytes: ArraySlice<UInt8>, maximumNestingDepth: Int,
                                  maximumValueCount: Int) throws(PropertyListDocumentError) -> PropertyListValue {
        if bytes.starts(with: binaryMagicPrefix) {
            do throws(BinaryPropertyListError) {
                let propertyList = try BinaryPropertyList(bytes: bytes)
                return try propertyList.plainValue(ofObjectAt: propertyList.topObjectIndex, maximumNestingDepth: maximumNestingDepth,
                                                   maximumValueCount: maximumValueCount)
            } catch {
                throw .binary(error)
            }
        }
        guard !xmlNesting(in: bytes, exceeds: maximumNestingDepth) else { throw .nestingTooDeep(limit: maximumNestingDepth) }
        guard let rootObject = parsedXMLObject(bytes) else { throw .xmlNotReadable }
        return try plainValue(of: rootObject, depth: 0, maximumNestingDepth: maximumNestingDepth)
    }

    private static func parsedXMLObject(_ bytes: ArraySlice<UInt8>) -> NSObject? {
        do {
            return try PropertyListSerialization.propertyList(from: Data(bytes), options: [], format: nil) as? NSObject
        } catch {
            return nil
        }
    }

    /// Whether `<array>` and `<dict>` elements nest deeper than `limit`, reading tags as an XML parser does: a tag's
    /// name ends at whitespace, `/` or `>`, so `<array >` and `<array x="1">` count; a self-closing `<array/>` does not
    /// nest; comments, CDATA sections, declarations and processing instructions are skipped. The scan stops as soon
    /// as the depth passes the limit; the values Foundation parses are checked against the limit again.
    private static func xmlNesting(in bytes: ArraySlice<UInt8>, exceeds limit: Int) -> Bool {
        var depth = 0
        var position = bytes.startIndex
        while let tagOpening = bytes[position...].firstIndex(of: tagStart) {
            guard let tag = XMLTag(in: bytes, openingAt: tagOpening) else { return false }
            position = tag.end
            guard tag.isContainer else { continue }
            if tag.isClosing {
                depth -= 1
            } else if !tag.isSelfClosing {
                depth += 1
                if depth > limit { return true }
            }
        }
        return false
    }

    private static func plainValue(of object: NSObject, depth: Int, maximumNestingDepth: Int) throws(PropertyListDocumentError) -> PropertyListValue {
        if let string = object as? NSString { return .string(string as String) }
        if let number = object as? NSNumber { return plainValue(of: number) }
        if let date = object as? NSDate { return .date(secondsSince2001: date.timeIntervalSinceReferenceDate) }
        if let data = object as? NSData { return .data([UInt8](data as Data)[...]) }
        if let array = object as? NSArray {
            guard depth < maximumNestingDepth else { throw .nestingTooDeep(limit: maximumNestingDepth) }
            var members: [PropertyListValue] = []
            members.reserveCapacity(array.count)
            for member in array {
                guard let memberObject = member as? NSObject else { throw .valueKindUnknown }
                members.append(try plainValue(of: memberObject, depth: depth + 1, maximumNestingDepth: maximumNestingDepth))
            }
            return .array(members)
        }
        if let dictionary = object as? NSDictionary {
            guard depth < maximumNestingDepth else { throw .nestingTooDeep(limit: maximumNestingDepth) }
            return .dictionary(try plainDictionary(of: dictionary, depth: depth, maximumNestingDepth: maximumNestingDepth))
        }
        throw .valueKindUnknown
    }

    /// The dictionary's entries with their keys sorted, since Foundation does not keep the file's order.
    private static func plainDictionary(of dictionary: NSDictionary, depth: Int,
                                        maximumNestingDepth: Int) throws(PropertyListDocumentError) -> PropertyListDictionary {
        var plainDictionary = PropertyListDictionary()
        let keys = dictionary.allKeys.compactMap { key in key as? String }.sorted()
        guard keys.count == dictionary.count else { throw .valueKindUnknown }
        for key in keys {
            guard let member = dictionary.object(forKey: key) as? NSObject else { throw .valueKindUnknown }
            plainDictionary.setValue(try plainValue(of: member, depth: depth + 1, maximumNestingDepth: maximumNestingDepth), named: key)
        }
        return plainDictionary
    }

    private static func plainValue(of number: NSNumber) -> PropertyListValue {
        if CFGetTypeID(number) == CFBooleanGetTypeID() { return .boolean(number.boolValue) }
        if CFNumberIsFloatType(number) { return .real(number.doubleValue) }
        return .integer(number.int64Value)
    }
}

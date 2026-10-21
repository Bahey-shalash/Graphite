import Foundation

/// Gives a stream PDFKit wrote without `/Length` its length, which a stream must have
/// (ISO 32000-1, 7.3.8.2). The stream's data runs from the line after `stream` to the line
/// break before `endstream`, which is not part of it; `/Length` is written first in its
/// dictionary, and every other byte of the object is copied as it is.
enum StreamLengthRepair {
    private static let endKeyword = Array("endstream".utf8)

    /// The streams' new bytes, by object number.
    static func find(in candidates: Set<Int>, objects: (Int) -> (generation: Int, range: Range<Int>)?, bytes: UnsafeRawBufferPointer) -> [Int: Data] {
        var replacements: [Int: Data] = [:]
        for number in candidates {
            guard let object = objects(number) else { continue }
            var scanner = PDFSyntaxScanner(bytes: bytes)
            scanner.position = object.range.lowerBound
            guard scanner.readUnsignedInteger() == number, scanner.readUnsignedInteger() == object.generation, scanner.readKeyword() == "obj" else { continue }
            let dictionaryStart = scanner.skipWhitespaceAndComments()
            guard case .dictionary(let dictionary)? = scanner.readValue(), dictionary.entries["Length"] == nil,
                  let dataStart = scanner.streamDataStart(before: object.range.upperBound),
                  let dataEnd = dataEnd(from: dataStart, before: object.range.upperBound, bytes: bytes),
                  dictionaryStart + 2 <= object.range.upperBound else { continue }
            var objectBytes = Data(UnsafeRawBufferPointer(rebasing: bytes[object.range.lowerBound..<(dictionaryStart + 2)]))
            objectBytes.append(Data(" /Length \(dataEnd - dataStart)".utf8))
            objectBytes.append(Data(UnsafeRawBufferPointer(rebasing: bytes[(dictionaryStart + 2)..<object.range.upperBound])))
            replacements[number] = objectBytes
        }
        return replacements
    }

    /// Where the stream's data ends: at the last `endstream` of the object, less the line
    /// break before it.
    private static func dataEnd(from dataStart: Int, before objectEnd: Int, bytes: UnsafeRawBufferPointer) -> Int? {
        var candidate = objectEnd - endKeyword.count
        while candidate >= dataStart {
            if (0..<endKeyword.count).allSatisfy({ offset in bytes[candidate + offset] == endKeyword[offset] }) {
                var end = candidate
                if end > dataStart, bytes[end - 1] == 0x0A { end -= 1 }
                if end > dataStart, bytes[end - 1] == 0x0D { end -= 1 }
                return end
            }
            candidate -= 1
        }
        return nil
    }
}

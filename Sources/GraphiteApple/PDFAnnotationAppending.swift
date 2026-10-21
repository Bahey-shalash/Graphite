import Foundation

/// Writes a PDF that PDFKit wrote together with annotation objects Graphite wrote itself (`PDFObjectSpool`): every
/// object of PDFKit's file byte for byte, except each page that gets annotations, whose `/Annots` array is written again
/// with their references; then the spooled objects, numbered after PDFKit's; then one cross-reference table for all.
///
/// A page's new annotations go before Graphite's text boxes and the links over their text, which stay the page's last
/// annotations (invariant M-15); everything else on the page stays before them in its order. Only the form PDFKit writes
/// is understood, as by `PDFObjectCompaction` (invariant PDF-04): one uncompressed cross-reference table without
/// `/Prev`, `/XRefStm` or `/Encrypt`. Anything else is refused, and the caller's write fails rather than lose ink.
///
/// Time and memory grow with the file's objects and the spooled bytes, never with their square: the source and the
/// spool are read memory-mapped and copied through a 1 MiB buffer.
enum PDFAnnotationAppending {
    enum AppendingError: Error, Equatable {
        /// The file is not in the form PDFKit writes, or a page or its annotations could not be read.
        case sourceNotUnderstood
        case pageMissing(pageIndex: Int)
    }

    /// - Parameters:
    ///   - annotationPlacesByPageIndex: For each page index, the spool places of the annotations it gets, in order.
    static func write(source: URL, spool: URL, spooledObjectCount: Int, annotationPlacesByPageIndex: [Int: [Int]], to destination: URL) throws {
        let sourceBytes = try Data(contentsOf: source, options: .alwaysMapped)
        let plan = try sourceBytes.withUnsafeBytes { buffer in
            try AppendingPlanner(bytes: buffer).plan(annotationPlacesByPageIndex: annotationPlacesByPageIndex, spooledObjectCount: spooledObjectCount)
        }
        FileManager.default.createFile(atPath: destination.path, contents: nil)
        let handle = try FileHandle(forWritingTo: destination)
        defer { try? handle.close() }
        var output = BufferedOutput(handle: handle)
        try plan.write(sourceBytes: sourceBytes, spool: spool, into: &output)
        try output.flush()
    }
}

/// Collects small writes into 1 MiB ones and counts the bytes written, for the cross-reference offsets.
struct BufferedOutput {
    private static let bufferByteCount = 1_048_576
    let handle: FileHandle
    private var buffer = Data()
    private(set) var writtenByteCount = 0

    init(handle: FileHandle) { self.handle = handle }

    mutating func write(_ bytes: Data) throws {
        writtenByteCount += bytes.count
        if buffer.count + bytes.count > Self.bufferByteCount { try flush() }
        if bytes.count >= Self.bufferByteCount { try handle.write(contentsOf: bytes) } else { buffer.append(bytes) }
    }

    mutating func flush() throws {
        guard !buffer.isEmpty else { return }
        try handle.write(contentsOf: buffer)
        buffer.removeAll(keepingCapacity: true)
    }
}

/// What the written file holds, found by reading the source's cross-reference table, its page tree and the pages that
/// get annotations.
private struct AppendingPlan {
    struct SourceObject {
        let number: Int
        let generation: Int
        let range: Range<Int>
        /// New bytes for the object, from its header to `endobj`: a page or an `/Annots` array written again.
        let replacement: Data?
    }

    let headerRange: Range<Int>
    let objects: [SourceObject]
    let crossReferenceSize: Int
    let freeGenerations: [Int: Int]
    /// The trailer dictionary with its `/Size` written again.
    let trailer: Data

    func write(sourceBytes: Data, spool: URL, into output: inout BufferedOutput) throws {
        func sourceSlice(_ range: Range<Int>) -> Data { sourceBytes[(sourceBytes.startIndex + range.lowerBound)..<(sourceBytes.startIndex + range.upperBound)] }
        try output.write(sourceSlice(headerRange))
        var offsets: [Int: (offset: Int, generation: Int)] = [:]
        offsets.reserveCapacity(objects.count)
        for object in objects {
            offsets[object.number] = (output.writtenByteCount, object.generation)
            try output.write(object.replacement ?? sourceSlice(object.range))
        }
        let firstSpooledNumber = crossReferenceSize
        var spooledOffsets: [Int] = []
        try PDFObjectSpool.forEachObject(in: spool) { place, parts in
            spooledOffsets.append(output.writtenByteCount)
            try output.write(Data("\(firstSpooledNumber + place) 0 obj\n".utf8))
            for part in parts {
                switch part {
                case .bytes(let bytes): try output.write(bytes)
                case .reference(let referencedPlace): try output.write(Data("\(firstSpooledNumber + referencedPlace) 0 R".utf8))
                }
            }
            try output.write(Data("\nendobj\n".utf8))
        }
        let crossReferenceOffset = output.writtenByteCount
        try output.write(crossReferenceTable(sourceOffsets: offsets, spooledOffsets: spooledOffsets))
        try output.write(Data("trailer\n".utf8) + trailer + Data("\nstartxref\n\(crossReferenceOffset)\n%%EOF\n".utf8))
    }

    /// Free numbers keep their generation and form the free list through entry 0, as the standard asks.
    private func crossReferenceTable(sourceOffsets: [Int: (offset: Int, generation: Int)], spooledOffsets: [Int]) -> Data {
        let totalSize = crossReferenceSize + spooledOffsets.count
        var table = "xref\n0 \(totalSize)\n"
        table.reserveCapacity(table.utf8.count + totalSize * 20)
        let freeNumbers = (0..<crossReferenceSize).filter { number in sourceOffsets[number] == nil }
        var nextFreeNumber: [Int: Int] = [:]
        for (position, number) in freeNumbers.enumerated() { nextFreeNumber[number] = position + 1 < freeNumbers.count ? freeNumbers[position + 1] : 0 }
        for number in 0..<crossReferenceSize {
            if let entry = sourceOffsets[number] {
                table += Self.entry(entry.offset, entry.generation, kind: "n")
            } else {
                table += Self.entry(nextFreeNumber[number] ?? 0, number == 0 ? 65_535 : freeGenerations[number] ?? 0, kind: "f")
            }
        }
        for offset in spooledOffsets { table += Self.entry(offset, 0, kind: "n") }
        return Data(table.utf8)
    }

    private static func entry(_ offset: Int, _ generation: Int, kind: Character) -> String {
        let offsetText = String(offset), generationText = String(generation)
        return String(repeating: "0", count: max(0, 10 - offsetText.count)) + offsetText + " "
            + String(repeating: "0", count: max(0, 5 - generationText.count)) + generationText + " \(kind)\r\n"
    }
}

/// Reads the source as `PDFObjectCompaction` reads it and plans the pages' new `/Annots`.
private struct AppendingPlanner {
    private typealias Failure = PDFAnnotationAppending.AppendingError
    private static let maximumObjectCount = 10_000_000
    private static let trailerSearchDistance = 4_096
    private static let maximumPageTreeDepth = 64
    /// The keys that mark Graphite's text boxes and the links over their text.
    private static let textBoxKeys = [PDFPageManager.textBoxRecordKey.rawValue, PDFPageManager.textBoxLinkOwnerKey.rawValue]

    let bytes: UnsafeRawBufferPointer

    func plan(annotationPlacesByPageIndex: [Int: [Int]], spooledObjectCount: Int) throws -> AppendingPlan {
        let table = try crossReferenceTable()
        let pageNumbers = try pageObjectNumbers(root: table.trailer.entries["Root"], entries: table.entries)
        var replacements: [Int: Data] = [:]
        for (pageIndex, places) in annotationPlacesByPageIndex where !places.isEmpty {
            guard pageNumbers.indices.contains(pageIndex) else { throw Failure.pageMissing(pageIndex: pageIndex) }
            let references = places.map { place in "\(table.size + place) 0 R" }
            let replacement = try annotsReplacement(pageNumber: pageNumbers[pageIndex], newReferences: references, entries: table.entries)
            replacements[replacement.number] = replacement.bytes
        }
        let ordered = table.entries.filter { _, entry in entry.inUse }.sorted { first, second in first.value.offset < second.value.offset }
        guard let firstOffset = ordered.first?.value.offset else { throw Failure.sourceNotUnderstood }
        var objects: [AppendingPlan.SourceObject] = []
        objects.reserveCapacity(ordered.count)
        for (position, element) in ordered.enumerated() {
            let end = position + 1 < ordered.count ? ordered[position + 1].value.offset : table.offset
            guard end > element.value.offset else { throw Failure.sourceNotUnderstood }
            objects.append(AppendingPlan.SourceObject(number: element.key, generation: element.value.generation, range: element.value.offset..<end,
                                                      replacement: replacements[element.key]))
        }
        var freeGenerations: [Int: Int] = [:]
        for (number, entry) in table.entries where !entry.inUse { freeGenerations[number] = entry.generation }
        return AppendingPlan(headerRange: 0..<firstOffset, objects: objects, crossReferenceSize: table.size, freeGenerations: freeGenerations,
                             trailer: try trailer(table, newSize: table.size + spooledObjectCount))
    }

    // MARK: Cross-reference table

    private struct Entry { let offset: Int; let generation: Int; let inUse: Bool }

    private struct Table {
        let offset: Int
        let entries: [Int: Entry]
        let trailer: PDFSyntaxDictionary
        let trailerRange: Range<Int>
        let size: Int
    }

    private func crossReferenceTable() throws -> Table {
        var scanner = PDFSyntaxScanner(bytes: bytes)
        guard let offset = crossReferenceOffset(), offset < bytes.count else { throw Failure.sourceNotUnderstood }
        scanner.position = offset
        guard scanner.readKeyword() == "xref" else { throw Failure.sourceNotUnderstood }
        var entries: [Int: Entry] = [:]
        while true {
            let keywordStart = scanner.position
            if scanner.readKeyword() == "trailer" { break }
            scanner.position = keywordStart
            guard let firstNumber = scanner.readUnsignedInteger(), let count = scanner.readUnsignedInteger(),
                  entries.count + count <= Self.maximumObjectCount else { throw Failure.sourceNotUnderstood }
            for entryIndex in 0..<count {
                guard let entryOffset = scanner.readUnsignedInteger(), let generation = scanner.readUnsignedInteger() else { throw Failure.sourceNotUnderstood }
                let kind = scanner.readKeyword()
                guard kind == "n" || kind == "f" else { throw Failure.sourceNotUnderstood }
                entries[firstNumber + entryIndex] = Entry(offset: entryOffset, generation: generation, inUse: kind == "n")
            }
        }
        let trailerStart = scanner.skipWhitespaceAndComments()
        guard case .dictionary(let trailer)? = scanner.readValue(), trailer.entries["Prev"] == nil, trailer.entries["XRefStm"] == nil,
              trailer.entries["Encrypt"] == nil, case .integer(let size)? = trailer.entries["Size"], size > 0, size <= Self.maximumObjectCount,
              entries.keys.allSatisfy({ number in number < size }),
              entries.values.allSatisfy({ entry in !entry.inUse || entry.offset < offset }) else { throw Failure.sourceNotUnderstood }
        return Table(offset: offset, entries: entries, trailer: trailer, trailerRange: trailerStart..<scanner.position, size: size)
    }

    private func crossReferenceOffset() -> Int? {
        let keyword = Array("startxref".utf8)
        let searchStart = max(0, bytes.count - Self.trailerSearchDistance)
        var candidate = bytes.count - keyword.count
        while candidate >= searchStart {
            if (0..<keyword.count).allSatisfy({ index in bytes[candidate + index] == keyword[index] }) {
                var scanner = PDFSyntaxScanner(bytes: bytes)
                scanner.position = candidate + keyword.count
                return scanner.readUnsignedInteger()
            }
            candidate -= 1
        }
        return nil
    }

    private func trailer(_ table: Table, newSize: Int) throws -> Data {
        guard let sizeRange = table.trailer.sourceRanges["Size"] else { throw Failure.sourceNotUnderstood }
        return slice(table.trailerRange.lowerBound..<sizeRange.lowerBound) + Data(String(newSize).utf8) + slice(sizeRange.upperBound..<table.trailerRange.upperBound)
    }

    // MARK: Objects and pages

    /// The object's value and where it starts and ends in the file.
    private func object(_ number: Int, entries: [Int: Entry]) throws -> (value: PDFSyntaxValue, start: Int, valueRange: Range<Int>, generation: Int) {
        guard let entry = entries[number], entry.inUse else { throw Failure.sourceNotUnderstood }
        var scanner = PDFSyntaxScanner(bytes: bytes)
        scanner.position = entry.offset
        guard scanner.readUnsignedInteger() == number, scanner.readUnsignedInteger() == entry.generation, scanner.readKeyword() == "obj" else {
            throw Failure.sourceNotUnderstood
        }
        let valueStart = scanner.skipWhitespaceAndComments()
        guard let value = scanner.readValue() else { throw Failure.sourceNotUnderstood }
        return (value, entry.offset, valueStart..<scanner.position, entry.generation)
    }

    private func dictionary(_ value: PDFSyntaxValue?, entries: [Int: Entry]) throws -> PDFSyntaxDictionary? {
        switch value {
        case .dictionary(let dictionary)?: return dictionary
        case .reference(let number)?: return try dictionary(object(number, entries: entries).value, entries: entries)
        default: return nil
        }
    }

    /// The page objects in page order, from the catalog's page tree.
    private func pageObjectNumbers(root: PDFSyntaxValue?, entries: [Int: Entry]) throws -> [Int] {
        guard let catalog = try dictionary(root, entries: entries), case .reference(let pagesNumber)? = catalog.entries["Pages"] else {
            throw Failure.sourceNotUnderstood
        }
        var pages: [Int] = []
        var pending: [(number: Int, depth: Int)] = [(pagesNumber, 0)]
        var visited: Set<Int> = []
        while let (number, depth) = pending.popLast() {
            guard depth <= Self.maximumPageTreeDepth, visited.insert(number).inserted,
                  let node = try dictionary(.reference(number), entries: entries) else { throw Failure.sourceNotUnderstood }
            if case .array(let kids)? = node.entries["Kids"] {
                for kid in kids.reversed() {
                    guard case .reference(let kidNumber) = kid else { throw Failure.sourceNotUnderstood }
                    pending.append((kidNumber, depth + 1))
                }
            } else {
                pages.append(number)
            }
        }
        return pages
    }

    /// The page, or the array object its `/Annots` refers to, written again with the new references before the page's
    /// first Graphite text box or text-box link.
    private func annotsReplacement(pageNumber: Int, newReferences: [String], entries: [Int: Entry]) throws -> (number: Int, bytes: Data) {
        let page = try object(pageNumber, entries: entries)
        guard case .dictionary(let pageDictionary) = page.value else { throw Failure.sourceNotUnderstood }
        switch pageDictionary.entries["Annots"] {
        case .reference(let arrayNumber)?:
            let array = try object(arrayNumber, entries: entries)
            guard case .array(let existing) = array.value else { throw Failure.sourceNotUnderstood }
            let text = try annotsText(existing, newReferences: newReferences, entries: entries)
            return (arrayNumber, header(arrayNumber, array.generation) + Data(text.utf8) + Data("\nendobj\n".utf8))
        case .array(let existing)?:
            guard let range = pageDictionary.sourceRanges["Annots"] else { throw Failure.sourceNotUnderstood }
            let text = try annotsText(existing, newReferences: newReferences, entries: entries)
            return (pageNumber, header(pageNumber, page.generation) + slice(page.valueRange.lowerBound..<range.lowerBound) + Data(text.utf8)
                        + slice(range.upperBound..<page.valueRange.upperBound) + Data("\nendobj\n".utf8))
        case nil:
            // A page without annotations: the array goes just before the dictionary's closing `>>`.
            let closing = page.valueRange.upperBound - 2
            return (pageNumber, header(pageNumber, page.generation) + slice(page.valueRange.lowerBound..<closing)
                        + Data((" /Annots " + (try annotsText([], newReferences: newReferences, entries: entries)) + " ").utf8)
                        + slice(closing..<page.valueRange.upperBound) + Data("\nendobj\n".utf8))
        default:
            throw Failure.sourceNotUnderstood
        }
    }

    private func annotsText(_ existing: [PDFSyntaxValue], newReferences: [String], entries: [Int: Entry]) throws -> String {
        var existingTexts: [String] = []
        var insertionIndex = existing.count
        for (index, element) in existing.enumerated() {
            guard case .reference(let number) = element else { throw Failure.sourceNotUnderstood }
            existingTexts.append("\(number) \(entries[number]?.generation ?? 0) R")
            if insertionIndex == existing.count, let annotation = try? dictionary(element, entries: entries),
               Self.textBoxKeys.contains(where: { key in annotation.entries[key] != nil }) {
                insertionIndex = index
            }
        }
        let all = existingTexts[..<insertionIndex] + newReferences + existingTexts[insertionIndex...]
        return "[ " + all.joined(separator: " ") + " ]"
    }

    private func header(_ number: Int, _ generation: Int) -> Data { Data("\(number) \(generation) obj\n".utf8) }

    private func slice(_ range: Range<Int>) -> Data { Data(UnsafeRawBufferPointer(rebasing: bytes[range])) }
}

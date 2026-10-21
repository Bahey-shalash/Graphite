import Foundation
import Markdown

public struct ReadAloudSection: Equatable, Sendable, Identifiable {
    public let title: String
    public let level: Int
    public let range: NSRange
    public var id: Int { range.location }

    /// Top-level Markdown headings, including Setext headings. A section includes
    /// its subheadings and ends before the next heading at its level or higher.
    public static func sections(in source: String) throws -> [ReadAloudSection] {
        let original = source as NSString
        guard original.length <= ReadAloudDocument.maximumSourceUTF16Count else { throw ReadAloudError.passageTooLarge }
        guard !MarkdownNesting.exceedsSafeDepth(source) else { throw ReadAloudError.excessiveNesting }
        let prepared = NSMutableString(string: source)
        let hiddenRanges = [NSRange(location: 0, length: FrontmatterLocator.length(in: original))]
            + ObsidianInlineMarkup.commentRanges(in: source)
        for range in hiddenRanges where range.length > 0 {
            var units = Array(repeating: UInt16(0x2060), count: range.length)
            for index in units.indices {
                let character = original.character(at: range.location + index)
                if character == 10 || character == 13 { units[index] = character }
            }
            prepared.replaceCharacters(in: range, with: String(decoding: units, as: UTF16.self))
        }
        let parsedSource = prepared as String
        guard let document = BoundedMarkdownParser.document(parsing: parsedSource) else { throw ReadAloudError.excessiveNesting }
        var converter = MarkdownSourceLocationConverter(parsedSource)
        var headings: [(title: String, level: Int, location: Int)] = []
        for node in document.children {
            try Task.checkCancellation()
            guard let heading = node as? Heading, let range = heading.range else { continue }
            guard headings.count < 4_096 else { throw ReadAloudError.passageTooLarge }
            let location = converter.utf16Range(of: range, role: nil, containerIndex: nil).location
            guard location >= 0, location < original.length else { throw ReadAloudError.sourceMappingUnavailable }
            headings.append((heading.plainText, heading.level, location))
        }
        var sectionEnds = Array(repeating: original.length, count: headings.count)
        var pendingHeadingIndexes: [Int] = []
        // Resolve all section endpoints in one pass, including nested sections.
        for headingIndex in headings.indices {
            while let previousIndex = pendingHeadingIndexes.last, headings[previousIndex].level >= headings[headingIndex].level {
                sectionEnds[previousIndex] = headings[headingIndex].location
                pendingHeadingIndexes.removeLast()
            }
            pendingHeadingIndexes.append(headingIndex)
        }
        return headings.enumerated().map { headingIndex, heading in
            ReadAloudSection(title: heading.title, level: heading.level,
                range: NSRange(location: heading.location, length: sectionEnds[headingIndex] - heading.location))
        }
    }
}

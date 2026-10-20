import Foundation

/// The typed text of `richText.attributedString` (`stringKey` and `subRangesKey`), whose runs count UTF-16 units.
extension NotabilitySessionReading {
    private static let colorComponentCount = 4

    mutating func readTypedText(in richText: KeyedArchiveFields) throws(NotabilityReadingError) -> NotabilityTypedText {
        let attributedString = try requiredFields(NotabilityRichTextKey.attributedString, in: richText)
        let text = try optionalString(NotabilityAttributedStringKey.text, in: attributedString) ?? ""
        let textUTF16Length = text.utf16.count
        var runs: [NotabilityTextRun] = []
        for (runIndex, runReference) in try optionalMembers(NotabilityAttributedStringKey.runs, in: attributedString).enumerated() {
            do throws(NotabilityReadingError) {
                let run = try NotabilityReadingError.readingSession { () throws(KeyedArchiveError) in
                    try archive.fields(of: archive.value(of: runReference))
                }
                runs.append(try readTextRun(run, runIndex: runIndex, textUTF16Length: textUTF16Length))
            } catch {
                issues.report(.textRunSkipped(runIndex: runIndex, error))
            }
        }
        return NotabilityTypedText(text: text, runs: runs)
    }

    private mutating func readTextRun(_ run: KeyedArchiveFields, runIndex: Int, textUTF16Length: Int) throws(NotabilityReadingError) -> NotabilityTextRun {
        let range = try textRunRange(run, runIndex: runIndex)
        guard range.location >= 0, range.length >= 0, range.location <= textUTF16Length - range.length else {
            throw .textRunOutsideText(runIndex: runIndex, utf16Location: range.location, utf16Length: range.length, textUTF16Length: textUTF16Length)
        }
        let otherAttributes = try optionalFields(NotabilityTextRunKey.otherAttributes, in: run) ?? KeyedArchiveFields()
        issues.reportUnknownKeys(otherAttributes.keys, in: .textAttributes, known: NotabilityKnownKeys.textAttributes)
        let font = try optionalFields(NotabilityTextRunKey.font, in: run) ?? KeyedArchiveFields()
        let underline = try NotabilityReadingError.readingSession { () throws(KeyedArchiveError) in
            try archive.value(named: NotabilityTextAttributeKey.underline.rawValue, in: otherAttributes)
        }
        let strikeThrough = try NotabilityReadingError.readingSession { () throws(KeyedArchiveError) in
            try archive.value(named: NotabilityTextAttributeKey.strikethrough.rawValue, in: otherAttributes)
        }
        return NotabilityTextRun(
            utf16Location: range.location, utf16Length: range.length, fontName: try optionalString(NotabilityTextFontKey.name, in: font),
            fontSize: try optionalNumber(NotabilityTextFontKey.size, in: font), color: try textRunColor(run, runIndex: runIndex),
            isUnderlined: isTruthy(underline), isStruckThrough: isTruthy(strikeThrough),
            lineSpacing: try optionalNumber(NotabilityTextAttributeKey.lineSpacing, in: otherAttributes),
            baselineOffset: try optionalNumber(NotabilityTextAttributeKey.baselineOffset, in: otherAttributes))
    }

    /// `subRangeRangeKey`, `{location, length}`: exactly two numbers, truncated to whole numbers as the reference
    /// reader truncates them.
    private func textRunRange(_ run: KeyedArchiveFields, runIndex: Int) throws(NotabilityReadingError) -> (location: Int, length: Int) {
        let numbers = NotabilityGeometryString.numbers(in: try optionalString(NotabilityTextRunKey.range, in: run) ?? "")
        guard numbers.count == 2, let location = Int(exactly: numbers[0].rounded(.towardZero)),
              let length = Int(exactly: numbers[1].rounded(.towardZero)) else { throw .textRunRangeNotReadable(runIndex: runIndex) }
        return (location, length)
    }

    /// `subRangeColorCrossPlatformKey`, `"r,g,b,a"` from 0 to 1; nil when absent or empty, and reported when it is
    /// not four numbers.
    private mutating func textRunColor(_ run: KeyedArchiveFields, runIndex: Int) throws(NotabilityReadingError) -> NotebookImportColor? {
        guard let colorText = try optionalString(NotabilityTextRunKey.color, in: run), !colorText.isEmpty else { return nil }
        let components = colorText.split(separator: ",", omittingEmptySubsequences: false).compactMap { component in
            Double(component.trimmingCharacters(in: .whitespaces))
        }
        guard components.count == Self.colorComponentCount, colorText.split(separator: ",", omittingEmptySubsequences: false).count == components.count else {
            issues.report(.textRunColorNotReadable(runIndex: runIndex))
            return nil
        }
        return NotebookImportColor(red: components[0], green: components[1], blue: components[2], alpha: components[3])
    }
}

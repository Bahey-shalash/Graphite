import Foundation

/// Inline Obsidian syntax that Markdown renderers do not know, rewritten for the reading
/// view and Live Preview's rendered blocks: the pipeline that runs `ReadingMarkers`,
/// `ObsidianComments`, `ReadingInlineMarking` and `ReadingMathPreparation` in order.
package enum ObsidianInlineMarkup {
    /// Rewrites color sections, highlights, tasks, math, and comments for display.
    /// - Parameter taskLocation: Where the task on a line of `markdown`, given by its index,
    ///   is in the note, when a tap on its checkbox can change the note there; nil draws
    ///   every checkbox as a picture.
    package static func preparedForReading(_ markdown: String, colorsEnabled: Bool, paletteHexByName: [String: String],
                                          taskLocation: ((_ lineIndex: Int, _ status: Unicode.Scalar) -> ReadingTasks.Location?)? = nil) -> String {
        // The note's own marker characters are escaped first, so they are not read as
        // markers; `ObsidianMarkdownParser` restores them.
        var text = ReadingInlineMarking.removingBlockIdentifiers(from: ObsidianComments.removingComments(from: ReadingMarkers.escaping(markdown)))
        text = ReadingMathPreparation.displayMathInTableCellsMadeInline(text)
        // A comment removed here can join two lines; the lines that follow no longer have
        // the indices `taskLocation` knows them by, so no task is given a place.
        let keepsLines = taskLocation != nil && lineCount(of: text) == lineCount(of: markdown)
        let protected = ReadingMathPreparation.protectingMathKeepingLineIndices(in: text)
        text = protected.text
        if colorsEnabled { text = ReadingInlineMarking.markingColors(in: text, paletteHexByName: paletteHexByName) }
        return ReadingInlineMarking.markingTasks(in: ReadingInlineMarking.markingHighlights(in: text),
                                                 lineIndices: keepsLines ? protected.lineIndices : nil, taskLocation: taskLocation)
    }

    private static func lineCount(of text: String) -> Int {
        text.utf8.reduce(1) { count, byte in byte == UInt8(ascii: "\n") ? count + 1 : count }
    }
}

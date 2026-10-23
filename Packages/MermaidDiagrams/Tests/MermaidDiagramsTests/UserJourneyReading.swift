@testable import MermaidDiagrams

/// Reads a user journey for a test, from its whole text.
enum UserJourneyReading {
    /// The example of Mermaid's user journey documentation.
    static let workingDay = """
    journey
      title My working day
      section Go to work
        Make tea: 5: Me
        Go upstairs: 3: Me
        Do work: 1: Me, Cat
      section Go home
        Go downstairs: 5: Me
        Sit down: 5: Me
    """

    static func userJourney(_ source: String, limits: MermaidDiagramLimits = .standard) throws(MermaidDiagramReadError) -> UserJourneyDiagram {
        try UserJourneyParser.parse(cursorAfterKeyword(source), limits: limits)
    }

    /// The error reading `source` throws, or nil when it reads.
    static func readError(_ source: String, limits: MermaidDiagramLimits = .standard) -> MermaidDiagramReadError? {
        do {
            _ = try userJourney(source, limits: limits)
            return nil
        } catch {
            return error
        }
    }

    /// The user journey of `source` laid out with text of fixed widths: cards 7 points a character at 14 points
    /// (21-point lines), the scale's numbers 6 at 12, the title 8 at 16.
    static func uniformLayout(_ source: String) throws -> UserJourneyLayout {
        UserJourneyLayoutEngine.layout(try userJourney(source), taskText: UniformWidthTextMeasurer(characterWidth: 7, fontSize: 14, lineHeight: 21),
                                       scaleText: UniformWidthTextMeasurer(characterWidth: 6, fontSize: 12, lineHeight: 18),
                                       titleText: UniformWidthTextMeasurer(), font: DiagramFont(postScriptName: nil, size: 16))
    }

    /// A cursor just past the `journey` keyword that every test text starts with.
    private static func cursorAfterKeyword(_ source: String) -> MermaidTextCursor {
        var cursor = MermaidTextCursor(bytes: Array(source.utf8))
        cursor.skipWhitespace()
        precondition(cursor.readWord() == "journey", "A user journey's text starts with its keyword")
        return cursor
    }
}

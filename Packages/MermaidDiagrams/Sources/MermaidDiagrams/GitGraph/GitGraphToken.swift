/// A piece of a Git graph's statements, as the lexer of Mermaid's Git graph grammar reads it. Keywords and names are
/// compared exactly, case included.
enum GitGraphToken: Equatable {
    /// `gitGraph` again, followed by a space, a comment or the end, which no statement takes.
    case diagramKeyword
    /// `gitGraph:` written as one word, which no statement takes either.
    case diagramKeywordWithColon
    case statement(GitGraphStatementKeyword)
    case attribute(GitGraphAttribute)
    case commitType(GitGraphCommitType)
    /// `LR`, `TB` or `BT`, a direction after the keyword.
    case direction(GitGraphDirection)
    case colon
    /// `title` and the rest of its line up to a comment, without the spaces around it and with runs of spaces made one.
    case title(String)
    case accessibility(MermaidAccessibilityStatement)
    /// A whole number: `0`, or digits from 1 to 9 then any digits, not followed by a `.`.
    case integer(Int)
    /// Text in quotation marks or apostrophes, without them and with its escapes read (`\"`, `\n`).
    case quotedText(String)
    /// A letter, a digit or `_`, then letters, digits, `_`, `-`, `.` and `/`, ending with no `.` or `/`: a branch's
    /// name such as `feature/x_y-z` or `1.0.1`.
    case name(String)
    case lineBreak
    case endOfText
}

/// The words that start a statement.
enum GitGraphStatementKeyword: Equatable {
    case commit
    case branch
    case merge
    /// `checkout` or `switch`.
    case checkout
    /// `cherry-pick`.
    case cherryPick
}

/// The words, each with its colon, that give a statement's values.
enum GitGraphAttribute: Equatable {
    /// `id:`.
    case identifier
    /// `msg:`.
    case message
    /// `tag:`.
    case tag
    /// `type:`.
    case type
    /// `parent:`.
    case parent
    /// `order:`.
    case order
}

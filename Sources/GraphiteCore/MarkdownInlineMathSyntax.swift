import Foundation

/// Inline math, `$…$` within one line, as Obsidian reads it. The editor's styling, the
/// reading view's math protection and text colors all find formulas here; the reading view
/// writes this pattern into its one pass for `$$…$$` and `$…$`
/// (`ReadingMathPreparationPattern.mathSpanPattern`), and `InlineMathRuleTests` holds the two
/// to the same text.
///
/// The opening `$` is not preceded by `\` or `$` and not followed by whitespace or `$`; the
/// closing `$` is not preceded by whitespace and not followed by a digit, so "$5 and $10"
/// are prices, nor by `$`, which would start display math. Between them a backslash escapes
/// the next character, so `$a\$b$` is one formula holding a dollar sign, as MathJax reads
/// `\$`, and `\$` never closes one.
///
/// This keeps the editor's rule. The reading view and text colors allowed no `$` inside a
/// formula and no backslash before the closing `$`, so `$a\$b$` was a formula for the
/// editor and text for them, and `$a\\$` (a formula ending in an escaped backslash) was
/// text for them. The editor's rule is the one Obsidian and MathJax follow for escapes.
enum MarkdownInlineMathSyntax {
    /// A formula: its range, both `$` included, and the range of its LaTeX between them.
    struct Formula: Equatable {
        let range: NSRange
        let latexRange: NSRange
    }

    private static let pattern = MarkdownInlineMathPattern.formula.compiled()

    /// The formulas in `range` of `text`, left to right. A formula never crosses a line break.
    static func formulas(in text: String, range: NSRange) -> [Formula] {
        pattern.matches(in: text, range: range).map { match in Formula(range: match.range, latexRange: match.range(at: 1)) }
    }
}

/// The constant pattern of `MarkdownInlineMathSyntax`; `StaticPatternTests` compiles every case.
/// A formula's LaTeX cannot hold an unescaped `$`, so it always ends at the first one, and
/// the possessive quantifiers say so: the pattern never backtracks into the LaTeX, which
/// keeps it as fast as the simpler patterns it replaced.
enum MarkdownInlineMathPattern: String, StaticPatternSet {
    case formula = #"(?<![\\$])\$(?![\s$])((?:[^$\r\n\\]++|\\.)++)(?<!\s)\$(?![$\d])"#
}

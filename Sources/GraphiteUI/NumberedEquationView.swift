import SwiftUI
import Textual
import GraphiteCore

/// A display formula with its equation numbers, laid out as Obsidian's MathJax lays them
/// out: the formula centered in the text column, where it is without numbers, and each
/// number at the right edge of the column, on the baseline of its row.
///
/// Where the column is too narrow for the formula and its numbers side by side, nothing
/// is cut off: a formula of rows is drawn row by row, and a number that still does not
/// fit beside its formula goes on a line of its own below it, as LaTeX places one.
struct NumberedEquationView: View {
    let equation: NumberedEquation
    let textSize: Double

    /// The size block math has in `StructuredText`, which this view stands in for.
    private var mathFontSize: CGFloat { CGFloat(textSize) * MathProperties().fontScale }

    /// Whether the typesetter can draw the formula. One it cannot draw is shown as its
    /// source, as a formula without numbers is.
    static func canDraw(_ equation: NumberedEquation, textSize: Double) -> Bool {
        DisplayMathRendering.metrics(for: equation.latex, fontSize: CGFloat(textSize) * MathProperties().fontScale) != nil
    }

    var body: some View {
        Group {
            if equation.rows.isEmpty {
                numberedFormula(equation.latex, number: equation.tags.first)
            } else if let numberBaselines = numberBaselines {
                ViewThatFits(in: .horizontal) {
                    NumberedRowsLayout(numberBaselines: numberBaselines, minimumNumberSpacing: minimumNumberSpacing) {
                        TypesetMath(latex: equation.latex, fallbackText: equation.latex, fontSize: mathFontSize)
                        ForEach(equation.tags.indices, id: \.self) { tagIndex in numberView(equation.tags[tagIndex]) }
                    }
                    rowByRow
                }
            } else {
                rowByRow
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel((["Equation"] + equation.tags.map(\.text)).joined(separator: " "))
    }

    /// MathJax's least space between a formula and its number, `minlabelspacing`.
    private var minimumNumberSpacing: CGFloat { mathFontSize * 0.8 }

    /// The rows one below the other, each with its own number, for a column too narrow
    /// for the whole formula beside its numbers. The rows are no longer aligned with each
    /// other, which a row broken into lines could not be either.
    private var rowByRow: some View {
        VStack(spacing: mathFontSize * 0.5) {
            ForEach(equation.rows.indices, id: \.self) { rowIndex in
                let number = equation.tags.first { tag in tag.rowIndex == rowIndex }
                if !equation.rows[rowIndex].latex.trimmingCharacters(in: .whitespaces).isEmpty || number != nil {
                    numberedFormula(equation.rows[rowIndex].latex, number: number)
                }
            }
        }
    }

    private func numberedFormula(_ latex: String, number: NumberedEquation.Tag?) -> some View {
        let textFont = PlatformFont.systemFont(ofSize: CGFloat(textSize))
        return NumberedFormulaLayout(minimumNumberSpacing: minimumNumberSpacing, numberLineSpacing: mathFontSize * 0.3,
                                     minimumAscent: textFont.ascender, minimumDescent: -textFont.descender) {
            TypesetMath(latex: latex, fallbackText: latex, fontSize: mathFontSize)
            if let number { numberView(number) }
        }
    }

    private func numberView(_ tag: NumberedEquation.Tag) -> some View {
        TypesetMath(latex: tag.latex, fallbackText: tag.text, fontSize: mathFontSize)
    }

    /// For each number, how far below the top of the formula the baseline of its row is;
    /// nil when the typesetter cannot measure a row. The first row's baseline is its
    /// height below the top. A later row's is found from the rows down to it, stacked as
    /// the formula stacks them: they are as tall as the formula is down to that row's
    /// depth.
    private var numberBaselines: [CGFloat]? {
        var baselines: [CGFloat] = []
        for tag in equation.tags {
            guard let rowIndex = tag.rowIndex, equation.rows.indices.contains(rowIndex),
                  let row = DisplayMathRendering.metrics(for: equation.rows[rowIndex].latex, fontSize: mathFontSize) else { return nil }
            if rowIndex == 0 {
                baselines.append(row.ascent)
            } else {
                guard let stackedRows = DisplayMathRendering.metrics(for: equation.stackedRowsLatex(through: rowIndex), fontSize: mathFontSize) else { return nil }
                baselines.append(stackedRows.ascent + stackedRows.descent - row.descent)
            }
        }
        return baselines
    }
}

/// A formula or an equation number, typeset, with the baseline it is laid out by.
private struct TypesetMath: View {
    let latex: String
    /// Shown when the typesetter cannot draw `latex`, as for a number written with a
    /// command it does not know.
    let fallbackText: String
    let fontSize: CGFloat

    var body: some View {
        if let metrics = DisplayMathRendering.metrics(for: latex, fontSize: fontSize) {
            DisplayMathView(latex: latex, fontSize: fontSize)
                .alignmentGuide(.firstTextBaseline) { _ in metrics.ascent }
        } else {
            Text(fallbackText).font(.system(size: fontSize))
        }
    }
}

/// How far, in points, a formula may overhang the width it is given and still be drawn
/// on one line: measured widths are fractions of a point apart.
private let naturalWidthTolerance: CGFloat = 1

/// Lays out a formula and, when it has one, its number. Its subviews are the formula,
/// then the number.
private struct NumberedFormulaLayout: Layout {
    let minimumNumberSpacing: CGFloat
    /// The space above a number that goes below its formula.
    let numberLineSpacing: CGFloat
    /// The height and depth of a line of the note's text, which a short formula's line
    /// has too, as it does in `StructuredText`.
    let minimumAscent: CGFloat
    let minimumDescent: CGFloat

    private struct Arrangement {
        var size: CGSize
        var formulaOrigin: CGPoint
        /// The formula's natural size, or the column's width for one broken into lines.
        var formulaProposal: ProposedViewSize
        var numberOrigin: CGPoint?
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrangement(inWidth: proposal.width, subviews: subviews)?.size ?? .zero
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let arrangement = arrangement(inWidth: bounds.width, subviews: subviews) else { return }
        subviews[0].place(at: CGPoint(x: bounds.minX + arrangement.formulaOrigin.x, y: bounds.minY + arrangement.formulaOrigin.y), proposal: arrangement.formulaProposal)
        if let numberOrigin = arrangement.numberOrigin, subviews.count > 1 {
            subviews[1].place(at: CGPoint(x: bounds.minX + numberOrigin.x, y: bounds.minY + numberOrigin.y), proposal: .unspecified)
        }
    }

    private func arrangement(inWidth width: CGFloat?, subviews: Subviews) -> Arrangement? {
        guard let formula = subviews.first else { return nil }
        let formulaDimensions = formula.dimensions(in: .unspecified)
        let number = subviews.dropFirst().first
        let numberDimensions = number?.dimensions(in: .unspecified)
        let widthBesideNumber = formulaDimensions.width + (numberDimensions.map { dimensions in minimumNumberSpacing + dimensions.width } ?? 0)
        let columnWidth = width ?? widthBesideNumber
        if widthBesideNumber <= columnWidth + naturalWidthTolerance {
            let formulaAscent = formulaDimensions[.firstTextBaseline]
            let numberAscent = numberDimensions?[.firstTextBaseline] ?? 0
            let ascent = max(formulaAscent, numberAscent, minimumAscent)
            let descent = max(formulaDimensions.height - formulaAscent, (numberDimensions?.height ?? 0) - numberAscent, minimumDescent)
            // Centered in the column, and moved left only as far as the number needs.
            let widthLeftOfNumber = columnWidth - (numberDimensions.map { dimensions in minimumNumberSpacing + dimensions.width } ?? 0)
            let formulaOriginX = max(min((columnWidth - formulaDimensions.width) / 2, widthLeftOfNumber - formulaDimensions.width), 0)
            return Arrangement(size: CGSize(width: columnWidth, height: ascent + descent),
                               formulaOrigin: CGPoint(x: formulaOriginX, y: ascent - formulaAscent), formulaProposal: .unspecified,
                               numberOrigin: numberDimensions.map { dimensions in CGPoint(x: columnWidth - dimensions.width, y: ascent - numberAscent) })
        }
        // The formula takes the column, broken into lines when it is wider, as a formula
        // without a number is; the number goes below it, at the right.
        let fitsOnOneLine = formulaDimensions.width <= columnWidth + naturalWidthTolerance
        let formulaProposal: ProposedViewSize = fitsOnOneLine ? .unspecified : ProposedViewSize(width: columnWidth, height: nil)
        let formulaSize = formula.sizeThatFits(formulaProposal)
        let formulaOrigin = CGPoint(x: max((columnWidth - formulaSize.width) / 2, 0), y: 0)
        guard let numberDimensions else {
            return Arrangement(size: CGSize(width: columnWidth, height: formulaSize.height), formulaOrigin: formulaOrigin, formulaProposal: formulaProposal, numberOrigin: nil)
        }
        let numberOrigin = CGPoint(x: max(columnWidth - numberDimensions.width, 0), y: formulaSize.height + numberLineSpacing)
        return Arrangement(size: CGSize(width: columnWidth, height: numberOrigin.y + numberDimensions.height),
                           formulaOrigin: formulaOrigin, formulaProposal: formulaProposal, numberOrigin: numberOrigin)
    }
}

/// Lays out a formula of rows with a number beside some of its rows. Its subviews are
/// the formula, then the numbers. Its ideal width is the least the formula and its
/// numbers need side by side, so `ViewThatFits` can tell whether they fit the column.
private struct NumberedRowsLayout: Layout {
    /// For each number, how far below the top of the formula its row's baseline is.
    let numberBaselines: [CGFloat]
    let minimumNumberSpacing: CGFloat

    private struct Arrangement {
        var size: CGSize
        var formulaOrigin: CGPoint
        var numberOrigins: [CGPoint]
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrangement(inWidth: proposal.width, subviews: subviews)?.size ?? .zero
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let arrangement = arrangement(inWidth: bounds.width, subviews: subviews) else { return }
        subviews[0].place(at: CGPoint(x: bounds.minX + arrangement.formulaOrigin.x, y: bounds.minY + arrangement.formulaOrigin.y), proposal: .unspecified)
        for (number, origin) in zip(subviews.dropFirst(), arrangement.numberOrigins) {
            number.place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y), proposal: .unspecified)
        }
    }

    private func arrangement(inWidth width: CGFloat?, subviews: Subviews) -> Arrangement? {
        guard let formula = subviews.first else { return nil }
        let formulaSize = formula.sizeThatFits(.unspecified)
        let numbers = zip(subviews.dropFirst(), numberBaselines).map { number, rowBaseline in (dimensions: number.dimensions(in: .unspecified), rowBaseline: rowBaseline) }
        let numbersWidth = numbers.map(\.dimensions.width).max() ?? 0
        let widthBesideNumbers = formulaSize.width + minimumNumberSpacing + numbersWidth
        let columnWidth = max(width ?? widthBesideNumbers, widthBesideNumbers)
        // A number taller than the first row reaches above the formula, and one deeper
        // than the last row below it.
        let heightAboveFormula = numbers.map { number in number.dimensions[.firstTextBaseline] - number.rowBaseline }.max().map { height in max(height, 0) } ?? 0
        let depth = numbers.map { number in number.rowBaseline + number.dimensions.height - number.dimensions[.firstTextBaseline] }.max() ?? 0
        let formulaOriginX = max(min((columnWidth - formulaSize.width) / 2, columnWidth - numbersWidth - minimumNumberSpacing - formulaSize.width), 0)
        return Arrangement(size: CGSize(width: columnWidth, height: heightAboveFormula + max(formulaSize.height, depth)),
                           formulaOrigin: CGPoint(x: formulaOriginX, y: heightAboveFormula),
                           numberOrigins: numbers.map { number in
                               CGPoint(x: columnWidth - number.dimensions.width, y: heightAboveFormula + number.rowBaseline - number.dimensions[.firstTextBaseline])
                           })
    }
}

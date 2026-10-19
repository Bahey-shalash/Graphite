import Foundation
import GraphiteCore

/// The size of a new notebook's pages: one of the named sizes in an orientation, or a
/// width and height of the person's own.
public enum NotebookPageSizeChoice: Equatable, Sendable {
    case named(NotebookPageSize, PageOrientation)
    case custom(widthPoints: Double, heightPoints: Double)

    public var pointSize: CGSize {
        switch self {
        case .named(let size, let orientation): size.pointSize(in: orientation)
        case .custom(let widthPoints, let heightPoints): CGSize(width: widthPoints, height: heightPoints)
        }
    }
}

/// Everything the New Notebook sheet decides, and the paper it makes.
public struct NewNotebookOptions: Equatable, Sendable {
    /// 1 to 40 inches, in PDF points; what `PDFTemplateGenerator` accepts.
    public static let sideLengthRangePoints: ClosedRange<Double> = 72...2880
    public static let pageCountRange: ClosedRange<Int> = 1...1000

    public private(set) var paperChoice: NotebookPaperChoice
    /// Spacing, line color and strength, and paper color. Its template and size are
    /// replaced by `paperChoice` and `pageSize` in `paper`.
    public var paperStyle: PaperSpecification
    public var pageSize: NotebookPageSizeChoice
    public var pageCount: Int

    public init(paperChoice: NotebookPaperChoice, paperStyle: PaperSpecification, pageSize: NotebookPageSizeChoice, pageCount: Int = 1) {
        self.paperChoice = paperChoice
        self.paperStyle = paperStyle
        self.pageSize = pageSize
        self.pageCount = pageCount
        if let spacingPoints = paperChoice.spacingPoints { self.paperStyle.spacing = spacingPoints }
    }

    /// Chooses a paper; ruled narrow and wide also set their spacing.
    public mutating func choose(_ choice: NotebookPaperChoice) {
        paperChoice = choice
        if let spacingPoints = choice.spacingPoints { paperStyle.spacing = spacingPoints }
    }

    /// The paper of every page of the new notebook.
    public var paper: PaperSpecification {
        var paper = paperStyle.sized(pageSize.pointSize)
        paper.template = paperChoice.template
        return paper
    }

    /// The same options with another paper, for drawing that paper's picture beside the
    /// chosen one.
    public func choosing(_ choice: NotebookPaperChoice) -> NewNotebookOptions {
        var options = self
        options.choose(choice)
        return options
    }

    public var problem: NewNotebookProblem? {
        let size = pageSize.pointSize
        let sidesAreValid = [Double(size.width), Double(size.height)].allSatisfy { sideLength in
            sideLength.isFinite && Self.sideLengthRangePoints.contains(sideLength)
        }
        if !sidesAreValid { return .pageSizeOutOfRange }
        if !Self.pageCountRange.contains(pageCount) { return .pageCountOutOfRange }
        return nil
    }
}

/// Why a notebook cannot be made with the chosen options.
public enum NewNotebookProblem: Equatable, Sendable {
    case pageSizeOutOfRange
    case pageCountOutOfRange
}

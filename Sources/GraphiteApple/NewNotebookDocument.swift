import Foundation
import GraphiteCore

/// The PDF of a new notebook, as the New Notebook sheet's options ask for it: pages of the
/// chosen paper or of one of the person's own templates, with a cover first when it is asked for.
public enum NewNotebookDocument {
    /// - Parameters:
    ///   - title: The notebook's name, which the cover shows.
    ///   - templateLocation: Where the chosen template's PDF is; needed only when `options` choose one.
    public static func data(for options: NewNotebookOptions, titled title: String, templateLocation: URL?) throws -> Data {
        var notebookData: Data
        if options.myTemplateFileName != nil {
            guard let templateLocation else { throw MyPaperTemplateError.unreadableTemplate }
            notebookData = try MyPaperTemplateNotebook.documentData(templateAt: templateLocation, pageCount: options.pageCount)
        } else {
            notebookData = try PDFTemplateGenerator.documentData(paper: options.paper, pageCount: options.pageCount)
        }
        if let cover = options.cover {
            notebookData = try NotebookCoverPage.prepending(coverTitled: title, color: cover, to: notebookData)
        }
        return notebookData
    }
}

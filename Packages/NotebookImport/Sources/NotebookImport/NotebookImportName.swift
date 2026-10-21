import Foundation

/// The name of the file an imported notebook becomes.
public enum NotebookImportName {
    private static let pdfSuffix = ".pdf"

    /// The notebook's file name without its extension, and without the ".pdf" an app keeps in the name of a notebook made
    /// from a PDF ("Past exam.pdf.goodnotes" becomes "Past exam"), path separators, colons and control characters as
    /// hyphens, and without leading dots or surrounding spaces; `fallback` when nothing is left.
    public static func pdfStem(forNotebookFileName fileName: String, fallback: String) -> String {
        var stem = (fileName as NSString).deletingPathExtension
        // A name that is only an extension (".goodnotes") has no stem, though Foundation reads it as a hidden file's name.
        if let format = NotebookFileFormat.allCases.first(where: { format in fileName.lowercased().hasSuffix("." + format.fileExtension) }) {
            stem = String(fileName.dropLast(format.fileExtension.count + 1))
        }
        if stem.lowercased().hasSuffix(pdfSuffix) { stem = String(stem.dropLast(pdfSuffix.count)) }
        return ImportedRecording.fileName(from: stem, fallback: fallback)
    }
}

import Foundation

/// Reads the files a page plan names from the notebook it was planned from. A protocol because the Goodnotes and the
/// Notability readers both provide it and the import writer takes either.
public protocol ImportSourceFiles: Sendable {
    /// The file's bytes; throws the reader's own typed error when the file is missing or unreadable.
    func contents(of file: ImportedSourceFile) throws -> [UInt8]
}

extension GoodnotesNotebookReader: ImportSourceFiles {
    public func contents(of file: ImportedSourceFile) throws -> [UInt8] {
        try contents(ofFileAt: file.path)
    }
}

extension NotabilityNoteReader: ImportSourceFiles {
    public func contents(of file: ImportedSourceFile) throws -> [UInt8] {
        try fileBytes(file.path)
    }
}

import Foundation

/// Reads the files a page plan names from the notebook it was planned from. A protocol because the Goodnotes and the
/// Notability readers both provide it and the import writer takes either.
public protocol ImportSourceFiles: Sendable {
    /// The file's bytes, without a copy where the notebook stores the file uncompressed; throws the reader's own typed
    /// error when the file is missing or unreadable.
    func contents(of file: ImportedSourceFile) throws -> Data

    /// Hands the file's bytes to `consume` in order, in pieces, so a large file is never held whole. The bytes are
    /// checked only at the end: what `consume` wrote must not be used unless this returns without an error.
    func copy(_ file: ImportedSourceFile, to consume: (UnsafeRawBufferPointer) throws -> Void) throws
}

extension ImportSourceFiles {
    /// For sources that hold their files whole, such as tests' fakes: the whole file in one piece.
    public func copy(_ file: ImportedSourceFile, to consume: (UnsafeRawBufferPointer) throws -> Void) throws {
        let contents = try contents(of: file)
        try contents.withUnsafeBytes { buffer in try consume(buffer) }
    }
}

extension GoodnotesNotebookReader: ImportSourceFiles {
    public func contents(of file: ImportedSourceFile) throws -> Data {
        try contents(ofFileAt: file.path)
    }

    public func copy(_ file: ImportedSourceFile, to consume: (UnsafeRawBufferPointer) throws -> Void) throws {
        try copy(fileAt: file.path, to: consume)
    }
}

extension NotabilityNoteReader: ImportSourceFiles {
    public func contents(of file: ImportedSourceFile) throws -> Data {
        try contents(ofFileAt: file.path)
    }

    public func copy(_ file: ImportedSourceFile, to consume: (UnsafeRawBufferPointer) throws -> Void) throws {
        try copy(fileAt: file.path, to: consume)
    }
}

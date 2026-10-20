import Foundation
import GraphiteCore

/// Writes one imported recording (`ImportedRecording`) as an `.m4a` file: the source's bytes, unchanged, copied in
/// pieces (`ImportSourceFiles.copy(_:to:)`), so a long recording is never held whole. The copy goes to a staged file
/// that is moved into place only when the source's size and CRC-32 checked out and nothing is at the destination, as
/// `NotebookImportWriter` writes the PDF; the notebook is only read. Where the file goes is the caller's choice.
///
/// Synchronous: run it away from the main actor.
public struct NotebookImportRecordingWriter: Sendable {
    /// An MPEG-4 file starts with a box whose type, after its four-byte size, is `ftyp`.
    private static let fileTypeBoxType = Array("ftyp".utf8)
    private static let fileTypeBoxEnd = 8

    private let fileWriter: AtomicFileWriter

    public init(fileWriter: AtomicFileWriter) {
        self.fileWriter = fileWriter
    }

    @discardableResult
    public func write(_ recording: ImportedRecording, from sourceFiles: any ImportSourceFiles, to destination: URL) throws -> FileRevision {
        // Checked first so a recording is not copied only to be refused; the writer checks again as it moves the file.
        guard !FileManager.default.fileExists(atPath: destination.path) else { throw NotebookImportWriterError.destinationExists(destination) }
        do {
            return try fileWriter.replace(destination, expecting: .absent) { staging in
                try copy(recording.file, from: sourceFiles, to: staging, destination: destination)
            }
        } catch GraphiteError.conflict {
            throw NotebookImportWriterError.destinationExists(destination)
        }
    }

    private func copy(_ file: ImportedSourceFile, from sourceFiles: any ImportSourceFiles, to staging: URL, destination: URL) throws {
        guard FileManager.default.createFile(atPath: staging.path, contents: nil) else {
            throw NotebookImportWriterError.recordingNotWritten(destination, underlyingError: CocoaError(.fileWriteUnknown))
        }
        let handle = try FileHandle(forWritingTo: staging)
        var header: [UInt8] = []
        var refusal: NotebookImportWriterError?
        do {
            try sourceFiles.copy(file) { piece in
                if header.count < Self.fileTypeBoxEnd {
                    header += piece.prefix(Self.fileTypeBoxEnd - header.count)
                    if header.count == Self.fileTypeBoxEnd && Array(header[4..<8]) != Self.fileTypeBoxType {
                        refusal = .recordingNotMPEG4(file)
                        throw NotebookImportWriterError.recordingNotMPEG4(file)
                    }
                }
                do { try handle.write(contentsOf: piece) } catch {
                    refusal = .recordingNotWritten(destination, underlyingError: error)
                    throw error
                }
            }
            try handle.close()
        } catch {
            try? handle.close() // the staged file is removed whatever happens here
            throw refusal ?? NotebookImportWriterError.sourceFileUnreadable(file, underlyingError: error)
        }
        guard header.count == Self.fileTypeBoxEnd else { throw NotebookImportWriterError.recordingNotMPEG4(file) }
    }
}

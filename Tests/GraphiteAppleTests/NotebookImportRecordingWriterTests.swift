import XCTest
import GraphiteCore
import NotebookImport
import GraphiteTestSupport
@testable import GraphiteApple

/// An imported recording written as an `.m4a` file: the source's bytes unchanged, copied in pieces, and nothing at the
/// destination when the copy cannot be trusted.
final class NotebookImportRecordingWriterTests: XCTestCase {
    /// Hands a file over in pieces of `pieceByteCount` bytes, as a reader's copy does, failing after `failingAfterPieces`.
    private struct PieceByPieceFiles: ImportSourceFiles {
        struct SourceDamaged: Error {}
        let contentsByPath: [String: [UInt8]]
        var pieceByteCount = 5
        var failingAfterPieces: Int?

        func contents(of file: ImportedSourceFile) throws -> Data {
            Data(contentsByPath[file.pathInSource] ?? [])
        }

        func copy(_ file: ImportedSourceFile, to consume: (UnsafeRawBufferPointer) throws -> Void) throws {
            guard let contents = contentsByPath[file.pathInSource] else { throw SourceDamaged() }
            var pieceCount = 0
            for start in stride(from: 0, to: contents.count, by: pieceByteCount) {
                if pieceCount == failingAfterPieces { throw SourceDamaged() }
                try contents[start..<min(start + pieceByteCount, contents.count)].withUnsafeBytes { piece in try consume(piece) }
                pieceCount += 1
            }
            if pieceCount == failingAfterPieces { throw SourceDamaged() }
        }
    }

    /// The start of an MPEG-4 audio file: a 24-byte `ftyp` box of brand `mp42`, then other boxes.
    private static let audioBytes: [UInt8] = [0, 0, 0, 24] + Array("ftypmp42".utf8) + [0, 0, 0, 0] + Array("mp42isom".utf8)
        + (0..<200).map { byteIndex in UInt8(byteIndex & 0xFF) }
    private static let recording = ImportedRecording(file: sourceFile("attachments/AUDIO"), name: "Recording 1", durationSeconds: 47.2)

    private static func sourceFile(_ text: String) -> ImportedSourceFile {
        guard let path = NotebookArchivePath(validating: text) else { preconditionFailure("not a safe archive path: \(text)") }
        return ImportedSourceFile(path: path)
    }

    func testTheRecordingIsWrittenWithTheSourcesBytesUnchanged() throws {
        let destination = try destinationURL()
        let files = PieceByPieceFiles(contentsByPath: ["attachments/AUDIO": Self.audioBytes])
        let revision = try NotebookImportRecordingWriter(fileWriter: AtomicFileWriter()).write(Self.recording, from: files, to: destination)
        XCTAssertEqual(Array(try Data(contentsOf: destination)), Self.audioBytes)
        XCTAssertEqual(revision, try FileRevision.read(destination))
    }

    func testAFileThatIsNotMPEG4IsRefusedAndNothingIsWritten() throws {
        let destination = try destinationURL()
        let files = PieceByPieceFiles(contentsByPath: ["attachments/AUDIO": Array("%PDF-1.7 not a recording at all".utf8)])
        XCTAssertThrowsError(try NotebookImportRecordingWriter(fileWriter: AtomicFileWriter()).write(Self.recording, from: files, to: destination)) { error in
            guard case NotebookImportWriterError.recordingNotMPEG4(let file) = error else { return XCTFail("\(error)") }
            XCTAssertEqual(file, Self.recording.file)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
    }

    func testASourceThatFailsPartWayLeavesNothingAtTheDestination() throws {
        let destination = try destinationURL()
        // Pieces were written before the failure, as when a deflated recording fails its checksum at the end.
        let files = PieceByPieceFiles(contentsByPath: ["attachments/AUDIO": Self.audioBytes], failingAfterPieces: 10)
        XCTAssertThrowsError(try NotebookImportRecordingWriter(fileWriter: AtomicFileWriter()).write(Self.recording, from: files, to: destination)) { error in
            guard case NotebookImportWriterError.sourceFileUnreadable(let file, let underlyingError) = error else { return XCTFail("\(error)") }
            XCTAssertEqual(file, Self.recording.file)
            XCTAssertTrue(underlyingError is PieceByPieceFiles.SourceDamaged)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
    }

    func testAFileAlreadyAtTheDestinationIsLeftAsItWas() throws {
        let destination = try destinationURL()
        try Data("an earlier recording".utf8).write(to: destination)
        let files = PieceByPieceFiles(contentsByPath: ["attachments/AUDIO": Self.audioBytes])
        XCTAssertThrowsError(try NotebookImportRecordingWriter(fileWriter: AtomicFileWriter()).write(Self.recording, from: files, to: destination)) { error in
            guard case NotebookImportWriterError.destinationExists = error else { return XCTFail("\(error)") }
        }
        XCTAssertEqual(try Data(contentsOf: destination), Data("an earlier recording".utf8))
    }

    func testAFileShorterThanItsTypeBoxIsRefused() throws {
        let destination = try destinationURL()
        let files = PieceByPieceFiles(contentsByPath: ["attachments/AUDIO": [0, 0, 0, 24, 0x66]])
        XCTAssertThrowsError(try NotebookImportRecordingWriter(fileWriter: AtomicFileWriter()).write(Self.recording, from: files, to: destination)) { error in
            guard case NotebookImportWriterError.recordingNotMPEG4 = error else { return XCTFail("\(error)") }
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
    }

    private func destinationURL() throws -> URL {
        try TemporaryVault.make(prefix: "NotebookImportRecordingWriter", for: self).location(of: "Recording 1.m4a")
    }
}

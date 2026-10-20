import XCTest
import PDFKit
import CoreGraphics
import GraphiteCore
@testable import GraphiteApple
import GraphiteTestSupport

/// What `PDFFileService.save` refuses to write and when it replaces the file: never a PDF
/// that is locked or forbids comments or changes, and only the file at the revision it read.
final class PDFFileServiceSaveGuardsTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = try TemporaryVault.make(prefix: "PDFFileServiceSaveGuards", for: self).root
    }

    // MARK: Fixtures

    private func makePDF(named filename: String, pageCount: Int = 2, auxiliaryInfo: [CFString: Any] = [:]) throws -> URL {
        let location = directory.appendingPathComponent(filename)
        var mediaBox = CGRect(x: 0, y: 0, width: 300, height: 400)
        let context = try XCTUnwrap(CGContext(location as CFURL, mediaBox: &mediaBox, auxiliaryInfo as CFDictionary))
        for pageNumber in 1...pageCount {
            context.beginPDFPage(nil)
            context.setFillColor(CGColor(gray: 0.3, alpha: 1))
            context.fill(CGRect(x: 20, y: 20, width: 10 * pageNumber, height: 10))
            context.endPDFPage()
        }
        context.closePDF()
        return location
    }

    private func restrictedPDF(named filename: String, permissions: CGPDFAccessPermissions) throws -> URL {
        try makePDF(named: filename, auxiliaryInfo: [
            kCGPDFContextOwnerPassword: "owner", kCGPDFContextUserPassword: "", kCGPDFContextAccessPermissions: permissions.rawValue
        ])
    }

    private var snapshotLocation: URL { directory.appendingPathComponent("snapshot-\(UUID().uuidString).pdf") }

    // MARK: Documents that are never written

    /// PDFKit reports commenting and document changes as allowed together or forbidden together
    /// for files made with Core Graphics, so the fixture forbids both.
    func testAPDFThatForbidsCommentingAndChangesIsNeverWritten() async throws {
        let location = try restrictedPDF(named: "Restricted.pdf", permissions: [.allowsLowQualityPrinting, .allowsHighQualityPrinting, .allowsContentCopying])
        let document = try XCTUnwrap(PDFDocument(url: location))
        XCTAssertFalse(document.allowsCommenting)
        XCTAssertFalse(document.allowsDocumentChanges)
        let bytesBefore = try Data(contentsOf: location)
        let destination = snapshotLocation

        do {
            _ = try await PDFFileService().save(url: location, revision: FileRevision.read(location), edits: [.rotate(page: 0, clockwise: true)],
                                                baselineURL: nil, savedSnapshotDestination: destination)
            XCTFail("A PDF that forbids commenting and changes must not be written.")
        } catch let error as GraphiteError {
            guard case .unavailable = error else { return XCTFail("It was refused with \(error)") }
        }
        XCTAssertEqual(try Data(contentsOf: location), bytesBefore, "The file is unchanged.")
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path), "No snapshot is left for a refused save.")
    }

    func testAPDFThatOpensOnlyWithAPasswordIsNeverWritten() async throws {
        let location = try makePDF(named: "Locked.pdf", auxiliaryInfo: [kCGPDFContextOwnerPassword: "owner", kCGPDFContextUserPassword: "reader"])
        XCTAssertEqual(PDFDocument(url: location)?.isLocked, true)
        let bytesBefore = try Data(contentsOf: location)
        do {
            _ = try await PDFFileService().save(url: location, revision: FileRevision.read(location), edits: [.rotate(page: 0, clockwise: true)])
            XCTFail("A locked PDF must not be written.")
        } catch let error as GraphiteError {
            guard case .invalidFile = error else { return XCTFail("A locked PDF was refused with \(error)") }
        }
        XCTAssertEqual(try Data(contentsOf: location), bytesBefore)
    }

    // MARK: Replacing only the file that was read

    func testASaveReplacesTheFileAndReturnsTheRevisionOfTheBytesItWrote() async throws {
        let location = try makePDF(named: "Notes.pdf")
        let destination = snapshotLocation
        let savedRevision = try await PDFFileService().save(url: location, revision: FileRevision.read(location), edits: [.rotate(page: 1, clockwise: true)],
                                                            baselineURL: nil, savedSnapshotDestination: destination)
        XCTAssertEqual(savedRevision, try FileRevision.read(location))
        XCTAssertEqual(try Data(contentsOf: destination), try Data(contentsOf: location), "The snapshot is the exact bytes written.")
        XCTAssertEqual(PDFDocument(url: location)?.page(at: 1)?.rotation, 90)
    }

    func testASaveOfAFileChangedSinceItWasReadIsAConflictAndLeavesTheOtherVersion() async throws {
        let location = try makePDF(named: "Notes.pdf")
        let baseline = directory.appendingPathComponent("baseline.pdf")
        try FileManager.default.copyItem(at: location, to: baseline)
        let revisionRead = try FileRevision.read(location)
        // Another app replaces the file after it was read.
        let otherVersion = try Data(contentsOf: makePDF(named: "Other.pdf", pageCount: 3))
        try otherVersion.write(to: location)

        for baselineURL in [baseline, nil] as [URL?] {
            let destination = snapshotLocation
            do {
                _ = try await PDFFileService().save(url: location, revision: revisionRead, edits: [.rotate(page: 0, clockwise: true)],
                                                    baselineURL: baselineURL, savedSnapshotDestination: destination)
                XCTFail("A save over another version must fail.")
            } catch {
                XCTAssertEqual(error as? GraphiteError, .conflict)
            }
            XCTAssertEqual(try Data(contentsOf: location), otherVersion, "The other app's version is kept.")
            XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path), "A failed save leaves no baseline behind.")
        }
    }

    func testTheSameRevisionSavesAgainOnlyAfterTheFileIsRead() async throws {
        let location = try makePDF(named: "Notes.pdf")
        let service = PDFFileService()
        let firstRevision = try FileRevision.read(location)
        let secondRevision = try await service.save(url: location, revision: firstRevision, edits: [.rotate(page: 0, clockwise: true)])
        XCTAssertNotEqual(secondRevision, firstRevision)
        do {
            _ = try await service.save(url: location, revision: firstRevision, edits: [.rotate(page: 0, clockwise: true)])
            XCTFail("The first revision is no longer the file's.")
        } catch {
            XCTAssertEqual(error as? GraphiteError, .conflict)
        }
        XCTAssertEqual(try FileRevision.read(location), secondRevision)
    }
}

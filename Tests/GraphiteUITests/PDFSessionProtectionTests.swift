import XCTest
import PDFKit
import GraphiteCore
import GraphiteApple
@testable import GraphiteUI
import GraphiteTestSupport

/// A PDF that is encrypted, forbids comments and changes, or is digitally signed is shown
/// without being changed: every edit is refused and the file is never written.
@MainActor
final class PDFSessionProtectionTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = try TemporaryVault.make(prefix: "PDFSessionProtection", for: self).root
    }

    // MARK: Fixtures

    private func makePDF(named filename: String, auxiliaryInfo: [CFString: Any] = [:]) throws -> URL {
        let location = directory.appendingPathComponent(filename)
        var mediaBox = CGRect(x: 0, y: 0, width: 300, height: 400)
        let context = try XCTUnwrap(CGContext(location as CFURL, mediaBox: &mediaBox, auxiliaryInfo as CFDictionary))
        for pageNumber in 1...2 {
            context.beginPDFPage(nil)
            context.setFillColor(CGColor(gray: 0.3, alpha: 1))
            context.fill(CGRect(x: 20, y: 20, width: 10 * pageNumber, height: 10))
            context.endPDFPage()
        }
        context.closePDF()
        return location
    }

    /// A minimal one-page PDF whose form says its signatures break unless changes are appended.
    private func makeSignedPDF(named filename: String) throws -> URL {
        let objects = ["<< /Type /Catalog /Pages 2 0 R /AcroForm << /Fields [] /SigFlags 3 >> >>", "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
                       "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 300 400] >>"]
        var fileText = "%PDF-1.7\n"
        var offsets: [Int] = []
        for (objectIndex, object) in objects.enumerated() {
            offsets.append(fileText.utf8.count)
            fileText += "\(objectIndex + 1) 0 obj\n\(object)\nendobj\n"
        }
        let crossReferenceOffset = fileText.utf8.count
        fileText += "xref\n0 \(objects.count + 1)\n0000000000 65535 f \n"
        for offset in offsets { fileText += String(format: "%010d 00000 n \n", offset) }
        fileText += "trailer\n<< /Size \(objects.count + 1) /Root 1 0 R >>\nstartxref\n\(crossReferenceOffset)\n%%EOF\n"
        let location = directory.appendingPathComponent(filename)
        try Data(fileText.utf8).write(to: location)
        return location
    }

    private func highlight() -> PDFMarkup {
        PDFMarkup(name: UUID().uuidString, kind: .highlight, color: .yellow, lineBounds: [CGRect(x: 40, y: 300, width: 100, height: 14)])
    }

    /// Every kind of edit a person can make is refused with `unavailable`.
    private func assertEveryEditIsRefused(by session: PDFSession, _ description: String, file: StaticString = #filePath, line: UInt = #line) {
        let edits: [PDFEdit] = [.addMarkup(page: 0, markup: highlight()), .rotate(page: 0, clockwise: true), .bookmark(page: 0, label: "Page 1"),
                                .move(from: 0, to: 1), .delete(pages: [0]), .duplicate(page: 0)]
        for edit in edits {
            XCTAssertThrowsError(try session.apply(edit), description, file: file, line: line) { error in
                guard case .unavailable? = error as? GraphiteError else { return XCTFail("\(description) refused with \(error)", file: file, line: line) }
            }
        }
        XCTAssertFalse(session.hasUnsavedChanges, "A refused edit is not recorded as unsaved work: \(description)", file: file, line: line)
    }

    private func assertSavingLeavesTheFileUnchanged(_ session: PDFSession, at location: URL, _ description: String,
                                                    file: StaticString = #filePath, line: UInt = #line) async throws {
        let bytesBefore = try Data(contentsOf: location)
        try await session.save()
        try await session.saveBeforeClosing()
        XCTAssertEqual(try Data(contentsOf: location), bytesBefore, "The file is unchanged: \(description)", file: file, line: line)
    }

    // MARK: Protected kinds

    func testAnEncryptedPDFWithEveryPermissionIsStillShownWithoutChanges() async throws {
        let location = try makePDF(named: "Encrypted.pdf", auxiliaryInfo: [kCGPDFContextOwnerPassword: "owner", kCGPDFContextUserPassword: ""])
        let session = try await PDFSession.open(location)
        XCTAssertTrue(session.document.isEncrypted)
        XCTAssertTrue(session.isPasswordProtected, "Saving would write it back without its encryption.")
        XCTAssertTrue(session.isProtected)
        assertEveryEditIsRefused(by: session, "encrypted")
        try await assertSavingLeavesTheFileUnchanged(session, at: location, "encrypted")
    }

    func testAPDFThatNeedsAPasswordOpensOnlyWithItAndIsThenShownWithoutChanges() async throws {
        let location = try makePDF(named: "Locked.pdf", auxiliaryInfo: [kCGPDFContextOwnerPassword: "owner", kCGPDFContextUserPassword: "reader"])
        do {
            _ = try await PDFSession.open(location)
            XCTFail("A locked PDF needs its password.")
        } catch let required as PDFPasswordRequired {
            XCTAssertFalse(required.wasPasswordWrong)
        }
        do {
            _ = try await PDFSession.open(location, password: "wrong")
            XCTFail("A wrong password does not open it.")
        } catch let required as PDFPasswordRequired {
            XCTAssertTrue(required.wasPasswordWrong)
        }
        let session = try await PDFSession.open(location, password: "reader")
        XCTAssertTrue(session.isProtected)
        assertEveryEditIsRefused(by: session, "opened with its password")
        try await assertSavingLeavesTheFileUnchanged(session, at: location, "opened with its password")
    }

    func testAPDFThatForbidsCommentingAndChangesIsShownWithoutChanges() async throws {
        let permissions: CGPDFAccessPermissions = [.allowsLowQualityPrinting, .allowsHighQualityPrinting, .allowsContentCopying]
        let location = try makePDF(named: "Restricted.pdf", auxiliaryInfo: [
            kCGPDFContextOwnerPassword: "owner", kCGPDFContextUserPassword: "", kCGPDFContextAccessPermissions: permissions.rawValue
        ])
        let session = try await PDFSession.open(location)
        XCTAssertFalse(session.document.allowsCommenting)
        XCTAssertFalse(session.document.allowsDocumentChanges)
        XCTAssertTrue(session.isProtected)
        assertEveryEditIsRefused(by: session, "restricted")
        try await assertSavingLeavesTheFileUnchanged(session, at: location, "restricted")
    }

    func testASignedPDFIsShownWithoutChangesUntilTheUserAcceptsInvalidatingTheSignature() async throws {
        let location = try makeSignedPDF(named: "Contract.pdf")
        let session = try await PDFSession.open(location)
        XCTAssertTrue(session.hasDigitalSignatures)
        XCTAssertFalse(session.isPasswordProtected)
        XCTAssertTrue(session.isProtected)
        assertEveryEditIsRefused(by: session, "signed")
        try await assertSavingLeavesTheFileUnchanged(session, at: location, "signed, not accepted")

        session.acceptsSignatureInvalidation = true
        XCTAssertFalse(session.isProtected)
        try session.apply(.rotate(page: 0, clockwise: true))
        try await session.save()
        XCTAssertEqual(PDFDocument(url: location)?.page(at: 0)?.rotation, 90, "After the user accepts, the edit is written.")
    }

    func testAcceptingTheLossOfASignatureDoesNotUnlockAnEncryptedPDF() async throws {
        let location = try makePDF(named: "Encrypted.pdf", auxiliaryInfo: [kCGPDFContextOwnerPassword: "owner", kCGPDFContextUserPassword: ""])
        let session = try await PDFSession.open(location)
        session.acceptsSignatureInvalidation = true
        XCTAssertTrue(session.isProtected, "Accepting the loss of a signature does not unlock an encrypted PDF.")
        assertEveryEditIsRefused(by: session, "encrypted, signature accepted")
    }

    /// BUG-LECTURE-02: the embed's banner named a password for every protected PDF.
    func testASignedPDFIsProtectedBecauseOfItsSignatureNotAPassword() async throws {
        let signedSession = try await PDFSession.open(try makeSignedPDF(named: "Contract.pdf"))
        XCTAssertFalse(signedSession.document.isEncrypted)
        XCTAssertEqual(signedSession.protection, .digitallySigned)
        XCTAssertEqual(EmbeddedPDFViewer.protectionBannerSymbolName(for: .digitallySigned), "signature",
                       "The embed shows the signature's reason, as the PDF view does.")

        let encryptedLocation = try makePDF(named: "Encrypted.pdf", auxiliaryInfo: [kCGPDFContextOwnerPassword: "owner", kCGPDFContextUserPassword: ""])
        let encryptedSession = try await PDFSession.open(encryptedLocation)
        XCTAssertTrue(encryptedSession.document.isEncrypted)
        XCTAssertFalse(encryptedSession.document.isLocked, "PDFKit opens an empty user password by itself.")
        XCTAssertEqual(encryptedSession.protection, .passwordProtected)
        XCTAssertEqual(EmbeddedPDFViewer.protectionBannerSymbolName(for: .passwordProtected), "lock.fill")

        signedSession.acceptsSignatureInvalidation = true
        XCTAssertNil(signedSession.protection, "Accepting the signature's loss lifts its protection.")
        encryptedSession.acceptsSignatureInvalidation = true
        XCTAssertEqual(encryptedSession.protection, .passwordProtected, "A password outranks a signature.")
    }

    func testAnOrdinaryPDFTakesEditsAndIsWritten() async throws {
        let location = try makePDF(named: "Plain.pdf")
        let session = try await PDFSession.open(location)
        XCTAssertFalse(session.isProtected)
        try session.apply(.rotate(page: 1, clockwise: true))
        XCTAssertTrue(session.hasUnsavedChanges)
        try await session.save()
        XCTAssertEqual(PDFDocument(url: location)?.page(at: 1)?.rotation, 90)
    }
}

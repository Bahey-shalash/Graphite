import XCTest
import PDFKit
@testable import GraphiteApple
import GraphiteTestSupport

/// Compaction runs only on a file with a single plain cross-reference table: no `/Prev`
/// (an incremental update), no `/XRefStm` (a hybrid file) and no `/Encrypt`. In every other
/// case it writes nothing and PDFKit's file stays as it is.
final class PDFObjectCompactionApplicabilityTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = try TemporaryVault.make(prefix: "PDFObjectCompactionApplicability", for: self).root
    }

    /// One page and one object nothing refers to, with the given extra trailer entries.
    private func fileData(trailerExtras: String) -> Data {
        let objects = ["<< /Type /Catalog /Pages 2 0 R >>", "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
                       "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] >>", "<< /Unused true >>"]
        var text = "%PDF-1.7\n"
        var offsets: [Int] = []
        for (objectIndex, object) in objects.enumerated() {
            offsets.append(text.utf8.count)
            text += "\(objectIndex + 1) 0 obj\n\(object)\nendobj\n"
        }
        let crossReferenceOffset = text.utf8.count
        text += "xref\n0 \(objects.count + 1)\n0000000000 65535 f \n"
        for offset in offsets { text += String(format: "%010d 00000 n \n", offset) }
        text += "trailer\n<< /Size \(objects.count + 1) /Root 1 0 R \(trailerExtras) >>\nstartxref\n\(crossReferenceOffset)\n%%EOF\n"
        return Data(text.utf8)
    }

    private func compact(_ data: Data) throws -> (report: PDFObjectCompaction.Report?, destination: URL) {
        let source = directory.appendingPathComponent("Source-\(UUID().uuidString).pdf")
        let destination = directory.appendingPathComponent("Compacted-\(UUID().uuidString).pdf")
        try data.write(to: source)
        return (try PDFObjectCompaction.compact(fileAt: source, writingTo: destination), destination)
    }

    func testASingleCrossReferenceTableIsCompactedAndTheResultOpensWithTheSamePages() throws {
        let result = try compact(fileData(trailerExtras: ""))
        XCTAssertEqual(result.report?.removedObjectCount, 1)
        XCTAssertEqual(PDFDocument(url: result.destination)?.pageCount, 1)
    }

    func testAnIncrementalUpdateAHybridFileAndAnEncryptedFileAreLeftAlone() throws {
        let trailerExtras = [("an incremental update", "/Prev 9"), ("a hybrid file", "/XRefStm 9"), ("an encrypted file", "/Encrypt 4 0 R")]
        for (description, extras) in trailerExtras {
            let data = fileData(trailerExtras: extras)
            XCTAssertNil(PDFObjectCompaction.compacted(data), description)
            let result = try compact(data)
            XCTAssertNil(result.report, description)
            XCTAssertFalse(FileManager.default.fileExists(atPath: result.destination.path), "Nothing is written for \(description).")
        }
    }
}

#if os(iOS)
import Foundation
import GraphiteCore
import GraphiteApple

/// A blank notebook written to a new file in the temporary folder, for hosted tests that open
/// a PDF session (this target cannot import the package's `TemporaryVault`). The caller
/// removes the file when the test ends.
func makeHostedBlankNotebook(named name: String, pageCount: Int = 1) throws -> URL {
    let location = FileManager.default.temporaryDirectory.appendingPathComponent("\(name)-\(UUID().uuidString).pdf")
    try PDFTemplateGenerator.documentData(paper: PaperSpecification(template: .blank), pageCount: pageCount).write(to: location)
    return location
}
#endif

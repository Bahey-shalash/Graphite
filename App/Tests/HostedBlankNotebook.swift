/**
 * File: HostedBlankNotebook.swift
 * -------------------------------
 * Layer: Tests
 * Description: Temporary files for hosted tests: a blank notebook PDF, and a fresh place in the temporary folder.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 21/10/2026
 */

#if os(iOS)
import Foundation
import GraphiteCore
import GraphiteApple

/// A blank notebook written to a new file in the temporary folder, for hosted tests that open
/// a PDF session (this target cannot import the package's `TemporaryVault`). The caller
/// removes the file when the test ends.
func makeHostedBlankNotebook(named name: String, pageCount: Int = 1) throws -> URL {
    let location = hostedTemporaryLocation(named: name).appendingPathExtension("pdf")
    try PDFTemplateGenerator.documentData(paper: PaperSpecification(template: .blank), pageCount: pageCount).write(to: location)
    return location
}

/// A new place in the temporary folder, named after `name` and a fresh identifier, for a file
/// or folder a hosted test makes and removes when it ends.
func hostedTemporaryLocation(named name: String) -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("\(name)-\(UUID().uuidString)").resolvingSymlinksInPath()
}
#endif

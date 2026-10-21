import Foundation
import XCTest

/// A folder in the system's temporary directory for one test, removed when the test ends.
struct TemporaryFolder {
    let location: URL

    static func make(for testCase: XCTestCase) throws -> TemporaryFolder {
        let location = FileManager.default.temporaryDirectory.appendingPathComponent("ShareInboxTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: location, withIntermediateDirectories: true)
        testCase.addTeardownBlock { try? FileManager.default.removeItem(at: location) } // the system clears its temporary folder too
        return TemporaryFolder(location: location)
    }

    /// A file holding `text`, outside any inbox, to share.
    func writeFile(named fileName: String, text: String) throws -> URL {
        let file = location.appendingPathComponent(fileName)
        try Data(text.utf8).write(to: file)
        return file
    }
}

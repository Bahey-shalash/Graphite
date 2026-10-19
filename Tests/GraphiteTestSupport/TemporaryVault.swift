import Foundation
import XCTest

/// A folder in the system's temporary directory that a test uses as a vault (or as any
/// folder it writes files into), with helpers to put files in it and to read them back.
/// It is removed when the test ends, and so is the `.cache` folder beside it that the
/// tests of the index keep their database in (`cacheDirectory`).
///
/// Create it with `make(prefix:for:)`, which registers the removal with the test case, or
/// with `init(prefix:)` and call `remove()` yourself where there is no test case (a test
/// bed object that outlives one test) or where `tearDown()` still needs the folder: XCTest
/// runs the registered removal before `tearDown()`, not after it.
public struct TemporaryVault: Sendable {
    /// The folder, as `URL.resolvingSymlinksInPath()` gives it, which is the form the
    /// workspace reads a vault by.
    public let root: URL

    /// Where the index of this vault keeps its database in tests: the folder's name with
    /// `.cache` added, beside the folder and not inside it, so the index is never scanned.
    public var cacheDirectory: URL { root.appendingPathExtension("cache") }

    /// Creates an empty folder named after `prefix` and a fresh identifier. The prefix says
    /// which test made a folder that a crashed run left behind.
    public init(prefix: String = "Vault") throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        root = folder.resolvingSymlinksInPath()
    }

    /// A vault that is removed after the test, whatever the test does.
    @discardableResult
    public static func make(prefix: String = "Vault", for testCase: XCTestCase) throws -> TemporaryVault {
        let vault = try TemporaryVault(prefix: prefix)
        testCase.addTeardownBlock { vault.remove() }
        return vault
    }

    /// A vault holding `files` (text by path relative to the vault), removed after the test.
    @discardableResult
    public static func make(prefix: String = "Vault", files: [String: String], for testCase: XCTestCase) throws -> TemporaryVault {
        let vault = try make(prefix: prefix, for: testCase)
        try vault.writeFiles(files)
        return vault
    }

    /// The location of `relativePath` in the vault.
    public func location(of relativePath: String) -> URL { root.appendingPathComponent(relativePath) }

    @discardableResult
    public func writeFile(_ relativePath: String, text: String) throws -> URL {
        try writeFile(relativePath, data: Data(text.utf8))
    }

    /// Writes the file, making the folders above it first.
    @discardableResult
    public func writeFile(_ relativePath: String, data: Data) throws -> URL {
        let fileLocation = location(of: relativePath)
        try FileManager.default.createDirectory(at: fileLocation.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileLocation)
        return fileLocation
    }

    public func writeFiles(_ files: [String: String]) throws {
        for (relativePath, text) in files { try writeFile(relativePath, text: text) }
    }

    @discardableResult
    public func createFolder(_ relativePath: String) throws -> URL {
        let folderLocation = location(of: relativePath)
        try FileManager.default.createDirectory(at: folderLocation, withIntermediateDirectories: true)
        return folderLocation
    }

    public func readText(at relativePath: String) throws -> String {
        try String(contentsOf: location(of: relativePath), encoding: .utf8)
    }

    public func fileExists(at relativePath: String) -> Bool {
        FileManager.default.fileExists(atPath: location(of: relativePath).path)
    }

    /// Removes the folder and its cache folder. Best effort: a folder that is already gone
    /// is what a test that removed it on purpose leaves.
    public func remove() {
        try? FileManager.default.removeItem(at: root)
        try? FileManager.default.removeItem(at: cacheDirectory)
    }
}

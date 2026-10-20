import XCTest
import WebKit
import GraphiteCore
@testable import GraphiteUI

/// A scheme task that records what the handler answers.
@MainActor
private final class RecordingSchemeTask: NSObject, @preconcurrency WKURLSchemeTask {
    let request: URLRequest
    private(set) var response: HTTPURLResponse?
    private(set) var body = Data()
    private(set) var didFail = false
    var onEnd: (() -> Void)?

    init(address: String) {
        request = URLRequest(url: URL(string: address)!)
    }

    func didReceive(_ response: URLResponse) { self.response = response as? HTTPURLResponse }
    func didReceive(_ data: Data) { body = data }
    func didFinish() { onEnd?() }
    func didFailWithError(_ error: any Error) { didFail = true; onEnd?() }
}

/// What the plugin web view can load through `graphite-plugins://` from the open vault: files
/// only, inside the vault, up to 256 MiB. Each test sends the request an attacking plugin page
/// would make (a path with `..`, a symbolic link out of the vault, a folder) and checks the
/// answer is 404 and no content is sent.
@MainActor
final class CommunityPluginSchemeHandlerVaultBoundaryTests: XCTestCase {
    private var container: URL!
    private var vault: URL!
    private var outsideFolder: URL!

    private static let mebibyte = 1_048_576

    override func setUpWithError() throws {
        container = FileManager.default.temporaryDirectory.appendingPathComponent("SchemeBoundary-\(UUID().uuidString)", isDirectory: true).resolvingSymlinksInPath()
        vault = container.appendingPathComponent("Vault", isDirectory: true)
        outsideFolder = container.appendingPathComponent("Outside", isDirectory: true)
        try FileManager.default.createDirectory(at: vault.appendingPathComponent("Folder"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outsideFolder, withIntermediateDirectories: true)
        try Data("outside secret".utf8).write(to: outsideFolder.appendingPathComponent("secret.txt"))
        try Data("note text".utf8).write(to: vault.appendingPathComponent("Note.md"))
        try FileManager.default.createSymbolicLink(at: vault.appendingPathComponent("FolderLink"), withDestinationURL: outsideFolder)
        try FileManager.default.createSymbolicLink(at: vault.appendingPathComponent("FileLink.txt"), withDestinationURL: outsideFolder.appendingPathComponent("secret.txt"))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: container)
    }

    // MARK: Helpers

    private struct Answer {
        let statusCode: Int?
        let headers: [String: String]
        let body: Data
    }

    private func answer(to address: String) async -> Answer {
        let handler = CommunityPluginSchemeHandler(vaultRoot: vault)
        let task = RecordingSchemeTask(address: address)
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            task.onEnd = { continuation.resume() }
            handler.webView(WKWebView(frame: .zero), start: task)
        }
        let headers = (task.response?.allHeaderFields as? [String: String]) ?? [:]
        return Answer(statusCode: task.response?.statusCode, headers: headers, body: task.body)
    }

    private func assertRefused(_ address: String, file: StaticString = #filePath, line: UInt = #line) async {
        let refusal = await answer(to: address)
        XCTAssertEqual(refusal.statusCode, 404, address, file: file, line: line)
        XCTAssertTrue(refusal.body.isEmpty, "\(address) sends no content.", file: file, line: line)
    }

    // MARK: Refusals

    func testAPathThatClimbsOutOfTheVaultIsRefused() async throws {
        await assertRefused("graphite-plugins://vault/../Outside/secret.txt")
        await assertRefused("graphite-plugins://vault/Folder/../../Outside/secret.txt")
        await assertRefused("graphite-plugins://vault/%2e%2e/Outside/secret.txt")
        await assertRefused("graphite-plugins://vault/Folder/..%2F..%2FOutside/secret.txt")
        await assertRefused("graphite-plugins://vault//etc/hosts")
    }

    func testASymbolicLinkLeadingOutOfTheVaultIsRefusedForFilesAndFolders() async throws {
        await assertRefused("graphite-plugins://vault/FileLink.txt")
        await assertRefused("graphite-plugins://vault/FolderLink/secret.txt")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: outsideFolder.path), ["secret.txt"])
    }

    func testAFolderAndTheVaultRootAreRefused() async throws {
        await assertRefused("graphite-plugins://vault/Folder")
        await assertRefused("graphite-plugins://vault/Folder/")
        await assertRefused("graphite-plugins://vault/")
        await assertRefused("graphite-plugins://vault")
    }

    func testAFileInsideTheVaultIsStillServed() async throws {
        let served = await answer(to: "graphite-plugins://vault/Note.md")
        XCTAssertEqual(served.statusCode, 200)
        XCTAssertEqual(served.body, Data("note text".utf8))
    }

    // MARK: Size

    func testAVaultFileOfTwoHundredFiftySixMebibytesIsServedAndOneByteMoreIsRefused() async throws {
        let cap = 256 * Self.mebibyte
        for (name, size) in [("AtCap.bin", cap), ("OverCap.bin", cap + 1)] {
            let location = vault.appendingPathComponent(name)
            XCTAssertTrue(FileManager.default.createFile(atPath: location.path, contents: nil))
            let handle = try FileHandle(forWritingTo: location)
            // A sparse file: the length is set without writing the bytes.
            try handle.truncate(atOffset: UInt64(size))
            try handle.close()
        }
        let atCap = await answer(to: "graphite-plugins://vault/AtCap.bin")
        XCTAssertEqual(atCap.statusCode, 200)
        XCTAssertEqual(atCap.headers["Content-Length"], String(cap))
        await assertRefused("graphite-plugins://vault/OverCap.bin")
    }
}

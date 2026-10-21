import XCTest
import CryptoKit
import GraphiteCore
import GraphiteTestSupport
@testable import GraphiteApple

/// Add-on packs downloaded from a folder of files (a file:// address stands in for the
/// server): a pack is used only when every file arrived whole, and nothing changes on the
/// device when one does not.
final class AddOnPackStoreTests: XCTestCase {
    private var server: URL!
    private var store: AddOnPackStore!
    private let session = URLSession(configuration: .ephemeral)

    override func setUpWithError() throws {
        let root = try TemporaryVault.make(prefix: "AddOnPackStoreTests", for: self).root
        server = root.appendingPathComponent("Server", isDirectory: true)
        try FileManager.default.createDirectory(at: server, withIntermediateDirectories: true)
        store = AddOnPackStore(packsFolder: root.appendingPathComponent("Add-ons", isDirectory: true))
    }

    /// Puts `contents` on the server under `name` and returns the file as a pack lists it.
    private func serve(_ name: String, _ contents: String) throws -> AddOnFile {
        let data = Data(contents.utf8)
        try data.write(to: server.appendingPathComponent(name))
        let hash = SHA256.hash(data: data).map { byte in String(format: "%02x", byte) }.joined()
        return AddOnFile(name: name, byteCount: Int64(data.count), sha256: hash)
    }

    private func pack(revision: String = "first", files: [AddOnFile]) -> AddOnPack {
        AddOnPack(id: "pictures", title: "Pictures", revision: revision, baseAddress: server, files: files)
    }

    func testAPackIsInstalledOnlyOnceEveryFileArrivedAndMatched() async throws {
        let pictures = pack(files: [try serve("one.jpg", "first picture"), try serve("two.jpg", "second picture")])
        XCTAssertFalse(store.isInstalled(pictures))
        XCTAssertNil(store.location(of: pictures.files[0], in: pictures))

        try await store.install(pictures, using: session)

        XCTAssertTrue(store.isInstalled(pictures))
        let location = try XCTUnwrap(store.location(of: pictures.files[1], in: pictures))
        XCTAssertEqual(try String(contentsOf: location, encoding: .utf8), "second picture")
        XCTAssertEqual(pictures.byteCount, Int64("first picture".utf8.count + "second picture".utf8.count))
    }

    func testAFileThatDoesNotMatchItsHashLeavesNothingInstalled() async throws {
        let good = try serve("one.jpg", "first picture")
        var damaged = try serve("two.jpg", "second picture")
        damaged = AddOnFile(name: damaged.name, byteCount: damaged.byteCount, sha256: String(repeating: "0", count: 64))
        let pictures = pack(files: [good, damaged])

        do {
            try await store.install(pictures, using: session)
            XCTFail("A damaged file must stop the install.")
        } catch let error as AddOnPackStore.InstallError {
            XCTAssertEqual(error, .fileDoesNotMatch(fileName: "two.jpg"))
        }

        XCTAssertFalse(store.isInstalled(pictures))
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.folder(of: pictures).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.stagingFolder(of: pictures).path), "No half-downloaded folder is left.")
    }

    func testANewRevisionIsDownloadedAgainAndReplacesTheOldFiles() async throws {
        let first = pack(revision: "first", files: [try serve("one.jpg", "old picture")])
        try await store.install(first, using: session)
        let second = pack(revision: "second", files: [try serve("one.jpg", "new picture")])
        XCTAssertFalse(store.isInstalled(second), "Another revision is not the one installed.")

        try await store.install(second, using: session)

        XCTAssertTrue(store.isInstalled(second))
        XCTAssertFalse(store.isInstalled(first))
        let location = try XCTUnwrap(store.location(of: second.files[0], in: second))
        XCTAssertEqual(try String(contentsOf: location, encoding: .utf8), "new picture")
    }

    func testRemovingAPackDeletesItsFiles() async throws {
        let pictures = pack(files: [try serve("one.jpg", "first picture")])
        try await store.install(pictures, using: session)

        try store.remove(pictures)

        XCTAssertFalse(store.isInstalled(pictures))
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.folder(of: pictures).path))
    }

    func testThePackFolderIsBelowApplicationSupportNeverAVault() throws {
        let applicationSupport = URL(fileURLWithPath: "/tmp/Application Support", isDirectory: true)
        let store = try AddOnPackStore.inApplicationSupport(applicationSupport)
        XCTAssertEqual(store.packsFolder.path, "/tmp/Application Support/Graphite/Add-ons")
    }
}

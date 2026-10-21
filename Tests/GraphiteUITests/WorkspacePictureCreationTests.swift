import XCTest
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import GraphiteCore
import GraphiteIndex
import GraphiteApple
@testable import GraphiteUI
import GraphiteTestSupport

/// Image from Photos and Take Photo in the New menu: the picture becomes an image file in the folder shown.
@MainActor
final class WorkspacePictureCreationTests: XCTestCase {
    private let takenAt = Date(timeIntervalSince1970: 1_792_000_000)

    private func makeWorkspace(files: [String: String] = [:]) async throws -> (WorkspaceModel, TemporaryVault) {
        let vault = try TemporaryVault.make(prefix: "PictureCreation", files: files, for: self)
        let indexFolder = try TemporaryVault.make(prefix: "PictureCreationIndex", for: self).root
        let index = try VaultIndex(databaseURL: indexFolder.appendingPathComponent("index.sqlite"))
        _ = try await index.reconcile(root: vault.root)
        let workspace = WorkspaceModel()
        workspace.folderAccess = FolderAccess(root: vault.root)
        workspace.store = VaultStore(root: vault.root)
        workspace.index = index
        workspace.hasCompletedIndexScan = true
        return (workspace, vault)
    }

    private func pngData() throws -> Data {
        var pixels = [UInt8](repeating: 255, count: 8 * 8 * 4)
        let context = try XCTUnwrap(CGContext(data: &pixels, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 32,
                                              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let output = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try XCTUnwrap(context.makeImage()), nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return output as Data
    }

    func testAPictureIsSavedAsAFileInTheFolderNamedFromWhenItWasMadeAndOpened() async throws {
        let (workspace, vault) = try await makeWorkspace(files: ["Course/Note.md": "x"])
        let picture = try pngData()
        await workspace.createPicture(picture, takenAt: takenAt, in: try VaultPath("Course"))
        XCTAssertNil(workspace.errorMessage)
        let stem = PhotoFileName.stem(createdAt: takenAt, calendar: Calendar(identifier: .gregorian))
        let savedPath = try VaultPath("Course/\(stem).png")
        XCTAssertEqual(try Data(contentsOf: vault.location(of: savedPath.rawValue)), picture, "The picture's own data is the file.")
        XCTAssertEqual(workspace.selection, savedPath, "It opens, as a new notebook and a scan do.")
    }

    func testTwoPicturesOfTheSameMinuteKeepBothFiles() async throws {
        let (workspace, vault) = try await makeWorkspace()
        let picture = try pngData()
        await workspace.createPicture(picture, takenAt: takenAt, in: .root)
        await workspace.createPicture(picture, takenAt: takenAt, in: .root)
        let names = try FileManager.default.contentsOfDirectory(atPath: vault.root.path).filter { $0.hasPrefix("Photo ") }
        XCTAssertEqual(names.count, 2)
    }

    func testSomethingThatIsNotAPictureSavesNothingAndSaysSo() async throws {
        let (workspace, vault) = try await makeWorkspace()
        await workspace.createPicture(Data("not a picture".utf8), takenAt: takenAt, in: .root)
        XCTAssertNotNil(workspace.errorMessage)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: vault.root.path).filter { $0.hasPrefix("Photo ") }.isEmpty)
    }
}

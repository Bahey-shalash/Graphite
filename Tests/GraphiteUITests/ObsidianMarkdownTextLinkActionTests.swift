import XCTest
import SwiftUI
import GraphiteCore
@testable import GraphiteUI

/// The links of rendered Markdown that name files: in reading view a file link reaches the
/// vault's files only by a vault path, never a path elsewhere on the disk. Each test taps a
/// file address an attacking note could contain and records what is passed on to Graphite.
@MainActor
final class ObsidianMarkdownTextLinkActionTests: XCTestCase {
    private var container: URL!
    private var vault: URL!
    private var outsideFolder: URL!
    private var navigations: [(target: String, isWiki: Bool)] = []

    override func setUpWithError() throws {
        container = FileManager.default.temporaryDirectory.appendingPathComponent("ReadingLinks-\(UUID().uuidString)", isDirectory: true).resolvingSymlinksInPath()
        vault = container.appendingPathComponent("Vault", isDirectory: true)
        outsideFolder = container.appendingPathComponent("Vault-Neighbour", isDirectory: true)
        try FileManager.default.createDirectory(at: vault.appendingPathComponent("Folder"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outsideFolder, withIntermediateDirectories: true)
        try Data("outside".utf8).write(to: outsideFolder.appendingPathComponent("secret.png"))
        try Data("inside".utf8).write(to: vault.appendingPathComponent("Folder/Image.png"))
        try FileManager.default.createSymbolicLink(at: vault.appendingPathComponent("FolderLink"), withDestinationURL: outsideFolder)
        navigations = []
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: container)
    }

    private func tap(_ address: URL) {
        let action = ObsidianMarkdownText.linkAction(root: vault, navigate: { [self] target, isWiki in navigations.append((target, isWiki)) }, scrollToHeading: nil)
        action(address)
    }

    func testAFileLinkInsideTheVaultOpensTheFileByItsVaultPath() {
        tap(vault.appendingPathComponent("Folder/Image.png"))
        XCTAssertEqual(navigations.map(\.target), ["Folder/Image.png"])
        XCTAssertEqual(navigations.map(\.isWiki), [true])
    }

    func testAFileLinkKeepsItsFragmentAfterTheVaultPath() throws {
        let address = try XCTUnwrap(URL(string: vault.appendingPathComponent("Folder/Image.png").absoluteString + "#Heading"))
        tap(address)
        XCTAssertEqual(navigations.map(\.target), ["Folder/Image.png#Heading"])
    }

    func testAFileLinkOutsideTheVaultOpensNothing() throws {
        let climbing = try XCTUnwrap(URL(string: vault.absoluteString + "../Vault-Neighbour/secret.png"))
        let addresses = [
            climbing,
            outsideFolder.appendingPathComponent("secret.png"),
            URL(fileURLWithPath: "/etc/hosts"),
            URL(fileURLWithPath: vault.path + "-Neighbour/secret.png"),
            URL(fileURLWithPath: "/"),
        ]
        for address in addresses {
            tap(address)
        }
        XCTAssertTrue(navigations.isEmpty, "\(navigations)")
    }

    func testAFileLinkThroughASymbolicLinkOutOfTheVaultReachesOnlyTheVaultPathWhichTheVaultRefuses() throws {
        tap(vault.appendingPathComponent("FolderLink/secret.png"))
        XCTAssertEqual(navigations.map(\.target), ["FolderLink/secret.png"], "Graphite is given the path inside the vault, never the path the link leads to.")
        let target = try VaultPath(try XCTUnwrap(navigations.first).target)
        XCTAssertThrowsError(try target.url(in: vault)) { error in
            XCTAssertEqual(error as? GraphiteError, .outsideVault)
        }
    }
}

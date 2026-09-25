import XCTest
@testable import GraphiteCore

final class VaultListTests: XCTestCase {
    private let physicsLocation = VaultLocation(anchor: .bookmark(Data("physics".utf8)))
    private let physicsPath = "/Users/student/Documents/Physics"

    func testPickingTheSameFolderAgainUpdatesItsEntry() throws {
        var list = VaultList()
        let firstIdentifier = list.recordOpening(name: "Physics", location: physicsLocation, path: physicsPath, at: Date(timeIntervalSince1970: 10))
        let refreshedLocation = VaultLocation(anchor: .bookmark(Data("fresh bookmark".utf8)))
        let secondIdentifier = list.recordOpening(name: "Physics", location: refreshedLocation, path: physicsPath, at: Date(timeIntervalSince1970: 20))
        XCTAssertEqual(firstIdentifier, secondIdentifier)
        XCTAssertEqual(list.vaults.count, 1)
        XCTAssertEqual(list.vaults.first?.location, refreshedLocation)
        XCTAssertEqual(list.vaults.first?.lastOpenedDate, Date(timeIntervalSince1970: 20))
    }

    func testTellsAVaultsIdentifierBeforeRecordingIt() throws {
        var list = VaultList()
        XCTAssertNil(list.existingIdentifier(location: physicsLocation, path: physicsPath))
        let newIdentifier = UUID()
        XCTAssertEqual(list.recordOpening(identifier: newIdentifier, name: "Physics", location: physicsLocation, path: physicsPath, at: .now), newIdentifier,
                       "A new vault keeps the identifier chosen for it.")
        XCTAssertEqual(list.existingIdentifier(location: VaultLocation(anchor: .bookmark(Data("other".utf8))), path: physicsPath), newIdentifier)
        XCTAssertEqual(list.existingIdentifier(identifier: newIdentifier, location: physicsLocation, path: "/Elsewhere"), newIdentifier)
        XCTAssertEqual(list.vaults.count, 1)
    }

    func testReopeningByIdentifierFollowsAMovedFolder() throws {
        var list = VaultList()
        let identifier = list.recordOpening(name: "Physics", location: physicsLocation, path: physicsPath, at: .now)
        list.recordOpening(identifier: identifier, name: "Physics 2026", location: physicsLocation, path: "/Users/student/Archive/Physics 2026", at: .now)
        XCTAssertEqual(list.vaults.count, 1)
        XCTAssertEqual(list.vault(withIdentifier: identifier)?.name, "Physics 2026")
        XCTAssertEqual(list.vault(withIdentifier: identifier)?.lastKnownPath, "/Users/student/Archive/Physics 2026")
    }

    func testVaultsSortByNameAndRestoreTheMostRecent() throws {
        var list = VaultList()
        list.recordOpening(name: "physics", location: physicsLocation, path: physicsPath, at: Date(timeIntervalSince1970: 30))
        list.recordOpening(name: "Chemistry", location: VaultLocation(anchor: .applicationDocuments, relativePath: "Chemistry"), path: "/container/Documents/Chemistry", at: Date(timeIntervalSince1970: 50))
        list.recordOpening(name: "Biology 10", location: VaultLocation(anchor: .bookmark(Data("b10".utf8))), path: "/b10", at: Date(timeIntervalSince1970: 40))
        list.recordOpening(name: "Biology 9", location: VaultLocation(anchor: .bookmark(Data("b9".utf8))), path: "/b9", at: Date(timeIntervalSince1970: 20))
        XCTAssertEqual(list.sortedByName.map(\.name), ["Biology 9", "Biology 10", "Chemistry", "physics"])
        XCTAssertEqual(list.mostRecentlyOpened?.name, "Chemistry")
    }

    func testLastDocumentAndRemovalAreStoredWithTheList() throws {
        var list = VaultList()
        let identifier = list.recordOpening(name: "Physics", location: physicsLocation, path: physicsPath, at: .now)
        list.setLastOpenedDocument(try VaultPath("Lectures/Optics.md"), inVault: identifier)
        let decoded = try JSONDecoder().decode(VaultList.self, from: JSONEncoder().encode(list))
        XCTAssertEqual(decoded, list)
        XCTAssertEqual(decoded.vault(withIdentifier: identifier)?.lastOpenedDocument, try VaultPath("Lectures/Optics.md"))
        list.remove(identifier)
        XCTAssertTrue(list.vaults.isEmpty)
    }

    func testNewVaultNamesMustBeOrdinaryVisibleFolderNames() throws {
        XCTAssertEqual(try VaultList.validatedFolderName("  Physics 2026 "), "Physics 2026")
        for invalidName in ["", "   ", ".hidden", "Physics/Optics", "Physics:Optics", "Line\nbreak"] {
            XCTAssertThrowsError(try VaultList.validatedFolderName(invalidName), invalidName)
        }
    }

    func testLocationsReadAsTheFilesApp() throws {
        func vault(at path: String, location: VaultLocation? = nil) -> KnownVault {
            KnownVault(id: UUID(), name: (path as NSString).lastPathComponent, location: location ?? physicsLocation, lastKnownPath: path, lastOpenedDate: .now)
        }
        XCTAssertEqual(VaultList.readableLocation(of: vault(at: "/private/var/mobile/Library/Mobile Documents/iCloud~md~obsidian/Documents/Physics"), deviceName: "iPad"), "iCloud Drive › Obsidian")
        XCTAssertEqual(VaultList.readableLocation(of: vault(at: "/private/var/mobile/Library/Mobile Documents/com~apple~CloudDocs/School/Physics"), deviceName: "iPad"), "iCloud Drive › School")
        XCTAssertEqual(VaultList.readableLocation(of: vault(at: "/private/var/mobile/Containers/Shared/AppGroup/1234/File Provider Storage/Physics"), deviceName: "iPad"), "Files")
        XCTAssertEqual(VaultList.readableLocation(of: vault(at: "/private/var/mobile/Containers/Shared/AppGroup/1234/File Provider Storage/Repositories/Physics"), deviceName: "iPad"), "Files › Repositories")
        XCTAssertEqual(VaultList.readableLocation(of: vault(at: "/var/mobile/Containers/Data/Application/5678/Documents/Physics", location: VaultLocation(anchor: .applicationDocuments, relativePath: "Physics")), deviceName: "iPhone"), "On My iPhone › Graphite")
        XCTAssertEqual(VaultList.readableLocation(of: vault(at: "/Volumes/Studies/Physics"), deviceName: "Mac"), "/Volumes/Studies")
    }
}

import XCTest
import GraphiteCore
@testable import GraphiteUI

/// Where each vault's documents were left, read from the device once and written only on change.
@MainActor
final class DocumentPlaceStoreTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() async throws {
        suiteName = "DocumentPlaceStoreTests-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func memory(withNoteAtLine topLocation: Int) throws -> DocumentPlaceMemory {
        var memory = DocumentPlaceMemory()
        memory.remember(.note(NotePlace(topLocation: topLocation, selectionLocation: topLocation, selectionLength: 0)),
                        of: try VaultPath("Lecture.md"), at: Date(timeIntervalSince1970: 100))
        return memory
    }

    private func storedMemory(forVault vaultIdentifier: UUID) -> DocumentPlaceMemory? {
        defaults.data(forKey: WorkspaceModel.placesKey(for: vaultIdentifier))
            .flatMap { storedPlaces in try? JSONDecoder().decode(DocumentPlaceMemory.self, from: storedPlaces) }
    }

    func testAVaultsPlacesAreReadOnceAndKeptInMemory() throws {
        let vault = UUID()
        let saved = try memory(withNoteAtLine: 400)
        defaults.set(try JSONEncoder().encode(saved), forKey: WorkspaceModel.placesKey(for: vault))
        let store = DocumentPlaceStore(defaults: defaults)
        XCTAssertEqual(store.memory(forVault: vault), saved)
        // Read once: what is stored later is not decoded again on every access.
        defaults.set(try JSONEncoder().encode(try memory(withNoteAtLine: 900)), forKey: WorkspaceModel.placesKey(for: vault))
        XCTAssertEqual(store.memory(forVault: vault), saved)
        XCTAssertEqual(store.memory(forVault: UUID()), DocumentPlaceMemory(), "Another vault starts with no places.")
    }

    func testPlacesAreWrittenOnlyWhenTheyChange() throws {
        let vault = UUID()
        let store = DocumentPlaceStore(defaults: defaults)
        let changed = try memory(withNoteAtLine: 1_200)
        store.update(changed, forVault: vault)
        XCTAssertEqual(storedMemory(forVault: vault), changed)
        XCTAssertEqual(store.memory(forVault: vault), changed)

        // The same places again are not written: a marker left in their place stays.
        let marker = Data("unchanged".utf8)
        defaults.set(marker, forKey: WorkspaceModel.placesKey(for: vault))
        store.update(changed, forVault: vault)
        XCTAssertEqual(defaults.data(forKey: WorkspaceModel.placesKey(for: vault)), marker)

        // Damaged places read as none, and a new place replaces them.
        let damagedVault = UUID()
        defaults.set(Data("not JSON".utf8), forKey: WorkspaceModel.placesKey(for: damagedVault))
        XCTAssertEqual(store.memory(forVault: damagedVault), DocumentPlaceMemory())
        store.update(changed, forVault: damagedVault)
        XCTAssertEqual(storedMemory(forVault: damagedVault), changed)
    }

    func testForgettingAVaultRemovesItsPlacesInMemoryAndOnTheDevice() throws {
        let vault = UUID()
        let store = DocumentPlaceStore(defaults: defaults)
        store.update(try memory(withNoteAtLine: 300), forVault: vault)
        store.forgetVault(vault)
        XCTAssertNil(defaults.data(forKey: WorkspaceModel.placesKey(for: vault)))
        XCTAssertEqual(store.memory(forVault: vault), DocumentPlaceMemory())
    }
}

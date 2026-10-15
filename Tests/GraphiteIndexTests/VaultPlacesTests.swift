import XCTest
import GraphiteCore
@testable import GraphiteIndex

/// The notes the map view places, read from the index.
final class VaultPlacesTests: XCTestCase {
    private var vault: URL!
    private var index: VaultIndex!

    override func setUp() async throws {
        vault = FileManager.default.temporaryDirectory.appendingPathComponent("PlacesVault-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault.appendingPathComponent("Travel"), withIntermediateDirectories: true)
        index = try VaultIndex(databaseURL: vault.appendingPathExtension("cache").appendingPathComponent("index.sqlite"))
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: vault)
        try? FileManager.default.removeItem(at: vault.appendingPathExtension("cache"))
    }

    private func write(_ text: String, to relativePath: String) throws {
        try Data(text.utf8).write(to: vault.appendingPathComponent(relativePath))
    }

    func testCoordinatesAndLocationPlaceNotesAndOtherValuesDoNot() async throws {
        try write("---\ncoordinates: [48.8566, 2.3522]\n---\n# Paris\n", to: "Travel/Paris.md")
        try write("---\nlocation: \"46.5197, 6.6323\"\n---\n# Lausanne\n", to: "Travel/Lausanne.md")
        try write("---\nlocation:\n  - \"40.7128\"\n  - \"-74.0060\"\n---\n# New York\n", to: "Travel/New York.md")
        // Both properties: `coordinates` is read first, as Bases reads it.
        try write("---\nlocation: [0, 0]\ncoordinates: [35.6762, 139.6503]\n---\n# Tokyo\n", to: "Travel/Tokyo.md")
        // Not coordinates: an address, a city as a mapping, decimal commas, a latitude past 90.
        try write("---\nlocation: 10 Downing Street, London\n---\n", to: "Travel/Address.md")
        try write("---\nlocation:\n  city: Lausanne\n---\n", to: "Travel/City.md")
        try write("---\ncoordinates: \"48,85, 2,35\"\n---\n", to: "Travel/Decimal commas.md")
        try write("---\ncoordinates: [95, 10]\n---\n", to: "Travel/Too far north.md")
        try write("# No properties\n", to: "Plain.md")
        _ = try await index.reconcile(root: vault)

        let places = try await index.placedNotes()
        let coordinatesByPath = Dictionary(uniqueKeysWithValues: places.map { place in (place.path.rawValue, place.coordinate) })

        XCTAssertEqual(Set(coordinatesByPath.keys), ["Travel/Paris.md", "Travel/Lausanne.md", "Travel/New York.md", "Travel/Tokyo.md"])
        XCTAssertEqual(coordinatesByPath["Travel/Paris.md"], BaseCoordinate(latitude: 48.8566, longitude: 2.3522))
        XCTAssertEqual(coordinatesByPath["Travel/Lausanne.md"], BaseCoordinate(latitude: 46.5197, longitude: 6.6323))
        XCTAssertEqual(coordinatesByPath["Travel/New York.md"], BaseCoordinate(latitude: 40.7128, longitude: -74.0060))
        XCTAssertEqual(coordinatesByPath["Travel/Tokyo.md"], BaseCoordinate(latitude: 35.6762, longitude: 139.6503))
    }

    func testAVaultsOwnPropertyPlacesNotesInTheFormsItsPluginWrites() async throws {
        // The owner's vault: Geocoding Properties writes `Coordonnées: lat,lng`, with or
        // without a space, and leaves the property empty when it found nothing.
        try write("---\nCoordonnées: 35.6459053,139.7002239\n---\n# 1LDK\n", to: "Travel/1LDK.md")
        try write("---\nCoordonnées: 43.64879055325513, -79.38156041948037\n---\n", to: "Travel/Toronto.md")
        try write("---\nCoordonnées:\n---\n", to: "Travel/Empty.md")
        _ = try await index.reconcile(root: vault)

        let places = try await index.placedNotes(propertyNames: ["Coordonnées", "coordinates", "location"])
        XCTAssertEqual(places.map(\.path.rawValue).sorted(), ["Travel/1LDK.md", "Travel/Toronto.md"])
        let defaultPlaces = try await index.placedNotes()
        XCTAssertTrue(defaultPlaces.isEmpty, "Without the vault's own property nothing is placed.")
    }

    func testAPlaceFollowsTheNoteWhenItsPropertyChangesOrGoesAway() async throws {
        try write("---\ncoordinates: [48.8566, 2.3522]\n---\n", to: "Travel/Paris.md")
        _ = try await index.reconcile(root: vault)
        let firstPlaces = try await index.placedNotes()
        XCTAssertEqual(firstPlaces.map(\.coordinate), [try XCTUnwrap(BaseCoordinate(latitude: 48.8566, longitude: 2.3522))])

        try write("---\ncoordinates: [43.2965, 5.3698]\n---\n", to: "Travel/Paris.md")
        _ = try await index.reconcile(root: vault)
        let movedPlaces = try await index.placedNotes()
        XCTAssertEqual(movedPlaces.map(\.coordinate), [try XCTUnwrap(BaseCoordinate(latitude: 43.2965, longitude: 5.3698))])

        try write("# Paris, without a place\n", to: "Travel/Paris.md")
        _ = try await index.reconcile(root: vault)
        let remainingPlaces = try await index.placedNotes()
        XCTAssertTrue(remainingPlaces.isEmpty)
    }
}

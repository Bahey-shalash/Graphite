import XCTest
@testable import GraphiteCore
import GraphiteTestSupport

/// The properties a vault places notes with, as its map plugins are set up.
final class PlacedNotePropertyNamesTests: XCTestCase {
    private var vault: URL!

    override func setUp() async throws {
        vault = try TemporaryVault.make(prefix: "PlacePropertiesVault", for: self).root
    }

    private func writeSettings(_ json: String, forPlugin identifier: String) throws {
        let folder = vault.appendingPathComponent(".obsidian/plugins/\(identifier)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(json.utf8).write(to: folder.appendingPathComponent("data.json"))
    }

    func testAVaultWithoutMapPluginsIsPlacedByCoordinatesAlone() {
        XCTAssertEqual(PlacedNote.propertyNames(vaultRoot: vault), ["coordinates"])
    }

    func testAnInstalledMapViewWithoutSettingsReadsItsDefaultLocation() throws {
        let folder = vault.appendingPathComponent(".obsidian/plugins/obsidian-map-view", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(#"{"id":"obsidian-map-view"}"#.utf8).write(to: folder.appendingPathComponent("manifest.json"))
        XCTAssertEqual(PlacedNote.propertyNames(vaultRoot: vault), ["location", "coordinates"])
    }

    func testThePropertiesThePluginsAreSetToUseComeFirst() throws {
        // As in the owner's vault: Geocoding Properties writes coordinates into `Coordonnées`.
        try writeSettings(#"{"properties":{"address":{"frontmatterKey":"Adresse","enabled":true},"location":{"frontmatterKey":"Coordonnées","enabled":true}}}"#,
                          forPlugin: "geocoding-properties")
        try writeSettings(#"{"frontMatterKey":"geo"}"#, forPlugin: "obsidian-map-view")
        XCTAssertEqual(PlacedNote.propertyNames(vaultRoot: vault), ["Coordonnées", "geo", "coordinates"])
    }

    func testATurnedOffPropertyAndRepeatedNamesAreLeftOut() throws {
        try writeSettings(#"{"properties":{"location":{"frontmatterKey":"Coordonnées","enabled":false}}}"#, forPlugin: "geocoding-properties")
        try writeSettings(#"{"frontMatterKey":"Location"}"#, forPlugin: "obsidian-map-view")
        XCTAssertEqual(PlacedNote.propertyNames(vaultRoot: vault), ["Location", "coordinates"])
    }

    func testUnreadableOrOversizedSettingsAreIgnored() throws {
        try writeSettings("not JSON", forPlugin: "geocoding-properties")
        let oversized = String(repeating: " ", count: PlacedNote.maximumSettingsBytes) + #"{"frontMatterKey":"geo"}"#
        try writeSettings(oversized, forPlugin: "obsidian-map-view")
        // Map View is installed, so its default stands in for the setting that was not read.
        XCTAssertEqual(PlacedNote.propertyNames(vaultRoot: vault), ["location", "coordinates"])
    }
}

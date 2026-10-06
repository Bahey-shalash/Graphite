import XCTest
@testable import GraphiteCore

/// A map view's `mapTiles` and `mapTilesDark`, read as the Maps plugin reads them, and
/// the tile addresses filled in as MapLibre fills them.
final class CoreBasesMapTilesTests: XCTestCase {
    private func mapOptions(_ viewOptions: String) throws -> BaseMapOptions {
        try BaseDefinition.parse("views:\n  - type: map\n    name: Map\n" + viewOptions).views[0].map
    }

    private let openStreetMap = "https://tile.openstreetmap.org/{z}/{x}/{y}.png"

    // MARK: What the settings mean

    func testNoTilesMeansThePluginsDefaultMap() throws {
        XCTAssertNil(try mapOptions("").background(isDark: false))
        XCTAssertNil(try mapOptions("    mapTiles: []\n").background(isDark: false))
        XCTAssertNil(try mapOptions("    mapTiles: \"  \"\n").background(isDark: false))
        XCTAssertNil(try mapOptions("    mapTilesDark: [\"https://dark.example/{z}/{x}/{y}.png\"]\n").background(isDark: true),
                     "The plugin reads dark tiles only together with mapTiles.")
    }

    func testTileTemplatesAreRasterTilesDrawnInOrder() throws {
        let options = try mapOptions("    mapTiles:\n      - \(openStreetMap)\n      - https://overlay.example/{z}/{x}/{y}.png\n")
        XCTAssertEqual(options.background(isDark: false), .rasterTiles([try XCTUnwrap(BaseMapTileTemplate(openStreetMap)),
                                                                        try XCTUnwrap(BaseMapTileTemplate("https://overlay.example/{z}/{x}/{y}.png"))]))
        XCTAssertEqual(try mapOptions("    mapTiles: \"  \(openStreetMap)  \"\n").background(isDark: false),
                       .rasterTiles([try XCTUnwrap(BaseMapTileTemplate(openStreetMap))]), "One text is one template, trimmed as the plugin trims it.")
    }

    func testDarkTilesApplyInDarkModeOnly() throws {
        let options = try mapOptions("    mapTiles: [\"\(openStreetMap)\"]\n    mapTilesDark: [\"https://dark.example/{z}/{x}/{y}.png\"]\n")
        XCTAssertEqual(options.background(isDark: false), .rasterTiles([try XCTUnwrap(BaseMapTileTemplate(openStreetMap))]))
        XCTAssertEqual(options.background(isDark: true), .rasterTiles([try XCTUnwrap(BaseMapTileTemplate("https://dark.example/{z}/{x}/{y}.png"))]))
        XCTAssertEqual(try mapOptions("    mapTiles: [\"\(openStreetMap)\"]\n").background(isDark: true),
                       .rasterTiles([try XCTUnwrap(BaseMapTileTemplate(openStreetMap))]), "Without dark tiles the light ones are used.")
    }

    func testOneAddressWithoutPlaceholdersIsAStyle() throws {
        XCTAssertEqual(try mapOptions("    mapTiles: https://tiles.openfreemap.org/styles/liberty\n").background(isDark: false),
                       .style("https://tiles.openfreemap.org/styles/liberty"))
        XCTAssertEqual(try mapOptions("    mapTiles: [\"https://api.maptiler.com/maps/streets/style.json?key=abc\"]\n").background(isDark: false),
                       .style("https://api.maptiler.com/maps/streets/style.json?key=abc"))
    }

    func testAddressesGraphiteDoesNotFetchAreReported() throws {
        for urlText in ["file:///Users/someone/tiles/{z}/{x}/{y}.png", "tiles/{z}/{x}/{y}.png", "https://{s}.tile.example/{z}/{x}/{y}.png",
                        "ftp://tiles.example/{z}/{x}/{y}.png", "javascript:alert(1)//{z}", "https:///{z}/{x}/{y}.png", "obsidian://{z}/{x}/{y}"] {
            let options = try mapOptions("    mapTiles: [\"\(urlText)\"]\n")
            XCTAssertEqual(options.background(isDark: false), .unusableTiles([urlText]), urlText)
            XCTAssertNil(BaseMapTileTemplate(urlText), urlText)
        }
        let mixed = try mapOptions("    mapTiles: [\"\(openStreetMap)\", \"file:///tiles/{z}/{x}/{y}.png\"]\n")
        XCTAssertEqual(mixed.background(isDark: false), .unusableTiles(["file:///tiles/{z}/{x}/{y}.png"]), "One unusable layer is reported, not dropped.")
    }

    // MARK: Tile addresses

    func testTileAddressesAreFilledInAsMapLibreFillsThem() throws {
        let template = try XCTUnwrap(BaseMapTileTemplate(openStreetMap))
        XCTAssertEqual(template.url(column: 4_402, row: 2_870, zoom: 13, scale: 1)?.absoluteString, "https://tile.openstreetmap.org/13/4402/2870.png")
        let retina = try XCTUnwrap(BaseMapTileTemplate("https://tiles.example/{z}/{x}/{y}{ratio}.png?key=a%20b"))
        XCTAssertEqual(retina.url(column: 1, row: 2, zoom: 3, scale: 2)?.absoluteString, "https://tiles.example/3/1/2@2x.png?key=a%20b")
        XCTAssertEqual(retina.url(column: 1, row: 2, zoom: 3, scale: 1)?.absoluteString, "https://tiles.example/3/1/2.png?key=a%20b")
    }

    func testQuadkeyPrefixAndBoundingBoxPlaceholders() throws {
        let bing = try XCTUnwrap(BaseMapTileTemplate("https://ecn.example/tiles/a{quadkey}.jpeg"))
        XCTAssertEqual(bing.url(column: 3, row: 5, zoom: 3, scale: 1)?.absoluteString, "https://ecn.example/tiles/a213.jpeg")
        XCTAssertEqual(bing.url(column: 0, row: 0, zoom: 0, scale: 1)?.absoluteString, "https://ecn.example/tiles/a.jpeg")
        let prefixed = try XCTUnwrap(BaseMapTileTemplate("https://{prefix}.tiles.example/{z}/{x}/{y}.png"))
        XCTAssertEqual(prefixed.url(column: 17, row: 44, zoom: 6, scale: 1)?.absoluteString, "https://1c.tiles.example/6/17/44.png")
        let wms = try XCTUnwrap(BaseMapTileTemplate("https://wms.example/wms?bbox={bbox-epsg-3857}&width=256"))
        XCTAssertEqual(wms.url(column: 0, row: 0, zoom: 0, scale: 1)?.absoluteString,
                       "https://wms.example/wms?bbox=-20037508.342789244,-20037508.342789244,20037508.342789244,20037508.342789244&width=256")
        XCTAssertEqual(wms.url(column: 1, row: 0, zoom: 1, scale: 1)?.absoluteString, "https://wms.example/wms?bbox=0,0,20037508.342789244,20037508.342789244&width=256")
    }

    func testATemplateThatDoesNotMakeAnAddressGivesNone() throws {
        let template = try XCTUnwrap(BaseMapTileTemplate("https://tiles.example/{z}/{x}/{y}.png"))
        XCTAssertNotNil(template.url(column: -1, row: -1, zoom: 0, scale: 1), "Negative numbers still form an address; MapKit never asks for them.")
        let spaced = try XCTUnwrap(BaseMapTileTemplate("https://tiles.example/{z} {x}/{y}.png"))
        XCTAssertEqual(spaced.url(column: 1, row: 2, zoom: 3, scale: 1)?.absoluteString, "https://tiles.example/3%201/2.png", "A space is escaped, as a browser escapes it.")
        XCTAssertNil(BaseMapTileTemplate("not a web address {z}/{x}/{y}"))
    }
}

import Foundation

/// The background a map view's `mapTiles` (and `mapTilesDark`) names, read as the Maps
/// plugin reads it. The plugin draws with MapLibre, which takes raster tile URL templates
/// and MapLibre style URLs. MapKit draws raster tiles only, so a style (vector tiles, or
/// a style made of TileJSON sources) is reported rather than drawn.
public enum BaseMapBackground: Hashable, Sendable {
    /// Raster tiles from these templates, 256 points square, drawn bottom to top.
    case rasterTiles([BaseMapTileTemplate])
    /// A MapLibre style: one URL without tile placeholders.
    case style(String)
    /// Tile URLs Graphite does not fetch: not a web address, or with a placeholder
    /// MapLibre does not fill in either.
    case unusableTiles([String])
}

extension BaseMapOptions {
    /// The background for the light or dark appearance, or nil for the plugin's default
    /// map, which Graphite shows as Apple Maps. As in the plugin, `mapTilesDark` applies
    /// in dark mode when it is set, and only together with `mapTiles`.
    public func background(isDark: Bool) -> BaseMapBackground? {
        guard !tileURLs.isEmpty else { return nil }
        let urlTexts = isDark && !darkTileURLs.isEmpty ? darkTileURLs : tileURLs
        if urlTexts.count == 1, let onlyURLText = urlTexts.first, !BaseMapTileTemplate.hasTilePlaceholder(onlyURLText) { return .style(onlyURLText) }
        let templates = urlTexts.compactMap(BaseMapTileTemplate.init)
        guard templates.count == urlTexts.count else { return .unusableTiles(urlTexts.filter { urlText in BaseMapTileTemplate(urlText) == nil }) }
        return .rasterTiles(templates)
    }
}

/// A raster tile URL template such as `https://tile.openstreetmap.org/{z}/{x}/{y}.png`,
/// filled in the way MapLibre fills it: `{z}`, `{x}` and `{y}` for the tile, `{ratio}`
/// (`@2x` on a Retina screen), `{quadkey}`, `{prefix}` and `{bbox-epsg-3857}`.
///
/// Only `https` and `http` addresses are templates, so a base never makes the map read a
/// local file or open another app.
public struct BaseMapTileTemplate: Hashable, Sendable {
    public let template: String

    private static let placeholders = ["{z}", "{x}", "{y}", "{ratio}", "{quadkey}", "{prefix}", "{bbox-epsg-3857}"]
    private static let webSchemes: Set<String> = ["https", "http"]
    /// Web Mercator's half circumference in meters, the extent of `{bbox-epsg-3857}`.
    private static let webMercatorHalfExtent = 20_037_508.342_789_244

    /// Nil for text that is not a web address, or that holds a placeholder MapLibre does
    /// not fill in (such as Leaflet's `{s}`), which would be requested as it is written.
    public init?(_ text: String) {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var remainder = trimmedText
        for placeholder in Self.placeholders { remainder = remainder.replacingOccurrences(of: placeholder, with: "0") }
        guard !remainder.contains("{"), !remainder.contains("}"), let sampleURL = URL(string: remainder),
              let scheme = sampleURL.scheme?.lowercased(), Self.webSchemes.contains(scheme), sampleURL.host?.isEmpty == false else { return nil }
        template = trimmedText
    }

    /// Whether the text names tiles rather than a style, as the plugin decides.
    static func hasTilePlaceholder(_ text: String) -> Bool {
        text.contains("{z}") || text.contains("{x}") || text.contains("{y}")
    }

    /// The address of one tile.
    /// - Parameters:
    ///   - column: The tile's column (`{x}`), from the antimeridian eastward.
    ///   - row: The tile's row (`{y}`), from the north.
    ///   - zoom: The zoom level (`{z}`), 0 for the whole world in one tile.
    ///   - scale: The screen's scale; 2 or more asks `{ratio}` for `@2x` tiles.
    public func url(column: Int, row: Int, zoom: Int, scale: Double) -> URL? {
        var urlText = template
        if urlText.contains("{prefix}") { urlText = urlText.replacingOccurrences(of: "{prefix}", with: String(column % 16, radix: 16) + String(row % 16, radix: 16)) }
        urlText = urlText.replacingOccurrences(of: "{z}", with: String(zoom))
            .replacingOccurrences(of: "{x}", with: String(column))
            .replacingOccurrences(of: "{y}", with: String(row))
            .replacingOccurrences(of: "{ratio}", with: scale > 1 ? "@2x" : "")
        if urlText.contains("{quadkey}") { urlText = urlText.replacingOccurrences(of: "{quadkey}", with: Self.quadkey(column: column, row: row, zoom: zoom)) }
        if urlText.contains("{bbox-epsg-3857}") { urlText = urlText.replacingOccurrences(of: "{bbox-epsg-3857}", with: Self.boundingBox(column: column, row: row, zoom: zoom)) }
        guard let url = URL(string: urlText), let scheme = url.scheme?.lowercased(), Self.webSchemes.contains(scheme) else { return nil }
        return url
    }

    /// Bing's tile key: one digit per zoom level, from the tile's column and row bits.
    private static func quadkey(column: Int, row: Int, zoom: Int) -> String {
        guard zoom > 0 else { return "" }
        return String((1...zoom).reversed().map { level in
            let mask = 1 << (level - 1)
            let digit = (column & mask != 0 ? 1 : 0) + (row & mask != 0 ? 2 : 0)
            return Character(String(digit))
        })
    }

    /// The tile's extent in Web Mercator meters, `west,south,east,north`, as WMS servers
    /// take it, with numbers written as JavaScript writes them.
    private static func boundingBox(column: Int, row: Int, zoom: Int) -> String {
        let tileExtent = 2 * webMercatorHalfExtent / pow(2, Double(zoom))
        let west = -webMercatorHalfExtent + Double(column) * tileExtent
        let north = webMercatorHalfExtent - Double(row) * tileExtent
        return [west, north - tileExtent, west + tileExtent, north].map(BaseValue.formatted).joined(separator: ",")
    }
}

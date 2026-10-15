import Foundation

/// A note placed on the map by one of its properties.
public struct PlacedNote: Hashable, Sendable, Identifiable {
    public let path: VaultPath
    public let coordinate: BaseCoordinate
    public var id: VaultPath { path }

    public init(path: VaultPath, coordinate: BaseCoordinate) {
        self.path = path
        self.coordinate = coordinate
    }

    /// The properties that place a note, in the order they are read: `coordinates`, which
    /// Bases' map view and Obsidian's Maps plugin read, then `location`, which the Map View
    /// community plugin writes. Both hold `[lat, lng]` or `"lat, lng"`.
    public static let propertyNames = ["coordinates", "location"]

    /// The place a note's properties give, or nil. The first property that reads as a
    /// coordinate wins; a value that is not one, such as an address or a city written as
    /// text, places nothing rather than being guessed at.
    public static func coordinate(in properties: [BaseFrontmatterEntry], source: VaultPath, calendar: Calendar = .current) -> BaseCoordinate? {
        for name in propertyNames {
            for entry in properties where entry.key.caseInsensitiveCompare(name) == .orderedSame {
                let value = BaseFrontmatter.value(of: entry.node, declaredType: nil, source: source, calendar: calendar)
                if let coordinate = BaseCoordinate(value: value) { return coordinate }
            }
        }
        return nil
    }
}

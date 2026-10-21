import Foundation

/// The constant patterns of `BaseDurationParsing`; `StaticPatternTests` compiles every case.
enum BaseDurationParsingPattern: String, StaticPatternSet {
    case partPattern = #"\s*([+-]?\d+(?:\.\d+)?)\s*([A-Za-z]+)\s*,?"#
    case isoPattern = #"^([+-])?P(?:(\d+(?:\.\d+)?)Y)?(?:(\d+(?:\.\d+)?)M)?(?:(\d+(?:\.\d+)?)W)?(?:(\d+(?:\.\d+)?)D)?(?:(T)(?:(\d+(?:\.\d+)?)H)?(?:(\d+(?:\.\d+)?)M)?(?:(\d+(?:\.\d+)?)S)?)?$"#
}

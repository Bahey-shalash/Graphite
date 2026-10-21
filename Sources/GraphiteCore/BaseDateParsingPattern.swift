import Foundation

/// The constant patterns of `BaseDateParsing`; `StaticPatternTests` compiles every case.
enum BaseDateParsingPattern: String, StaticPatternSet {
    case datePattern = #"^(\d{4})-(\d{1,2})-(\d{1,2})(?:[T ](\d{1,2}):(\d{2})(?::(\d{2})(?:\.(\d+))?)?)?\s*(Z|[+-]\d{2}(?::?\d{2})?)?$"#
}

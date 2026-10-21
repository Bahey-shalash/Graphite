import Foundation

/// The constant patterns of `BaseQueryEngine`; `StaticPatternTests` compiles every case.
enum BaseQueryEnginePattern: String, StaticPatternSet {
    case hexColorPattern = #"^#([0-9a-fA-F]{3}|[0-9a-fA-F]{4}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})\z"#
}

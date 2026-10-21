import Foundation

/// The regular expressions written in Graphite's source, grouped by the type that owns them.
/// Each pattern is a case whose raw value is the pattern text, so one test compiles every
/// case of every set (`StaticPatternTests`), and a malformed pattern never ships.
public protocol StaticPatternSet: CaseIterable, Sendable, RawRepresentable where RawValue == String {
    /// The options of a case; none unless the set says otherwise.
    var options: NSRegularExpression.Options { get }
}

public extension StaticPatternSet {
    var options: NSRegularExpression.Options { [] }

    /// The compiled pattern. Keep it in a `static let`, so it compiles once, on first use.
    /// A pattern that does not compile is a programming error and stops here.
    func compiled() -> NSRegularExpression {
        do { return try NSRegularExpression(pattern: rawValue, options: options) }
        catch { preconditionFailure("The pattern \(Self.self).\(self) does not compile: \(error)") }
    }
}

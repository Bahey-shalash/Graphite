import Foundation

/// Values by string key, the keys in the order first written. A key written again keeps its first place and takes the
/// later value, as property lists, keyed archives and Goodnotes layers resolve a key or element written twice.
public struct KeyOrderedDictionary<Value: Sendable>: Sendable {
    public private(set) var keys: [String] = []
    private var valuesByKey: [String: Value] = [:]

    public init() {}

    public subscript(key: String) -> Value? { valuesByKey[key] }

    public mutating func setValue(_ value: Value, named key: String) {
        if valuesByKey.updateValue(value, forKey: key) == nil { keys.append(key) }
    }

    /// Every key with its value, in key order.
    public var entries: [(key: String, value: Value)] {
        keys.compactMap { key in valuesByKey[key].map { value in (key, value) } }
    }
}

extension KeyOrderedDictionary: Equatable where Value: Equatable {}

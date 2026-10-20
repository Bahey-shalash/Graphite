import Foundation

/// Where a value of a keyed archive is stored: the property list object that a key, an array member or `$top` names.
/// The object is often a UID, which `KeyedArchive.value(of:)` follows to the member of `$objects` it names.
public struct KeyedArchiveReference: Hashable, Sendable {
    public let objectIndex: Int
}

/// A value of a keyed archive, resolved one level: an archived object's members stay references until asked for.
public enum KeyedArchiveValue: Equatable, Sendable {
    /// The `$null` string, which archives store for nil.
    case null
    case object(KeyedArchiveObject)
    /// A value stored as itself: a number, boolean, date, string or data, or a container without a class.
    case primitive(BinaryPropertyListObject, objectIndex: Int)

    /// The property list object the value was read from; nil for `null`.
    public var objectIndex: Int? {
        switch self {
        case .null: nil
        case .object(let object): object.objectIndex
        case .primitive(_, let objectIndex): objectIndex
        }
    }
}

/// An archived object: a dictionary with a `$class`, its class name and keys decoded and its values not.
public struct KeyedArchiveObject: Equatable, Sendable {
    public let objectIndex: Int
    public let className: String
    /// The object's own keys, without `$class`.
    public let fields: KeyedArchiveFields
}

/// Keys and the references they name, of an archived object or of an archived `NSDictionary`; keys keep their file
/// order, and a key written twice names its later value.
public typealias KeyedArchiveFields = KeyOrderedDictionary<KeyedArchiveReference>

extension KeyOrderedDictionary where Value == KeyedArchiveReference {
    public func reference(named key: String) -> KeyedArchiveReference? { self[key] }

    mutating func setReference(_ reference: KeyedArchiveReference, named key: String) { setValue(reference, named: key) }
}

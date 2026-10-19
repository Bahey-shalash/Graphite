import Foundation

/// Why a keyed archive, or a value in it, could not be read.
public enum KeyedArchiveError: Error, Hashable, Sendable {
    case propertyList(BinaryPropertyListError)
    /// The top object is not a dictionary with `$archiver`, `$objects` and `$top`.
    case notKeyedArchive
    case archiverNotSupported(name: String)
    /// `$top` names neither `$0` nor `root`.
    case rootMissing
    /// A UID names a position past the end of `$objects`.
    case referenceOutOfRange(uid: Int, archivedObjectCount: Int)
    /// A chain of UIDs comes back to an object it already passed through.
    case referenceCycle(objectIndex: Int)
    /// A chain of UIDs is longer than the limit.
    case referenceChainTooLong(limit: Int)
    /// An archived object whose `$class` does not lead to a class description with a `$classname` string.
    case classNameMissing(objectIndex: Int)
    case keyMissing(key: String)
    case valueNotOfExpectedKind(expected: KeyedArchiveValueKind, objectIndex: Int?)
    /// A dictionary whose key is not a string, or an `NSDictionary` whose `NS.keys` and `NS.objects` differ in length.
    case dictionaryDamaged(objectIndex: Int)
}

/// What a typed accessor of `KeyedArchive` expected to find.
public enum KeyedArchiveValueKind: Hashable, Sendable {
    case object
    case string
    case integer
    case number
    case boolean
    case data
    case date
    case uuid
    case array
}

/// The `$archiver` names a keyed archive may carry: Foundation's, and the one Notability writes with the same layout.
public enum KeyedArchiverName: Hashable, Sendable {
    case nsKeyedArchiver
    case glKeyedArchiver

    init?(rawName: String) {
        switch rawName {
        case "NSKeyedArchiver": self = .nsKeyedArchiver
        case "GLKeyedArchiver": self = .glKeyedArchiver
        default: return nil
        }
    }
}

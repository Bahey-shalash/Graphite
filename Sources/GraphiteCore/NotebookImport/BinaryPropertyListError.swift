import Foundation

/// Why a binary property list, or one of its objects, could not be read.
public enum BinaryPropertyListError: Error, Hashable, Sendable {
    /// The bytes do not start with `bplist00`, or are too short to hold its header and trailer.
    case notBinaryPropertyList
    /// The trailer's integer sizes, object count or top object are impossible for a file of this size.
    case trailerDamaged
    /// The offset table does not fit between the objects and the trailer.
    case offsetTableOutsideFile
    case objectIndexOutOfRange(objectIndex: Int, objectCount: Int)
    /// The object's offset points outside the object area between the header and the offset table.
    case objectOffsetOutsideObjects(objectIndex: Int)
    /// The object's length or contents run past the end of the object area.
    case objectTruncated(objectIndex: Int)
    case objectMarkerUnknown(objectIndex: Int, marker: UInt8)
    /// An integer or UID whose value does not fit in 64 bits: none of the formats read needs one.
    case integerTooWide(objectIndex: Int, byteCount: Int)
    /// An ASCII string with a byte above 127, or a UTF-16 string with an unpaired surrogate.
    case stringNotDecodable(objectIndex: Int)
    case dictionaryKeyNotString(objectIndex: Int)
    /// A plain value nests arrays and dictionaries deeper than the limit.
    case nestingTooDeep(limit: Int)
    /// An array or dictionary contains itself, directly or through its members.
    case containerCycle(objectIndex: Int)
    /// A plain value would hold more values than the budget: shared members expanded too often.
    case valueCountOverBudget(budget: Int)
}

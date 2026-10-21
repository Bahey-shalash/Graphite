import Foundation

/// One object of a binary property list, decoded alone: containers name their members by object index, so reading
/// an object never reads another one.
public enum BinaryPropertyListObject: Equatable, Sendable {
    case null
    case boolean(Bool)
    case integer(Int64)
    /// A 4-byte real is widened to `Double` exactly.
    case real(Double)
    case date(secondsSince2001: Double)
    /// The bytes as a slice of the property list's own bytes, never copied.
    case data(ArraySlice<UInt8>)
    case string(String)
    /// A keyed archive's reference to the member of its `$objects` array at this position.
    case uid(Int)
    case array(memberIndices: [Int])
    /// A set or ordered set.
    case set(memberIndices: [Int])
    case dictionary(keyIndices: [Int], valueIndices: [Int])
}

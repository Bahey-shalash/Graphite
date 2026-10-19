import Foundation

/// A property list value with its containers expanded: what a plain (not keyed-archive) property list holds.
public indirect enum PropertyListValue: Equatable, Sendable {
    case null
    case boolean(Bool)
    case integer(Int64)
    case real(Double)
    case date(secondsSince2001: Double)
    case data(ArraySlice<UInt8>)
    case string(String)
    case uid(Int)
    /// An array, a set or an ordered set, members in file order.
    case array([PropertyListValue])
    case dictionary(PropertyListDictionary)

    /// An integer or a real as a `Double`; nil for every other value.
    public var number: Double? {
        switch self {
        case .integer(let integer): Double(integer)
        case .real(let real): real
        case .null, .boolean, .date, .data, .string, .uid, .array, .dictionary: nil
        }
    }

    public var string: String? {
        guard case .string(let string) = self else { return nil }
        return string
    }

    public var array: [PropertyListValue]? {
        guard case .array(let members) = self else { return nil }
        return members
    }

    public var dictionary: PropertyListDictionary? {
        guard case .dictionary(let dictionary) = self else { return nil }
        return dictionary
    }
}

/// A dictionary with string keys, which keeps its keys in file order. A key written twice keeps its later value.
public struct PropertyListDictionary: Equatable, Sendable {
    public private(set) var keys: [String] = []
    private var valuesByKey: [String: PropertyListValue] = [:]

    public init() {}

    public subscript(key: String) -> PropertyListValue? { valuesByKey[key] }

    public mutating func setValue(_ value: PropertyListValue, named key: String) {
        if valuesByKey.updateValue(value, forKey: key) == nil { keys.append(key) }
    }
}

extension BinaryPropertyList {
    /// The object with its containers expanded, at most `maximumNestingDepth` arrays and dictionaries deep. A
    /// container that contains itself fails with `containerCycle`. A member shared by several containers is expanded
    /// each time, so the expansion stops at as many values as the list has bytes: a tree whose containers are not
    /// shared never reaches that, since every value but the first is named by a reference of at least one byte.
    public func plainValue(ofObjectAt objectIndex: Int, maximumNestingDepth: Int) throws(BinaryPropertyListError) -> PropertyListValue {
        var expansion = PlainValueExpansion(propertyList: self, maximumNestingDepth: maximumNestingDepth, valueBudget: byteCount)
        return try expansion.value(ofObjectAt: objectIndex, depth: 0)
    }
}

/// One expansion of an object into a plain value: the values left in the budget and the containers being expanded.
private struct PlainValueExpansion {
    let propertyList: BinaryPropertyList
    let maximumNestingDepth: Int
    let valueBudget: Int
    private var remainingValues: Int
    private var containersBeingExpanded: Set<Int> = []

    init(propertyList: BinaryPropertyList, maximumNestingDepth: Int, valueBudget: Int) {
        self.propertyList = propertyList
        self.maximumNestingDepth = maximumNestingDepth
        self.valueBudget = valueBudget
        remainingValues = valueBudget
    }

    mutating func value(ofObjectAt objectIndex: Int, depth: Int) throws(BinaryPropertyListError) -> PropertyListValue {
        try spendValue()
        switch try propertyList.object(at: objectIndex) {
        case .null: return .null
        case .boolean(let flag): return .boolean(flag)
        case .integer(let integer): return .integer(integer)
        case .real(let real): return .real(real)
        case .date(let seconds): return .date(secondsSince2001: seconds)
        case .data(let bytes): return .data(bytes)
        case .string(let string): return .string(string)
        case .uid(let uid): return .uid(uid)
        case .array(let memberIndices), .set(let memberIndices):
            return .array(try members(memberIndices, ofContainerAt: objectIndex, depth: depth))
        case .dictionary(let keyIndices, let valueIndices):
            return .dictionary(try dictionary(keyIndices: keyIndices, valueIndices: valueIndices, ofContainerAt: objectIndex, depth: depth))
        }
    }

    private mutating func members(_ memberIndices: [Int], ofContainerAt objectIndex: Int,
                                  depth: Int) throws(BinaryPropertyListError) -> [PropertyListValue] {
        try enterContainer(objectIndex, depth: depth)
        var members: [PropertyListValue] = []
        members.reserveCapacity(memberIndices.count)
        for memberIndex in memberIndices { members.append(try value(ofObjectAt: memberIndex, depth: depth + 1)) }
        containersBeingExpanded.remove(objectIndex)
        return members
    }

    private mutating func dictionary(keyIndices: [Int], valueIndices: [Int], ofContainerAt objectIndex: Int,
                                     depth: Int) throws(BinaryPropertyListError) -> PropertyListDictionary {
        try enterContainer(objectIndex, depth: depth)
        var dictionary = PropertyListDictionary()
        for (keyIndex, valueIndex) in zip(keyIndices, valueIndices) {
            try spendValue()
            guard case .string(let key) = try propertyList.object(at: keyIndex) else { throw .dictionaryKeyNotString(objectIndex: keyIndex) }
            dictionary.setValue(try value(ofObjectAt: valueIndex, depth: depth + 1), named: key)
        }
        containersBeingExpanded.remove(objectIndex)
        return dictionary
    }

    private mutating func enterContainer(_ objectIndex: Int, depth: Int) throws(BinaryPropertyListError) {
        guard depth < maximumNestingDepth else { throw .nestingTooDeep(limit: maximumNestingDepth) }
        guard containersBeingExpanded.insert(objectIndex).inserted else { throw .containerCycle(objectIndex: objectIndex) }
    }

    private mutating func spendValue() throws(BinaryPropertyListError) {
        guard remainingValues > 0 else { throw .valueCountOverBudget(budget: valueBudget) }
        remainingValues -= 1
    }
}

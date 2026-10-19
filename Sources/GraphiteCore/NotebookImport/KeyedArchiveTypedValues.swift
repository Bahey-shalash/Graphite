import Foundation

/// Typed reads of keyed-archive values: Foundation's archived classes, and values stored as themselves. Each read
/// resolves only the references it needs.
extension KeyedArchive {
    private static let dictionaryClassNames: Set<String> = ["NSDictionary", "NSMutableDictionary"]
    private static let arrayClassNames: Set<String> = ["NSArray", "NSMutableArray", "NSSet", "NSMutableSet", "NSOrderedSet"]
    private static let stringClassNames: Set<String> = ["NSString", "NSMutableString"]
    private static let dataClassNames: Set<String> = ["NSData", "NSMutableData"]
    private static let uuidByteCount = 16

    /// The value a key names; nil when the key is absent. A key whose value is `$null` gives `.null`.
    public func value(named key: String, in fields: KeyedArchiveFields) throws(KeyedArchiveError) -> KeyedArchiveValue? {
        guard let reference = fields.reference(named: key) else { return nil }
        return try value(of: reference)
    }

    /// The value a key names; nil when the key is absent or its value is `$null`.
    public func nonNullValue(named key: String, in fields: KeyedArchiveFields) throws(KeyedArchiveError) -> KeyedArchiveValue? {
        guard let value = try value(named: key, in: fields), value != .null else { return nil }
        return value
    }

    /// The value a key names, which must be present (it may be `.null`).
    public func requiredValue(named key: String, in fields: KeyedArchiveFields) throws(KeyedArchiveError) -> KeyedArchiveValue {
        guard let value = try value(named: key, in: fields) else { throw .keyMissing(key: key) }
        return value
    }

    /// An archived object's own keys, or the entries of an archived `NSDictionary`, whose keys must be strings.
    public func fields(of value: KeyedArchiveValue) throws(KeyedArchiveError) -> KeyedArchiveFields {
        guard case .object(let object) = value else { throw .valueNotOfExpectedKind(expected: .object, objectIndex: value.objectIndex) }
        guard Self.dictionaryClassNames.contains(object.className) else { return object.fields }
        let keyReferences = try rawMemberReferences(named: "NS.keys", in: object)
        let valueReferences = try rawMemberReferences(named: "NS.objects", in: object)
        guard keyReferences.count == valueReferences.count else { throw .dictionaryDamaged(objectIndex: object.objectIndex) }
        var fields = KeyedArchiveFields()
        for (keyReference, valueReference) in zip(keyReferences, valueReferences) {
            let key: String
            do throws(KeyedArchiveError) {
                key = try string(self.value(of: keyReference))
            } catch {
                throw .dictionaryDamaged(objectIndex: object.objectIndex)
            }
            fields.setReference(valueReference, named: key)
        }
        return fields
    }

    /// The members of an archived array or set (`NS.objects`), or of a property list array stored without a class.
    public func members(of value: KeyedArchiveValue) throws(KeyedArchiveError) -> [KeyedArchiveReference] {
        switch value {
        case .object(let object) where Self.arrayClassNames.contains(object.className):
            return try rawMemberReferences(named: "NS.objects", in: object)
        case .primitive(.array(let memberIndices), _), .primitive(.set(let memberIndices), _):
            return memberIndices.map { memberIndex in KeyedArchiveReference(objectIndex: memberIndex) }
        case .null, .object, .primitive:
            throw .valueNotOfExpectedKind(expected: .array, objectIndex: value.objectIndex)
        }
    }

    /// A string stored as itself, or an `NSString` / `NSMutableString` with `NS.string` or UTF-8 `NS.bytes`.
    public func string(_ value: KeyedArchiveValue) throws(KeyedArchiveError) -> String {
        switch value {
        case .primitive(.string(let string), _):
            return string
        case .object(let object) where Self.stringClassNames.contains(object.className):
            if case .primitive(.string(let string), _)? = try self.value(named: "NS.string", in: object.fields), !string.isEmpty {
                return string
            }
            guard let bytesValue = try nonNullValue(named: "NS.bytes", in: object.fields) else { return "" }
            guard let string = String(validating: try data(bytesValue), as: UTF8.self) else {
                throw .valueNotOfExpectedKind(expected: .string, objectIndex: object.objectIndex)
            }
            return string
        case .null, .object, .primitive:
            throw .valueNotOfExpectedKind(expected: .string, objectIndex: value.objectIndex)
        }
    }

    public func integer(_ value: KeyedArchiveValue) throws(KeyedArchiveError) -> Int64 {
        guard case .primitive(.integer(let integer), _) = value else {
            throw .valueNotOfExpectedKind(expected: .integer, objectIndex: value.objectIndex)
        }
        return integer
    }

    /// An integer or a real, as a `Double`.
    public func number(_ value: KeyedArchiveValue) throws(KeyedArchiveError) -> Double {
        switch value {
        case .primitive(.integer(let integer), _): return Double(integer)
        case .primitive(.real(let real), _): return real
        case .null, .object, .primitive: throw .valueNotOfExpectedKind(expected: .number, objectIndex: value.objectIndex)
        }
    }

    public func boolean(_ value: KeyedArchiveValue) throws(KeyedArchiveError) -> Bool {
        guard case .primitive(.boolean(let flag), _) = value else {
            throw .valueNotOfExpectedKind(expected: .boolean, objectIndex: value.objectIndex)
        }
        return flag
    }

    /// Data stored as itself, or an `NSData` / `NSMutableData` with `NS.data`: a slice of the archive's bytes.
    public func data(_ value: KeyedArchiveValue) throws(KeyedArchiveError) -> ArraySlice<UInt8> {
        switch value {
        case .primitive(.data(let bytes), _):
            return bytes
        case .object(let object) where Self.dataClassNames.contains(object.className):
            guard case .primitive(.data(let bytes), _) = try requiredValue(named: "NS.data", in: object.fields) else {
                throw .valueNotOfExpectedKind(expected: .data, objectIndex: object.objectIndex)
            }
            return bytes
        case .null, .object, .primitive:
            throw .valueNotOfExpectedKind(expected: .data, objectIndex: value.objectIndex)
        }
    }

    /// A date stored as itself, or an `NSDate` with `NS.time`, in seconds since 2001-01-01.
    public func date(_ value: KeyedArchiveValue) throws(KeyedArchiveError) -> Double {
        switch value {
        case .primitive(.date(let seconds), _):
            return seconds
        case .object(let object) where object.className == "NSDate":
            return try number(requiredValue(named: "NS.time", in: object.fields))
        case .null, .object, .primitive:
            throw .valueNotOfExpectedKind(expected: .date, objectIndex: value.objectIndex)
        }
    }

    /// An `NSUUID` with its 16 bytes in `NS.uuidbytes`.
    public func uuid(_ value: KeyedArchiveValue) throws(KeyedArchiveError) -> UUID {
        guard case .object(let object) = value, object.className == "NSUUID",
              let uuid = Self.uuid(fromBytes: try data(requiredValue(named: "NS.uuidbytes", in: object.fields))) else {
            throw .valueNotOfExpectedKind(expected: .uuid, objectIndex: value.objectIndex)
        }
        return uuid
    }

    /// A UUID from exactly 16 bytes in the order they are stored; nil for any other count.
    static func uuid(fromBytes bytes: ArraySlice<UInt8>) -> UUID? {
        guard bytes.count == uuidByteCount else { return nil }
        var uuidBytes: uuid_t = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
        withUnsafeMutableBytes(of: &uuidBytes) { destination in destination.copyBytes(from: bytes) }
        return UUID(uuid: uuidBytes)
    }

    /// The references of a property list array an archived object stores under this key; none when it is absent.
    private func rawMemberReferences(named key: String, in object: KeyedArchiveObject) throws(KeyedArchiveError) -> [KeyedArchiveReference] {
        guard let reference = object.fields.reference(named: key) else { return [] }
        let target = try target(ofObjectAt: reference.objectIndex)
        guard case .array(let memberIndices) = target.object else {
            throw .valueNotOfExpectedKind(expected: .array, objectIndex: target.objectIndex)
        }
        return memberIndices.map { memberIndex in KeyedArchiveReference(objectIndex: memberIndex) }
    }
}

import Foundation

/// Builds keyed archives (`$archiver`, `$objects`, `$top`) for the reader tests over `BinaryPropertyListWriter`.
/// Each method adds a member to `$objects` and returns its UID, the position a field refers to it by.
struct KeyedArchiveBuilder {
    /// The value of an archived object's key: a UID of another member of `$objects`, or a value stored as itself.
    enum Field {
        case uid(Int)
        case integer(Int64)
        case real(Double)
        case float(Float)
        case boolean(Bool)
        case data([UInt8])
        case string(String)
        /// A property list object written as it is, for damaged archives.
        case object(BinaryPropertyListWriter.Object)
    }

    static let nullUID = 0

    private(set) var writer = BinaryPropertyListWriter()
    /// The property list object index of each member of `$objects`.
    private var archivedObjectIndices: [Int] = []
    private var classUIDsByName: [String: Int] = [:]

    init() {
        _ = archive(.string("$null"))
    }

    /// Adds a property list object to `$objects` and returns its UID.
    mutating func archive(_ object: BinaryPropertyListWriter.Object) -> Int {
        archivedObjectIndices.append(writer.add(object))
        return archivedObjectIndices.count - 1
    }

    /// Makes the member at this UID another object, for graphs that refer back to an object made later.
    mutating func replaceArchivedObject(_ uid: Int, with object: BinaryPropertyListWriter.Object) {
        writer.replace(archivedObjectIndices[uid], with: object)
    }

    /// Adds a property list object that is not a member of `$objects`, and returns its object index.
    mutating func propertyListObject(_ object: BinaryPropertyListWriter.Object) -> Int { writer.add(object) }

    mutating func string(_ string: String) -> Int { archive(.string(string)) }

    mutating func object(className: String, _ fields: [(String, Field)]) -> Int {
        let classUID = classUID(named: className)
        let dictionary = dictionaryObject(fields + [("$class", .uid(classUID))])
        return archive(dictionary)
    }

    /// An archived object whose fields are filled in later with `replaceObject`, for cycles.
    mutating func reserveObject() -> Int { archive(.null) }

    mutating func replaceObject(_ uid: Int, className: String, _ fields: [(String, Field)]) {
        let classUID = classUID(named: className)
        let dictionary = dictionaryObject(fields + [("$class", .uid(classUID))])
        replaceArchivedObject(uid, with: dictionary)
    }

    mutating func array(_ memberUIDs: [Int], className: String = "NSArray") -> Int {
        let members = memberUIDs.map { uid in writer.add(.uid(uid)) }
        let objectsIndex = writer.add(.array(members))
        let classUID = classUID(named: className)
        let keys = [writer.add(.string("NS.objects")), writer.add(.string("$class"))]
        let classReference = writer.add(.uid(classUID))
        return archive(.dictionary(keys: keys, values: [objectsIndex, classReference]))
    }

    /// An `NSDictionary` whose keys are archived strings.
    mutating func dictionary(_ entries: [(String, Field)], className: String = "NSDictionary") -> Int {
        let keyUIDs = entries.map { entry in string(entry.0) }
        let keyMembers = keyUIDs.map { uid in writer.add(.uid(uid)) }
        let valueMembers = entries.map { entry in fieldObjectIndex(entry.1) }
        return object(className: className, [("NS.keys", .object(.array(keyMembers))), ("NS.objects", .object(.array(valueMembers)))])
    }

    mutating func classUID(named className: String) -> Int {
        if let uid = classUIDsByName[className] { return uid }
        let names = [writer.add(.string(className)), writer.add(.string("NSObject"))]
        let namesIndex = writer.add(.array(names))
        let keys = [writer.add(.string("$classname")), writer.add(.string("$classes"))]
        let classNameIndex = writer.add(.string(className))
        let uid = archive(.dictionary(keys: keys, values: [classNameIndex, namesIndex]))
        classUIDsByName[className] = uid
        return uid
    }

    /// The archive, its root under `$top.<rootKey>`.
    func archiveBytes(rootUID: Int, archiver: String = "GLKeyedArchiver", rootKey: String = "$0") -> [UInt8] {
        var writer = self.writer
        let objectsIndex = writer.add(.array(archivedObjectIndices))
        let rootKeyIndex = writer.add(.string(rootKey))
        let rootReferenceIndex = writer.add(.uid(rootUID))
        let topIndex = writer.add(.dictionary(keys: [rootKeyIndex], values: [rootReferenceIndex]))
        let keys = [writer.add(.string("$version")), writer.add(.string("$archiver")), writer.add(.string("$top")), writer.add(.string("$objects"))]
        let values = [writer.add(.integer(100_000)), writer.add(.string(archiver)), topIndex, objectsIndex]
        let rootIndex = writer.add(.dictionary(keys: keys, values: values))
        return writer.bytes(topObjectIndex: rootIndex)
    }

    private mutating func dictionaryObject(_ fields: [(String, Field)]) -> BinaryPropertyListWriter.Object {
        let keys = fields.map { field in writer.add(.string(field.0)) }
        let values = fields.map { field in fieldObjectIndex(field.1) }
        return .dictionary(keys: keys, values: values)
    }

    private mutating func fieldObjectIndex(_ field: Field) -> Int {
        switch field {
        case .uid(let uid): writer.add(.uid(uid))
        case .integer(let integer): writer.add(.integer(integer))
        case .real(let real): writer.add(.real(real))
        case .float(let float): writer.add(.float(float))
        case .boolean(let flag): writer.add(.boolean(flag))
        case .data(let bytes): writer.add(.data(bytes))
        case .string(let string): writer.add(.string(string))
        case .object(let object): writer.add(object)
        }
    }
}

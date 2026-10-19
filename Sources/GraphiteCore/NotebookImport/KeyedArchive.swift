import Foundation

/// An `NSKeyedArchiver` archive, or Notability's `GLKeyedArchiver` archive of the same layout, read over a
/// `BinaryPropertyList`. The archive's objects are never expanded as a whole: a reader starts at `rootValue()` and
/// follows the keys it knows one level at a time, so an object graph with cycles (an object whose key names an
/// ancestor, an array that contains itself) cannot make it loop. Only a chain of UIDs is followed without the
/// caller asking, and that chain carries the objects it passed and stops at `maximumArchiveReferenceDepth`.
/// Foundation's `PropertyListSerialization` is not used: it returns UIDs as opaque objects whose number is not public.
public struct KeyedArchive: Sendable {
    private static let nullMarker = "$null"
    private static let classKey = "$class"
    private static let classNameKey = "$classname"
    /// Notability names the root `$0`; `NSKeyedArchiver` names it `root` by default.
    private static let rootKeys = ["$0", "root"]

    public let archiver: KeyedArchiverName
    private let propertyList: BinaryPropertyList
    /// The property list object index of each member of `$objects`, which UIDs name by position.
    private let archivedObjectIndices: [Int]
    private let rootReference: KeyedArchiveReference
    private let maximumReferenceDepth: Int

    public init(archiveBytes: ArraySlice<UInt8>, limits: NotebookImportLimits) throws(KeyedArchiveError) {
        let propertyList: BinaryPropertyList
        do throws(BinaryPropertyListError) {
            propertyList = try BinaryPropertyList(bytes: archiveBytes)
        } catch {
            throw .propertyList(error)
        }
        let top = try Self.dictionaryFields(at: propertyList.topObjectIndex, in: propertyList)
        guard let archiverReference = top.reference(named: "$archiver"), let objectsReference = top.reference(named: "$objects"),
              let topReference = top.reference(named: "$top"),
              case .string(let archiverName) = try Self.object(at: archiverReference.objectIndex, in: propertyList),
              case .array(let archivedObjectIndices) = try Self.object(at: objectsReference.objectIndex, in: propertyList)
        else { throw .notKeyedArchive }
        guard let archiver = KeyedArchiverName(rawName: archiverName) else { throw .archiverNotSupported(name: archiverName) }
        let rootFields = try Self.dictionaryFields(at: topReference.objectIndex, in: propertyList)
        guard let rootReference = Self.rootKeys.lazy.compactMap({ key in rootFields.reference(named: key) }).first else { throw .rootMissing }
        self.archiver = archiver
        self.propertyList = propertyList
        self.archivedObjectIndices = archivedObjectIndices
        self.rootReference = rootReference
        maximumReferenceDepth = limits.maximumArchiveReferenceDepth
    }

    /// The archive's root object, `$top.$0` or `$top.root`.
    public func rootValue() throws(KeyedArchiveError) -> KeyedArchiveValue {
        try value(of: rootReference)
    }

    /// The value a reference names, after following its chain of UIDs into `$objects`.
    public func value(of reference: KeyedArchiveReference) throws(KeyedArchiveError) -> KeyedArchiveValue {
        let target = try target(ofObjectAt: reference.objectIndex)
        switch target.object {
        case .string(Self.nullMarker):
            return .null
        case .dictionary(let keyIndices, let valueIndices):
            let dictionary = try Self.dictionary(keyIndices: keyIndices, valueIndices: valueIndices, dictionaryIndex: target.objectIndex,
                                                 in: propertyList)
            guard let classReference = dictionary.classReference else { return .primitive(target.object, objectIndex: target.objectIndex) }
            let className = try className(of: classReference, objectIndex: target.objectIndex)
            return .object(KeyedArchiveObject(objectIndex: target.objectIndex, className: className, fields: dictionary.fields))
        case .null, .boolean, .integer, .real, .date, .data, .string, .uid, .array, .set:
            return .primitive(target.object, objectIndex: target.objectIndex)
        }
    }

    /// The property list object at the end of a chain of UIDs that starts at this object.
    func target(ofObjectAt startIndex: Int) throws(KeyedArchiveError) -> (object: BinaryPropertyListObject, objectIndex: Int) {
        var objectIndex = startIndex
        var passedObjectIndices: Set<Int> = []
        while true {
            let object = try Self.object(at: objectIndex, in: propertyList)
            guard case .uid(let uid) = object else { return (object, objectIndex) }
            guard uid < archivedObjectIndices.count else {
                throw .referenceOutOfRange(uid: uid, archivedObjectCount: archivedObjectIndices.count)
            }
            guard passedObjectIndices.insert(objectIndex).inserted else { throw .referenceCycle(objectIndex: objectIndex) }
            guard passedObjectIndices.count <= maximumReferenceDepth else { throw .referenceChainTooLong(limit: maximumReferenceDepth) }
            objectIndex = archivedObjectIndices[uid]
        }
    }

    /// The `$classname` of the class description `$class` names, read without treating that description as an
    /// archived object, so a `$class` that names its own object ends here.
    private func className(of classReference: KeyedArchiveReference, objectIndex: Int) throws(KeyedArchiveError) -> String {
        let classTarget = try target(ofObjectAt: classReference.objectIndex)
        guard case .dictionary(let keyIndices, let valueIndices) = classTarget.object,
              let nameReference = try Self.dictionary(keyIndices: keyIndices, valueIndices: valueIndices, dictionaryIndex: classTarget.objectIndex,
                                                      in: propertyList).fields.reference(named: Self.classNameKey),
              case .string(let className) = try target(ofObjectAt: nameReference.objectIndex).object
        else { throw .classNameMissing(objectIndex: objectIndex) }
        return className
    }

    /// A property list dictionary's string keys and the references they name, with `$class` set apart.
    private struct ArchivedDictionary {
        var fields = KeyedArchiveFields()
        var classReference: KeyedArchiveReference?
    }

    private static func dictionary(keyIndices: [Int], valueIndices: [Int], dictionaryIndex: Int,
                                   in propertyList: BinaryPropertyList) throws(KeyedArchiveError) -> ArchivedDictionary {
        var dictionary = ArchivedDictionary()
        for (keyIndex, valueIndex) in zip(keyIndices, valueIndices) {
            guard case .string(let key) = try object(at: keyIndex, in: propertyList) else { throw .dictionaryDamaged(objectIndex: dictionaryIndex) }
            if key == classKey {
                dictionary.classReference = KeyedArchiveReference(objectIndex: valueIndex)
            } else {
                dictionary.fields.setReference(KeyedArchiveReference(objectIndex: valueIndex), named: key)
            }
        }
        return dictionary
    }

    /// The keys of the property list dictionary at this index, for the archive's own top-level dictionaries.
    private static func dictionaryFields(at objectIndex: Int, in propertyList: BinaryPropertyList) throws(KeyedArchiveError) -> KeyedArchiveFields {
        guard case .dictionary(let keyIndices, let valueIndices) = try object(at: objectIndex, in: propertyList) else { throw .notKeyedArchive }
        return try dictionary(keyIndices: keyIndices, valueIndices: valueIndices, dictionaryIndex: objectIndex, in: propertyList).fields
    }

    static func object(at objectIndex: Int, in propertyList: BinaryPropertyList) throws(KeyedArchiveError) -> BinaryPropertyListObject {
        do throws(BinaryPropertyListError) {
            return try propertyList.object(at: objectIndex)
        } catch {
            throw .propertyList(error)
        }
    }
}

import CoreGraphics
import Foundation

/// The recognised shapes of the ink's `shapes` value: an embedded property list (not a keyed archive) of three
/// arrays of one length, `shapes`, `kinds` and `indices`. A list that cannot be read costs the shapes, not the note;
/// a shape that cannot be read is skipped. Both are reported.
extension NotabilitySessionReading {
    private struct ShapeArrays {
        let shapes: [PropertyListValue]
        let kinds: [PropertyListValue]
        let indices: [PropertyListValue]
    }

    mutating func readShapes(in ink: KeyedArchiveFields) -> [NotabilityShape] {
        let arrays: ShapeArrays
        do throws(NotabilityElementFailure) {
            guard let shapeArrays = try readShapeArrays(in: ink) else { return [] }
            arrays = shapeArrays
        } catch {
            issues.report(.shapesSkipped(error))
            return []
        }
        for kind in arrays.kinds {
            if case .string(let rawKind) = kind, case .unknown = NotabilityShapeKind(rawKind: rawKind) {
                issues.report(.shapeKindUnknown(rawKind: rawKind))
            }
        }
        var shapes: [NotabilityShape] = []
        for shapeIndex in arrays.shapes.indices {
            do throws(NotabilityElementFailure) {
                shapes.append(try readShape(at: shapeIndex, of: arrays))
            } catch {
                issues.report(.shapeSkipped(shapeIndex: shapeIndex, error))
            }
        }
        return shapes
    }

    /// The three arrays; nil when the ink has no shapes (no value, `$null` or empty data).
    private func readShapeArrays(in ink: KeyedArchiveFields) throws(NotabilityElementFailure) -> ShapeArrays? {
        let shapesBytes = try Self.readingElement { () throws(KeyedArchiveError) -> ArraySlice<UInt8>? in
            try archive.nonNullValue(named: NotabilityInkKey.shapes.rawValue, in: ink).map(archive.data)
        }
        guard let shapesBytes, !shapesBytes.isEmpty else { return nil }
        let shapesList: PropertyListValue
        do throws(PropertyListDocumentError) {
            shapesList = try PropertyListDocument.plainValue(of: shapesBytes, maximumNestingDepth: limits.maximumPropertyListNestingDepth,
                                                                 maximumValueCount: limits.maximumPlainValueCount)
        } catch {
            throw .propertyList(error)
        }
        guard let dictionary = shapesList.dictionary else { throw .valueNotReadable(key: NotabilityShapeListKey.shapes.rawValue) }
        func array(_ key: NotabilityShapeListKey) throws(NotabilityElementFailure) -> [PropertyListValue] {
            guard let value = dictionary[key.rawValue] else { return [] }
            guard let members = value.array else { throw .valueNotReadable(key: key.rawValue) }
            return members
        }
        let arrays = ShapeArrays(shapes: try array(.shapes), kinds: try array(.kinds), indices: try array(.indices))
        guard arrays.shapes.count == arrays.kinds.count, arrays.kinds.count == arrays.indices.count else {
            throw .shapeArraysDiffer(shapeCount: arrays.shapes.count, kindCount: arrays.kinds.count, indexCount: arrays.indices.count)
        }
        return arrays
    }

    private mutating func readShape(at shapeIndex: Int, of arrays: ShapeArrays) throws(NotabilityElementFailure) -> NotabilityShape {
        guard let shape = arrays.shapes[shapeIndex].dictionary else { throw .valueNotReadable(key: NotabilityShapeListKey.shapes.rawValue) }
        issues.reportUnknownKeys(shape.keys, in: .shape, known: NotabilityKnownKeys.shape)
        guard let rawKind = arrays.kinds[shapeIndex].string else { throw .valueNotReadable(key: NotabilityShapeListKey.kinds.rawValue) }
        guard case .integer(let drawnBeforeCurveIndex) = arrays.indices[shapeIndex] else {
            throw .valueNotReadable(key: NotabilityShapeListKey.indices.rawValue)
        }
        guard let appearance = shape[NotabilityShapeKey.appearance.rawValue]?.dictionary else {
            throw .valueNotReadable(key: NotabilityShapeKey.appearance.rawValue)
        }
        let strokeColor = appearance[NotabilityShapeAppearanceKey.strokeColor.rawValue]?.dictionary
        guard let rgba = strokeColor?[NotabilityShapeColorKey.rgba.rawValue]?.array?.compactMap(\.number), rgba.count == 4 else {
            throw .valueNotReadable(key: NotabilityShapeAppearanceKey.strokeColor.rawValue)
        }
        return NotabilityShape(
            kind: NotabilityShapeKind(rawKind: rawKind), drawnBeforeCurveIndex: Int(drawnBeforeCurveIndex),
            start: try Self.point(.startPoint, in: shape), end: try Self.point(.endPoint, in: shape),
            quadraticControlPoint: shape[NotabilityShapeKey.controlPoint.rawValue] == nil ? nil : try Self.point(.controlPoint, in: shape),
            width: appearance[NotabilityShapeAppearanceKey.strokeWidth.rawValue]?.number,
            color: NotebookImportColor(red: rgba[0], green: rgba[1], blue: rgba[2], alpha: rgba[3]),
            dashPattern: appearance[NotabilityShapeAppearanceKey.dashStyle.rawValue].map { dashStyle in
                dashStyle.dictionary?[NotabilityShapeDashStyleKey.pattern.rawValue]?.array?.compactMap(\.number) ?? []
            })
    }

    /// A point stored as an array whose first two members are numbers.
    private static func point(_ key: NotabilityShapeKey, in shape: PropertyListDictionary) throws(NotabilityElementFailure) -> CGPoint {
        guard let coordinates = shape[key.rawValue]?.array, coordinates.count >= 2, let horizontal = coordinates[0].number,
              let vertical = coordinates[1].number else {
            throw .valueNotReadable(key: key.rawValue)
        }
        return CGPoint(x: horizontal, y: vertical)
    }
}

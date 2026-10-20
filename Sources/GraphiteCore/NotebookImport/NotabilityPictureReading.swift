import CoreGraphics
import Foundation

/// The pictures of `richText.mediaObjects`. A media object that cannot be read as a picture is skipped and reported
/// with the reason, so one damaged picture does not cost the note.
extension NotabilitySessionReading {
    private static let pictureClassName = "ImageMediaObject"

    mutating func readPictures(in richText: KeyedArchiveFields) throws(NotabilityReadingError) -> [NotabilityPicture] {
        let mediaReferences = try NotabilityReadingError.readingSession { () throws(KeyedArchiveError) in
            try archive.members(of: archive.requiredValue(named: NotabilityRichTextKey.mediaObjects.rawValue, in: richText))
        }
        var pictures: [NotabilityPicture] = []
        for (mediaIndex, mediaReference) in mediaReferences.enumerated() {
            do throws(NotabilityElementFailure) {
                pictures.append(try readPicture(at: mediaReference))
            } catch {
                issues.report(.pictureSkipped(mediaIndex: mediaIndex, error))
            }
        }
        return pictures
    }

    private mutating func readPicture(at reference: KeyedArchiveReference) throws(NotabilityElementFailure) -> NotabilityPicture {
        let mediaValue = try Self.readingElement { () throws(KeyedArchiveError) in try archive.value(of: reference) }
        guard case .object(let media) = mediaValue else {
            throw .archive(.valueNotOfExpectedKind(expected: .object, objectIndex: mediaValue.objectIndex))
        }
        if media.className != Self.pictureClassName { issues.report(.mediaClassUnknown(className: media.className)) }
        issues.reportUnknownKeys(media.fields.keys, in: .picture, known: NotabilityKnownKeys.picture)
        let figure = try elementFields(NotabilityPictureKey.figure, in: media.fields)
        let size = try geometryNumbers(NotabilityPictureKey.unscaledContentSize, in: media.fields)
        let crop = try geometryNumbers(NotabilityFigureKey.cropRectangle, in: figure)
        let origin = try geometryNumbers(NotabilityPictureKey.documentOrigin, in: media.fields)
        guard size.count == 2 else { throw .valueNotReadable(key: NotabilityPictureKey.unscaledContentSize.rawValue) }
        guard crop.count == 4, crop[2] > 0 else { throw .valueNotReadable(key: NotabilityFigureKey.cropRectangle.rawValue) }
        guard origin.count >= 2 else { throw .valueNotReadable(key: NotabilityPictureKey.documentOrigin.rawValue) }
        let snapshot = try elementFields(NotabilityFigureBackgroundKey.imageSnapshot,
                                     in: elementFields(NotabilityFigureKey.backgroundObject, in: figure))
        let pathText = try Self.readingElement { () throws(KeyedArchiveError) in
            try archive.string(archive.requiredValue(named: NotabilityImageSnapshotKey.relativePath.rawValue, in: snapshot))
        }
        guard let file = NotebookArchivePath(validating: pathText) else { throw .archivePathNotValid(path: pathText) }
        return try Self.readingElement { () throws(KeyedArchiveError) in
            NotabilityPicture(
                file: file,
                origin: CGPoint(x: origin[0], y: origin[1]), size: CGSize(width: size[0], height: size[1]),
                rotationRadiansClockwise: try archive.number(archive.requiredValue(named: NotabilityPictureKey.rotationDegrees.rawValue, in: media.fields)),
                zIndex: Int(try archive.integer(archive.requiredValue(named: NotabilityPictureKey.zIndex.rawValue, in: media.fields))),
                cropRectangle: CGRect(x: crop[0], y: crop[1], width: crop[2], height: crop[3]),
                isFlippedHorizontally: try archive.nonNullValue(named: NotabilityPictureKey.isFlippedHorizontal.rawValue, in: media.fields)
                    .map(archive.boolean) ?? false,
                isFlippedVertically: try archive.nonNullValue(named: NotabilityPictureKey.isFlippedVertical.rawValue, in: media.fields)
                    .map(archive.boolean) ?? false)
        }
    }

    private func elementFields(_ key: some NotabilityKey, in fields: KeyedArchiveFields) throws(NotabilityElementFailure) -> KeyedArchiveFields {
        try Self.readingElement { () throws(KeyedArchiveError) in try archive.fields(of: archive.requiredValue(named: key.rawValue, in: fields)) }
    }

    private func geometryNumbers(_ key: some NotabilityKey, in fields: KeyedArchiveFields) throws(NotabilityElementFailure) -> [Double] {
        let geometry = try Self.readingElement { () throws(KeyedArchiveError) in
            try archive.string(archive.requiredValue(named: key.rawValue, in: fields))
        }
        return NotabilityGeometryString.numbers(in: geometry)
    }
}

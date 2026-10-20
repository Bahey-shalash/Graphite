import Foundation

/// A curve of a synthetic note, with one width factor, force, altitude and azimuth per knot.
struct SyntheticNotabilityCurve {
    var points: [(Float, Float)]
    var width: Float = 2.5
    var color: [UInt8] = [10, 20, 30, 255]
    var style: UInt8 = 3
    var uuid: [UInt8]
    var widthFactors: [Float]
    var forces: [Float]
    var altitudeAngles: [Float]
    var azimuthUnitVectors: [(Float, Float)]

    /// A pen curve through these points with knot values that differ per knot.
    static func pen(_ points: [(Float, Float)], uuidByte: UInt8) -> SyntheticNotabilityCurve {
        let knotCount = (points.count - 1) / 3 + 1
        return SyntheticNotabilityCurve(
            points: points, uuid: [UInt8](repeating: uuidByte, count: 16),
            widthFactors: (0..<knotCount).map { knotIndex in 0.5 + Float(knotIndex) * 0.25 },
            forces: (0..<knotCount).map { knotIndex in 1 + Float(knotIndex) },
            altitudeAngles: (0..<knotCount).map { knotIndex in 1.5 - Float(knotIndex) * 0.125 },
            azimuthUnitVectors: (0..<knotCount).map { knotIndex in (knotIndex % 2 == 0 ? (1, 0) : (0, 1)) })
    }
}

struct SyntheticNotabilityPicture {
    var relativePath = "Images/Image 1.png"
    var origin = "{10, 20}"
    var size = "{200, 150}"
    var cropRectangle = "{{0, 0}, {400, 300}}"
    var rotationRadians = 0.0
    var zIndex: Int64 = 0
    var className = "ImageMediaObject"
}

struct SyntheticNotabilityTextRun {
    var range: String
    var fontName = "HelveticaNeue"
    var fontSize = 12.0
    var color = "0.0,0.0,0.0,1.0"
    var otherAttributes: [(String, KeyedArchiveBuilder.Field)] = [("NSUnderline", .integer(0)), ("NSStrikethrough", .integer(0)),
                                                                   ("line-spacing", .real(1)), ("NSBaselineOffset", .real(0))]
}

struct SyntheticNotabilityPlaybackEvent {
    var curveUUID: [UInt8]
    var secondsFromRecordingStart: Float
    var recordingIdentifier: UInt32
    var durationSeconds: Float
}

/// Builds small synthetic Notability notes for the reader tests: a ZIP archive with one folder, a `Session.plist`
/// keyed archive laid out as Notability writes it, and optional recordings library, pictures and PDFs. Nothing in it
/// comes from a real note.
struct NotabilityNoteBuilder {
    var folderName = "Synthetic Note"
    var curves: [SyntheticNotabilityCurve] = []
    var paperFields: [(String, String)] = [("paperIdentifier", "Legacy:13"), ("paperSize", "letter"), ("paperOrientation", "portrait"),
                                           ("paperSizingBehavior", "lockedWidth:572.0:Mac"), ("lineStyle2", "Lines:false:false:0.5")]
    var reflowStateClassName = "NBReflowStateLocked"
    var storedPageWidth: Double? = 572
    var sessionFormatVersion: Int64 = 9
    var shapesPropertyList: [UInt8]?
    var pictures: [SyntheticNotabilityPicture] = []
    var text = ""
    var textRuns: [SyntheticNotabilityTextRun] = []
    var importedPDFFileNames: [String] = []
    /// Strings put in `pageLayoutArray` after the imported pages, where Notability writes dictionaries.
    var pageLayoutStrings: [String] = []
    var playbackEvents: [SyntheticNotabilityPlaybackEvent] = []
    var recordingsLibraryXML: String?
    var extraFiles: [(String, [UInt8])] = []
    var extraSessionFields: [(String, KeyedArchiveBuilder.Field)] = []
    /// Ink keys replaced or added after the curves are packed; a nil value removes the key.
    var inkFieldOverrides: [String: KeyedArchiveBuilder.Field?] = [:]
    /// Damaged graphs: `Handwriting Overlay` naming the rich text that holds it, `mediaObjects` containing itself,
    /// and the session's `name` a UID that names itself.
    var handwritingOverlayNamesRichText = false
    var mediaObjectsContainThemselves = false
    var nameIsAUIDLoop = false

    func noteArchiveBytes(sessionPlistBytes: [UInt8]? = nil) -> Data {
        var zipBuilder = ZipArchiveBuilder()
        zipBuilder.addEntry(named: "\(folderName)/", contents: [], compression: .stored)
        zipBuilder.addEntry(named: "\(folderName)/Session.plist", contents: sessionPlistBytes ?? self.sessionPlistBytes(), compression: .stored)
        if let recordingsLibraryXML {
            zipBuilder.addEntry(named: "\(folderName)/Recordings/library.plist", text: recordingsLibraryXML, compression: .stored)
        }
        for (path, contents) in extraFiles { zipBuilder.addEntry(named: "\(folderName)/\(path)", contents: contents, compression: .stored) }
        return zipBuilder.archiveBytes()
    }

    func sessionPlistBytes() -> [UInt8] {
        var archive = KeyedArchiveBuilder()
        let richText = richTextUID(in: &archive)
        let paperAttributes = archive.object(className: "GLModel.PaperAttributes", paperFields.map { field in (field.0, .uid(archive.string(field.1))) })
        let layoutModel = archive.object(className: "Notability.NoteDocumentPaperLayoutModel",
                                         [("documentPaperAttributes", .uid(paperAttributes)), ("pageLayoutArray", .uid(archive.array([])))])
        let eventManager = archive.object(className: "NBCPEventManager", [
            ("NBCPTimeManagerSOANumEventsKey", .integer(Int64(playbackEvents.count))),
            ("NBCPTimeManagerSOAEventUUIDsKey", .data(playbackEvents.flatMap(\.curveUUID))),
            ("NBCPTimeManagerSOATimestampsKey", .data(Self.packed(playbackEvents.map(\.secondsFromRecordingStart)))),
            ("NBCPTimeManagerSOARecordingIDsKey", .data(Self.packed(playbackEvents.map(\.recordingIdentifier)))),
            ("NBCPTimeManagerSOADurationsKey", .data(Self.packed(playbackEvents.map(\.durationSeconds)))),
        ])
        let session = archive.object(className: "NoteTakingSession", [
            ("name", .uid(nameIsAUIDLoop ? Self.uidLoop(in: &archive) : archive.string(folderName))),
            ("sessionFormatVersion", .integer(sessionFormatVersion)),
            ("NBNoteTakingSessionBundleVersionNumberKey", .uid(archive.string("16.13"))), ("richText", .uid(richText)),
            ("NBNoteTakingSessionDocumentPaperLayoutModelKey", .uid(layoutModel)), ("contentPlaybackEventManager", .uid(eventManager)),
            ("NBNoteTakingSessionLastUsedFontKey", .uid(KeyedArchiveBuilder.nullUID)),
        ] + extraSessionFields)
        return archive.archiveBytes(rootUID: session)
    }

    private func richTextUID(in archive: inout KeyedArchiveBuilder) -> Int {
        let richText = archive.reserveObject()
        let ink = archive.object(className: "InkedSpatialHash", inkFields(in: &archive))
        let handwriting = handwritingOverlayNamesRichText ? richText : archive.object(className: "HandwritingObject", [("SpatialHash", .uid(ink))])
        let runs = textRuns.map { run in textRunUID(run, in: &archive) }
        let attributedString = archive.dictionary([("stringKey", .uid(archive.string(text))), ("subRangesKey", .uid(archive.array(runs)))],
                                                  className: "NSMutableDictionary")
        var reflowFields: [(String, KeyedArchiveBuilder.Field)] = [("nativeLayoutDeviceStringKey", .uid(archive.string("Mac")))]
        if let storedPageWidth { reflowFields.append(("pageWidthInDocumentCoordsKey", .real(storedPageWidth))) }
        let reflowState = archive.object(className: reflowStateClassName, reflowFields)
        let media = pictures.map { picture in pictureUID(picture, in: &archive) }
        let layouts = importedPDFFileNames.enumerated().map { pageIndex, fileName in
            archive.dictionary([("kPageLayoutDocumentPageNumberKey", .integer(Int64(pageIndex + 1))),
                                ("kPageLayoutPDFFileNameKey", .uid(archive.string(fileName))), ("kPageLayoutPDFPageNumberKey", .integer(1)),
                                ("kPageLayoutPageIsBookmarkedKey", .boolean(pageIndex == 0))])
        }
        let layoutStrings = pageLayoutStrings.map { text in archive.string(text) }
        let mediaObjects = mediaObjectsContainThemselves ? Self.arrayContainingItself(in: &archive) : archive.array(media)
        archive.replaceObject(richText, className: "FormattedString", [
            ("attributedString", .uid(attributedString)), ("Handwriting Overlay", .uid(handwriting)), ("reflowState", .uid(reflowState)),
            ("mediaObjects", .uid(mediaObjects)), ("pageLayoutArray", .uid(archive.array(layouts + layoutStrings, className: "NSMutableArray"))),
            ("formatVersion", .integer(5)),
        ])
        return richText
    }

    private static func arrayContainingItself(in archive: inout KeyedArchiveBuilder) -> Int {
        let array = archive.reserveObject()
        let member = archive.propertyListObject(.uid(array))
        archive.replaceObject(array, className: "NSArray", [("NS.objects", .object(.array([member])))])
        return array
    }

    private static func uidLoop(in archive: inout KeyedArchiveBuilder) -> Int {
        let looping = archive.reserveObject()
        archive.replaceArchivedObject(looping, with: .uid(looping))
        return looping
    }

    private func inkFields(in archive: inout KeyedArchiveBuilder) -> [(String, KeyedArchiveBuilder.Field)] {
        let pointCount = curves.reduce(0) { count, curve in count + curve.points.count }
        let knotCount = curves.reduce(0) { count, curve in count + curve.widthFactors.count }
        var fields: [(String, KeyedArchiveBuilder.Field)] = [
            ("numcurves", .uid(archive.archive(.integer(Int64(curves.count))))), ("numpoints", .integer(Int64(pointCount))),
            ("numfractionalwidths", .integer(Int64(knotCount))),
            ("curvesnumpoints", .data(Self.packed(curves.map { curve in UInt32(curve.points.count) }))),
            ("curvespoints", .data(Self.packed(curves.flatMap { curve in curve.points.flatMap { point in [point.0, point.1] } }))),
            ("curveswidth", .data(Self.packed(curves.map(\.width)))), ("curvescolors", .data(curves.flatMap(\.color))),
            ("curvesstyles", .data(curves.map(\.style))), ("curveUUIDs", .data(curves.flatMap(\.uuid))),
            ("options", .data([UInt8](repeating: 0, count: 8 * curves.count))),
            ("curvesfractionalwidths", .data(Self.packed(curves.flatMap(\.widthFactors)))),
            ("curvesforces", .data(Self.packed(curves.flatMap(\.forces)))),
            ("curvesaltitudeangles", .data(Self.packed(curves.flatMap(\.altitudeAngles)))),
            ("curvesazimuthunitvector", .data(Self.packed(curves.flatMap { curve in curve.azimuthUnitVectors.flatMap { vector in [vector.0, vector.1] } }))),
            ("groupsArrays", .uid(archive.array([], className: "NSMutableArray"))),
        ]
        if let shapesPropertyList { fields.append(("shapes", .data(shapesPropertyList))) }
        for (key, override) in inkFieldOverrides.sorted(by: { left, right in left.key < right.key }) {
            fields.removeAll { field in field.0 == key }
            if let override { fields.append((key, override)) }
        }
        return fields
    }

    private func textRunUID(_ run: SyntheticNotabilityTextRun, in archive: inout KeyedArchiveBuilder) -> Int {
        let font = archive.dictionary([("NSFontNameAttribute", .uid(archive.string(run.fontName))), ("NSFontSizeAttribute", .real(run.fontSize))])
        let otherAttributes = archive.dictionary(run.otherAttributes)
        return archive.dictionary([("subRangeRangeKey", .uid(archive.string(run.range))), ("subRangeFontKey", .uid(font)),
                                   ("subRangeColorCrossPlatformKey", .uid(archive.string(run.color))),
                                   ("subRangeOtherAttributesKey", .uid(otherAttributes))])
    }

    private func pictureUID(_ picture: SyntheticNotabilityPicture, in archive: inout KeyedArchiveBuilder) -> Int {
        let snapshot = archive.object(className: "GLSnapshot", [("relativePath", .uid(archive.string(picture.relativePath))), ("saveAsJPEG", .boolean(false))])
        let background = archive.object(className: "ImageObject", [("kImageObjectSnapshotKey", .uid(snapshot))])
        let figure = archive.object(className: "Figure", [("FigureCropRectKey", .uid(archive.string(picture.cropRectangle))),
                                                          ("FigureBackgroundObjectKey", .uid(background))])
        return archive.object(className: picture.className, [
            ("documentOrigin", .uid(archive.string(picture.origin))), ("unscaledContentSize", .uid(archive.string(picture.size))),
            ("rotationDegrees", .real(picture.rotationRadians)), ("zIndex", .integer(picture.zIndex)), ("figure", .uid(figure)),
            ("isFlippedHorizontal", .boolean(false)), ("isFlippedVertical", .boolean(true)),
        ])
    }

    static func packed(_ values: [Float]) -> [UInt8] {
        values.flatMap { value in packed([value.bitPattern]) }
    }

    static func packed(_ values: [UInt32]) -> [UInt8] {
        values.flatMap { value in (0..<4).map { byteIndex in UInt8(truncatingIfNeeded: value >> (8 * UInt32(byteIndex))) } }
    }

    /// A recordings library in Notability's XML layout, one recording per entry.
    static func recordingsLibraryXML(_ recordings: [(key: String, identifier: Int, filePath: String, durationSeconds: Double, name: String)]) -> String {
        let entries = recordings.map { recording in
            """
            <key>\(recording.key)</key><dict><key>identifier</key><integer>\(recording.identifier)</integer>\
            <key>filepath</key><string>\(recording.filePath)</string><key>duration</key><real>\(recording.durationSeconds)</real>\
            <key>name</key><string>\(recording.name)</string><key>filetype</key><string>m4a</string></dict>
            """
        }
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict><key>library-format-version</key><string>1.0</string>\
        <key>recordings</key><dict>\(entries.joined())</dict></dict></plist>
        """
    }
}

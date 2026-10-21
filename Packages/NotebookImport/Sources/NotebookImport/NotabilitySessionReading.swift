import Foundation

/// What `Session.plist` holds, read once when a note is opened: everything but the recordings library.
struct NotabilitySessionContent: Sendable {
    let name: String?
    let sessionFormatVersion: Int64?
    let applicationVersion: String?
    let paper: NotabilityPaper
    let reflowState: NotabilityReflowState
    let pageGeometry: NotabilityPageGeometry
    let ink: NotabilityInk
    let shapes: [NotabilityShape]
    let pictures: [NotabilityPicture]
    let typedText: NotabilityTypedText
    let importedPDFPages: [NotabilityImportedPDFPage]
    let playbackEvents: [NotabilityPlaybackEvent]
}

/// One read of a note's session archive. It follows the format's fixed key paths from the root, so it never walks
/// the object graph, and reports what it does not know in `issues`. A value the note cannot be read without is
/// required, as in the reference reader; a picture or shape that cannot be read is skipped and reported.
struct NotabilitySessionReading {
    static let supportedSessionFormatVersion: Int64 = 9
    /// Where a note keeps its imported PDFs.
    static let pdfFolder = "PDFs"

    let archive: KeyedArchive
    let limits: NotebookImportLimits
    var issues = NotabilityReadingIssues()

    init(archive: KeyedArchive, limits: NotebookImportLimits) {
        self.archive = archive
        self.limits = limits
    }

    mutating func content() throws(NotabilityReadingError) -> NotabilitySessionContent {
        let session = try NotabilityReadingError.readingSession { () throws(KeyedArchiveError) in try archive.fields(of: archive.rootValue()) }
        issues.reportUnknownKeys(session.keys, in: .session, known: NotabilityKnownKeys.session)
        let sessionFormatVersion = try sessionFormatVersion(in: session)
        let richText = try requiredFields(NotabilitySessionKey.richText, in: session)
        issues.reportUnknownKeys(richText.keys, in: .richText, known: NotabilityKnownKeys.richText)
        let paperAttributes = try requiredFields(NotabilityPaperLayoutModelKey.paperAttributes,
                                                 in: requiredFields(NotabilitySessionKey.paperLayoutModel, in: session))
        let paper = try paper(from: paperAttributes)
        let (reflowState, pageWidth) = try reflowStateAndPageWidth(in: richText, paper: paper)
        if NotabilityPageGeometry.exportPageSize(of: paper) == nil {
            issues.report(.paperSizeUnknown(rawSize: try optionalString(NotabilityPaperAttributeKey.size, in: paperAttributes)))
        }
        let inkFields = try requiredFields(NotabilityHandwritingOverlayKey.spatialHash,
                                       in: requiredFields(NotabilityRichTextKey.handwritingOverlay, in: richText))
        issues.reportUnknownKeys(inkFields.keys, in: .ink, known: NotabilityKnownKeys.ink)
        let ink = try NotabilityInk(fields: inkFields, archive: archive, issues: &issues)
        let shapes = readShapes(in: inkFields)
        let pictures = try readPictures(in: richText)
        let typedText = try readTypedText(in: richText)
        let importedPDFPages = try readImportedPDFPages(in: richText)
        let playbackEvents: [NotabilityPlaybackEvent]
        do throws(NotabilityReadingError) {
            playbackEvents = try readPlaybackEvents(in: requiredFields(NotabilitySessionKey.contentPlaybackEventManager, in: session), ink: ink)
        } catch {
            issues.report(.playbackEventsSkipped(error))
            playbackEvents = []
        }
        return NotabilitySessionContent(
            name: try optionalString(NotabilitySessionKey.name, in: session), sessionFormatVersion: sessionFormatVersion,
            applicationVersion: try optionalString(NotabilitySessionKey.applicationVersion, in: session), paper: paper,
            reflowState: reflowState, pageGeometry: NotabilityPageGeometry(pageWidthInUnits: pageWidth, paper: paper), ink: ink, shapes: shapes,
            pictures: pictures, typedText: typedText, importedPDFPages: importedPDFPages, playbackEvents: playbackEvents)
    }

    private mutating func sessionFormatVersion(in session: KeyedArchiveFields) throws(NotabilityReadingError) -> Int64? {
        let version = try NotabilityReadingError.readingSession { () throws(KeyedArchiveError) -> Int64? in
            let storedVersion = try archive.value(named: NotabilitySessionKey.sessionFormatVersion.rawValue, in: session)
            guard case .primitive(.integer(let version), _)? = storedVersion else { return nil }
            return version
        }
        if version != Self.supportedSessionFormatVersion { issues.report(.sessionFormatNotSupported(version: version)) }
        return version
    }

    private func paper(from attributes: KeyedArchiveFields) throws(NotabilityReadingError) -> NotabilityPaper {
        NotabilityPaper(
            identifier: try optionalString(NotabilityPaperAttributeKey.identifier, in: attributes).map(NotabilityPaperIdentifier.init(rawIdentifier:)),
            size: try optionalString(NotabilityPaperAttributeKey.size, in: attributes).map(NotabilityPaperSize.init(rawSize:)),
            orientation: try optionalString(NotabilityPaperAttributeKey.orientation, in: attributes).map(NotabilityPaperOrientation.init(rawOrientation:)),
            sizingBehaviour: try optionalString(NotabilityPaperAttributeKey.sizingBehaviour, in: attributes)
                .map(NotabilityPaperSizingBehaviour.init(rawBehaviour:)),
            lineStyle: try optionalString(NotabilityPaperAttributeKey.lineStyle, in: attributes).map(NotabilityPaperLineStyle.init(rawStyle:)))
    }

    /// The page width is the reflow state's when stored, else the locked width of the paper's sizing behaviour; a
    /// note with neither is expected to be reflowable, and any other reflow state is reported.
    private mutating func reflowStateAndPageWidth(in richText: KeyedArchiveFields,
                                                  paper: NotabilityPaper) throws(NotabilityReadingError) -> (NotabilityReflowState, Double?) {
        let reflowValue = try NotabilityReadingError.readingSession { () throws(KeyedArchiveError) in
            try archive.requiredValue(named: NotabilityRichTextKey.reflowState.rawValue, in: richText)
        }
        guard case .object(let reflowObject) = reflowValue else {
            throw .session(.valueNotOfExpectedKind(expected: .object, objectIndex: reflowValue.objectIndex))
        }
        let reflowFields = try NotabilityReadingError.readingSession { () throws(KeyedArchiveError) in try archive.fields(of: reflowValue) }
        let storedWidth = try optionalNumber(NotabilityReflowStateKey.pageWidth, in: reflowFields)
        let reflowState: NotabilityReflowState
        switch reflowObject.className {
        case "NBReflowStateLocked":
            reflowState = .locked(pageWidth: storedWidth, device: try optionalString(NotabilityReflowStateKey.nativeLayoutDevice, in: reflowFields))
        case "NBReflowStateReflowable": reflowState = .reflowable
        default: reflowState = .unknown(className: reflowObject.className)
        }
        var width = storedWidth
        if width == nil, case .lockedWidth(let lockedWidth, _)? = paper.sizingBehaviour { width = lockedWidth }
        guard let width else {
            if reflowState != .reflowable { issues.report(.reflowStateUnknown(className: reflowObject.className)) }
            return (reflowState, nil)
        }
        guard width.isFinite && width > 0 else {
            issues.report(.pageWidthNotUsable(widthInUnits: width))
            return (reflowState, nil)
        }
        return (reflowState, width)
    }

    private mutating func readImportedPDFPages(in richText: KeyedArchiveFields) throws(NotabilityReadingError) -> [NotabilityImportedPDFPage] {
        var pages: [NotabilityImportedPDFPage] = []
        for (layoutIndex, layoutReference) in try optionalMembers(NotabilityRichTextKey.pageLayoutArray, in: richText).enumerated() {
            do throws(NotabilityReadingError) {
                pages.append(try readImportedPDFPage(layoutReference))
            } catch {
                issues.report(.pageLayoutSkipped(layoutIndex: layoutIndex, error))
            }
        }
        return pages
    }

    private mutating func readImportedPDFPage(_ layoutReference: KeyedArchiveReference) throws(NotabilityReadingError) -> NotabilityImportedPDFPage {
        let layout = try NotabilityReadingError.readingSession { () throws(KeyedArchiveError) in
            try archive.fields(of: archive.value(of: layoutReference))
        }
        issues.reportUnknownKeys(layout.keys, in: .pageLayout, known: NotabilityKnownKeys.pageLayout)
        var pdfFile: NotebookArchivePath?
        if let fileName = try optionalString(NotabilityPageLayoutKey.pdfFileName, in: layout) {
            pdfFile = NotebookArchivePath.file(named: fileName, inFolder: Self.pdfFolder)
            if pdfFile == nil { issues.report(.archivePathNotValid(path: Self.pdfFolder + "/" + fileName)) }
        }
        return NotabilityImportedPDFPage(
            documentPageNumber: try optionalInteger(NotabilityPageLayoutKey.documentPageNumber, in: layout),
            pdfFile: pdfFile,
            pdfPageNumber: try optionalInteger(NotabilityPageLayoutKey.pdfPageNumber, in: layout),
            isBookmarked: try optionalBoolean(NotabilityPageLayoutKey.isBookmarked, in: layout) ?? false)
    }
}

/// Reads of values under a key, their archive errors wrapped as `NotabilityReadingError.session`. An optional
/// value is nil when its key is absent or `$null`; a value of another kind is an error.
extension NotabilitySessionReading {
    func requiredFields(_ key: some NotabilityKey, in fields: KeyedArchiveFields) throws(NotabilityReadingError) -> KeyedArchiveFields {
        try NotabilityReadingError.readingSession { () throws(KeyedArchiveError) in
            try archive.fields(of: archive.requiredValue(named: key.rawValue, in: fields))
        }
    }

    func optionalFields(_ key: some NotabilityKey, in fields: KeyedArchiveFields) throws(NotabilityReadingError) -> KeyedArchiveFields? {
        try NotabilityReadingError.readingSession { () throws(KeyedArchiveError) -> KeyedArchiveFields? in
            guard let value = try archive.nonNullValue(named: key.rawValue, in: fields) else { return nil }
            return try archive.fields(of: value)
        }
    }

    func optionalMembers(_ key: some NotabilityKey, in fields: KeyedArchiveFields) throws(NotabilityReadingError) -> [KeyedArchiveReference] {
        try NotabilityReadingError.readingSession { () throws(KeyedArchiveError) -> [KeyedArchiveReference] in
            guard let value = try archive.nonNullValue(named: key.rawValue, in: fields) else { return [] }
            return try archive.members(of: value)
        }
    }

    func optionalString(_ key: some NotabilityKey, in fields: KeyedArchiveFields) throws(NotabilityReadingError) -> String? {
        try NotabilityReadingError.readingSession { () throws(KeyedArchiveError) -> String? in
            guard let value = try archive.nonNullValue(named: key.rawValue, in: fields) else { return nil }
            return try archive.string(value)
        }
    }

    func optionalNumber(_ key: some NotabilityKey, in fields: KeyedArchiveFields) throws(NotabilityReadingError) -> Double? {
        try NotabilityReadingError.readingSession { () throws(KeyedArchiveError) -> Double? in
            guard let value = try archive.nonNullValue(named: key.rawValue, in: fields) else { return nil }
            return try archive.number(value)
        }
    }

    func optionalInteger(_ key: some NotabilityKey, in fields: KeyedArchiveFields) throws(NotabilityReadingError) -> Int? {
        try NotabilityReadingError.readingSession { () throws(KeyedArchiveError) -> Int? in
            guard let value = try archive.nonNullValue(named: key.rawValue, in: fields) else { return nil }
            return Int(try archive.integer(value))
        }
    }

    func optionalBoolean(_ key: some NotabilityKey, in fields: KeyedArchiveFields) throws(NotabilityReadingError) -> Bool? {
        try NotabilityReadingError.readingSession { () throws(KeyedArchiveError) -> Bool? in
            guard let value = try archive.nonNullValue(named: key.rawValue, in: fields) else { return nil }
            return try archive.boolean(value)
        }
    }

    /// Whether a value counts as true the way Python's `bool()` counts it: false for nil, false, zero and empty values.
    func isTruthy(_ value: KeyedArchiveValue?) -> Bool {
        switch value {
        case nil, .null?: return false
        case .object?: return true
        case .primitive(let object, _)?:
            switch object {
            case .null: return false
            case .boolean(let flag): return flag
            case .integer(let integer): return integer != 0
            case .real(let real): return real != 0
            case .string(let string): return !string.isEmpty
            case .data(let bytes): return !bytes.isEmpty
            case .array(let memberIndices), .set(let memberIndices): return !memberIndices.isEmpty
            case .dictionary(let keyIndices, _): return !keyIndices.isEmpty
            case .date, .uid: return true
            }
        }
    }
}

extension NotabilitySessionReading {
    /// A read of one picture's or shape's value, its archive error wrapped as the element's failure.
    static func readingElement<Value>(_ read: () throws(KeyedArchiveError) -> Value) throws(NotabilityElementFailure) -> Value {
        do throws(KeyedArchiveError) {
            return try read()
        } catch {
            throw .archive(error)
        }
    }
}

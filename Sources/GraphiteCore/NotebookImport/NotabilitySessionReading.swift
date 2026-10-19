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
        let richText = try requiredFields("richText", in: session)
        issues.reportUnknownKeys(richText.keys, in: .richText, known: NotabilityKnownKeys.richText)
        let paperAttributes = try requiredFields("documentPaperAttributes",
                                                 in: requiredFields("NBNoteTakingSessionDocumentPaperLayoutModelKey", in: session))
        let paper = try paper(from: paperAttributes)
        let (reflowState, pageWidth) = try reflowStateAndPageWidth(in: richText, paper: paper)
        if NotabilityPageGeometry.exportPageSize(of: paper) == nil {
            issues.report(.paperSizeUnknown(rawSize: try optionalString("paperSize", in: paperAttributes)))
        }
        let inkFields = try requiredFields("SpatialHash", in: requiredFields("Handwriting Overlay", in: richText))
        issues.reportUnknownKeys(inkFields.keys, in: .ink, known: NotabilityKnownKeys.ink)
        let ink = try NotabilityInk(fields: inkFields, archive: archive, issues: &issues)
        let shapes = readShapes(in: inkFields)
        let pictures = try readPictures(in: richText)
        let typedText = try readTypedText(in: richText)
        let importedPDFPages = try readImportedPDFPages(in: richText)
        let playbackEvents = try readPlaybackEvents(in: requiredFields("contentPlaybackEventManager", in: session), ink: ink)
        return NotabilitySessionContent(
            name: try optionalString("name", in: session), sessionFormatVersion: sessionFormatVersion,
            applicationVersion: try optionalString("NBNoteTakingSessionBundleVersionNumberKey", in: session), paper: paper,
            reflowState: reflowState, pageGeometry: NotabilityPageGeometry(pageWidthInUnits: pageWidth, paper: paper), ink: ink, shapes: shapes,
            pictures: pictures, typedText: typedText, importedPDFPages: importedPDFPages, playbackEvents: playbackEvents)
    }

    private mutating func sessionFormatVersion(in session: KeyedArchiveFields) throws(NotabilityReadingError) -> Int64? {
        let version = try NotabilityReadingError.readingSession { () throws(KeyedArchiveError) -> Int64? in
            guard case .primitive(.integer(let version), _)? = try archive.value(named: "sessionFormatVersion", in: session) else { return nil }
            return version
        }
        if version != Self.supportedSessionFormatVersion { issues.report(.sessionFormatNotSupported(version: version)) }
        return version
    }

    private func paper(from attributes: KeyedArchiveFields) throws(NotabilityReadingError) -> NotabilityPaper {
        NotabilityPaper(identifier: try optionalString("paperIdentifier", in: attributes).map(NotabilityPaperIdentifier.init(rawIdentifier:)),
                        size: try optionalString("paperSize", in: attributes).map(NotabilityPaperSize.init(rawSize:)),
                        orientation: try optionalString("paperOrientation", in: attributes).map(NotabilityPaperOrientation.init(rawOrientation:)),
                        sizingBehaviour: try optionalString("paperSizingBehavior", in: attributes).map(NotabilityPaperSizingBehaviour.init(rawBehaviour:)),
                        lineStyle: try optionalString("lineStyle2", in: attributes).map(NotabilityPaperLineStyle.init(rawStyle:)))
    }

    /// The page width is the reflow state's when stored, else the locked width of the paper's sizing behaviour; a
    /// note with neither is expected to be reflowable, and any other reflow state is reported.
    private mutating func reflowStateAndPageWidth(in richText: KeyedArchiveFields,
                                                  paper: NotabilityPaper) throws(NotabilityReadingError) -> (NotabilityReflowState, Double?) {
        let reflowValue = try NotabilityReadingError.readingSession { () throws(KeyedArchiveError) in
            try archive.requiredValue(named: "reflowState", in: richText)
        }
        guard case .object(let reflowObject) = reflowValue else {
            throw .session(.valueNotOfExpectedKind(expected: .object, objectIndex: reflowValue.objectIndex))
        }
        let reflowFields = try NotabilityReadingError.readingSession { () throws(KeyedArchiveError) in try archive.fields(of: reflowValue) }
        let storedWidth = try optionalNumber("pageWidthInDocumentCoordsKey", in: reflowFields)
        let reflowState: NotabilityReflowState
        switch reflowObject.className {
        case "NBReflowStateLocked": reflowState = .locked(pageWidth: storedWidth, device: try optionalString("nativeLayoutDeviceStringKey", in: reflowFields))
        case "NBReflowStateReflowable": reflowState = .reflowable
        default: reflowState = .unknown(className: reflowObject.className)
        }
        if let storedWidth { return (reflowState, storedWidth) }
        if case .lockedWidth(let width, _)? = paper.sizingBehaviour { return (reflowState, width) }
        if reflowState != .reflowable { issues.report(.reflowStateUnknown(className: reflowObject.className)) }
        return (reflowState, nil)
    }

    private mutating func readImportedPDFPages(in richText: KeyedArchiveFields) throws(NotabilityReadingError) -> [NotabilityImportedPDFPage] {
        var pages: [NotabilityImportedPDFPage] = []
        for layoutReference in try optionalMembers("pageLayoutArray", in: richText) {
            let layout = try NotabilityReadingError.readingSession { () throws(KeyedArchiveError) in
                try archive.fields(of: archive.value(of: layoutReference))
            }
            issues.reportUnknownKeys(layout.keys, in: .pageLayout, known: NotabilityKnownKeys.pageLayout)
            pages.append(NotabilityImportedPDFPage(
                documentPageNumber: try optionalInteger("kPageLayoutDocumentPageNumberKey", in: layout),
                pdfRelativePath: "PDFs/" + (try optionalString("kPageLayoutPDFFileNameKey", in: layout) ?? ""),
                pdfPageNumber: try optionalInteger("kPageLayoutPDFPageNumberKey", in: layout),
                isBookmarked: try optionalBoolean("kPageLayoutPageIsBookmarkedKey", in: layout) ?? false))
        }
        return pages
    }
}

/// Reads of values under a key, their archive errors wrapped as `NotabilityReadingError.session`. An optional
/// value is nil when its key is absent or `$null`; a value of another kind is an error.
extension NotabilitySessionReading {
    func requiredFields(_ key: String, in fields: KeyedArchiveFields) throws(NotabilityReadingError) -> KeyedArchiveFields {
        try NotabilityReadingError.readingSession { () throws(KeyedArchiveError) in try archive.fields(of: archive.requiredValue(named: key, in: fields)) }
    }

    func optionalFields(_ key: String, in fields: KeyedArchiveFields) throws(NotabilityReadingError) -> KeyedArchiveFields? {
        try NotabilityReadingError.readingSession { () throws(KeyedArchiveError) -> KeyedArchiveFields? in
            guard let value = try archive.nonNullValue(named: key, in: fields) else { return nil }
            return try archive.fields(of: value)
        }
    }

    func optionalMembers(_ key: String, in fields: KeyedArchiveFields) throws(NotabilityReadingError) -> [KeyedArchiveReference] {
        try NotabilityReadingError.readingSession { () throws(KeyedArchiveError) -> [KeyedArchiveReference] in
            guard let value = try archive.nonNullValue(named: key, in: fields) else { return [] }
            return try archive.members(of: value)
        }
    }

    func optionalString(_ key: String, in fields: KeyedArchiveFields) throws(NotabilityReadingError) -> String? {
        try NotabilityReadingError.readingSession { () throws(KeyedArchiveError) -> String? in
            guard let value = try archive.nonNullValue(named: key, in: fields) else { return nil }
            return try archive.string(value)
        }
    }

    func optionalNumber(_ key: String, in fields: KeyedArchiveFields) throws(NotabilityReadingError) -> Double? {
        try NotabilityReadingError.readingSession { () throws(KeyedArchiveError) -> Double? in
            guard let value = try archive.nonNullValue(named: key, in: fields) else { return nil }
            return try archive.number(value)
        }
    }

    func optionalInteger(_ key: String, in fields: KeyedArchiveFields) throws(NotabilityReadingError) -> Int? {
        try NotabilityReadingError.readingSession { () throws(KeyedArchiveError) -> Int? in
            guard let value = try archive.nonNullValue(named: key, in: fields) else { return nil }
            return Int(try archive.integer(value))
        }
    }

    func optionalBoolean(_ key: String, in fields: KeyedArchiveFields) throws(NotabilityReadingError) -> Bool? {
        try NotabilityReadingError.readingSession { () throws(KeyedArchiveError) -> Bool? in
            guard let value = try archive.nonNullValue(named: key, in: fields) else { return nil }
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

import CoreGraphics
import Foundation

/// The kinds of record in a notebook's event log (`index.events.pb`), as far as the samples show them.
enum GoodnotesEventKind: Int {
    case paper = 2
    case pagePaperChanged = 3
    case attachment = 6
    case lastPageViewed = 10
    case documentCreated = 30
    case documentRenamed = 31
    case sharing = 33
    case documentChanged = 34
    case pageCreated = 54
    case pageMoved = 55
    case pageDeleted = 56
    case pageBookmarked = 57
    case outlineEntry = 62
    case pageFlag = 63
    case inkLayerCreated = 102
    case searchIndexFirst = 103
    case searchIndexSecond = 104
    case searchIndexThird = 105
    case inkLayerMembers = 106
    case recording = 160
    case recordingDeleted = 163
}

/// The notebook's event log, applied record by record: each record is `{1: entity id, <kind>: body}`, and editable
/// values are last-writer-wins registers, so a later record with a higher counter replaces an earlier value.
struct GoodnotesEventLog {
    static let attachmentFolder = "attachments"

    private struct PaperRecord {
        let attachmentIdentifier: String
        let pdfPageNumber: UInt64
        let sizeInUnits: CGSize
        let templateIdentifier: String
    }

    private struct PageRecord {
        var paper: GoodnotesRegister?
        var position: GoodnotesRegister?
        var deleted: GoodnotesRegister?
        var bookmarked: GoodnotesRegister?
    }

    private struct RecordingRecord {
        let audioAttachmentIdentifier: String
        let durationSeconds: Double
        let elementTimings: [GoodnotesRecording.ElementTiming]
    }

    private var title: GoodnotesRegister?
    private(set) var attachments: [String: GoodnotesAttachment] = [:]
    private var papers: [String: PaperRecord] = [:]
    private var pages: [String: PageRecord] = [:]
    /// Each ink layer's members, by order id or element id.
    private(set) var layerMembers: [String: Set<String>] = [:]
    private var outlineEntries: [GoodnotesOutlineEntry] = []
    private var recordings: [String: RecordingRecord] = [:]
    private var recordingOrder: [String] = []
    private var deletedRecordings: Set<String> = []
    private var flaggedPages: Set<String> = []
    var issues = GoodnotesIssueList()

    mutating func apply(record: ArraySlice<UInt8>) throws(GoodnotesReadingError) {
        let top = try GoodnotesRecordFields(parsing: record)
        guard let entityField = top.message.fields.first else { throw .emptyRecord }
        let entity = try Self.string(entityField)
        let bodies = top.message.fields.dropFirst()
        guard bodies.count == 1, let body = bodies.first else { throw .eventBodyCount(bodies.count) }
        let bodyBytes: ArraySlice<UInt8>
        do throws(ProtocolBufferError) { bodyBytes = try ProtocolBufferMessage.bytes(of: body.value, fieldNumber: body.number) } catch {
            throw .protocolBuffer(error)
        }
        let fields = try GoodnotesRecordFields(parsing: bodyBytes)
        guard let kind = GoodnotesEventKind(rawValue: body.number) else {
            issues.report(.eventKindNotKnown(body.number))
            return
        }
        try apply(kind, entity: entity, fields: fields)
    }

    private mutating func apply(_ kind: GoodnotesEventKind, entity: String, fields: GoodnotesRecordFields) throws(GoodnotesReadingError) {
        switch kind {
        case .documentCreated, .documentRenamed:
            title = GoodnotesRegister.latest(title, try fields.register(2))
        case .attachment:
            let file = NotebookArchivePath.file(named: try fields.string(2), inFolder: Self.attachmentFolder)
            if file == nil { issues.report(.attachmentPathNotValid(attachmentIdentifier: entity)) }
            attachments[entity] = GoodnotesAttachment(identifier: entity, file: file, byteCount: try fields.varint(5),
                                                      pdfPageCount: try fields.fields(12).varint(2))
        case .paper:
            papers[entity] = PaperRecord(attachmentIdentifier: try fields.string(4), pdfPageNumber: try fields.varint(5) ?? 1,
                                         sizeInUnits: try fields.size(8), templateIdentifier: try fields.string(9))
        case .pageCreated, .pagePaperChanged, .pageMoved, .pageDeleted, .pageBookmarked:
            try applyPageEvent(kind, page: entity, fields: fields)
        case .pageFlag:
            flaggedPages.insert(entity)
        case .outlineEntry:
            outlineEntries.append(GoodnotesOutlineEntry(title: try fields.string(5), orderKey: try fields.string(6),
                                                        pointOnTargetPage: try fields.fields(3).point(1), targetIdentifier: try fields.string(2)))
        case .inkLayerMembers:
            var members: Set<String> = []
            // Each member is a register whose value names an element.
            for member in try fields.repeatedFields(2) { members.insert(try member.string(1)) }
            layerMembers[entity] = members
        case .recording:
            try applyRecording(entity, fields: fields)
        case .recordingDeleted:
            deletedRecordings.insert(entity)
        case .lastPageViewed, .sharing, .documentChanged, .inkLayerCreated, .searchIndexFirst, .searchIndexSecond, .searchIndexThird:
            break
        }
    }

    /// Created and paper changed carry the paper in field 3; created carries the position in 4 and moved a new one
    /// in 3; deleted and bookmarked carry a register in 3 whose value 1 means yes.
    private mutating func applyPageEvent(_ kind: GoodnotesEventKind, page identifier: String, fields: GoodnotesRecordFields) throws(GoodnotesReadingError) {
        var page = pages[identifier] ?? PageRecord()
        if (kind == .pageCreated || kind == .pagePaperChanged) && fields.contains(3) {
            page.paper = GoodnotesRegister.latest(page.paper, try fields.register(3))
        }
        if kind == .pageCreated && fields.contains(4) { page.position = GoodnotesRegister.latest(page.position, try fields.register(4)) }
        if kind == .pageMoved && fields.contains(3) { page.position = GoodnotesRegister.latest(page.position, try fields.register(3)) }
        if kind == .pageDeleted { page.deleted = GoodnotesRegister.latest(page.deleted, try fields.register(3)) }
        if kind == .pageBookmarked { page.bookmarked = GoodnotesRegister.latest(page.bookmarked, try fields.register(3)) }
        pages[identifier] = page
    }

    /// The audio attachment (field 2), the duration (4) and, for each element written during the recording, its
    /// time from the start and its page (5).
    private mutating func applyRecording(_ identifier: String, fields: GoodnotesRecordFields) throws(GoodnotesReadingError) {
        var timings: [GoodnotesRecording.ElementTiming] = []
        for timing in try fields.fields(5).repeatedFields(1) {
            let moment = try timing.fields(2)
            timings.append(GoodnotesRecording.ElementTiming(
                elementIdentifier: try timing.string(1), secondsFromStart: Double(try moment.varint(1) ?? 0) / GoodnotesRecording.flicksPerSecond,
                pageIdentifier: try moment.string(2)))
        }
        if recordings[identifier] == nil { recordingOrder.append(identifier) }
        recordings[identifier] = RecordingRecord(audioAttachmentIdentifier: try fields.string(2),
                                                 durationSeconds: Double(try fields.varint(4) ?? 0) / GoodnotesRecording.flicksPerSecond,
                                                 elementTimings: timings)
    }

    /// The pages in order: those with a position and not deleted, sorted by position byte by byte (a fractional
    /// index), then by identifier.
    func orderedPages() -> (pages: [GoodnotesPageDescriptor], deletedPageCount: Int, issues: [GoodnotesReadingIssue]) {
        var issues = GoodnotesIssueList()
        var placed: [(position: ArraySlice<UInt8>, descriptor: GoodnotesPageDescriptor)] = []
        for (identifier, page) in pages where page.deleted?.varintValue != 1 {
            guard let position = page.position else { continue }
            guard let positionBytes = position.bytesValue else {
                issues.report(.pagePositionNotReadable(pageIdentifier: identifier))
                continue
            }
            placed.append((positionBytes, descriptor(identifier, page, issues: &issues)))
        }
        placed.sort { left, right in
            if left.position != right.position { return left.position.lexicographicallyPrecedes(right.position) }
            return left.descriptor.identifier.utf8.lexicographicallyPrecedes(right.descriptor.identifier.utf8)
        }
        let deletedPageCount = pages.values.filter { page in page.deleted?.varintValue == 1 }.count
        return (placed.map(\.descriptor), deletedPageCount, issues.issues)
    }

    var titleText: String {
        guard let bytes = title?.bytesValue else { return "" }
        return String(validating: bytes, as: UTF8.self) ?? ""
    }

    /// Outline entries sorted by their order key, byte by byte; entries with equal keys keep the log's order.
    var sortedOutlineEntries: [GoodnotesOutlineEntry] {
        outlineEntries.enumerated().sorted { left, right in
            if left.element.orderKey != right.element.orderKey {
                return left.element.orderKey.utf8.lexicographicallyPrecedes(right.element.orderKey.utf8)
            }
            return left.offset < right.offset
        }.map(\.element)
    }

    /// Recordings that were not deleted, in the order the log first names them; a recording whose audio attachment is
    /// not in the log is reported.
    func liveRecordings(issues: inout GoodnotesIssueList) -> [GoodnotesRecording] {
        recordingOrder.filter { identifier in !deletedRecordings.contains(identifier) }.compactMap { identifier in
            recordings[identifier].map { record in
                GoodnotesRecording(identifier: identifier, audio: attachment(record.audioAttachmentIdentifier, issues: &issues),
                                   durationSeconds: record.durationSeconds, elementTimings: record.elementTimings)
            }
        }
    }

    /// The attachment a record names; nil and reported when the log has none of that identifier. An empty identifier
    /// names no attachment.
    func attachment(_ identifier: String, issues: inout GoodnotesIssueList) -> GoodnotesAttachment? {
        guard !identifier.isEmpty else { return nil }
        guard let attachment = attachments[identifier] else {
            issues.report(.attachmentNotInLog(attachmentIdentifier: identifier))
            return nil
        }
        return attachment
    }

    private func descriptor(_ identifier: String, _ page: PageRecord, issues: inout GoodnotesIssueList) -> GoodnotesPageDescriptor {
        var paper: GoodnotesPaper?
        if let paperBytes = page.paper?.bytesValue {
            paper = self.paper(identifier: String(decoding: paperBytes, as: UTF8.self), issues: &issues)
            if paper == nil { issues.report(.paperNotInLog(pageIdentifier: identifier)) }
        }
        return GoodnotesPageDescriptor(identifier: identifier, layerIdentifier: Self.layerIdentifier(forPage: identifier), paper: paper,
                                       isBookmarked: page.bookmarked?.varintValue == 1, isFlagged: flaggedPages.contains(identifier))
    }

    private func paper(identifier: String, issues: inout GoodnotesIssueList) -> GoodnotesPaper? {
        guard let record = papers[identifier] else { return nil }
        return GoodnotesPaper(identifier: identifier, attachment: attachment(record.attachmentIdentifier, issues: &issues),
                              pdfPageNumber: record.pdfPageNumber,
                              sizeInUnits: record.sizeInUnits,
                              template: record.templateIdentifier.isEmpty ? nil : GoodnotesTemplateIdentifier(rawIdentifier: record.templateIdentifier))
    }

    /// A page's ink layer: the page identifier with 1 added to its last byte, without carry (`…25FF` becomes `…2500`).
    static func layerIdentifier(forPage pageIdentifier: String) -> String? {
        guard pageIdentifier.count >= 2, let lastByte = UInt8(pageIdentifier.suffix(2), radix: 16) else { return nil }
        let nextByte = String(lastByte &+ 1, radix: 16, uppercase: true)
        return String(pageIdentifier.dropLast(2)) + (nextByte.count == 1 ? "0" + nextByte : nextByte)
    }

    private static func string(_ field: ProtocolBufferField) throws(GoodnotesReadingError) -> String {
        do throws(ProtocolBufferError) {
            return try ProtocolBufferMessage.string(from: ProtocolBufferMessage.bytes(of: field.value, fieldNumber: field.number), fieldNumber: field.number)
        } catch {
            throw .protocolBuffer(error)
        }
    }
}

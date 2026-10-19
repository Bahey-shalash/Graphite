import Foundation

/// Reads one page's layer file (`notes/<layer id>`): length-prefixed records, each element a header and then its
/// body. The layer is the authority on which elements a page has; the member list of the event log, where there is
/// one, is only checked against it. Elements whose header marks them deleted are left out, and the rest are sorted
/// into drawing order.
struct GoodnotesLayerReader {
    private static let knownHeaderFieldNumbers: Set<Int> = [1, 2, 3, 4, 6, 7, 8, 9, 10, 14, 16]
    private static let headerIdentifierField = 1
    private static let headerDeletedField = 3
    private static let headerOrderIdentifierField = 6

    private struct Header {
        let isDeleted: Bool
        let orderIdentifier: String
    }

    private struct Body {
        let kind: Int
        let fields: GoodnotesRecordFields
    }

    let decoder: GoodnotesElementDecoder
    /// The layer's member list from the event log; nil when the log has none for this layer.
    let members: Set<String>?

    func elements(inLayer layerBytes: ArraySlice<UInt8>, issues: inout GoodnotesIssueList) -> [GoodnotesElement] {
        let (records, framingFailure) = ProtocolBufferMessage.lengthPrefixedRecords(in: layerBytes)
        var headers: [String: Header] = [:]
        var bodies = OrderedBodies()
        for record in records {
            do throws(GoodnotesReadingError) {
                try read(record, headers: &headers, bodies: &bodies, issues: &issues)
            } catch {
                issues.report(.recordSkipped(error))
            }
        }
        if let framingFailure { issues.report(.recordsTruncated(.protocolBuffer(framingFailure))) }
        var placed: [(element: GoodnotesElement, sequence: Int)] = []
        for (sequence, (identifier, body)) in bodies.inFirstSeenOrder.enumerated() {
            guard let header = headers[identifier] else {
                issues.report(.bodyWithoutHeader(elementIdentifier: identifier))
                continue
            }
            if let members, !members.contains(header.orderIdentifier.isEmpty ? identifier : header.orderIdentifier) {
                issues.report(.elementMissingFromMemberList(elementIdentifier: identifier))
            }
            guard !header.isDeleted else { continue }
            do throws(GoodnotesReadingError) {
                if let element = try element(identifier, body, issues: &issues) { placed.append((element, sequence)) }
            } catch {
                issues.report(.elementSkipped(elementIdentifier: identifier, error))
            }
        }
        placed.sort { left, right in (left.element.drawingPosition, left.sequence) < (right.element.drawingPosition, right.sequence) }
        return placed.map(\.element)
    }

    /// A header has field 1 and more fields; a body has one field, whose number is its kind.
    private func read(_ record: ArraySlice<UInt8>, headers: inout [String: Header], bodies: inout OrderedBodies,
                      issues: inout GoodnotesIssueList) throws(GoodnotesReadingError) {
        let top = try GoodnotesRecordFields(parsing: record)
        guard let firstField = top.message.fields.first else { throw .emptyRecord }
        if firstField.number == Self.headerIdentifierField && top.message.fields.count > 1 {
            for fieldNumber in top.fieldNumbers.subtracting(Self.knownHeaderFieldNumbers).sorted() {
                issues.report(.elementHeaderFieldNotKnown(fieldNumber))
            }
            headers[try top.string(Self.headerIdentifierField)] = Header(isDeleted: try top.varint(Self.headerDeletedField) == 1,
                                                                         orderIdentifier: try top.string(Self.headerOrderIdentifierField))
            return
        }
        let bodyBytes: ArraySlice<UInt8>
        do throws(ProtocolBufferError) { bodyBytes = try ProtocolBufferMessage.bytes(of: firstField.value, fieldNumber: firstField.number) } catch {
            throw .protocolBuffer(error)
        }
        let fields = try GoodnotesRecordFields(parsing: bodyBytes)
        bodies.set(Body(kind: firstField.number, fields: fields), for: try fields.string(1))
    }

    private func element(_ identifier: String, _ body: Body, issues: inout GoodnotesIssueList) throws(GoodnotesReadingError) -> GoodnotesElement? {
        guard let kind = GoodnotesElementKind(rawValue: body.kind) else {
            issues.report(.elementKindNotKnown(body.kind))
            return nil
        }
        guard let content = try decoder.content(of: kind, fields: body.fields, issues: &issues) else { return nil }
        let position = try body.fields.fields(kind.positionFieldNumber).clock(1)
        return GoodnotesElement(identifier: identifier, drawingPosition: GoodnotesDrawingPosition(counter: position.counter, replica: position.replica),
                                content: content)
    }

    /// Bodies by element id: a later body of the same id replaces the earlier one but keeps its place.
    private struct OrderedBodies {
        private var identifiers: [String] = []
        private var bodies: [String: Body] = [:]

        mutating func set(_ body: Body, for identifier: String) {
            if bodies.updateValue(body, forKey: identifier) == nil { identifiers.append(identifier) }
        }

        var inFirstSeenOrder: [(String, Body)] {
            identifiers.compactMap { identifier in bodies[identifier].map { body in (identifier, body) } }
        }
    }
}

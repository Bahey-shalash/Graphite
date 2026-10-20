import Foundation

/// Reads one page's layer file (`notes/<layer id>`): length-prefixed records, each element a header and then its
/// body. The layer is the authority on which elements a page has; the member list of the event log, where there is
/// one, is only checked against it. Elements whose header marks them deleted are left out, and the rest are sorted
/// into drawing order.
struct GoodnotesLayerReader {
    private static let knownHeaderFieldNumbers = GoodnotesElementHeaderField.knownFieldNumbers

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
        var bodies = KeyOrderedDictionary<Body>()
        for record in records {
            do throws(GoodnotesReadingError) {
                try read(record, headers: &headers, bodies: &bodies, issues: &issues)
            } catch {
                issues.report(.recordSkipped(error))
            }
        }
        if let framingFailure { issues.report(.recordsTruncated(.protocolBuffer(framingFailure))) }
        var placed: [(element: GoodnotesElement, sequence: Int)] = []
        for (sequence, (identifier, body)) in bodies.entries.enumerated() {
            guard let header = headers[identifier] else {
                issues.report(.bodyWithoutHeader(elementIdentifier: identifier))
                continue
            }
            if let members, !members.contains(header.orderIdentifier.isEmpty ? identifier : header.orderIdentifier) {
                issues.report(.elementMissingFromMemberList(elementIdentifier: identifier))
            }
            guard !header.isDeleted else { continue }
            do throws(GoodnotesReadingError) {
                placed.append((try element(identifier, body, issues: &issues), sequence))
            } catch {
                issues.report(.elementSkipped(elementIdentifier: identifier, error))
            }
        }
        placed.sort { left, right in (left.element.drawingPosition, left.sequence) < (right.element.drawingPosition, right.sequence) }
        return placed.map(\.element)
    }

    /// A header has field 1 and more fields; a body has one field, whose number is its kind.
    private func read(_ record: ArraySlice<UInt8>, headers: inout [String: Header], bodies: inout KeyOrderedDictionary<Body>,
                      issues: inout GoodnotesIssueList) throws(GoodnotesReadingError) {
        let top = try GoodnotesRecordFields(parsing: record)
        guard let firstField = top.message.fields.first else { throw .emptyRecord }
        if firstField.number == GoodnotesElementHeaderField.elementIdentifier.rawValue && top.message.fields.count > 1 {
            for fieldNumber in top.fieldNumbers.subtracting(Self.knownHeaderFieldNumbers).sorted() {
                issues.report(.elementHeaderFieldNotKnown(fieldNumber))
            }
            headers[try top.string(GoodnotesElementHeaderField.elementIdentifier)] = Header(
                isDeleted: try top.varint(GoodnotesElementHeaderField.isDeleted) == 1,
                orderIdentifier: try top.string(GoodnotesElementHeaderField.orderIdentifier))
            return
        }
        let bodyBytes: ArraySlice<UInt8>
        do throws(ProtocolBufferError) { bodyBytes = try ProtocolBufferMessage.bytes(of: firstField.value, fieldNumber: firstField.number) } catch {
            throw .protocolBuffer(error)
        }
        let fields = try GoodnotesRecordFields(parsing: bodyBytes)
        // A later body of the same element replaces the earlier one but keeps its place.
        bodies.setValue(Body(kind: firstField.number, fields: fields), named: try fields.string(GoodnotesElementBodyField.elementIdentifier))
    }

    /// An element of a kind or path layout this reader does not know is kept, and reported with its identifier.
    private func element(_ identifier: String, _ body: Body, issues: inout GoodnotesIssueList) throws(GoodnotesReadingError) -> GoodnotesElement {
        guard let kind = GoodnotesElementKind(rawValue: body.kind) else {
            issues.report(.elementKindNotKnown(kind: body.kind, elementIdentifier: identifier))
            return GoodnotesElement(identifier: identifier, drawingPosition: .unknown,
                                    content: .unknown(kind: body.kind, fieldNumbers: body.fields.fieldNumbers.sorted()))
        }
        let content = try decoder.content(of: kind, fields: body.fields, issues: &issues)
        if case .stroke(let stroke) = content, case .unknownLayout(let formatString) = stroke.path {
            issues.report(.strokePathFormatNotKnown(formatString: formatString, elementIdentifier: identifier))
        }
        let position = try body.fields.fields(kind.positionFieldNumber).clock(1)
        return GoodnotesElement(identifier: identifier, drawingPosition: GoodnotesDrawingPosition(counter: position.counter, replica: position.replica),
                                content: content)
    }
}

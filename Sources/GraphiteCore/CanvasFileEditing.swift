import Foundation
import CoreGraphics

/// One change to a canvas. Each changes only the bytes of what it names: a moved card
/// gets new numbers for `x` and `y`, and the rest of the file stays as written.
public enum CanvasChange: Sendable {
    /// Moves or resizes cards. Positions and sizes are written as whole pixels.
    case setFrames([String: CGRect])
    /// - Parameter color: Nil removes the color.
    case setNodeColor(CanvasColor?, nodeIdentifiers: Set<String>)
    case setEdgeColor(CanvasColor?, edgeIdentifiers: Set<String>)
    case setText(String, nodeIdentifier: String)
    /// An empty label removes it.
    case setGroupLabel(String, nodeIdentifier: String)
    case setEdgeLabel(String, edgeIdentifier: String)
    case setEdgeEnds(fromEnd: CanvasEdgeEnd, toEnd: CanvasEdgeEnd, edgeIdentifiers: Set<String>)
    /// Adds cards on top of the others, and connections.
    case add(nodes: [CanvasNode], edges: [CanvasEdge])
    /// Copies cards and connections with everything written in them, known or not, under
    /// new `id`s.
    case duplicate(nodes: [CanvasNodeCopy], edges: [CanvasEdgeCopy])
    /// Removes cards, the connections attached to them, and the named connections.
    case remove(nodeIdentifiers: Set<String>, edgeIdentifiers: Set<String>)
    /// Moves cards to the end of the file's list, which draws them on top.
    case moveToFront(nodeIdentifiers: Set<String>)
    case moveToBack(nodeIdentifiers: Set<String>)
}

public struct CanvasNodeCopy: Sendable {
    public let sourceIdentifier: String
    public let newIdentifier: String
    public let origin: CGPoint

    public init(sourceIdentifier: String, newIdentifier: String, origin: CGPoint) {
        self.sourceIdentifier = sourceIdentifier; self.newIdentifier = newIdentifier; self.origin = origin
    }
}

public struct CanvasEdgeCopy: Sendable {
    public let sourceIdentifier: String
    public let newIdentifier: String
    public let fromNode: String
    public let toNode: String

    public init(sourceIdentifier: String, newIdentifier: String, fromNode: String, toNode: String) {
        self.sourceIdentifier = sourceIdentifier; self.newIdentifier = newIdentifier; self.fromNode = fromNode; self.toNode = toNode
    }
}

/// One replacement of a run of bytes.
struct CanvasSplice: Sendable, Equatable {
    let range: Range<Int>
    let replacement: [UInt8]
}

/// The byte replacements that turn one version of a canvas file into another. Applying
/// a patch also gives the patch that turns the result back, byte for byte, which is what
/// Undo keeps: only the bytes that changed, not a copy of the file.
public struct CanvasPatch: Sendable {
    /// Each step's splices are in ascending order, do not overlap, and refer to the bytes
    /// the step before it produced.
    let steps: [[CanvasSplice]]

    public var isEmpty: Bool { steps.allSatisfy(\.isEmpty) }

    /// Nil when the patch does not fit these bytes, as when it was made for another version.
    func applying(to bytes: [UInt8]) -> (bytes: [UInt8], inverse: CanvasPatch)? {
        var currentBytes = bytes
        var inverseSteps: [[CanvasSplice]] = []
        for splices in steps {
            var output: [UInt8] = []
            output.reserveCapacity(currentBytes.count)
            var inverseSplices: [CanvasSplice] = []
            var copiedUpTo = 0
            for splice in splices {
                guard splice.range.lowerBound >= copiedUpTo, splice.range.upperBound <= currentBytes.count else { return nil }
                output += currentBytes[copiedUpTo..<splice.range.lowerBound]
                inverseSplices.append(CanvasSplice(range: output.count..<output.count + splice.replacement.count, replacement: Array(currentBytes[splice.range])))
                output += splice.replacement
                copiedUpTo = splice.range.upperBound
            }
            output += currentBytes[copiedUpTo...]
            currentBytes = output
            inverseSteps.append(inverseSplices)
        }
        return (currentBytes, CanvasPatch(steps: inverseSteps.reversed()))
    }
}

extension CanvasFile {
    /// The canvas with `changes` made one after the other, and the patch that turns it
    /// back. A file that comes out unreadable is never returned.
    public func applying(_ changes: [CanvasChange]) throws -> (file: CanvasFile, undoPatch: CanvasPatch) {
        var currentFile = self
        var inverseSteps: [[CanvasSplice]] = []
        for change in changes {
            let splices = try currentFile.splices(for: change).sorted { firstSplice, secondSplice in
                (firstSplice.range.lowerBound, firstSplice.range.upperBound) < (secondSplice.range.lowerBound, secondSplice.range.upperBound)
            }
            guard !splices.isEmpty else { continue }
            guard let result = CanvasPatch(steps: [splices]).applying(to: currentFile.bytes) else { throw CanvasFileError.editNotApplied }
            do { currentFile = try CanvasFile(validatedBytes: result.bytes) } catch { throw CanvasFileError.editNotApplied }
            inverseSteps.insert(contentsOf: result.inverse.steps, at: 0)
        }
        return (currentFile, CanvasPatch(steps: inverseSteps))
    }

    /// The canvas with a patch from `applying(_:)` applied: an undo, or the redo the undo gave.
    public func applying(_ patch: CanvasPatch) throws -> (file: CanvasFile, undoPatch: CanvasPatch) {
        guard let result = patch.applying(to: bytes) else { throw CanvasFileError.editNotApplied }
        do { return (try CanvasFile(validatedBytes: result.bytes), result.inverse) } catch { throw CanvasFileError.editNotApplied }
    }

    /// An `id` as Obsidian makes them: 16 hexadecimal digits, different from every `id` in
    /// the file and in `taken`.
    public func newIdentifier(avoiding taken: Set<String> = []) -> String {
        var generator = SystemRandomNumberGenerator()
        return newIdentifier(avoiding: taken, using: &generator)
    }

    func newIdentifier(avoiding taken: Set<String>, using generator: inout some RandomNumberGenerator) -> String {
        let identifiersInFile = identifiersInFile
        while true {
            let candidate = String(format: "%016llx", UInt64.random(in: .min ... .max, using: &generator))
            if !identifiersInFile.contains(candidate), !taken.contains(candidate) { return candidate }
        }
    }

    // MARK: Splices

    private func splices(for change: CanvasChange) throws -> [CanvasSplice] {
        switch change {
        case .setFrames(let framesByIdentifier):
            return try framesByIdentifier.flatMap { identifier, frame in
                var edit = CanvasObjectEdit(object: try nodeValue(identifier), bytes: bytes)
                edit.setNumber("x", to: frame.minX)
                edit.setNumber("y", to: frame.minY)
                edit.setNumber("width", to: max(frame.width, 1))
                edit.setNumber("height", to: max(frame.height, 1))
                return edit.splices()
            }
        case .setNodeColor(let color, let nodeIdentifiers):
            return try nodeIdentifiers.flatMap { identifier in
                var edit = CanvasObjectEdit(object: try nodeValue(identifier), bytes: bytes)
                if node(withIdentifier: identifier)?.color != color { edit.setString("color", to: color?.text) }
                return edit.splices()
            }
        case .setEdgeColor(let color, let edgeIdentifiers):
            return try edgeIdentifiers.flatMap { identifier in
                var edit = CanvasObjectEdit(object: try edgeValue(identifier), bytes: bytes)
                if edge(withIdentifier: identifier)?.color != color { edit.setString("color", to: color?.text) }
                return edit.splices()
            }
        case .setText(let text, let nodeIdentifier):
            var edit = CanvasObjectEdit(object: try nodeValue(nodeIdentifier), bytes: bytes)
            edit.setString("text", to: text)
            return edit.splices()
        case .setGroupLabel(let label, let nodeIdentifier):
            var edit = CanvasObjectEdit(object: try nodeValue(nodeIdentifier), bytes: bytes)
            edit.setString("label", to: label.isEmpty ? nil : label)
            return edit.splices()
        case .setEdgeLabel(let label, let edgeIdentifier):
            var edit = CanvasObjectEdit(object: try edgeValue(edgeIdentifier), bytes: bytes)
            edit.setString("label", to: label.isEmpty ? nil : label)
            return edit.splices()
        case .setEdgeEnds(let fromEnd, let toEnd, let edgeIdentifiers):
            return try edgeIdentifiers.flatMap { identifier in
                guard let edge = edge(withIdentifier: identifier) else { throw CanvasFileError.missingItem }
                var edit = CanvasObjectEdit(object: try edgeValue(identifier), bytes: bytes)
                // An end is left out of the file when it has the format's default, as Obsidian
                // leaves it out. An end that does not change is not touched either way.
                if edge.fromEnd != fromEnd { edit.setString("fromEnd", to: fromEnd == .none ? nil : fromEnd.rawValue) }
                if edge.toEnd != toEnd { edit.setString("toEnd", to: toEnd == .arrow ? nil : toEnd.rawValue) }
                return edit.splices()
            }
        case .add(let addedNodes, let addedEdges):
            return try appendingSplices(nodeElements: addedNodes.map(Self.elementBytes(of:)), edgeElements: addedEdges.map(Self.elementBytes(of:)))
        case .duplicate(let nodeCopies, let edgeCopies):
            let nodeElements = try nodeCopies.map { copy in
                let sourceValue = try nodeValue(copy.sourceIdentifier)
                var edit = CanvasObjectEdit(object: sourceValue, bytes: bytes)
                edit.setString("id", to: copy.newIdentifier)
                edit.setNumber("x", to: copy.origin.x)
                edit.setNumber("y", to: copy.origin.y)
                return try edit.editedObjectBytes()
            }
            let edgeElements = try edgeCopies.map { copy in
                var edit = CanvasObjectEdit(object: try edgeValue(copy.sourceIdentifier), bytes: bytes)
                edit.setString("id", to: copy.newIdentifier)
                edit.setString("fromNode", to: copy.fromNode)
                edit.setString("toNode", to: copy.toNode)
                return try edit.editedObjectBytes()
            }
            return try appendingSplices(nodeElements: nodeElements, edgeElements: edgeElements)
        case .remove(let nodeIdentifiers, let edgeIdentifiers):
            let removedNodeElementIndexes = Set(try nodeIdentifiers.map { identifier in
                guard let nodeIndex = nodeIndex(withIdentifier: identifier) else { throw CanvasFileError.missingItem }
                return nodeElementIndexes[nodeIndex]
            })
            // A connection goes with either of its cards, as in Obsidian. A removed card
            // whose `id` another card shares leaves the connections to that other card.
            let remainingNames = Set(nodes.filter { node in !nodeIdentifiers.contains(node.id) }.map(\.identifierInFile))
            let orphanedNames = Set(nodes.filter { node in nodeIdentifiers.contains(node.id) }.map(\.identifierInFile)).subtracting(remainingNames)
            var removedEdgeElementIndexes = Set(try edgeIdentifiers.map { identifier in
                guard let edgeIndex = edgeIndex(withIdentifier: identifier) else { throw CanvasFileError.missingItem }
                return edgeElementIndexes[edgeIndex]
            })
            for (edgeIndex, edge) in edges.enumerated() where orphanedNames.contains(edge.fromNode) || orphanedNames.contains(edge.toNode) {
                removedEdgeElementIndexes.insert(edgeElementIndexes[edgeIndex])
            }
            return Self.removalSplices(of: removedNodeElementIndexes, from: root.member("nodes")?.value)
                + Self.removalSplices(of: removedEdgeElementIndexes, from: root.member("edges")?.value)
        case .moveToFront(let nodeIdentifiers):
            return reorderingSplices(movedNodeIdentifiers: nodeIdentifiers, toFront: true)
        case .moveToBack(let nodeIdentifiers):
            return reorderingSplices(movedNodeIdentifiers: nodeIdentifiers, toFront: false)
        }
    }

    private func nodeValue(_ identifier: String) throws -> CanvasJSONValue {
        guard let nodeIndex = nodeIndex(withIdentifier: identifier) else { throw CanvasFileError.missingItem }
        return nodeValues[nodeElementIndexes[nodeIndex]]
    }

    private func edgeValue(_ identifier: String) throws -> CanvasJSONValue {
        guard let edgeIndex = edgeIndex(withIdentifier: identifier) else { throw CanvasFileError.missingItem }
        return edgeValues[edgeElementIndexes[edgeIndex]]
    }

    // MARK: New cards and connections

    /// A new card as Obsidian writes one: on one line, its keys in Obsidian's order.
    private static func elementBytes(of node: CanvasNode) throws -> [UInt8] {
        var members: [(key: String, value: [UInt8])] = [("id", CanvasJSONWriter.string(node.identifierInFile))]
        var trailingMembers: [(key: String, value: [UInt8])] = []
        switch node.content {
        case .text(let text):
            members += [("type", CanvasJSONWriter.string("text")), ("text", CanvasJSONWriter.string(text))]
        case .file(let path, let subpath):
            members += [("type", CanvasJSONWriter.string("file")), ("file", CanvasJSONWriter.string(path))]
            if let subpath, !subpath.isEmpty { members.append(("subpath", CanvasJSONWriter.string(subpath))) }
        case .link(let address):
            members += [("type", CanvasJSONWriter.string("link")), ("url", CanvasJSONWriter.string(address))]
        case .group(let label, let background, let backgroundStyle):
            members.append(("type", CanvasJSONWriter.string("group")))
            if let label, !label.isEmpty { trailingMembers.append(("label", CanvasJSONWriter.string(label))) }
            if let background, !background.isEmpty {
                trailingMembers += [("background", CanvasJSONWriter.string(background)), ("backgroundStyle", CanvasJSONWriter.string(backgroundStyle.rawValue))]
            }
        case .unknown:
            // Graphite does not know what such a card needs; it can only be copied.
            throw CanvasFileError.editNotApplied
        }
        members += [("x", CanvasJSONWriter.integer(node.frame.minX)), ("y", CanvasJSONWriter.integer(node.frame.minY)),
                    ("width", CanvasJSONWriter.integer(max(node.frame.width, 1))), ("height", CanvasJSONWriter.integer(max(node.frame.height, 1)))]
        if let color = node.color { members.append(("color", CanvasJSONWriter.string(color.text))) }
        return objectBytes(members + trailingMembers)
    }

    private static func elementBytes(of edge: CanvasEdge) -> [UInt8] {
        var members: [(key: String, value: [UInt8])] = [("id", CanvasJSONWriter.string(edge.id)), ("fromNode", CanvasJSONWriter.string(edge.fromNode))]
        if let fromSide = edge.fromSide { members.append(("fromSide", CanvasJSONWriter.string(fromSide.rawValue))) }
        if edge.fromEnd != .none { members.append(("fromEnd", CanvasJSONWriter.string(edge.fromEnd.rawValue))) }
        members.append(("toNode", CanvasJSONWriter.string(edge.toNode)))
        if let toSide = edge.toSide { members.append(("toSide", CanvasJSONWriter.string(toSide.rawValue))) }
        if edge.toEnd != .arrow { members.append(("toEnd", CanvasJSONWriter.string(edge.toEnd.rawValue))) }
        if let color = edge.color { members.append(("color", CanvasJSONWriter.string(color.text))) }
        if let label = edge.label, !label.isEmpty { members.append(("label", CanvasJSONWriter.string(label))) }
        return objectBytes(members)
    }

    private static func objectBytes(_ members: [(key: String, value: [UInt8])]) -> [UInt8] {
        var output: [UInt8] = [UInt8(ascii: "{")]
        for (memberIndex, member) in members.enumerated() {
            if memberIndex > 0 { output.append(UInt8(ascii: ",")) }
            output += CanvasJSONWriter.string(member.key)
            output.append(UInt8(ascii: ":"))
            output += member.value
        }
        output.append(UInt8(ascii: "}"))
        return output
    }

    /// Obsidian's layout: a tab per level, one card or connection per line.
    private static let obsidianMemberLeading = Array("\n\t".utf8)

    private func appendingSplices(nodeElements: [[UInt8]], edgeElements: [[UInt8]]) throws -> [CanvasSplice] {
        let rootMembers = root.members ?? []
        // An empty canvas (`{}`, or a file with nothing in it) becomes what Obsidian writes.
        guard !rootMembers.isEmpty else {
            var lists: [[UInt8]] = []
            if !nodeElements.isEmpty { lists.append(Array("\"nodes\":".utf8) + Self.listBytes(nodeElements, memberLeading: Self.obsidianMemberLeading)) }
            if !edgeElements.isEmpty { lists.append(Array("\"edges\":".utf8) + Self.listBytes(edgeElements, memberLeading: Self.obsidianMemberLeading)) }
            guard !lists.isEmpty else { return [] }
            var output: [UInt8] = [UInt8(ascii: "{")]
            for (listIndex, list) in lists.enumerated() {
                if listIndex > 0 { output.append(UInt8(ascii: ",")) }
                output += Self.obsidianMemberLeading + list
            }
            output += Array("\n}".utf8)
            let replacedRange = root.range.isEmpty ? 0..<bytes.count : root.range
            return [CanvasSplice(range: replacedRange, replacement: output)]
        }
        // The whitespace the file puts before each top-level key says how it is laid out.
        let memberLeading = Array(bytes[root.range.lowerBound + 1..<rootMembers[0].keyRange.lowerBound])
        var rootEdit = CanvasObjectEdit(object: root, bytes: bytes)
        var splices: [CanvasSplice] = []
        for (listName, elements) in [("nodes", nodeElements), ("edges", edgeElements)] where !elements.isEmpty {
            guard let list = root.member(listName)?.value, let existingElements = list.elements else {
                // No list yet, or `null` in its place.
                rootEdit.setRawValue(listName, to: Self.listBytes(elements, memberLeading: memberLeading))
                continue
            }
            guard let lastElement = existingElements.last else {
                splices.append(CanvasSplice(range: list.range, replacement: Self.listBytes(elements, memberLeading: memberLeading)))
                continue
            }
            // New entries are set apart as the last two entries are, or, with one entry, as
            // it is set apart from the opening bracket.
            var separator: [UInt8] = [UInt8(ascii: ",")] + bytes[list.range.lowerBound + 1..<existingElements[0].range.lowerBound]
            if existingElements.count > 1 {
                separator = Array(bytes[existingElements[existingElements.count - 2].range.upperBound..<lastElement.range.lowerBound])
            }
            let insertion = elements.flatMap { element in separator + element }
            splices.append(CanvasSplice(range: lastElement.range.upperBound..<lastElement.range.upperBound, replacement: insertion))
        }
        return splices + rootEdit.splices()
    }

    /// A new list holding `elements`, laid out like a file whose top-level keys are
    /// preceded by `memberLeading`: one entry per line when that has a line break, all
    /// on one line otherwise.
    private static func listBytes(_ elements: [[UInt8]], memberLeading: [UInt8]) -> [UInt8] {
        guard let lineBreakIndex = memberLeading.lastIndex(where: { byte in byte == 0x0A || byte == 0x0D }) else {
            return [UInt8(ascii: "[")] + elements.joined(separator: [UInt8(ascii: ",")]) + [UInt8(ascii: "]")]
        }
        let indentation = memberLeading[(lineBreakIndex + 1)...]
        let elementLeading = memberLeading + indentation
        var output: [UInt8] = [UInt8(ascii: "[")]
        for (elementIndex, element) in elements.enumerated() {
            if elementIndex > 0 { output.append(UInt8(ascii: ",")) }
            output += elementLeading + element
        }
        return output + memberLeading + [UInt8(ascii: "]")]
    }

    // MARK: Removing and reordering

    /// Removes entries from a list with the comma and whitespace that set each apart, so
    /// the entries that stay keep their own lines.
    private static func removalSplices(of removedElementIndexes: Set<Int>, from list: CanvasJSONValue?) -> [CanvasSplice] {
        guard let list, let elements = list.elements, !removedElementIndexes.isEmpty else { return [] }
        return removalRanges(of: removedElementIndexes, itemCount: elements.count, containerRange: list.range,
                             start: { elementIndex in elements[elementIndex].range.lowerBound },
                             end: { elementIndex in elements[elementIndex].range.upperBound })
            .map { range in CanvasSplice(range: range, replacement: []) }
    }

    /// The byte ranges to delete so that the items at `removedIndexes` of a list or an
    /// object are gone and what is left is still separated by single commas.
    static func removalRanges(of removedIndexes: Set<Int>, itemCount: Int, containerRange: Range<Int>, start: (Int) -> Int, end: (Int) -> Int) -> [Range<Int>] {
        var ranges: [Range<Int>] = []
        var itemIndex = 0
        while itemIndex < itemCount {
            guard removedIndexes.contains(itemIndex) else { itemIndex += 1; continue }
            let runStart = itemIndex
            while itemIndex < itemCount, removedIndexes.contains(itemIndex) { itemIndex += 1 }
            let runEnd = itemIndex - 1
            if runStart > 0 {
                // With the comma before the run.
                ranges.append(end(runStart - 1)..<end(runEnd))
            } else if runEnd < itemCount - 1 {
                // With the comma after the run.
                ranges.append(start(runStart)..<start(runEnd + 1))
            } else {
                // Nothing is left: the brackets close up.
                ranges.append(containerRange.lowerBound + 1..<containerRange.upperBound - 1)
            }
        }
        return ranges
    }

    /// Moves cards to the end or the start of the list. Entries trade places; the commas
    /// and whitespace between them stay where they are.
    private func reorderingSplices(movedNodeIdentifiers: Set<String>, toFront: Bool) -> [CanvasSplice] {
        let elements = nodeValues
        let movedElementIndexes = Set(movedNodeIdentifiers.compactMap { identifier in nodeIndex(withIdentifier: identifier).map { nodeIndex in nodeElementIndexes[nodeIndex] } })
        guard !movedElementIndexes.isEmpty else { return [] }
        let moved = elements.indices.filter { elementIndex in movedElementIndexes.contains(elementIndex) }
        let others = elements.indices.filter { elementIndex in !movedElementIndexes.contains(elementIndex) }
        let newOrder = toFront ? others + moved : moved + others
        guard let firstChangedPosition = newOrder.indices.first(where: { position in newOrder[position] != position }),
              let lastChangedPosition = newOrder.indices.last(where: { position in newOrder[position] != position }) else { return [] }
        var output: [UInt8] = []
        for position in firstChangedPosition...lastChangedPosition {
            output += bytes[elements[newOrder[position]].range]
            if position < lastChangedPosition { output += bytes[elements[position].range.upperBound..<elements[position + 1].range.lowerBound] }
        }
        return [CanvasSplice(range: elements[firstChangedPosition].range.lowerBound..<elements[lastChangedPosition].range.upperBound, replacement: output)]
    }
}

/// Changes to the keys of one JSON object of a canvas file: a card, a connection, or
/// the file's top level. A key that is there gets a new value in place; a new key is
/// added after the last one, written the way the object writes its other keys.
struct CanvasObjectEdit {
    private let object: CanvasJSONValue
    private let members: [CanvasJSONValue.Member]
    private let bytes: [UInt8]
    private var replacedValues: [Int: [UInt8]] = [:]
    private var removedMemberIndexes: Set<Int> = []
    private var addedMembers: [(key: String, value: [UInt8])] = []

    init(object: CanvasJSONValue, bytes: [UInt8]) {
        self.object = object
        members = object.members ?? []
        self.bytes = bytes
    }

    /// Writes a whole number, unless the key already holds that number, however written.
    mutating func setNumber(_ key: String, to number: Double) {
        let wholeNumber = CanvasJSONWriter.wholeNumber(number)
        if let existingNumber = members.last(where: { member in member.key == key })?.value.number, existingNumber == Double(wholeNumber) { return }
        setRawValue(key, to: Array(String(wholeNumber).utf8))
    }

    /// Writes a string, unless the key already holds that text, however escaped. Nil
    /// removes the key.
    mutating func setString(_ key: String, to text: String?) {
        guard let text else {
            for (memberIndex, member) in members.enumerated() where member.key == key { removedMemberIndexes.insert(memberIndex) }
            addedMembers.removeAll { member in member.key == key }
            return
        }
        if members.last(where: { member in member.key == key })?.value.string == text { return }
        setRawValue(key, to: CanvasJSONWriter.string(text))
    }

    mutating func setRawValue(_ key: String, to valueBytes: [UInt8]) {
        if let memberIndex = members.lastIndex(where: { member in member.key == key }) {
            replacedValues[memberIndex] = valueBytes
        } else if let addedIndex = addedMembers.firstIndex(where: { member in member.key == key }) {
            addedMembers[addedIndex].value = valueBytes
        } else {
            addedMembers.append((key, valueBytes))
        }
    }

    func splices() -> [CanvasSplice] {
        var splices: [CanvasSplice] = []
        for (memberIndex, valueBytes) in replacedValues where !removedMemberIndexes.contains(memberIndex) {
            let valueRange = members[memberIndex].value.range
            if !bytes[valueRange].elementsEqual(valueBytes) { splices.append(CanvasSplice(range: valueRange, replacement: valueBytes)) }
        }
        let keepsAMember = removedMemberIndexes.count < members.count
        if !keepsAMember, !members.isEmpty, !addedMembers.isEmpty {
            // Every key goes and new ones come: the braces keep only the new keys.
            return [CanvasSplice(range: object.range.lowerBound + 1..<object.range.upperBound - 1, replacement: joinedMembers(addedMembers, separator: [UInt8(ascii: ",")], keySeparator: [UInt8(ascii: ":")]))]
        }
        splices += CanvasFile.removalRanges(of: removedMemberIndexes, itemCount: members.count, containerRange: object.range,
                                           start: { memberIndex in members[memberIndex].keyRange.lowerBound },
                                           end: { memberIndex in members[memberIndex].value.range.upperBound })
            .map { range in CanvasSplice(range: range, replacement: []) }
        guard !addedMembers.isEmpty else { return splices }
        guard let lastMember = members.last else {
            splices.append(CanvasSplice(range: object.range.lowerBound + 1..<object.range.lowerBound + 1,
                                        replacement: joinedMembers(addedMembers, separator: [UInt8(ascii: ",")], keySeparator: [UInt8(ascii: ":")])))
            return splices
        }
        // New keys are set apart as the object's last two keys are, or, with one key, as
        // it is set apart from the opening brace.
        var separator: [UInt8] = [UInt8(ascii: ",")] + bytes[object.range.lowerBound + 1..<members[0].keyRange.lowerBound]
        if members.count > 1 { separator = Array(bytes[members[members.count - 2].value.range.upperBound..<lastMember.keyRange.lowerBound]) }
        let keySeparator = Array(bytes[lastMember.keyRange.upperBound..<lastMember.value.range.lowerBound])
        let insertion = separator + joinedMembers(addedMembers, separator: separator, keySeparator: keySeparator)
        splices.append(CanvasSplice(range: lastMember.value.range.upperBound..<lastMember.value.range.upperBound, replacement: insertion))
        return splices
    }

    /// The object's own bytes with the changes made, for a copy of it.
    func editedObjectBytes() throws -> [UInt8] {
        let objectStart = object.range.lowerBound
        let localSplices = splices().map { splice in
            CanvasSplice(range: splice.range.lowerBound - objectStart..<splice.range.upperBound - objectStart, replacement: splice.replacement)
        }.sorted { firstSplice, secondSplice in
            (firstSplice.range.lowerBound, firstSplice.range.upperBound) < (secondSplice.range.lowerBound, secondSplice.range.upperBound)
        }
        guard let result = CanvasPatch(steps: [localSplices]).applying(to: Array(bytes[object.range])) else { throw CanvasFileError.editNotApplied }
        return result.bytes
    }

    private func joinedMembers(_ newMembers: [(key: String, value: [UInt8])], separator: [UInt8], keySeparator: [UInt8]) -> [UInt8] {
        var output: [UInt8] = []
        for (memberIndex, member) in newMembers.enumerated() {
            if memberIndex > 0 { output += separator }
            output += CanvasJSONWriter.string(member.key) + keySeparator + member.value
        }
        return output
    }
}

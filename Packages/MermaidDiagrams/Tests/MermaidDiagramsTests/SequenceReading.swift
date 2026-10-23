@testable import MermaidDiagrams

/// Reads a sequence diagram for a test.
enum SequenceReading {
    struct NotASequenceDiagram: Error {}

    static func sequence(_ source: String, limits: MermaidDiagramLimits = .standard) throws -> SequenceDiagram {
        guard case .sequence(let diagram) = try MermaidDiagramReader.read(source, limits: limits) else { throw NotASequenceDiagram() }
        return diagram
    }

    /// The error reading `source` throws, or nil when it reads.
    static func readError(_ source: String, limits: MermaidDiagramLimits = .standard) -> MermaidDiagramReadError? {
        do {
            _ = try MermaidDiagramReader.read(source, limits: limits)
            return nil
        } catch {
            return error
        }
    }
}

extension SequenceDiagram {
    /// The messages, in order, for tests that look at messages only.
    var messages: [SequenceMessage] {
        events.compactMap { event in
            guard case .message(let message) = event else { return nil }
            return message
        }
    }

    /// The identifiers of the participants, in order.
    var participantIdentifiers: [String] {
        participants.map(\.identifier)
    }

    /// The identifier of a message's source and target.
    func endpoints(of message: SequenceMessage) -> (source: String, target: String) {
        (participants[message.sourceIndex].identifier, participants[message.targetIndex].identifier)
    }
}

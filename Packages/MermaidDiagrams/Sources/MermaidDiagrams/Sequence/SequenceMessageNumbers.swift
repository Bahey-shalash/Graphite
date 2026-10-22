/// The number each message shows under `autonumber`, counted as Mermaid counts them: from 1 by 1 unless a statement
/// gives a start or a step, every message taking the next number whether it is shown or not.
struct SequenceMessageNumbers {
    /// For each event, the text of its message's number, or nil when it shows none.
    let numberTexts: [String?]

    private static let hundredthsPerUnit = 100

    init(events: [SequenceEvent]) {
        var current = Self.hundredthsPerUnit
        var step = Self.hundredthsPerUnit
        var isVisible = false
        var numberTexts: [String?] = []
        numberTexts.reserveCapacity(events.count)
        for event in events {
            switch event {
            case .numbering(let numbering):
                if let first = numbering.firstNumberInHundredths, first != 0 { current = first }
                if let given = numbering.stepInHundredths, given != 0 { step = given }
                isVisible = numbering.isVisible
                numberTexts.append(nil)
            case .message:
                numberTexts.append(isVisible ? Self.text(hundredths: current) : nil)
                current += step
            case .note, .activationStart, .activationEnd, .blockStart, .blockSection, .blockEnd:
                numberTexts.append(nil)
            }
        }
        self.numberTexts = numberTexts
    }

    /// A number written as JavaScript writes it: `3`, `10.1`, `10.01`.
    static func text(hundredths: Int) -> String {
        let whole = hundredths / hundredthsPerUnit
        let fraction = hundredths % hundredthsPerUnit
        if fraction == 0 { return String(whole) }
        if fraction % 10 == 0 { return "\(whole).\(fraction / 10)" }
        return fraction < 10 ? "\(whole).0\(fraction)" : "\(whole).\(fraction)"
    }
}

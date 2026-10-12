import Foundation

/// How Read Aloud makes its sound.
public enum ReadAloudQualityMode: String, Codable, Sendable, CaseIterable {
    /// A downloaded neural voice renders the note ahead of time, passage by passage.
    case highQuality
    /// The system's voice speaks immediately, with its own word timings.
    case quick

    /// High Quality whenever a neural voice is downloaded, unless the person chose Quick;
    /// Quick when there is no voice to render with.
    public static func effective(chosen: ReadAloudQualityMode?, hasDownloadedVoice: Bool) -> ReadAloudQualityMode {
        guard hasDownloadedVoice else { return .quick }
        return chosen ?? .highQuality
    }
}

/// What to do with the next passage in High Quality mode.
public enum ReadAloudPassageAudioDecision: Equatable, Sendable {
    /// Its rendered audio is ready.
    case playRendered
    /// Not ready, and the person allowed the system voice to fill in for passages that are not.
    case speakWithSystemVoice
    /// Not ready: wait, showing the preparation progress, then play it.
    case waitForRendering
}

public enum ReadAloudPassageAudioPolicy {
    public static func decision(isRendered: Bool, readsUnpreparedPassagesQuickly: Bool) -> ReadAloudPassageAudioDecision {
        if isRendered { return .playRendered }
        return readsUnpreparedPassagesQuickly ? .speakWithSystemVoice : .waitForRendering
    }

    /// The share of a document's text that is rendered, counted in characters so a long
    /// paragraph weighs more than a heading. Empty documents count as ready.
    public static func preparedShare(passageLengths: [Int], renderedPassages: Set<Int>) -> Double {
        let total = passageLengths.reduce(0) { sum, length in sum + max(0, length) }
        guard total > 0 else { return 1 }
        let rendered = passageLengths.enumerated().reduce(0) { sum, element in
            renderedPassages.contains(element.offset) ? sum + max(0, element.element) : sum
        }
        return Double(rendered) / Double(total)
    }
}

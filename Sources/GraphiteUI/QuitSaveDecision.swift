import Foundation

/// How saving the open documents ended when the person asked to quit.
enum QuitSaveOutcome {
    case succeeded
    case failed(any Error)
    /// The deadline passed while a save was still running.
    case timedOut
}

/// Why Graphite stays open instead of quitting.
enum QuitBlockingReason: Equatable {
    case saveFailed(errorDescription: String)
    case saveTooSlow

    /// What the workspace's alert tells the person, who can then resolve the conflict or
    /// save a copy of the note before quitting again.
    var presentedMessage: String {
        switch self {
        case .saveFailed(let errorDescription):
            return "Graphite did not quit because a note could not be saved, and quitting would lose what you typed. Resolve the conflict or save a copy of the note, then quit again. " + errorDescription
        case .saveTooSlow:
            return "Graphite did not quit because saving your notes is taking longer than expected, and quitting now could lose what you typed. Try quitting again in a moment."
        }
    }
}

/// Whether Graphite quits once saving the open documents has ended. Quitting happens only
/// when every save succeeded: a note that cannot be saved, or a save still running, keeps
/// the unsaved text alive in the open app.
struct QuitSaveDecision: Equatable {
    let allowsTermination: Bool
    let blockingReason: QuitBlockingReason?

    init(outcome: QuitSaveOutcome) {
        switch outcome {
        case .succeeded:
            allowsTermination = true
            blockingReason = nil
        case .failed(let error):
            allowsTermination = false
            blockingReason = .saveFailed(errorDescription: error.localizedDescription)
        case .timedOut:
            allowsTermination = false
            blockingReason = .saveTooSlow
        }
    }
}

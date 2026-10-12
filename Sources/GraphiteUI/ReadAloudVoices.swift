import Foundation
#if canImport(UIKit)
import UIKit
#endif
import GraphiteCore
import GraphiteApple
import GraphiteVoices

/// The app's one set of downloadable voices, shared by every window: one background download
/// session, one audio cache and one loaded model, however many workspaces exist.
@MainActor
enum ReadAloudVoices {
    /// Nil only if the shipped manifest is missing or malformed; Read Aloud then offers the
    /// system voice alone.
    static let library: NeuralVoiceLibrary? = try? NeuralVoiceLibrary.standard()

    static let preparation: ReadAloudPassagePreparation? = makePreparation()

    private static func makePreparation() -> ReadAloudPassagePreparation? {
        guard let library else { return nil }
        let preparation = ReadAloudPassagePreparation(cache: library.audioCache, renderer: MLXPassageRenderer(), aligner: OnDeviceSpeechAlignment())
        #if canImport(UIKit)
        // iOS refuses graphics work in the background; rendering waits for Graphite to return.
        NotificationCenter.default.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { ReadAloudVoices.preparation?.suspend() }
        }
        NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { ReadAloudVoices.preparation?.resumeAfterSuspension() }
        }
        #endif
        return preparation
    }

    /// A reading controller whose speech uses a downloaded voice in High Quality mode and the
    /// system voice otherwise.
    static func makeController() -> ReadAloudController {
        guard let library, let preparation else { return ReadAloudController(playsWhenPrepared: true) }
        let speech = NeuralReadAloudSpeech(quick: AppleReadAloudSpeech(), library: library, preparation: preparation)
        return ReadAloudController(session: ReadAloudSession(speech: speech), neuralSpeech: speech, playsWhenPrepared: true)
    }
}

/// What the app scene needs to let voice downloads finish while Graphite is not running.
public enum GraphiteVoiceDownloads {
    public static let sessionIdentifier = NeuralVoiceDownloader.sessionIdentifier

    #if os(iOS)
    /// iOS relaunched Graphite in the background because voice downloads finished; returns
    /// once the downloaded files have been checked and moved, so iOS may suspend it again.
    @MainActor public static func handleBackgroundEvents() async {
        guard let library = ReadAloudVoices.library else { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            library.handleBackgroundDownloadEvents { continuation.resume() }
        }
    }
    #endif
}

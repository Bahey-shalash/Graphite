import Foundation
import AVFoundation
import Observation
#if os(iOS)
import UIKit
#endif
import GraphiteCore
import GraphiteApple

/// Read Aloud's speech in both modes. In Quick mode, and whenever no voice is downloaded, it
/// passes everything to the system voice. In High Quality mode it plays passages the chosen
/// downloaded voice rendered ahead of time, reports the word being heard from the passage's
/// alignment, and waits, showing how much is prepared, for a passage that is not ready yet,
/// or lets the system voice read it when the person allowed that.
@MainActor @Observable
public final class NeuralReadAloudSpeech: ReadAloudSpeaking {
    public var eventHandler: (@MainActor (ReadAloudSpeechEvent) -> Void)?
    /// True while High Quality reading waits for its next passage to be rendered.
    public private(set) var isWaitingForPassage = false
    public let preparation: ReadAloudPassagePreparation
    public let library: NeuralVoiceLibrary

    @ObservationIgnored private let quick: any ReadAloudSpeaking
    @ObservationIgnored private let player = RenderedPassagePlayer()
    @ObservationIgnored private var activeRequest: (identifier: UUID, request: ReadAloudUtteranceRequest)?
    /// The rendered passage playing now and the speech offset its word ranges are shifted by.
    @ObservationIgnored private var playingPassage: CachedReadAloudPassage?
    @ObservationIgnored private var lastReportedWordLocation: Int?
    @ObservationIgnored private var wordTimer: Timer?
    @ObservationIgnored private var pendingStart: Task<Void, Never>?
    private var routesToQuick = false
    @ObservationIgnored private var language = "en"
    #if os(iOS)
    @ObservationIgnored private var ownsActiveAudioSession = false
    #endif

    public init(quick: any ReadAloudSpeaking, library: NeuralVoiceLibrary, preparation: ReadAloudPassagePreparation) {
        self.quick = quick
        self.library = library
        self.preparation = preparation
        quick.eventHandler = { [weak self] event in
            guard let self, self.routesToQuick else { return }
            self.eventHandler?(event)
        }
        #if os(iOS)
        NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] notification in
            let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let rawOptions = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            MainActor.assumeIsolated { self?.audioInterrupted(rawType: rawType, rawOptions: rawOptions) }
        }
        #endif
    }

    // MARK: Pass-through to the system voice

    public var voices: [ReadAloudVoice] { quick.voices }
    public func systemDefaultVoiceIdentifier(language: String) -> String? { quick.systemDefaultVoiceIdentifier(language: language) }
    public func systemVoice(language: String) -> ReadAloudVoice? { quick.systemVoice(language: language) }
    public var assistiveSpeechSettingsMayApply: Bool { quick.assistiveSpeechSettingsMayApply }
    public var personalVoiceStatus: ReadAloudPersonalVoiceStatus { quick.personalVoiceStatus }
    public func requestPersonalVoiceAccess() async -> ReadAloudPersonalVoiceStatus { await quick.requestPersonalVoiceAccess() }

    /// Whether the next passage will be read by a downloaded voice.
    public var readsWithDownloadedVoice: Bool { library.mode == .highQuality && library.selectedVoice != nil }

    public func speak(_ text: String, voiceIdentifier: String, speed: Double, requestIdentifier: UUID) throws {
        try speak(ReadAloudUtteranceRequest(text: text, voiceIdentifier: voiceIdentifier, speed: speed, leadingPauseSeconds: 0,
                                            usesSystemSettings: false), requestIdentifier: requestIdentifier)
    }

    public func speak(_ request: ReadAloudUtteranceRequest, requestIdentifier: UUID) throws {
        stop()
        guard readsWithDownloadedVoice, let voice = library.selectedVoice else {
            routesToQuick = true
            try quick.speak(request, requestIdentifier: requestIdentifier)
            return
        }
        activeRequest = (requestIdentifier, request)
        let passageText = request.passageText ?? request.text
        pendingStart = Task { [weak self] in
            guard let self else { return }
            if let ready = await self.preparation.readyPassage(passageText, voice: voice) {
                self.start(ready, for: requestIdentifier)
                return
            }
            switch ReadAloudPassageAudioPolicy.decision(isRendered: false, readsUnpreparedPassagesQuickly: self.library.readsUnpreparedPassagesQuickly) {
            case .speakWithSystemVoice:
                self.speakQuickly(request, requestIdentifier: requestIdentifier)
            case .waitForRendering, .playRendered:
                self.isWaitingForPassage = true
                let passage = await self.preparation.waitForPassage(passageText, voice: voice)
                guard self.activeRequest?.identifier == requestIdentifier, !Task.isCancelled else { return }
                self.isWaitingForPassage = false
                if let passage { self.start(passage, for: requestIdentifier) }
                else { self.speakQuickly(request, requestIdentifier: requestIdentifier) }
            }
        }
    }

    /// Turns on or off reading unprepared passages with the system voice. Turned on while
    /// reading waits for a passage, that passage starts at once with the system voice.
    public func setReadsUnpreparedPassagesQuickly(_ readsQuickly: Bool) {
        library.readsUnpreparedPassagesQuickly = readsQuickly
        guard readsQuickly, isWaitingForPassage, let active = activeRequest else { return }
        pendingStart?.cancel()
        isWaitingForPassage = false
        speakQuickly(active.request, requestIdentifier: active.identifier)
    }

    /// The downloaded voice reading now, or nil while the system voice reads.
    public var currentVoiceName: String? {
        guard readsWithDownloadedVoice, !routesToQuick, let voice = library.selectedVoice?.description else { return nil }
        return voice.name
    }

    public func prepareAhead(_ passageTexts: [String], from passageIndex: Int) {
        guard readsWithDownloadedVoice, let voice = library.selectedVoice else { return }
        preparation.prepare(passageTexts, from: passageIndex, voice: voice, language: language)
    }

    public func cancelPreparation() {
        preparation.cancel()
    }

    /// The language passages are recognized in for the word highlight.
    public func setLanguage(_ language: String) {
        self.language = language
    }

    private func speakQuickly(_ request: ReadAloudUtteranceRequest, requestIdentifier: UUID) {
        guard activeRequest?.identifier == requestIdentifier else { return }
        activeRequest = nil
        routesToQuick = true
        do { try quick.speak(request, requestIdentifier: requestIdentifier) }
        catch { eventHandler?(.cancelled(requestIdentifier)) }
    }

    private func start(_ passage: CachedReadAloudPassage, for identifier: UUID) {
        guard let active = activeRequest, active.identifier == identifier else { return }
        let request = active.request
        let startSeconds = passage.wordTimings.map { timings in
            ReadAloudWordAlignment.startSeconds(forOffset: request.passageOffset, in: timings)
        } ?? 0
        activateAudioSession()
        pendingStart = Task { [weak self] in
            // The breath before a passage, as with the system voice's pre-utterance delay.
            if request.leadingPauseSeconds > 0 { try? await Task.sleep(for: .seconds(min(request.leadingPauseSeconds, 2))) }
            guard let self, !Task.isCancelled, self.activeRequest?.identifier == identifier else { return }
            do {
                try self.player.play(passage.audioFile, from: startSeconds, rate: request.speed) { [weak self] in
                    self?.passageFinished(identifier)
                }
            } catch {
                self.activeRequest = nil
                self.eventHandler?(.cancelled(identifier))
                return
            }
            self.playingPassage = passage
            self.lastReportedWordLocation = nil
            self.eventHandler?(.started(identifier))
            self.startWordTimer(for: identifier)
        }
    }

    private func startWordTimer(for identifier: UUID) {
        wordTimer?.invalidate()
        // Twenty times a second is finer than a syllable and costs nothing measurable.
        wordTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.reportWord(for: identifier) }
        }
    }

    private func reportWord(for identifier: UUID) {
        guard let active = activeRequest, active.identifier == identifier, let timings = playingPassage?.wordTimings,
              let seconds = player.currentSeconds, let word = ReadAloudWordAlignment.word(at: seconds, in: timings),
              word.location != lastReportedWordLocation else { return }
        lastReportedWordLocation = word.location
        // The session counts ranges from where this request's text starts in the passage.
        let location = word.location - active.request.passageOffset
        guard location >= 0 else { return }
        eventHandler?(.spoken(identifier, NSRange(location: location, length: word.length)))
    }

    private func passageFinished(_ identifier: UUID) {
        guard activeRequest?.identifier == identifier else { return }
        wordTimer?.invalidate()
        activeRequest = nil
        playingPassage = nil
        eventHandler?(.finished(identifier))
    }

    public func pause() -> Bool {
        if routesToQuick { return quick.pause() }
        guard playingPassage != nil, activeRequest != nil else { return false }
        player.pause()
        if let identifier = activeRequest?.identifier { eventHandler?(.paused(identifier)) }
        return true
    }

    public func resume() -> Bool {
        if routesToQuick { return quick.resume() }
        guard playingPassage != nil, let identifier = activeRequest?.identifier, player.isPaused else { return false }
        do { try player.resume() } catch { return false }
        eventHandler?(.continued(identifier))
        return true
    }

    public func stop() {
        pendingStart?.cancel()
        pendingStart = nil
        wordTimer?.invalidate()
        wordTimer = nil
        activeRequest = nil
        playingPassage = nil
        isWaitingForPassage = false
        player.stop()
        if routesToQuick { quick.stop() }
        routesToQuick = false
    }

    /// Changes the speed of the passage playing now without restarting it.
    public func setPlaybackRate(_ rate: Double) {
        player.setRate(rate)
    }

    public func releaseAudio() {
        quick.releaseAudio()
        player.shutDown()
        #if os(iOS)
        guard ownsActiveAudioSession else { return }
        ownsActiveAudioSession = false
        let audioSession = AVAudioSession.sharedInstance()
        guard audioSession.category == .playback else { return }
        try? audioSession.setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }

    /// Spoken audio the person asked for, like an audiobook: it plays with the Ring/Silent
    /// switch on, continues in the background and on the lock screen, and pauses other audio.
    private func activateAudioSession() {
        #if os(iOS)
        guard !ownsActiveAudioSession else { return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
            try AVAudioSession.sharedInstance().setActive(true)
            ownsActiveAudioSession = true
        } catch {
            ownsActiveAudioSession = false
        }
        #endif
    }

    #if os(iOS)
    private func audioInterrupted(rawType: UInt?, rawOptions: UInt) {
        guard !routesToQuick, let rawType, let type = AVAudioSession.InterruptionType(rawValue: rawType) else { return }
        switch type {
        case .began:
            guard activeRequest != nil else { return }
            stop()
            eventHandler?(.interrupted)
        case .ended:
            ownsActiveAudioSession = false
            eventHandler?(.interruptionEnded(shouldResume: AVAudioSession.InterruptionOptions(rawValue: rawOptions).contains(.shouldResume)))
        @unknown default:
            break
        }
    }
    #endif
}

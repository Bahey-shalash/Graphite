import AVFoundation
import Foundation
#if os(iOS)
import UIKit
#endif
import Observation
import GraphiteCore

/// This wrapper only retains the utterance; no framework API or mutable property
/// is exposed across actors. Thread-safe ARC retention prevents address reuse
/// while a delegate callback waits for the main actor. All utterance mutation
/// remains with the main-actor speech adapter and AVFoundation.
private struct SpeechCallbackIdentity: @unchecked Sendable {
    let identifier: ObjectIdentifier
    private let retainedUtterance: AVSpeechUtterance

    init(_ utterance: AVSpeechUtterance) {
        identifier = ObjectIdentifier(utterance)
        retainedUtterance = utterance
    }
}

public struct ReadAloudVoice: Equatable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let language: String
    /// Apple's quality tier (1 compact, 2 Enhanced, 3 Premium), not a listening-test score.
    public let quality: Int
    /// A voice the person recorded themselves and allowed Graphite to use.
    public let isPersonalVoice: Bool
    /// An old-style robotic or novelty voice: Eloquence (Eddy, Flo…), MacinTalk (Fred,
    /// Albert, Bad News…) or one Apple marks as novelty. Used only when picked by hand.
    public let isRobotic: Bool

    public init(id: String, name: String, language: String, quality: Int, isPersonalVoice: Bool = false, isRobotic: Bool? = nil) {
        self.id = id; self.name = name; self.language = language; self.quality = quality
        self.isPersonalVoice = isPersonalVoice
        self.isRobotic = isRobotic ?? Self.isRoboticIdentifier(id)
    }

    public static func isRoboticIdentifier(_ identifier: String) -> Bool {
        ["com.apple.speech.synthesis.voice.", "com.apple.eloquence."].contains { family in identifier.hasPrefix(family) }
    }

    /// Apple's quality tiers, as the voice lists in the system's voice settings name them.
    public var qualityDescription: String {
        if isPersonalVoice { return "Personal Voice" }
        if isRobotic { return "Classic" }
        switch quality {
        case 3...: return "Premium"
        case 2: return "Enhanced"
        default: return "Default"
        }
    }

    /// Default-quality voices are the small built-in ones that sound synthetic over long passages.
    public var isCompact: Bool { !isPersonalVoice && quality < 2 }

    public var languageCode: Substring { language.split(separator: "-").first ?? Substring(language) }

    /// The voice read with when the person has not chosen one: their own Personal Voice when
    /// they allowed it, then Premium, then Enhanced, then compact, always in the passage's
    /// language. Ties prefer the exact region (en-GB for a British device) and then the voice
    /// the system itself uses for that language.
    public static func preferred(in voices: [ReadAloudVoice], language: String,
                                 systemDefaultIdentifier: String? = nil) -> ReadAloudVoice? {
        let languagePrefix = language.split(separator: "-").first
        // Robotic voices are never picked automatically, not even as the last resort.
        return voices.filter { voice in voice.languageCode == languagePrefix && !voice.isRobotic }
            .sorted { first, second in
                if first.isPersonalVoice != second.isPersonalVoice { return first.isPersonalVoice }
                if first.quality != second.quality { return first.quality > second.quality }
                if (first.language == language) != (second.language == language) { return first.language == language }
                if (first.id == systemDefaultIdentifier) != (second.id == systemDefaultIdentifier) { return first.id == systemDefaultIdentifier }
                return first.name.localizedStandardCompare(second.name) == .orderedAscending
            }.first
    }
}

/// Whether the person has let Graphite speak with the Personal Voice they recorded.
public enum ReadAloudPersonalVoiceStatus: Equatable, Sendable {
    case unsupported, notDetermined, denied, authorized
}

public enum ReadAloudSpeechEvent: Sendable {
    case spoken(UUID, NSRange)
    /// The utterance began to sound (after any leading pause).
    case started(UUID)
    case paused(UUID)
    case continued(UUID)
    case finished(UUID)
    case cancelled(UUID)
    case interrupted
    /// A phone call or another app's audio ended; true when the system says playback may resume.
    case interruptionEnded(shouldResume: Bool)
}

/// The substitution boundary covers playback and real timing. Document views have
/// no dependency on AVSpeechUtterance or a future audio-generation service.
@MainActor
public protocol ReadAloudSpeaking: AnyObject {
    var eventHandler: (@MainActor (ReadAloudSpeechEvent) -> Void)? { get set }
    var voices: [ReadAloudVoice] { get }
    func speak(_ text: String, voiceIdentifier: String, speed: Double, requestIdentifier: UUID) throws
    /// Speaks after a silence, the breath between a heading and the paragraph that follows. With
    /// `usesSystemSettings` the system may replace the voice, rate and pitch with the person's
    /// own Read & Speak settings while an assistive feature is on.
    func speak(_ text: String, voiceIdentifier: String, speed: Double, leadingPauseSeconds: Double,
               usesSystemSettings: Bool, requestIdentifier: UUID) throws
    /// The full request, including IPA pronunciations for voices that accept them.
    func speak(_ utterance: ReadAloudUtteranceRequest, requestIdentifier: UUID) throws
    func pause() -> Bool
    func resume() -> Bool
    func stop()
    /// The voice the system uses for a language when nobody chose one, used to break ties.
    func systemDefaultVoiceIdentifier(language: String) -> String?
    /// The voice the system itself speaks a language with, whatever its family, so Graphite can
    /// follow the person's choice even when it would not offer that voice itself.
    func systemVoice(language: String) -> ReadAloudVoice?
    /// Whether an assistive feature that makes the system apply the person's own speech
    /// settings (VoiceOver, Speak Selection, Speak Screen) is on.
    var assistiveSpeechSettingsMayApply: Bool { get }
    var personalVoiceStatus: ReadAloudPersonalVoiceStatus { get }
    /// Shows the system's Personal Voice permission prompt. Call only from a person's tap.
    func requestPersonalVoiceAccess() async -> ReadAloudPersonalVoiceStatus
    /// Gives the audio route back to other apps once reading has stopped or finished.
    func releaseAudio()
    /// The document's passages from the one about to be read to the end, so a voice that
    /// renders ahead of time can start on them. The system voice speaks live and ignores this.
    func prepareAhead(_ passages: [ReadAloudPassage], from passageIndex: Int)
    /// The document was replaced or closed; rendering ahead for it stops.
    func cancelPreparation()
}

public extension ReadAloudSpeaking {
    func speak(_ utterance: ReadAloudUtteranceRequest, requestIdentifier: UUID) throws {
        try speak(utterance.text, voiceIdentifier: utterance.voiceIdentifier, speed: utterance.speed,
                  leadingPauseSeconds: utterance.leadingPauseSeconds, usesSystemSettings: utterance.usesSystemSettings,
                  requestIdentifier: requestIdentifier)
    }
    func speak(_ text: String, voiceIdentifier: String, speed: Double, leadingPauseSeconds: Double,
               usesSystemSettings: Bool, requestIdentifier: UUID) throws {
        try speak(text, voiceIdentifier: voiceIdentifier, speed: speed, requestIdentifier: requestIdentifier)
    }
    func systemVoice(language: String) -> ReadAloudVoice? { nil }
    var assistiveSpeechSettingsMayApply: Bool { false }
    func systemDefaultVoiceIdentifier(language: String) -> String? { nil }
    var personalVoiceStatus: ReadAloudPersonalVoiceStatus { .unsupported }
    func requestPersonalVoiceAccess() async -> ReadAloudPersonalVoiceStatus { .unsupported }
    func releaseAudio() {}
    func prepareAhead(_ passages: [ReadAloudPassage], from passageIndex: Int) {}
    func cancelPreparation() {}
}

@MainActor
public final class AppleReadAloudSpeech: NSObject, ReadAloudSpeaking, AVSpeechSynthesizerDelegate {
    public var eventHandler: (@MainActor (ReadAloudSpeechEvent) -> Void)?
    /// Made on first use: a silent reading never makes one, so it cannot reach the audio output.
    private lazy var synthesizer: AVSpeechSynthesizer = {
        hasCreatedSynthesizer = true
        let synthesizer = AVSpeechSynthesizer()
        synthesizer.delegate = self
        return synthesizer
    }()
    private(set) var hasCreatedSynthesizer = false
    /// How the utterance is voiced. `.speakers` speaks. `.silent` makes no sound and never reaches the synthesizer or the
    /// audio session: its events come at the pace of speech from `SilentSpeechPacing`, by the clock. The integration test of the
    /// synthesizer's own callbacks has it render to buffers that are dropped instead (`rendersToDroppedBuffers`).
    let output: AudioOutputRoute
    private let clock: any ApplicationClock
    private let rendersToDroppedBuffers: Bool
    private var activeUtterance: AVSpeechUtterance?
    private var requestIdentifier: UUID?
    /// The silent reading under way: its steps, the next one to happen, and the task that waits for it.
    private var pacedReading: (requestIdentifier: UUID, steps: [SilentSpeechPacing.Step], nextStepIndex: Int)?
    private var pacingTask: Task<Void, Never>?
    private var isPacedReadingPaused = false
    #if os(iOS)
    /// Whether this adapter activated the shared audio session for reading, so it only ever
    /// deactivates a session it started (never a lecture recording's).
    private var ownsActiveAudioSession = false
    #endif

    public convenience init(output: AudioOutputRoute = .thisProcess, clock: any ApplicationClock = LiveApplicationClock()) {
        self.init(output: output, clock: clock, rendersToDroppedBuffers: false)
    }

    init(output: AudioOutputRoute, clock: any ApplicationClock, rendersToDroppedBuffers: Bool) {
        self.output = output
        self.clock = clock
        self.rendersToDroppedBuffers = rendersToDroppedBuffers
        super.init()
        #if os(iOS)
        NotificationCenter.default.addObserver(self, selector: #selector(audioInterrupted), name: AVAudioSession.interruptionNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(audioInterrupted), name: AVAudioSession.routeChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(audioInterrupted), name: AVAudioSession.mediaServicesWereResetNotification, object: nil)
        #endif
    }

    public var voices: [ReadAloudVoice] {
        AVSpeechSynthesisVoice.speechVoices().filter(Self.isListed).map(Self.voice).sorted { first, second in
            if first.language != second.language { return first.language < second.language }
            if first.quality != second.quality { return first.quality > second.quality }
            return first.name.localizedStandardCompare(second.name) == .orderedAscending
        }
    }

    /// Every Apple voice, the robotic and novelty ones flagged so they can be picked by hand
    /// but never chosen automatically. Third-party voice extensions stay out.
    static func isListed(_ voice: AVSpeechSynthesisVoice) -> Bool {
        voice.voiceTraits.contains(.isPersonalVoice) || voice.identifier.hasPrefix("com.apple.")
    }

    private static func voice(_ voice: AVSpeechSynthesisVoice) -> ReadAloudVoice {
        ReadAloudVoice(id: voice.identifier, name: voice.name, language: voice.language, quality: voice.quality.rawValue,
                       isPersonalVoice: voice.voiceTraits.contains(.isPersonalVoice),
                       isRobotic: voice.voiceTraits.contains(.isNoveltyVoice) || ReadAloudVoice.isRoboticIdentifier(voice.identifier))
    }


    public func systemDefaultVoiceIdentifier(language: String) -> String? {
        AVSpeechSynthesisVoice(language: language)?.identifier
    }

    public func systemVoice(language: String) -> ReadAloudVoice? {
        AVSpeechSynthesisVoice(language: language).map(Self.voice)
    }

    public var assistiveSpeechSettingsMayApply: Bool {
        #if os(iOS)
        UIAccessibility.isVoiceOverRunning || UIAccessibility.isSpeakSelectionEnabled || UIAccessibility.isSpeakScreenEnabled
        #else
        false
        #endif
    }

    public var personalVoiceStatus: ReadAloudPersonalVoiceStatus {
        Self.status(AVSpeechSynthesizer.personalVoiceAuthorizationStatus)
    }

    public func requestPersonalVoiceAccess() async -> ReadAloudPersonalVoiceStatus {
        await withCheckedContinuation { continuation in
            AVSpeechSynthesizer.requestPersonalVoiceAuthorization { status in continuation.resume(returning: Self.status(status)) }
        }
    }

    private nonisolated static func status(_ status: AVSpeechSynthesizer.PersonalVoiceAuthorizationStatus) -> ReadAloudPersonalVoiceStatus {
        switch status {
        case .authorized: .authorized
        case .denied: .denied
        case .notDetermined: .notDetermined
        default: .unsupported
        }
    }

    public func speak(_ text: String, voiceIdentifier: String, speed: Double, requestIdentifier: UUID) throws {
        try speak(text, voiceIdentifier: voiceIdentifier, speed: speed, leadingPauseSeconds: 0,
                  usesSystemSettings: false, requestIdentifier: requestIdentifier)
    }

    public func speak(_ text: String, voiceIdentifier: String, speed: Double, leadingPauseSeconds: Double,
                      usesSystemSettings: Bool, requestIdentifier: UUID) throws {
        try speak(ReadAloudUtteranceRequest(text: text, voiceIdentifier: voiceIdentifier, speed: speed,
                                            leadingPauseSeconds: leadingPauseSeconds, usesSystemSettings: usesSystemSettings),
                  requestIdentifier: requestIdentifier)
    }

    public func speak(_ request: ReadAloudUtteranceRequest, requestIdentifier: UUID) throws {
        let text = request.text, voiceIdentifier = request.voiceIdentifier, speed = request.speed
        let leadingPauseSeconds = request.leadingPauseSeconds, usesSystemSettings = request.usesSystemSettings
        guard let voice = AVSpeechSynthesisVoice(identifier: voiceIdentifier) else {
            throw GraphiteError.unavailable("The chosen voice is no longer installed. Choose a voice before continuing.")
        }
        stop()
        if output == .silent && !rendersToDroppedBuffers {
            startPacedReading(request, requestIdentifier: requestIdentifier)
            return
        }
        if output == .speakers { activateAudioSession() }
        // Terms with an IPA transcription carry it as an attribute; a voice that ignores IPA
        // reads the respelling the text already holds ("sim dee" for SIMD).
        let attributedText = NSMutableAttributedString(string: text)
        let length = (text as NSString).length
        for phonetic in request.phoneticRanges where phonetic.range.location >= 0 && NSMaxRange(phonetic.range) <= length {
            attributedText.addAttribute(NSAttributedString.Key(rawValue: AVSpeechSynthesisIPANotationAttribute),
                                        value: phonetic.notation, range: phonetic.range)
        }
        let utterance = request.phoneticRanges.isEmpty ? AVSpeechUtterance(string: text) : AVSpeechUtterance(attributedString: attributedText)
        utterance.voice = voice
        utterance.rate = Self.rate(forSpeed: speed)
        utterance.pitchMultiplier = 1
        utterance.volume = 1
        // The pause belongs before the next passage rather than after this one, so pausing or
        // moving at the end of a passage never waits for a silence nobody will hear.
        utterance.preUtteranceDelay = max(0, min(leadingPauseSeconds, 2))
        // The system's own voice, rate, pitch and (iOS 27) timbre, sentence pause and equalizer
        // from Read & Speak, when an assistive feature is on; Apple documents that otherwise the
        // utterance's own values are used. The delays above are not among the replaced settings.
        utterance.prefersAssistiveTechnologySettings = usesSystemSettings
        activeUtterance = utterance
        self.requestIdentifier = requestIdentifier
        switch output {
        case .speakers: synthesizer.speak(utterance)
        case .silent: synthesizer.write(utterance) { _ in }
        }
    }

    // MARK: Silent reading

    private func startPacedReading(_ request: ReadAloudUtteranceRequest, requestIdentifier: UUID) {
        let steps = SilentSpeechPacing.schedule(for: request.text, speed: request.speed,
                                                leadingPauseSeconds: max(0, min(request.leadingPauseSeconds, 2)))
        pacedReading = (requestIdentifier, steps, 0)
        isPacedReadingPaused = false
        continuePacedReading()
    }

    /// Waits out each remaining step's delay on the clock and reports its event, until the reading
    /// ends, is paused or is replaced.
    private func continuePacedReading() {
        pacingTask?.cancel()
        guard let reading = pacedReading else { return }
        pacingTask = Task { @MainActor [weak self, clock] in
            var stepIndex = reading.nextStepIndex
            while stepIndex < reading.steps.count {
                let step = reading.steps[stepIndex]
                do { try await clock.sleep(for: .seconds(step.delaySeconds)) } catch { return } // Paused or replaced.
                guard let self, let current = self.pacedReading, current.requestIdentifier == reading.requestIdentifier else { return }
                stepIndex += 1
                self.pacedReading?.nextStepIndex = stepIndex
                switch step.event {
                case .started: self.eventHandler?(.started(reading.requestIdentifier))
                case .word(let range): self.eventHandler?(.spoken(reading.requestIdentifier, range))
                case .finished:
                    self.pacedReading = nil
                    self.eventHandler?(.finished(reading.requestIdentifier))
                }
            }
        }
    }

    /// Reading is spoken audio the person asked for, like an audiobook: it plays with the
    /// Ring/Silent switch on, keeps going in the background and on the lock screen, and
    /// pauses other audio while it speaks.
    private func activateAudioSession() {
        #if os(iOS)
        guard !ownsActiveAudioSession else { return }
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.playback, mode: .spokenAudio)
            try audioSession.setActive(true)
            ownsActiveAudioSession = true
        } catch {
            // Speech still plays through the default session, only without background audio.
            ownsActiveAudioSession = false
        }
        #endif
    }

    public func releaseAudio() {
        #if os(iOS)
        guard ownsActiveAudioSession else { return }
        ownsActiveAudioSession = false
        let audioSession = AVAudioSession.sharedInstance()
        // A recording that started meanwhile changed the category; its session stays active.
        guard audioSession.category == .playback else { return }
        try? audioSession.setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }

    /// The synthesizer's rate for a speed. Its scale is not linear: 0.5 is normal and 1.0 the
    /// fastest a voice reads, about three times normal. Speeds below normal scale the rate;
    /// faster ones spread over what remains, so 3× is the voice's fastest. The voice keeps its
    /// pitch at every rate.
    public nonisolated static func rate(forSpeed speed: Double) -> Float {
        let normal = AVSpeechUtteranceDefaultSpeechRate
        let fastest = AVSpeechUtteranceMaximumSpeechRate
        let rate = speed <= 1 ? normal * Float(speed) : normal + (fastest - normal) * Float((speed - 1) / 2)
        return min(fastest, max(AVSpeechUtteranceMinimumSpeechRate, rate))
    }

    public func pause() -> Bool {
        if let reading = pacedReading {
            guard !isPacedReadingPaused else { return false }
            isPacedReadingPaused = true
            pacingTask?.cancel()
            eventHandler?(.paused(reading.requestIdentifier))
            return true
        }
        guard hasCreatedSynthesizer else { return false }
        return synthesizer.pauseSpeaking(at: .immediate)
    }

    public func resume() -> Bool {
        if let reading = pacedReading {
            guard isPacedReadingPaused else { return false }
            isPacedReadingPaused = false
            continuePacedReading()
            eventHandler?(.continued(reading.requestIdentifier))
            return true
        }
        guard hasCreatedSynthesizer else { return false }
        return synthesizer.continueSpeaking()
    }
    public func stop() {
        // Invalidate before cancellation: a cancelled utterance must never advance
        // a replacement document, even if its callback arrives after speak().
        activeUtterance = nil
        requestIdentifier = nil
        pacedReading = nil
        isPacedReadingPaused = false
        pacingTask?.cancel()
        pacingTask = nil
        if hasCreatedSynthesizer { synthesizer.stopSpeaking(at: .immediate) }
    }

    private func receive(_ identity: SpeechCallbackIdentity, event: (UUID) -> ReadAloudSpeechEvent) {
        withExtendedLifetime(identity) {
            guard let activeUtterance, ObjectIdentifier(activeUtterance) == identity.identifier, let requestIdentifier else { return }
            eventHandler?(event(requestIdentifier))
        }
    }

    nonisolated public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString characterRange: NSRange, utterance: AVSpeechUtterance) {
        let identity = SpeechCallbackIdentity(utterance)
        Task { @MainActor [weak self] in self?.receive(identity) { identifier in .spoken(identifier, characterRange) } }
    }
    nonisolated public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        let identity = SpeechCallbackIdentity(utterance)
        Task { @MainActor [weak self] in self?.receive(identity) { identifier in .started(identifier) } }
    }
    nonisolated public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let identity = SpeechCallbackIdentity(utterance)
        Task { @MainActor [weak self] in self?.receive(identity) { identifier in .finished(identifier) } }
    }
    nonisolated public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        let identity = SpeechCallbackIdentity(utterance)
        Task { @MainActor [weak self] in self?.receive(identity) { identifier in .cancelled(identifier) } }
    }
    nonisolated public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didPause utterance: AVSpeechUtterance) {
        let identity = SpeechCallbackIdentity(utterance)
        Task { @MainActor [weak self] in self?.receive(identity) { identifier in .paused(identifier) } }
    }
    nonisolated public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didContinue utterance: AVSpeechUtterance) {
        let identity = SpeechCallbackIdentity(utterance)
        Task { @MainActor [weak self] in self?.receive(identity) { identifier in .continued(identifier) } }
    }

    #if os(iOS)
    @objc nonisolated private func audioInterrupted(_ notification: Notification) {
        if notification.name == AVAudioSession.interruptionNotification {
            guard let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: rawType) else { return }
            if type == .ended {
                let rawOptions = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
                let shouldResume = AVAudioSession.InterruptionOptions(rawValue: rawOptions).contains(.shouldResume)
                Task { @MainActor [weak self] in
                    // The system deactivated the session during the interruption.
                    self?.ownsActiveAudioSession = false
                    self?.eventHandler?(.interruptionEnded(shouldResume: shouldResume))
                }
                return
            }
        } else if notification.name == AVAudioSession.routeChangeNotification {
            // Unplugged headphones pause, as people expect; newly connected ones simply
            // take over the sound without interrupting it.
            guard let rawReason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                  AVAudioSession.RouteChangeReason(rawValue: rawReason) == .oldDeviceUnavailable else { return }
        }
        let isInterruption = notification.name == AVAudioSession.interruptionNotification
        Task { @MainActor [weak self] in
            guard let self else { return }
            // The system deactivates the session when an interruption begins, and often sends
            // no end; the next reading sets it up again rather than finding it still "owned".
            if isInterruption { self.ownsActiveAudioSession = false }
            guard self.activeUtterance != nil else { return }
            self.stop()
            self.eventHandler?(.interrupted)
        }
    }
    #endif
}

@MainActor @Observable
public final class ReadAloudSession {
    public enum State: Equatable, Sendable { case idle, speaking, paused, finished }
    public private(set) var state: State = .idle
    public private(set) var document: ReadAloudDocument?
    public private(set) var passageIndex = 0
    public private(set) var spokenRange: NSRange?
    /// Where reading is in the passage: the word spoken, or, paused after a move to another
    /// sentence, where it will go on. An edit while paused anchored on the passage's start.
    public var currentOffset: Int { spokenRange?.location ?? utteranceStartOffset }
    /// Words, sentences or nothing highlighted while reading; Words by default.
    public private(set) var highlightMode: ReadAloudHighlightMode
    /// The voice reports no word positions (seen with some voices and settings), so the
    /// whole passage being read is highlighted instead of nothing.
    public private(set) var lacksWordTiming = false
    @ObservationIgnored private var voicesWithoutWordTiming: Set<String> = []
    @ObservationIgnored private var wordTimingCheck: Task<Void, Never>?
    @ObservationIgnored private var speakingVoiceIdentifier: String?
    public private(set) var message: String?
    /// The voice the person picked for Graphite, or nil to follow the system's Read & Speak voice
    /// (the best installed voice for the passage's language when the system has none).
    public private(set) var chosenVoiceIdentifier: String?
    public private(set) var speed = 1.0
    /// The installed voices, listed the first time they are needed rather than when the
    /// session is made: the system's list took a tenth of a second at every launch on the
    /// Mac, whether or not anything was read (measured 2026-10-16).
    public var voices: [ReadAloudVoice] {
        if !hasListedVoices { refreshVoices() }
        return listedVoices
    }
    private var listedVoices: [ReadAloudVoice] = []
    @ObservationIgnored private var hasListedVoices = false
    /// The language of the loaded passage (BCP 47, such as en-US), recognized from its words so an
    /// English lecture on a French iPad is not read with a French voice.
    public private(set) var readingLanguage: String
    public private(set) var personalVoiceStatus: ReadAloudPersonalVoiceStatus = .unsupported
    @ObservationIgnored private let speech: any ReadAloudSpeaking
    @ObservationIgnored private let preferences: UserDefaults
    @ObservationIgnored private var requestIdentifier: UUID?
    @ObservationIgnored private var utteranceStartOffset = 0
    @ObservationIgnored private var needsRestart = false
    @ObservationIgnored private var wasSpeakingWhenInterrupted = false
    /// The silence before the next passage, from the kind of passage that just ended.
    @ObservationIgnored private var leadingPauseSeconds = 0.0
    /// Called when the last passage ends; returns true when more follows (a PDF's next page),
    /// so the audio session stays active through the short preparation in between.
    @ObservationIgnored public var didFinishDocument: (@MainActor () -> Bool)?
    /// A new key: the previous one also stored automatic choices, which pinned the first voice
    /// found (often the robotic Fred) even after a Premium voice was downloaded.
    private static let voiceChoiceKey = "GraphiteReadAloudVoiceChoice"
    /// From a slow, careful 0.5× to 3× for listening through a lot.
    public static let speedRange: ClosedRange<Double> = 0.5...3
    private static let highlightModeKey = "GraphiteReadAloudHighlightMode"
    /// Earlier builds stored automatic picks under these keys as if the person had chosen them
    /// (the owner's iPad kept the robotic Eloquence "Eddy" that way). They are never read and
    /// are removed, so everyone starts on the system's voice.
    private static let abandonedVoiceKeys = ["GraphiteReadAloudVoice", "GraphiteReadAloudChosenVoice"]
    private static let speedPreferenceKey = "GraphiteReadAloudSpeed"

    public init(speech: any ReadAloudSpeaking = AppleReadAloudSpeech(), preferences: UserDefaults = .standard) {
        self.speech = speech; self.preferences = preferences
        for key in Self.abandonedVoiceKeys { preferences.removeObject(forKey: key) }
        chosenVoiceIdentifier = ReadAloudVoiceChoice.stored(in: preferences, key: Self.voiceChoiceKey)?.identifier
        highlightMode = preferences.string(forKey: Self.highlightModeKey).flatMap(ReadAloudHighlightMode.init(rawValue:)) ?? .words
        readingLanguage = ReadAloudLanguage.deviceLanguage
        let savedSpeed = preferences.double(forKey: Self.speedPreferenceKey)
        if savedSpeed.isFinite, Self.speedRange.contains(savedSpeed) { speed = savedSpeed }
        speech.eventHandler = { [weak self] event in self?.receive(event) }
    }

    public var currentPassage: ReadAloudPassage? {
        guard let document, document.passages.indices.contains(passageIndex) else { return nil }
        return document.passages[passageIndex]
    }
    public var sourceRange: NSRange? { highlightRange.flatMap { range in currentPassage?.sourceRange(for: range) } }

    /// What to highlight in the current passage's speech text, by the highlight mode: the
    /// word being spoken, or its sentence; the whole passage when the voice gives no words.
    public var highlightRange: NSRange? {
        guard state == .speaking || state == .paused, let passage = currentPassage, highlightMode != .off else { return nil }
        let wholePassage = NSRange(location: 0, length: passage.text.utf16.count)
        guard let spokenRange else { return lacksWordTiming && state == .speaking ? wholePassage : nil }
        guard highlightMode == .sentences else { return spokenRange }
        return sentenceRanges(in: passage).last { sentence in sentence.location <= spokenRange.location } ?? spokenRange
    }

    public func setHighlightMode(_ mode: ReadAloudHighlightMode) {
        highlightMode = mode
        preferences.set(mode.rawValue, forKey: Self.highlightModeKey)
    }

    public func refreshVoices() {
        hasListedVoices = true
        listedVoices = speech.voices
        personalVoiceStatus = speech.personalVoiceStatus
    }

    /// The best installed voice for the passage's language. A device without a voice in that
    /// language gets none, so it asks for a choice rather than reading in another language.
    public var automaticVoice: ReadAloudVoice? {
        ReadAloudVoice.preferred(in: voices, language: readingLanguage,
                                 systemDefaultIdentifier: speech.systemDefaultVoiceIdentifier(language: readingLanguage))
    }

    /// The voice the system speaks the passage's language with, even one Graphite would not
    /// offer itself (the person chose it in Read & Speak).
    public var systemVoice: ReadAloudVoice? { speech.systemVoice(language: readingLanguage) }

    public var followsSystemVoice: Bool { chosenVoiceIdentifier == nil }

    /// In the system's mode while VoiceOver, Speak Selection or Speak Screen is on, the system
    /// applies its own Speaking Rate, so Graphite's speed has no effect and is not shown.
    public var speedFollowsSystem: Bool { followsSystemVoice && speech.assistiveSpeechSettingsMayApply }

    /// The system's voice when following it, unless that is a robotic one: then the best
    /// natural voice, while the system can still apply the person's own settings over it.
    public var followedSystemVoice: ReadAloudVoice? {
        guard let systemVoice, !systemVoice.isRobotic else { return automaticVoice }
        return systemVoice
    }

    public var selectedVoiceIdentifier: String? { chosenVoiceIdentifier ?? followedSystemVoice?.id }

    public var selectedVoice: ReadAloudVoice? {
        guard let selectedVoiceIdentifier else { return nil }
        if let followedSystemVoice, followedSystemVoice.id == selectedVoiceIdentifier { return followedSystemVoice }
        return voices.first { voice in voice.id == selectedVoiceIdentifier }
    }

    /// True when the voice in use is a compact one and a better voice could be downloaded for
    /// the passage's language: nothing Enhanced, Premium or personal is installed for it.
    public var canImproveVoiceByDownloading: Bool {
        guard let voice = selectedVoice ?? automaticVoice, voice.isCompact else { return false }
        return automaticVoice?.isCompact ?? true
    }

    /// Where the system keeps its voices.
    public static var systemSpeechSettingsName: String { "Read & Speak" }

    public static var voiceDownloadPath: String {
        #if os(macOS)
        "System Settings › Accessibility › \(systemSpeechSettingsName) › System Voice › Manage Voices"
        #else
        "Settings › Accessibility › \(systemSpeechSettingsName) › Voices"
        #endif
    }

    public func load(_ document: ReadAloudDocument) {
        resetPlayback()
        if self.document?.passages.map(\.text) != document.passages.map(\.text) { speech.cancelPreparation() }
        self.document = document
        readingLanguage = ReadAloudLanguage.language(of: document) ?? ReadAloudLanguage.deviceLanguage
        passageIndex = 0
        message = nil
    }

    public func play() {
        guard state != .speaking else { return }
        guard document != nil, currentPassage != nil else { return }
        if state == .paused, needsRestart, utteranceStartOffset == currentPassage?.text.utf16.count {
            state = .speaking
            finishCurrentPassage()
            return
        }
        if state == .paused, !needsRestart {
            if speech.resume() { state = .speaking; message = nil; return }
            // The synthesizer could not go on (it was reset, or another app took the audio):
            // reading starts again at the word reached, not at the start of the passage.
            utteranceStartOffset = spokenRange?.location ?? utteranceStartOffset
        }
        if state == .finished { passageIndex = 0; spokenRange = nil; utteranceStartOffset = 0 }
        speakCurrentPassage()
    }

    public func pause() {
        guard state == .speaking else { return }
        if !speech.pause() {
            invalidateSpeech()
            utteranceStartOffset = spokenRange?.location ?? utteranceStartOffset
            needsRestart = true
        }
        state = .paused
    }

    /// Stop as the person asks for it: playback ends and the audio session goes back to other apps.
    public func stop() {
        resetPlayback()
        speech.releaseAudio()
    }

    /// Gives the audio session back unless reading is going on, for a document that is loaded
    /// and waits for the person to press Play. The session stays active while one is replaced
    /// by the next page of a PDF, so that page break is not heard as a gap by other apps.
    public func releaseAudioUnlessSpeaking() {
        guard state != .speaking else { return }
        speech.releaseAudio()
    }

    /// Ends the current utterance and returns to the start of the passage without touching the
    /// audio session. Skipping, jumping and loading the next page of a PDF replace what is
    /// spoken; only `stop()`, `clear()` and the end of the last document release the session.
    private func resetPlayback() {
        invalidateSpeech()
        wasSpeakingWhenInterrupted = false
        leadingPauseSeconds = 0
        lacksWordTiming = false
        state = .idle
        spokenRange = nil
        utteranceStartOffset = 0
        needsRestart = false
    }

    public func clear() { stop(); speech.cancelPreparation(); document = nil; message = nil }

    public func move(to index: Int) {
        guard let document, document.passages.indices.contains(index) else { return }
        let wasSpeaking = state == .speaking
        resetPlayback()
        passageIndex = index
        state = .paused
        needsRestart = true
        if wasSpeaking { speakCurrentPassage() }
    }

    public var canMoveToPreviousSentence: Bool {
        passageIndex > 0 || sentenceRanges(in: currentPassage).contains { $0.location < currentSentenceStart }
    }

    public var canMoveToNextSentence: Bool {
        guard let document else { return false }
        return passageIndex + 1 < document.passages.count || sentenceRanges(in: currentPassage).contains { $0.location > currentSentenceStart }
    }

    public func moveToNextSentence() {
        if let next = sentenceRanges(in: currentPassage).first(where: { $0.location > currentSentenceStart }) {
            seek(to: passageIndex, offset: next.location)
        } else { move(to: passageIndex + 1) }
    }

    public func moveToPreviousSentence() {
        if let previous = sentenceRanges(in: currentPassage).last(where: { $0.location < currentSentenceStart }) {
            seek(to: passageIndex, offset: previous.location)
        } else if let document, passageIndex > 0 {
            let previousIndex = passageIndex - 1
            seek(to: previousIndex, offset: sentenceRanges(in: document.passages[previousIndex]).last?.location ?? 0)
        }
    }

    public func repeatPassage() { move(to: passageIndex) }

    /// Moves to a place inside a passage (an offset in its spoken text), keeping whether it
    /// was speaking: for continuing at the same sentence after the text around it changed.
    public func move(to index: Int, offset: Int) {
        guard let document, document.passages.indices.contains(index) else { return }
        seek(to: index, offset: min(max(0, offset), (document.passages[index].text as NSString).length))
    }

    private var currentSentenceStart: Int {
        let offset = spokenRange?.location ?? utteranceStartOffset
        return sentenceRanges(in: currentPassage).last(where: { $0.location <= offset })?.location ?? 0
    }

    private func sentenceRanges(in passage: ReadAloudPassage?) -> [NSRange] {
        guard let text = passage?.text else { return [] }
        var ranges: [NSRange] = []
        text.enumerateSubstrings(in: text.startIndex..<text.endIndex, options: [.bySentences, .substringNotRequired]) { _, range, _, _ in
            ranges.append(NSRange(range, in: text))
        }
        return ranges
    }

    private func seek(to index: Int, offset: Int) {
        guard let document, document.passages.indices.contains(index) else { return }
        let wasSpeaking = state == .speaking
        resetPlayback()
        passageIndex = index
        utteranceStartOffset = offset
        state = .paused
        needsRestart = true
        if wasSpeaking { speakCurrentPassage() }
    }

    /// Records the person's own choice of voice for Graphite, or nil to follow the system.
    /// Only a person's action calls this: the picker, or the Personal Voice button.
    public func chooseVoice(_ identifier: String?, madeWith source: ReadAloudVoiceChoice.Source = .picker) {
        if let identifier, !voices.contains(where: { voice in voice.id == identifier }) { return }
        prepareForVoiceOrSpeedChange()
        chosenVoiceIdentifier = identifier
        if let identifier { ReadAloudVoiceChoice(identifier: identifier, source: source).store(in: preferences, key: Self.voiceChoiceKey) }
        else { preferences.removeObject(forKey: Self.voiceChoiceKey) }
        message = nil
    }

    /// Asks once for the person's Personal Voice, from their own tap, and reads with it when allowed.
    public func requestPersonalVoice() async {
        personalVoiceStatus = await speech.requestPersonalVoiceAccess()
        refreshVoices()
        if personalVoiceStatus == .authorized, let personal = voices.first(where: \.isPersonalVoice) {
            chooseVoice(personal.id, madeWith: .personalVoiceButton)
        } else if personalVoiceStatus == .authorized {
            message = "No Personal Voice is ready on this device yet. Create one in Settings › Accessibility › Personal Voice."
        } else if personalVoiceStatus == .denied {
            message = "Graphite is not allowed to use your Personal Voice. Allow it in Settings › Accessibility › Personal Voice."
        }
    }

    public func setSpeed(_ speed: Double) {
        guard speed.isFinite, Self.speedRange.contains(speed), speed != self.speed else { return }
        prepareForVoiceOrSpeedChange()
        self.speed = speed
        preferences.set(speed, forKey: Self.speedPreferenceKey)
    }

    private func prepareForVoiceOrSpeedChange() {
        guard state == .speaking || state == .paused else { return }
        invalidateSpeech()
        utteranceStartOffset = spokenRange?.location ?? utteranceStartOffset
        needsRestart = true
        state = .paused
        // Resume is explicit so changing a picker never starts sound unexpectedly.
    }

    private func invalidateSpeech() {
        requestIdentifier = nil
        wordTimingCheck?.cancel()
        speech.stop()
    }

    private func speakCurrentPassage() {
        guard let passage = currentPassage else { return }
        guard let selectedVoiceIdentifier, selectedVoice != nil else {
            if chosenVoiceIdentifier != nil {
                message = "The voice you chose is no longer installed. Choose another voice; Graphite does not switch voices on its own."
            } else {
                let languageName = Locale.current.localizedString(forIdentifier: readingLanguage) ?? readingLanguage
                message = "No \(languageName) voice is installed. Download one in \(Self.voiceDownloadPath), or choose another voice."
            }
            state = .paused
            return
        }
        let identifier = UUID()
        requestIdentifier = identifier
        let text = passage.text as NSString
        utteranceStartOffset = min(utteranceStartOffset, text.length)
        do {
            speakingVoiceIdentifier = selectedVoiceIdentifier
            lacksWordTiming = false
            wordTimingCheck?.cancel()
            let pause = leadingPauseSeconds / speed
            leadingPauseSeconds = 0
            let phoneticRanges = passage.spans.compactMap { span -> ReadAloudPhoneticRange? in
                guard let notation = span.phoneticNotation, span.speechRange.location >= utteranceStartOffset else { return nil }
                return ReadAloudPhoneticRange(range: NSRange(location: span.speechRange.location - utteranceStartOffset, length: span.speechRange.length),
                                              notation: notation)
            }
            if let document { speech.prepareAhead(document.passages, from: passageIndex) }
            try speech.speak(ReadAloudUtteranceRequest(text: text.substring(from: utteranceStartOffset), voiceIdentifier: selectedVoiceIdentifier,
                                                       speed: speed, leadingPauseSeconds: pause, usesSystemSettings: followsSystemVoice,
                                                       phoneticRanges: phoneticRanges, passage: passage,
                                                       passageOffset: utteranceStartOffset), requestIdentifier: identifier)
            state = .speaking
            needsRestart = false
            message = nil
        } catch {
            requestIdentifier = nil
            state = .paused
            needsRestart = true
            message = error.localizedDescription
        }
    }

    private func receive(_ event: ReadAloudSpeechEvent) {
        if case .interruptionEnded(let shouldResume) = event {
            // Resume only reading that a call or another app interrupted, and only when the
            // system says so; a reading the person paused stays paused.
            if shouldResume, wasSpeakingWhenInterrupted, state == .paused { play() }
            wasSpeakingWhenInterrupted = false
            return
        }
        if case .interrupted = event {
            guard state == .speaking || state == .paused else { return }
            wasSpeakingWhenInterrupted = state == .speaking
            invalidateSpeech()
            utteranceStartOffset = spokenRange?.location ?? utteranceStartOffset
            needsRestart = true
            state = .paused
            message = "Reading paused because the audio connection changed. Resume when you are ready."
            return
        }
        switch event {
        case .spoken(let identifier, let range):
            guard identifier == requestIdentifier, state == .speaking, let passage = currentPassage,
                  range.location >= 0, range.length > 0, range.location <= passage.text.utf16.count - utteranceStartOffset,
                  range.length <= passage.text.utf16.count - utteranceStartOffset - range.location else { return }
            let passageRange = NSRange(location: range.location + utteranceStartOffset, length: range.length)
            // Some voices report a dash or other punctuation as a word; the highlight stays
            // on the last real word rather than jumping onto a lone mark.
            let spokenText = (passage.text as NSString).substring(with: passageRange)
            guard spokenText.rangeOfCharacter(from: .alphanumerics) != nil else { return }
            spokenRange = passageRange
            if lacksWordTiming { lacksWordTiming = false }
            wordTimingCheck?.cancel()
            if let speakingVoiceIdentifier { voicesWithoutWordTiming.remove(speakingVoiceIdentifier) }
        case .started(let identifier):
            guard identifier == requestIdentifier, state == .speaking else { return }
            startWordTimingCheck(for: identifier)
        case .paused, .continued:
            // These confirm operations already reflected synchronously by pause()
            // and play(). A late confirmation cannot reverse a newer user action.
            break
        case .finished(let identifier):
            guard identifier == requestIdentifier else { return }
            requestIdentifier = nil
            if state == .paused {
                utteranceStartOffset = currentPassage?.text.utf16.count ?? 0
                needsRestart = true
            } else { finishCurrentPassage() }
        case .cancelled(let identifier):
            guard identifier == requestIdentifier else { return }
            requestIdentifier = nil
            needsRestart = true
            utteranceStartOffset = spokenRange?.location ?? utteranceStartOffset
            state = .paused
        case .interrupted, .interruptionEnded: break
        }
    }

    /// A voice that has given no word positions for a while after starting is remembered, so
    /// its following passages are highlighted whole from their first moment.
    private func startWordTimingCheck(for identifier: UUID) {
        wordTimingCheck?.cancel()
        if let speakingVoiceIdentifier, voicesWithoutWordTiming.contains(speakingVoiceIdentifier) {
            lacksWordTiming = true
            return
        }
        wordTimingCheck = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(700))
            guard let self, !Task.isCancelled, self.requestIdentifier == identifier, self.spokenRange == nil else { return }
            self.lacksWordTiming = true
            if let voice = self.speakingVoiceIdentifier { self.voicesWithoutWordTiming.insert(voice) }
        }
    }

    private func finishCurrentPassage() {
        guard let document else { return }
        spokenRange = nil
        utteranceStartOffset = 0
        if passageIndex + 1 < document.passages.count {
            let finished = document.passages[passageIndex]
            passageIndex += 1
            let next = document.passages[passageIndex]
            leadingPauseSeconds = max(finished.kind.pauseAfterSeconds, next.kind == .heading ? ReadAloudPassageKind.heading.pauseAfterSeconds : 0)
            speakCurrentPassage()
        }
        else {
            state = .finished
            if didFinishDocument?() != true { speech.releaseAudio() }
        }
    }
}

/// One IPA pronunciation within an utterance's text.
public struct ReadAloudPhoneticRange: Equatable, Sendable {
    public let range: NSRange
    public let notation: String
}

/// Everything one utterance needs: its text, voice, speed, the silence before it, whether the
/// system's own speech settings are preferred, and IPA pronunciations within the text.
public struct ReadAloudUtteranceRequest: Equatable, Sendable {
    public let text: String
    public let voiceIdentifier: String
    public let speed: Double
    public let leadingPauseSeconds: Double
    public let usesSystemSettings: Bool
    public var phoneticRanges: [ReadAloudPhoneticRange] = []
    /// The whole passage `text` belongs to. Resuming in the middle of a passage speaks only its
    /// remainder, but a voice that renders whole passages ahead plays the passage's audio from
    /// the word at `passageOffset`.
    public var passage: ReadAloudPassage?
    /// Where `text` starts within the passage's text, in UTF-16 units.
    public var passageOffset = 0

    public init(text: String, voiceIdentifier: String, speed: Double, leadingPauseSeconds: Double, usesSystemSettings: Bool,
                phoneticRanges: [ReadAloudPhoneticRange] = [], passage: ReadAloudPassage? = nil, passageOffset: Int = 0) {
        self.text = text
        self.voiceIdentifier = voiceIdentifier
        self.speed = speed
        self.leadingPauseSeconds = leadingPauseSeconds
        self.usesSystemSettings = usesSystemSettings
        self.phoneticRanges = phoneticRanges
        self.passage = passage
        self.passageOffset = passageOffset
    }
}

/// How much of the text is highlighted while it is read.
public enum ReadAloudHighlightMode: String, CaseIterable, Sendable {
    case words, sentences, off
}

/// The person's own choice of voice for Graphite, with how it was made, so an automatic pick
/// can never be read back as a choice.
public struct ReadAloudVoiceChoice: Codable, Equatable, Sendable {
    public enum Source: String, Codable, Sendable {
        case picker, personalVoiceButton
    }

    public let identifier: String
    public let source: Source

    static func stored(in preferences: UserDefaults, key: String) -> ReadAloudVoiceChoice? {
        guard let data = preferences.data(forKey: key), data.count <= 4_096 else { return nil }
        return try? JSONDecoder().decode(ReadAloudVoiceChoice.self, from: data)
    }

    func store(in preferences: UserDefaults, key: String) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        preferences.set(data, forKey: key)
    }
}

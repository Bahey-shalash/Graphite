import AVFoundation
import Foundation
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

    public init(id: String, name: String, language: String, quality: Int, isPersonalVoice: Bool = false) {
        self.id = id; self.name = name; self.language = language; self.quality = quality
        self.isPersonalVoice = isPersonalVoice
    }

    /// Apple's own words from Settings › Accessibility › Spoken Content › Voices.
    public var qualityDescription: String {
        if isPersonalVoice { return "Personal Voice" }
        switch quality {
        case 3...: return "Premium"
        case 2: return "Enhanced"
        default: return "Compact"
        }
    }

    /// Compact voices are the small built-in ones that sound synthetic over long passages.
    public var isCompact: Bool { !isPersonalVoice && quality < 2 }

    public var languageCode: Substring { language.split(separator: "-").first ?? Substring(language) }

    /// The voice read with when the person has not chosen one: their own Personal Voice when
    /// they allowed it, then Premium, then Enhanced, then compact, always in the passage's
    /// language. Ties prefer the exact region (en-GB for a British device) and then the voice
    /// the system itself uses for that language.
    public static func preferred(in voices: [ReadAloudVoice], language: String,
                                 systemDefaultIdentifier: String? = nil) -> ReadAloudVoice? {
        let languagePrefix = language.split(separator: "-").first
        return voices.filter { voice in voice.languageCode == languagePrefix }
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
    func pause() -> Bool
    func resume() -> Bool
    func stop()
    /// The voice the system uses for a language when nobody chose one, used to break ties.
    func systemDefaultVoiceIdentifier(language: String) -> String?
    var personalVoiceStatus: ReadAloudPersonalVoiceStatus { get }
    /// Shows the system's Personal Voice permission prompt. Call only from a person's tap.
    func requestPersonalVoiceAccess() async -> ReadAloudPersonalVoiceStatus
    /// Gives the audio route back to other apps once reading has stopped or finished.
    func releaseAudio()
}

public extension ReadAloudSpeaking {
    func systemDefaultVoiceIdentifier(language: String) -> String? { nil }
    var personalVoiceStatus: ReadAloudPersonalVoiceStatus { .unsupported }
    func requestPersonalVoiceAccess() async -> ReadAloudPersonalVoiceStatus { .unsupported }
    func releaseAudio() {}
}

@MainActor
public final class AppleReadAloudSpeech: NSObject, ReadAloudSpeaking, AVSpeechSynthesizerDelegate {
    public var eventHandler: (@MainActor (ReadAloudSpeechEvent) -> Void)?
    private let synthesizer = AVSpeechSynthesizer()
    private var activeUtterance: AVSpeechUtterance?
    private var requestIdentifier: UUID?
    #if os(iOS)
    /// Whether this adapter activated the shared audio session for reading, so it only ever
    /// deactivates a session it started (never a lecture recording's).
    private var ownsActiveAudioSession = false
    #endif

    public override init() {
        super.init()
        synthesizer.delegate = self
        #if os(iOS)
        NotificationCenter.default.addObserver(self, selector: #selector(audioInterrupted), name: AVAudioSession.interruptionNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(audioInterrupted), name: AVAudioSession.routeChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(audioInterrupted), name: AVAudioSession.mediaServicesWereResetNotification, object: nil)
        #endif
    }

    public var voices: [ReadAloudVoice] {
        AVSpeechSynthesisVoice.speechVoices().filter(Self.isOffered).map { voice in
            ReadAloudVoice(id: voice.identifier, name: voice.name, language: voice.language, quality: voice.quality.rawValue,
                           isPersonalVoice: voice.voiceTraits.contains(.isPersonalVoice))
        }.sorted { first, second in
            if first.language != second.language { return first.language < second.language }
            if first.quality != second.quality { return first.quality > second.quality }
            return first.name.localizedStandardCompare(second.name) == .orderedAscending
        }
    }

    /// Apple's natural voices only. System speech also lists the 1980s-style MacinTalk voices
    /// (Fred, Kathy, Ralph…) and the Eloquence voices (Eddy, Flo, Grandma…), which are
    /// marked as ordinary voices but sound robotic, novelty voices, and third-party voice
    /// extensions whose network and privacy behavior is unknown. A Personal Voice appears
    /// only after the person allowed Graphite to use it.
    static func isOffered(_ voice: AVSpeechSynthesisVoice) -> Bool {
        if voice.voiceTraits.contains(.isPersonalVoice) { return true }
        guard voice.identifier.hasPrefix("com.apple."), !voice.voiceTraits.contains(.isNoveltyVoice) else { return false }
        let legacyFamilies = ["com.apple.speech.synthesis.voice.", "com.apple.eloquence."]
        return !legacyFamilies.contains { family in voice.identifier.hasPrefix(family) }
    }

    public func systemDefaultVoiceIdentifier(language: String) -> String? {
        AVSpeechSynthesisVoice(language: language)?.identifier
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
        guard let voice = AVSpeechSynthesisVoice(identifier: voiceIdentifier) else {
            throw GraphiteError.unavailable("The chosen voice is no longer installed. Choose a voice before continuing.")
        }
        stop()
        activateAudioSession()
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        utterance.rate = min(AVSpeechUtteranceMaximumSpeechRate, max(AVSpeechUtteranceMinimumSpeechRate, AVSpeechUtteranceDefaultSpeechRate * Float(speed)))
        utterance.pitchMultiplier = 1
        utterance.volume = 1
        utterance.postUtteranceDelay = 0.18
        activeUtterance = utterance
        self.requestIdentifier = requestIdentifier
        synthesizer.speak(utterance)
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

    public func pause() -> Bool { synthesizer.pauseSpeaking(at: .immediate) }
    public func resume() -> Bool { synthesizer.continueSpeaking() }
    public func stop() {
        // Invalidate before cancellation: a cancelled utterance must never advance
        // a replacement document, even if its callback arrives after speak().
        activeUtterance = nil
        requestIdentifier = nil
        synthesizer.stopSpeaking(at: .immediate)
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
        Task { @MainActor [weak self] in
            guard let self, self.activeUtterance != nil else { return }
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
    public private(set) var message: String?
    /// The voice the person picked, or nil for the best installed voice in the passage's language.
    public private(set) var chosenVoiceIdentifier: String?
    public private(set) var speed = 1.0
    public private(set) var voices: [ReadAloudVoice] = []
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
    /// Called when the last passage ends; returns true when more follows (a PDF's next page),
    /// so the audio session stays active through the short preparation in between.
    @ObservationIgnored public var didFinishDocument: (@MainActor () -> Bool)?
    /// A new key: the previous one also stored automatic choices, which pinned the first voice
    /// found (often the robotic Fred) even after a Premium voice was downloaded.
    private static let voicePreferenceKey = "GraphiteReadAloudChosenVoice"
    private static let speedPreferenceKey = "GraphiteReadAloudSpeed"

    public init(speech: any ReadAloudSpeaking = AppleReadAloudSpeech(), preferences: UserDefaults = .standard) {
        self.speech = speech; self.preferences = preferences
        chosenVoiceIdentifier = preferences.string(forKey: Self.voicePreferenceKey)
        readingLanguage = ReadAloudLanguage.deviceLanguage
        let savedSpeed = preferences.double(forKey: Self.speedPreferenceKey)
        if savedSpeed.isFinite, (0.5...1.5).contains(savedSpeed) { speed = savedSpeed }
        refreshVoices()
        speech.eventHandler = { [weak self] event in self?.receive(event) }
    }

    public var currentPassage: ReadAloudPassage? {
        guard let document, document.passages.indices.contains(passageIndex) else { return nil }
        return document.passages[passageIndex]
    }
    public var sourceRange: NSRange? { spokenRange.flatMap { range in currentPassage?.sourceRange(for: range) } }

    public func refreshVoices() {
        voices = speech.voices
        personalVoiceStatus = speech.personalVoiceStatus
    }

    /// The best installed voice for the passage's language. A device without a voice in that
    /// language gets none, so it asks for a choice rather than reading in another language.
    public var automaticVoice: ReadAloudVoice? {
        ReadAloudVoice.preferred(in: voices, language: readingLanguage,
                                 systemDefaultIdentifier: speech.systemDefaultVoiceIdentifier(language: readingLanguage))
    }

    public var selectedVoiceIdentifier: String? { chosenVoiceIdentifier ?? automaticVoice?.id }

    public var selectedVoice: ReadAloudVoice? {
        guard let selectedVoiceIdentifier else { return nil }
        return voices.first { voice in voice.id == selectedVoiceIdentifier }
    }

    /// True when the voice in use is a compact one and a better voice could be downloaded for
    /// the passage's language: nothing Enhanced, Premium or personal is installed for it.
    public var canImproveVoiceByDownloading: Bool {
        guard let voice = selectedVoice ?? automaticVoice, voice.isCompact else { return false }
        return automaticVoice?.isCompact ?? true
    }

    public func load(_ document: ReadAloudDocument) {
        stop()
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
        if state == .paused, !needsRestart, speech.resume() { state = .speaking; message = nil; return }
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

    public func stop() {
        invalidateSpeech()
        speech.releaseAudio()
        wasSpeakingWhenInterrupted = false
        state = .idle
        spokenRange = nil
        utteranceStartOffset = 0
        needsRestart = false
    }

    public func clear() { stop(); document = nil; message = nil }

    public func move(to index: Int) {
        guard let document, document.passages.indices.contains(index) else { return }
        let wasSpeaking = state == .speaking
        stop()
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
        stop()
        passageIndex = index
        utteranceStartOffset = offset
        state = .paused
        needsRestart = true
        if wasSpeaking { speakCurrentPassage() }
    }

    /// Chooses a voice, or the best available one when the identifier is nil.
    public func chooseVoice(_ identifier: String?) {
        if let identifier, !voices.contains(where: { voice in voice.id == identifier }) { return }
        prepareForVoiceOrSpeedChange()
        chosenVoiceIdentifier = identifier
        if let identifier { preferences.set(identifier, forKey: Self.voicePreferenceKey) }
        else { preferences.removeObject(forKey: Self.voicePreferenceKey) }
        message = nil
    }

    /// Asks once for the person's Personal Voice, from their own tap, and reads with it when allowed.
    public func requestPersonalVoice() async {
        personalVoiceStatus = await speech.requestPersonalVoiceAccess()
        refreshVoices()
        if personalVoiceStatus == .authorized, let personal = voices.first(where: \.isPersonalVoice) {
            chooseVoice(personal.id)
        } else if personalVoiceStatus == .authorized {
            message = "No Personal Voice is ready on this device yet. Create one in Settings › Accessibility › Personal Voice."
        } else if personalVoiceStatus == .denied {
            message = "Graphite is not allowed to use your Personal Voice. Allow it in Settings › Accessibility › Personal Voice."
        }
    }

    public func setSpeed(_ speed: Double) {
        guard speed.isFinite, (0.5...1.5).contains(speed), speed != self.speed else { return }
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

    private func invalidateSpeech() { requestIdentifier = nil; speech.stop() }

    private func speakCurrentPassage() {
        guard let passage = currentPassage else { return }
        guard let selectedVoiceIdentifier, voices.contains(where: { voice in voice.id == selectedVoiceIdentifier }) else {
            if chosenVoiceIdentifier != nil {
                message = "The voice you chose is no longer installed. Choose another voice; Graphite does not switch voices on its own."
            } else {
                let languageName = Locale.current.localizedString(forIdentifier: readingLanguage) ?? readingLanguage
                message = "No \(languageName) voice is installed. Download one in Settings › Accessibility › Spoken Content › Voices, or choose another voice."
            }
            state = .paused
            return
        }
        let identifier = UUID()
        requestIdentifier = identifier
        let text = passage.text as NSString
        utteranceStartOffset = min(utteranceStartOffset, text.length)
        do {
            try speech.speak(text.substring(from: utteranceStartOffset), voiceIdentifier: selectedVoiceIdentifier, speed: speed, requestIdentifier: identifier)
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
            spokenRange = NSRange(location: range.location + utteranceStartOffset, length: range.length)
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

    private func finishCurrentPassage() {
        guard let document else { return }
        spokenRange = nil
        utteranceStartOffset = 0
        if passageIndex + 1 < document.passages.count { passageIndex += 1; speakCurrentPassage() }
        else {
            state = .finished
            if didFinishDocument?() != true { speech.releaseAudio() }
        }
    }
}

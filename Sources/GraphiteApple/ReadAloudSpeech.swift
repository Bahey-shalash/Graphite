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
    /// Apple's quality tier, not a listening-test score.
    public let quality: Int

    public init(id: String, name: String, language: String, quality: Int) {
        self.id = id; self.name = name; self.language = language; self.quality = quality
    }

    public var qualityDescription: String {
        switch quality {
        case 3...: "Premium"
        case 2: "Enhanced"
        default: "Standard"
        }
    }

    public static func preferred(in voices: [ReadAloudVoice], language: String) -> ReadAloudVoice? {
        let languagePrefix = language.split(separator: "-").first
        return voices.filter { voice in voice.language.split(separator: "-").first == languagePrefix }
            .sorted { first, second in
                if first.quality != second.quality { return first.quality > second.quality }
                if (first.language == language) != (second.language == language) { return first.language == language }
                return first.id < second.id
            }.first
    }
}

public enum ReadAloudSpeechEvent: Sendable {
    case spoken(UUID, NSRange)
    case paused(UUID)
    case continued(UUID)
    case finished(UUID)
    case cancelled(UUID)
    case interrupted
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
}

@MainActor
public final class AppleReadAloudSpeech: NSObject, ReadAloudSpeaking, AVSpeechSynthesizerDelegate {
    public var eventHandler: (@MainActor (ReadAloudSpeechEvent) -> Void)?
    private let synthesizer = AVSpeechSynthesizer()
    private var activeUtterance: AVSpeechUtterance?
    private var requestIdentifier: UUID?

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
        AVSpeechSynthesisVoice.speechVoices().filter { voice in
            // System speech also lists third-party voice extensions. Until their
            // network/privacy capabilities are known, offer only Apple identifiers.
            voice.identifier.hasPrefix("com.apple.") && !voice.voiceTraits.contains(.isNoveltyVoice) && !voice.voiceTraits.contains(.isPersonalVoice)
        }.map { voice in
            ReadAloudVoice(id: voice.identifier, name: voice.name, language: voice.language, quality: voice.quality.rawValue)
        }.sorted { first, second in
            if first.language != second.language { return first.language < second.language }
            if first.quality != second.quality { return first.quality > second.quality }
            return first.name.localizedStandardCompare(second.name) == .orderedAscending
        }
    }

    public func speak(_ text: String, voiceIdentifier: String, speed: Double, requestIdentifier: UUID) throws {
        guard let voice = AVSpeechSynthesisVoice(identifier: voiceIdentifier) else {
            throw GraphiteError.unavailable("The chosen voice is no longer installed. Choose a voice before continuing.")
        }
        stop()
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
                  AVAudioSession.InterruptionType(rawValue: rawType) == .began else { return }
        } else if notification.name == AVAudioSession.routeChangeNotification {
            guard let rawReason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                  let reason = AVAudioSession.RouteChangeReason(rawValue: rawReason),
                  reason == .oldDeviceUnavailable || reason == .newDeviceAvailable else { return }
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
    public private(set) var selectedVoiceIdentifier: String?
    public private(set) var speed = 1.0
    public private(set) var voices: [ReadAloudVoice] = []
    @ObservationIgnored private let speech: any ReadAloudSpeaking
    @ObservationIgnored private let preferences: UserDefaults
    @ObservationIgnored private var requestIdentifier: UUID?
    @ObservationIgnored private var utteranceStartOffset = 0
    @ObservationIgnored private var needsRestart = false
    @ObservationIgnored public var didFinishDocument: (@MainActor () -> Void)?
    private static let voicePreferenceKey = "GraphiteReadAloudVoice"
    private static let speedPreferenceKey = "GraphiteReadAloudSpeed"

    public init(speech: any ReadAloudSpeaking = AppleReadAloudSpeech(), preferences: UserDefaults = .standard) {
        self.speech = speech; self.preferences = preferences
        selectedVoiceIdentifier = preferences.string(forKey: Self.voicePreferenceKey)
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
        if selectedVoiceIdentifier == nil {
            selectedVoiceIdentifier = ReadAloudVoice.preferred(in: voices, language: AVSpeechSynthesisVoice.currentLanguageCode())?.id
            if let selectedVoiceIdentifier { preferences.set(selectedVoiceIdentifier, forKey: Self.voicePreferenceKey) }
            // A device without a voice in its preferred language needs an explicit
            // choice, rather than silently reading in another language.
        }
    }

    public func load(_ document: ReadAloudDocument) {
        stop()
        self.document = document
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
        if state == .paused, !needsRestart, speech.resume() { state = .speaking; return }
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

    public func chooseVoice(_ identifier: String) {
        guard voices.contains(where: { voice in voice.id == identifier }) else { return }
        prepareForVoiceOrSpeedChange()
        selectedVoiceIdentifier = identifier
        preferences.set(identifier, forKey: Self.voicePreferenceKey)
        message = nil
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
            message = "Choose an installed voice to read this passage. Your previous voice has not been replaced."
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
        if case .interrupted = event {
            guard state == .speaking || state == .paused else { return }
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
        case .interrupted: break
        }
    }

    private func finishCurrentPassage() {
        guard let document else { return }
        spokenRange = nil
        utteranceStartOffset = 0
        if passageIndex + 1 < document.passages.count { passageIndex += 1; speakCurrentPassage() }
        else { state = .finished; didFinishDocument?() }
    }
}

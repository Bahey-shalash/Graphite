import SwiftUI
import AVFoundation
import GraphiteCore
import GraphiteApple

/// The voice and speed choices, shared by Settings › Read Aloud and the reading options sheet,
/// so both always show the same voice. By default Graphite speaks like the system's own Read &
/// Speak (its voice, and its rate, pitch and other settings when the system applies them); a
/// voice chosen here overrides that for Graphite only.
struct ReadAloudVoiceSettings: View {
    @Bindable var reader: ReadAloudController
    /// The sample keeps its choices in a separate domain, so trying a voice never changes the
    /// voice the person reads with.
    @State private var sample = ReadAloudSession(preferences: UserDefaults(suiteName: "com.graphite.study.readAloudSample") ?? .standard)
    @State private var samplePreparation: Task<Void, Never>?
    @State private var isRequestingPersonalVoice = false

    /// 0.75× to 3× in quarter steps, for heavy listening.
    static let speeds: [Double] = stride(from: 0.75, through: 3.0, by: 0.25).map { $0 }

    private var session: ReadAloudSession { reader.session }

    var body: some View {
        voiceSection
        Section {
            Picker("Highlight While Reading", selection: Binding(get: { session.highlightMode }, set: { mode in session.setHighlightMode(mode) })) {
                Text("Words").tag(ReadAloudHighlightMode.words)
                Text("Sentences").tag(ReadAloudHighlightMode.sentences)
                Text("Off").tag(ReadAloudHighlightMode.off)
            }
            .accessibilityIdentifier("readAloudHighlightPicker")
        } footer: {
            Text("A voice that does not report its words highlights the whole passage instead.")
        }
    }

    private var voiceSection: some View {
        Section {
            Picker("Voice", selection: Binding(get: { session.chosenVoiceIdentifier }, set: { identifier in
                stopSample(); session.chooseVoice(identifier)
            })) {
                Text(systemTitle).tag(String?.none)
                ForEach(Self.qualityGroups, id: \.self) { quality in
                    let group = offeredVoices.filter { voice in Self.group(of: voice) == quality }
                    if !group.isEmpty {
                        Section(quality) {
                            ForEach(group) { voice in
                                Text("\(voice.name), \(languageName(voice.language))").tag(String?.some(voice.id))
                            }
                        }
                    }
                }
            }
            .accessibilityIdentifier("readAloudVoicePicker")
            if !session.speedFollowsSystem {
                Picker("Speed", selection: Binding(get: { session.speed }, set: { speed in stopSample(); session.setSpeed(speed) })) {
                    ForEach(Self.speeds, id: \.self) { speed in Text(speed.formatted() + "×").tag(speed) }
                }
            }
            Button(isSamplePlaying ? "Stop Sample" : "Play Sample",
                   systemImage: isSamplePlaying ? "stop.fill" : "play.circle") {
                if isSamplePlaying { stopSample() } else { playSample() }
            }
            .disabled(session.selectedVoiceIdentifier == nil)
            if session.personalVoiceStatus == .notDetermined {
                Button("Use My Personal Voice…", systemImage: "person.wave.2") {
                    stopSample()
                    isRequestingPersonalVoice = true
                    Task { await session.requestPersonalVoice(); isRequestingPersonalVoice = false }
                }
                .disabled(isRequestingPersonalVoice)
            }
        } header: {
            Text("System Voice and Speed")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                if session.followsSystemVoice {
                    Text(systemFootnote)
                }
                if session.canImproveVoiceByDownloading {
                    Text("This is a default-quality voice. Enhanced and Premium voices sound far more natural.")
                }
                Text("Download More Voices: \(ReadAloudSession.voiceDownloadPath).")
                if session.personalVoiceStatus == .denied {
                    Text("To read with your Personal Voice, allow Graphite in Settings › Accessibility › Personal Voice.")
                }
                if let message = session.message ?? sample.message {
                    Text(message).foregroundStyle(.orange)
                }
            }
        }
        .onAppear { session.refreshVoices() }
        .onDisappear { stopSample() }
        .onReceive(NotificationCenter.default.publisher(for: AVSpeechSynthesizer.availableVoicesDidChangeNotification)) { _ in
            session.refreshVoices()
        }
    }

    private var systemTitle: String {
        let name = "Same as \(ReadAloudSession.systemSpeechSettingsName)"
        guard let voice = session.followedSystemVoice else { return name }
        return "\(name) (\(voice.name), \(voice.qualityDescription))"
    }

    private var systemFootnote: String {
        let settingsName = ReadAloudSession.systemSpeechSettingsName
        if session.systemVoice == nil, let fallback = session.automaticVoice {
            return "\(settingsName) has no voice for this language here, so Graphite reads with \(fallback.name) (\(fallback.qualityDescription))."
        }
        if session.speedFollowsSystem {
            return "Voice, speaking rate, pitch and the other \(settingsName) settings come from the system while VoiceOver, Speak Selection or Speak Screen is on. Change them in Settings › Accessibility › \(settingsName)."
        }
        return "Graphite uses the voice \(settingsName) uses for this language. Its rate and pitch apply only while VoiceOver, Speak Selection or Speak Screen is on; otherwise Graphite's speed applies."
    }

    /// Apple's quality tiers, best first, as the picker's sections.
    /// Classic holds the robotic Eloquence and MacinTalk voices, there to be picked by hand only.
    private static let qualityGroups = ["Personal Voice", "Premium", "Enhanced", "Default", "Classic"]

    private static func group(of voice: ReadAloudVoice) -> String { voice.qualityDescription }

    private func languageName(_ identifier: String) -> String {
        Locale.current.localizedString(forIdentifier: identifier) ?? identifier
    }

    /// Every installed voice Graphite offers, best first, the passage's language before others.
    private var offeredVoices: [ReadAloudVoice] {
        let languageCode = session.readingLanguage.split(separator: "-").first
        var voices = session.voices
        voices.sort { first, second in
            if first.isPersonalVoice != second.isPersonalVoice { return first.isPersonalVoice }
            if first.quality != second.quality { return first.quality > second.quality }
            if (first.languageCode == languageCode) != (second.languageCode == languageCode) { return first.languageCode == languageCode }
            if first.language != second.language { return languageName(first.language).localizedStandardCompare(languageName(second.language)) == .orderedAscending }
            return first.name.localizedStandardCompare(second.name) == .orderedAscending
        }
        return voices
    }

    private var isSamplePlaying: Bool { sample.state == .speaking || samplePreparation != nil }

    private func playSample() {
        stopSample()
        if session.state == .speaking { session.pause() }
        sample.refreshVoices()
        sample.chooseVoice(session.chosenVoiceIdentifier)
        sample.setSpeed(session.speed)
        samplePreparation = Task {
            defer { samplePreparation = nil }
            guard let document = try? await reader.prepareVoiceSample(), !Task.isCancelled else { return }
            sample.load(document)
            sample.play()
        }
    }

    private func stopSample() {
        samplePreparation?.cancel()
        samplePreparation = nil
        sample.stop()
    }
}

import SwiftUI
import AVFoundation
import GraphiteCore
import GraphiteApple

/// The voice and speed choices, shared by Settings › Read Aloud and the reading options sheet,
/// so both always show the same voice. Only Apple's natural voices are offered; the best one
/// installed for the passage's language is used until the person picks another.
struct ReadAloudVoiceSettings: View {
    @Bindable var reader: ReadAloudController
    /// The sample keeps its choices in a separate domain, so trying a voice never changes the
    /// voice the person reads with.
    @State private var sample = ReadAloudSession(preferences: UserDefaults(suiteName: "com.graphite.study.readAloudSample") ?? .standard)
    @State private var samplePreparation: Task<Void, Never>?
    @State private var isRequestingPersonalVoice = false

    static let speeds: [Double] = [0.75, 0.9, 1.0, 1.1, 1.25, 1.5]

    private var session: ReadAloudSession { reader.session }

    var body: some View {
        Section {
            Picker("Voice", selection: Binding(get: { session.chosenVoiceIdentifier }, set: { identifier in
                stopSample(); session.chooseVoice(identifier)
            })) {
                Text(automaticTitle).tag(String?.none)
                ForEach(offeredVoices) { voice in
                    Text("\(voice.name) (\(voice.qualityDescription))").tag(String?.some(voice.id))
                }
            }
            .accessibilityIdentifier("readAloudVoicePicker")
            Picker("Speed", selection: Binding(get: { session.speed }, set: { speed in stopSample(); session.setSpeed(speed) })) {
                ForEach(Self.speeds, id: \.self) { speed in Text(speed.formatted() + "×").tag(speed) }
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
            Text("Voice and Speed")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                if session.canImproveVoiceByDownloading {
                    Text("This is a compact voice. For a more natural one, download an Enhanced or Premium voice in Settings › Accessibility › Spoken Content › Voices; Graphite uses it automatically.")
                }
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

    private var automaticTitle: String {
        guard let voice = session.automaticVoice else { return "Automatic" }
        return "Automatic: \(voice.name) (\(voice.qualityDescription))"
    }

    /// Voices in the passage's language, best first, plus a chosen voice of another language.
    private var offeredVoices: [ReadAloudVoice] {
        let languageCode = session.readingLanguage.split(separator: "-").first
        var voices = session.voices.filter { voice in voice.languageCode == languageCode || voice.id == session.chosenVoiceIdentifier }
        voices.sort { first, second in
            if first.isPersonalVoice != second.isPersonalVoice { return first.isPersonalVoice }
            if first.quality != second.quality { return first.quality > second.quality }
            return first.name.localizedStandardCompare(second.name) == .orderedAscending
        }
        return voices
    }

    private var isSamplePlaying: Bool { sample.state == .speaking || samplePreparation != nil }

    private func playSample() {
        stopSample()
        if session.state == .speaking { session.pause() }
        sample.refreshVoices()
        sample.chooseVoice(session.selectedVoiceIdentifier)
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

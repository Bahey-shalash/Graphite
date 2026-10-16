import SwiftUI
import GraphiteCore
import GraphiteVoices

/// Settings › Read Aloud's reading mode: High Quality with a downloaded voice, rendered ahead,
/// or Quick with the system voice. High Quality can be chosen once a voice is downloaded.
struct ReadAloudModeSection: View {
    @Bindable var library: NeuralVoiceLibrary
    let speech: NeuralReadAloudSpeech?

    var body: some View {
        Section {
            Picker("Reading Mode", selection: Binding(get: { library.mode }, set: { mode in
                library.chooseMode(mode)
                // Quick needs nothing rendered; stop preparing the note being read.
                if mode == .quick { ReadAloudVoices.preparation?.cancel() }
            })) {
                Text("High Quality").tag(ReadAloudQualityMode.highQuality)
                Text("Quick").tag(ReadAloudQualityMode.quick)
            }
            .disabled(!library.hasDownloadedVoice)
            .accessibilityIdentifier("readAloudModePicker")
            if library.mode == .highQuality {
                Toggle("Read Unprepared Passages with System Voice", isOn: Binding(
                    get: { library.readsUnpreparedPassagesQuickly },
                    set: { readsQuickly in
                        if let speech { speech.setReadsUnpreparedPassagesQuickly(readsQuickly) }
                        else { library.readsUnpreparedPassagesQuickly = readsQuickly }
                    }))
            }
        } header: {
            Text("Reading Mode")
        } footer: {
            Text(footer)
                .formFooterAlignment()
        }
    }

    private var footer: String {
        if !library.hasDownloadedVoice {
            return "Quick reads at once with the system voice. Download a voice below for High Quality: it prepares the note ahead, passage by passage, and sounds far more natural. Everything runs on this device."
        }
        if library.mode == .highQuality {
            return "High Quality prepares the note ahead with the downloaded voice and starts as soon as the first passages are ready. Without the system voice filling in, reading waits for each passage. Preparing continues only while Graphite is on screen."
        }
        return "Quick reads at once with the system voice, chosen under System Voice and Speed."
    }
}

/// Settings › Read Aloud's downloadable voices, best first: each with its size, sound, license
/// and download control; tapping Use This Voice reads with it. Voices this device cannot run
/// are listed too, with the reason, so their absence is not a mystery.
struct NeuralVoicesSection: View {
    @Bindable var library: NeuralVoiceLibrary
    @State private var voicePendingDeletion: NeuralVoiceDescription?

    var body: some View {
        Section {
            ForEach(library.offeredVoices) { voice in
                NeuralVoiceRow(library: library, voice: voice) { voicePendingDeletion = voice }
            }
            ForEach(library.unavailableVoices) { voice in
                VStack(alignment: .leading, spacing: 4) {
                    Text(voice.name).font(.headline)
                    Text("\(voice.modelName) · \(NeuralVoicesSection.size(voice.byteCount)) · \(voice.license.name)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(library.unavailabilityReason(of: voice))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)
                .accessibilityElement(children: .combine)
            }
            NavigationLink("Voice Credits") {
                Form { Section { NeuralVoiceCredits(voices: library.manifest.voices) } }
                    .navigationTitle("Voice Credits")
            }
        } header: {
            Text("High Quality Voices")
        } footer: {
            Text("Voices download from their makers’ Hugging Face pages and run entirely on this device; your notes never leave it. Larger voices take longer to prepare a note.")
                .formFooterAlignment()
        }
        .onAppear { library.refreshInstalledVoices() }
        .confirmationDialog("Delete \(voicePendingDeletion?.name ?? "Voice")?", isPresented: Binding(
            get: { voicePendingDeletion != nil }, set: { isPresented in if !isPresented { voicePendingDeletion = nil } }),
            titleVisibility: .visible, presenting: voicePendingDeletion) { voice in
            Button("Delete Voice", role: .destructive) {
                if library.selectedVoice?.description.id == voice.id { ReadAloudVoices.preparation?.cancel() }
                library.delete(voice)
            }
        } message: { voice in
            Text("This frees \(Self.size(voice.byteCount)). You can download the voice again later.")
        }
    }

    static func size(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

/// One voice: name and model, how it sounds, size and license, and its download control.
private struct NeuralVoiceRow: View {
    @Bindable var library: NeuralVoiceLibrary
    let voice: NeuralVoiceDescription
    let requestDeletion: () -> Void

    private var state: NeuralVoiceDownloadState { library.state(of: voice) }
    private var isSelected: Bool { library.selectedVoice?.description.id == voice.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(voice.name).font(.headline)
                    Text("\(voice.modelName) · \(NeuralVoicesSection.size(voice.byteCount)) · \(voice.license.name)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                if isSelected, state == .installed {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.tint)
                        .accessibilityLabel("Reading Voice")
                }
            }
            Text(voice.qualityNote)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            control
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("neuralVoice-\(voice.id)")
    }

    @ViewBuilder private var control: some View {
        switch state {
        case .notInstalled:
            Button("Download", systemImage: "arrow.down.circle") { library.download(voice) }
                .buttonStyle(.bordered)
        case .downloading(let received, let total):
            progress(received: received, total: total, label: "Downloading")
            HStack {
                Button("Pause", systemImage: "pause.circle") { library.pauseDownload(voice) }
                Button("Cancel", systemImage: "xmark.circle", role: .destructive) { library.delete(voice) }
                    .tint(.red)
            }
            .buttonStyle(.bordered)
        case .paused(let received, let total):
            progress(received: received, total: total, label: "Paused")
            HStack {
                Button("Resume", systemImage: "arrow.down.circle") { library.download(voice) }
                Button("Cancel", systemImage: "xmark.circle", role: .destructive) { library.delete(voice) }
                    .tint(.red)
            }
            .buttonStyle(.bordered)
        case .verifying:
            ProgressView("Checking the Download…")
        case .installed:
            HStack {
                if !isSelected {
                    Button("Use This Voice", systemImage: "checkmark.circle") { library.selectVoice(voice) }
                }
                Button("Delete", systemImage: "trash", role: .destructive) { requestDeletion() }
                    .tint(.red)
            }
            .buttonStyle(.bordered)
        case .failed(let message):
            Text(message).font(.footnote).foregroundStyle(.red)
            Button("Try Again", systemImage: "arrow.clockwise") { library.download(voice) }
                .buttonStyle(.bordered)
        }
    }

    private func progress(received: Int64, total: Int64, label: String) -> some View {
        ProgressView(value: Double(received), total: Double(max(total, 1))) {
            Text(label)
        } currentValueLabel: {
            Text("\(NeuralVoicesSection.size(received)) of \(NeuralVoicesSection.size(total))")
        }
    }
}

/// The makers of the downloadable voices and their licenses. Pocket TTS's license, CC BY 4.0,
/// requires this credit wherever the voice is offered.
struct NeuralVoiceCredits: View {
    let voices: [NeuralVoiceDescription]

    /// One entry per model: both Qwen3-TTS sizes share a credit.
    private var creditedVoices: [NeuralVoiceDescription] {
        var seen = Set<String>()
        return voices.filter { voice in seen.insert(voice.license.attribution ?? voice.modelName).inserted }
    }

    var body: some View {
        ForEach(creditedVoices) { voice in
            VStack(alignment: .leading, spacing: 2) {
                Text(voice.license.attribution ?? "\(voice.modelName), \(voice.license.name).")
                    .font(.footnote)
                Link("\(voice.license.name) License", destination: voice.license.address)
                    .font(.footnote)
            }
            .padding(.vertical, 2)
        }
    }
}

/// Rendered audio kept in Graphite's caches, never in the vault, with a way to delete it.
struct ReadAloudStorageSection: View {
    @Bindable var library: NeuralVoiceLibrary

    var body: some View {
        Section {
            LabeledContent("Prepared Audio", value: NeuralVoicesSection.size(library.cacheBytes))
            Button("Delete Prepared Audio", systemImage: "trash", role: .destructive) {
                Task { await library.deleteRenderedAudio() }
            }
            .disabled(library.cacheBytes == 0)
        } header: {
            Text("Storage")
        } footer: {
            Text("Prepared passages are kept so a note reads at once the next time; only changed passages are prepared again. The oldest are removed when they pass \(NeuralVoicesSection.size(ReadAloudAudioCacheEviction.defaultCapacityBytes)). They are never stored in your vault.")
                .formFooterAlignment()
        }
        .task { await library.refreshCacheSize() }
    }
}

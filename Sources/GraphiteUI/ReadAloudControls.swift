import SwiftUI
import GraphiteCore
import GraphiteApple
import GraphiteVoices

/// Read Aloud's place in the window toolbar while a passage is loaded: Pause or Resume in
/// one tap, and the reading controls in a popover that leaves the page and its highlighted
/// word in view. Nothing is added above the page.
struct ReadAloudToolbarControls: View {
    @Bindable var reader: ReadAloudController
    let isDisabled: Bool
    /// The app's accent: the toolbar's monochrome tint would turn the Play button and the
    /// Follow Reading switch white on white in dark appearance.
    let accentColor: Color
    @State private var showsControls = false

    var body: some View {
        Group {
            if reader.isPreparing {
                ProgressView()
                    .controlSize(.small)
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityLabel("Preparing to Read")
            } else if reader.isWaitingForPreparedAudio {
                // The downloaded voice is still rendering the passage reading has reached.
                ProgressView(value: reader.neuralSpeech?.preparation.preparedShare ?? 0)
                    .progressViewStyle(.circular)
                    .controlSize(.small)
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityLabel(reader.preparingDescription)
            } else if reader.session.document != nil {
                ReadAloudPlayPauseButton(reader: reader, prominent: false)
            }
            Button("Reading Controls", systemImage: "speaker.wave.2") { showsControls = true }
                .accessibilityIdentifier("readAloudControlsButton")
                .popover(isPresented: $showsControls, arrowEdge: .top) {
                    ReadAloudControlsPanel(reader: reader) { showsControls = false }
                        .tint(accentColor)
                        .presentationCompactAdaptation(.popover)
                }
        }
        .disabled(isDisabled)
    }
}

/// Play when stopped or paused, Pause while speaking, labelled for VoiceOver either way.
struct ReadAloudPlayPauseButton: View {
    @Bindable var reader: ReadAloudController
    let prominent: Bool

    private var isSpeaking: Bool { reader.session.state == .speaking }

    var body: some View {
        let button = Button(isSpeaking ? "Pause Reading" : "Resume Reading",
                            systemImage: isSpeaking ? "pause.fill" : "play.fill") {
            if isSpeaking { reader.session.pause() } else { reader.session.play() }
        }
        .accessibilityIdentifier("readAloudPlayPause")
        .disabled(reader.session.document == nil || reader.isPreparing)
        if prominent {
            button
                .labelStyle(.iconOnly)
                .font(.title)
                .frame(width: 64, height: 64)
                .contentShape(Circle())
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.circle)
        } else {
            button
        }
    }
}

/// The popover from the toolbar: what is being read, the transport, speed and following.
/// Voice, math, PDF order and the transcript are one tap further, in Reading Options.
struct ReadAloudControlsPanel: View {
    @Bindable var reader: ReadAloudController
    let dismiss: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// At accessibility text sizes the panel widens, scrolls, stacks its actions and offers
    /// speed as a menu, since segments and side-by-side buttons would break words apart.
    private var usesLargeLayout: Bool { dynamicTypeSize.isAccessibilitySize }

    /// The system's secondary label color itself: the hierarchical .secondary style measured
    /// 3.1:1 in this popover in dark appearance, below the 4.5:1 small text needs.
    #if canImport(UIKit)
    private static let secondaryText = Color(uiColor: .secondaryLabel)
    #else
    private static let secondaryText = Color(nsColor: .secondaryLabelColor)
    #endif

    var body: some View {
        // Scrolls only when the text is too large for the screen.
        ViewThatFits(in: .vertical) {
            content
            ScrollView { content }
        }
        .frame(idealWidth: usesLargeLayout ? 560 : 360, maxWidth: usesLargeLayout ? 640 : 400)
        // Opaque, so secondary text stays readable over a white PDF page in dark appearance,
        // where the popover's glass turned mid-gray behind gray text.
        .background(GraphiteChrome.barBackground)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            transport
            if reader.session.speedFollowsSystem {
                Text("Speed follows \(ReadAloudSession.systemSpeechSettingsName)’s Speaking Rate.")
                    .font(.footnote)
                    .foregroundStyle(Self.secondaryText)
            } else {
                if usesLargeLayout {
                    HStack {
                        Text("Speed")
                        Spacer()
                        Picker("Speed", selection: Binding(get: { reader.session.speed }, set: { speed in reader.session.setSpeed(speed) })) {
                            ForEach(ReadAloudVoiceSettings.speeds, id: \.self) { speed in Text(speed.formatted() + "×").tag(speed) }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                    }
                } else {
                    Picker("Speed", selection: Binding(get: { reader.session.speed }, set: { speed in reader.session.setSpeed(speed) })) {
                        ForEach(ReadAloudVoiceSettings.speeds, id: \.self) { speed in Text(speed.formatted() + "×").tag(speed) }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityLabel("Speed")
                }
            }
            Toggle("Follow Reading", isOn: $reader.followsReading)
            preparation
            advice
            Divider()
            actions
        }
        .padding(20)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(reader.title)
                .font(.headline)
                .lineLimit(usesLargeLayout ? 4 : 2)
            Text(statusDescription)
                .font(.subheadline)
                .foregroundStyle(Self.secondaryText)
                .lineLimit(usesLargeLayout ? 6 : 2)
        }
        .accessibilityElement(children: .combine)
    }

    private var transport: some View {
        HStack(spacing: 20) {
            Spacer(minLength: 0)
            Button("Previous Sentence", systemImage: "backward.end.fill") { reader.session.moveToPreviousSentence() }
                .disabled(!reader.session.canMoveToPreviousSentence)
                .frame(minWidth: 44, minHeight: 44)
            ReadAloudPlayPauseButton(reader: reader, prominent: true)
            Button("Next Sentence", systemImage: "forward.end.fill") { reader.session.moveToNextSentence() }
                .disabled(!reader.session.canMoveToNextSentence)
                .frame(minWidth: 44, minHeight: 44)
            Spacer(minLength: 0)
        }
        .labelStyle(.iconOnly)
        .font(.title2)
        .disabled(reader.session.document == nil || reader.isPreparing)
    }

    /// While the downloaded voice is still preparing the note: how far it is, and the choice
    /// to let the system voice read the passages that are not ready yet.
    @ViewBuilder private var preparation: some View {
        if let share = reader.preparedAudioShare, let neuralSpeech = reader.neuralSpeech {
            VStack(alignment: .leading, spacing: 8) {
                ProgressView(value: share) {
                    Text(reader.isWaitingForPreparedAudio ? reader.preparingDescription : "Prepared \(Int((share * 100).rounded()))%")
                        .font(.subheadline)
                }
                .accessibilityIdentifier("readAloudPreparationProgress")
                Toggle("Read Unprepared Passages with System Voice", isOn: Binding(
                    get: { neuralSpeech.library.readsUnpreparedPassagesQuickly },
                    set: { readsQuickly in neuralSpeech.setReadsUnpreparedPassagesQuickly(readsQuickly) }))
                    .font(.subheadline)
            }
        }
    }

    @ViewBuilder private var advice: some View {
        if let message = reader.errorMessage ?? reader.session.message ?? reader.neuralSpeech?.preparation.failureMessage {
            Text(message)
                .font(.callout)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        } else if reader.session.canImproveVoiceByDownloading {
            Text("Default-quality voice. A more natural one: \(ReadAloudSession.voiceDownloadPath).")
                .font(.footnote)
                .foregroundStyle(Self.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var actions: some View {
        let layout = usesLargeLayout ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12)) : AnyLayout(HStackLayout())
        return layout {
            Button("Voice and Transcript", systemImage: "text.alignleft") {
                dismiss()
                // UIKit drops a sheet presented while this popover is still closing.
                Task {
                    try? await Task.sleep(for: .milliseconds(450))
                    reader.showsReader = true
                }
            }
            if !usesLargeLayout { Spacer() }
            Button("Stop", systemImage: "stop.fill", role: .destructive) {
                dismiss()
                reader.clear()
            }
        }
        .frame(minHeight: 44)
    }

    private var statusDescription: String {
        var parts: [String] = []
        if reader.isPreparing { parts.append("Preparing…") }
        else if reader.isWaitingForPreparedAudio { parts.append(reader.preparingDescription) }
        else {
            switch reader.session.state {
            case .speaking: parts.append("Reading")
            case .paused: parts.append("Paused")
            case .finished: parts.append("Finished")
            case .idle: parts.append("Ready")
            }
        }
        if !reader.scopeDescription.isEmpty { parts.append(reader.scopeDescription) }
        if let neuralVoice = reader.neuralSpeech?.currentVoiceName {
            parts.append(neuralVoice)
        } else if let voice = reader.session.selectedVoice { parts.append("\(voice.name) (\(voice.qualityDescription))") }
        return parts.joined(separator: " · ")
    }
}

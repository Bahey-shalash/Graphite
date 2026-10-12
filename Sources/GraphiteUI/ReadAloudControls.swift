import SwiftUI
import GraphiteCore
import GraphiteApple

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

    /// The system's secondary label color itself: the hierarchical .secondary style measured
    /// 3.1:1 in this popover in dark appearance, below the 4.5:1 small text needs.
    #if canImport(UIKit)
    private static let secondaryText = Color(uiColor: .secondaryLabel)
    #else
    private static let secondaryText = Color(nsColor: .secondaryLabelColor)
    #endif

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            transport
            Picker("Speed", selection: Binding(get: { reader.session.speed }, set: { speed in reader.session.setSpeed(speed) })) {
                ForEach(ReadAloudVoiceSettings.speeds, id: \.self) { speed in Text(speed.formatted() + "×").tag(speed) }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Speed")
            Toggle("Follow Reading", isOn: $reader.followsReading)
            advice
            Divider()
            actions
        }
        .padding(20)
        .frame(idealWidth: 360, maxWidth: 400)
        // Opaque, so secondary text stays readable over a white PDF page in dark appearance,
        // where the popover's glass turned mid-gray behind gray text.
        .background(GraphiteChrome.barBackground)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(reader.title)
                .font(.headline)
                .lineLimit(2)
            Text(statusDescription)
                .font(.subheadline)
                .foregroundStyle(Self.secondaryText)
                .lineLimit(2)
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

    @ViewBuilder private var advice: some View {
        if let message = reader.errorMessage ?? reader.session.message {
            Text(message)
                .font(.callout)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        } else if reader.session.canImproveVoiceByDownloading {
            Text("Compact voice. Download a Premium voice in Settings › Accessibility › Spoken Content › Voices for a more natural one.")
                .font(.footnote)
                .foregroundStyle(Self.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var actions: some View {
        HStack {
            Button("Voice and Transcript", systemImage: "text.alignleft") {
                dismiss()
                // UIKit drops a sheet presented while this popover is still closing.
                Task {
                    try? await Task.sleep(for: .milliseconds(450))
                    reader.showsReader = true
                }
            }
            Spacer()
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
        else {
            switch reader.session.state {
            case .speaking: parts.append("Reading")
            case .paused: parts.append("Paused")
            case .finished: parts.append("Finished")
            case .idle: parts.append("Ready")
            }
        }
        if !reader.scopeDescription.isEmpty { parts.append(reader.scopeDescription) }
        if let voice = reader.session.selectedVoice { parts.append("\(voice.name) (\(voice.qualityDescription))") }
        return parts.joined(separator: " · ")
    }
}

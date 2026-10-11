import SwiftUI
import AVFoundation
import GraphiteCore
import GraphiteApple

struct ReadAloudReader: View {
    @Bindable var reader: ReadAloudController
    @State private var preview = ReadAloudSession()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                voiceControls
                Divider()
                if reader.isPreparing {
                    ProgressView("Preparing your passage…").frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let errorMessage = reader.errorMessage {
                    ContentUnavailableView("Cannot Read This Passage", systemImage: "speaker.slash", description: Text(errorMessage))
                } else {
                    transcript
                }
                Divider()
                playbackControls
            }
            .navigationTitle(reader.title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .frame(minWidth: 320, idealWidth: 640, minHeight: 480, idealHeight: 720)
        .onDisappear { preview.stop() }
        .onChange(of: reader.session.state) { _, state in if state == .speaking { preview.stop() } }
        .onReceive(NotificationCenter.default.publisher(for: AVSpeechSynthesizer.availableVoicesDidChangeNotification)) { _ in reader.session.refreshVoices() }
    }

    private var voiceControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(reader.scopeDescription).font(.subheadline).foregroundStyle(.secondary)
            HStack {
                Picker("Voice", selection: Binding(get: { reader.session.selectedVoiceIdentifier ?? "" }, set: { identifier in
                    preview.stop(); reader.session.chooseVoice(identifier)
                })) {
                    Text("Choose a voice").tag("")
                    if let selected = reader.session.selectedVoiceIdentifier, !reader.session.voices.contains(where: { voice in voice.id == selected }) {
                        Text("Previous voice unavailable").tag(selected)
                    }
                    ForEach(reader.session.voices) { voice in
                        Text("\(voice.name) · \(voice.language) · \(voice.qualityDescription)").tag(voice.id)
                    }
                }
                Menu("Preview", systemImage: "speaker.wave.2") {
                    Button("Study Sample") { previewVoice() }
                    Button("Current Passage") { previewVoice(usesCurrentPassage: true) }
                        .disabled(reader.session.currentPassage == nil || reader.isPreparing || reader.errorMessage != nil)
                    if preview.state == .speaking || preview.state == .paused {
                        Button("Stop Preview", systemImage: "stop.fill") { preview.stop() }
                    }
                }
                .disabled(reader.session.selectedVoiceIdentifier == nil)
            }
            Text("Uses installed Apple voices on this device. Premium and Enhanced are Apple’s quality labels. Preview a voice to judge how natural it sounds.")
                .font(.caption).foregroundStyle(.secondary)
            if preview.state == .speaking {
                Text("Playing voice preview. Your reading position is paused.").font(.caption).foregroundStyle(.secondary)
            }
            Text("More voices can be downloaded in your device’s Accessibility settings. Math narration currently uses English. Cloud voices and scanned-page recognition are not available yet.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Picker("Speed", selection: Binding(get: { reader.session.speed }, set: { speed in preview.stop(); reader.session.setSpeed(speed) })) {
                    ForEach([0.5, 0.75, 1.0, 1.25, 1.5], id: \.self) { speed in Text(speed.formatted() + "×").tag(speed) }
                }
                Toggle("Follow Reading", isOn: $reader.followsReading).toggleStyle(.switch)
            }
            if reader.sourcePageIndex != nil || reader.scopeDescription == "Selected PDF text" {
                Text("PDF text follows the file’s extraction order. Check columns and equations in the transcript before playing.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Show in PDF", systemImage: "doc.text.magnifyingglass") {
                    if reader.showPDFPassage() { dismiss() }
                }
                .disabled(!reader.canShowPDFPassage)
            }
            if let message = reader.session.message ?? preview.message {
                Text(message).font(.callout).foregroundStyle(.orange).accessibilityIdentifier("readAloudMessage")
            }
            if let notice = reader.sourceHighlightNotice {
                Text(notice).font(.caption).foregroundStyle(.secondary)
            }
            ForEach(reader.session.document?.notices ?? [], id: \.self) { notice in Text(notice).font(.caption).foregroundStyle(.secondary) }
        }
        .padding()
    }

    private var transcript: some View {
        ScrollViewReader { scroll in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    ForEach(reader.session.document?.passages ?? []) { passage in
                        Text(highlighted(passage))
                            .font(.title3).lineSpacing(6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(passage.id == reader.session.passageIndex ? Color.accentColor.opacity(0.06) : .clear, in: RoundedRectangle(cornerRadius: 10))
                            .id(passage.id)
                            .contextMenu {
                                Button("Read From This Passage", systemImage: "play.fill") {
                                    preview.stop(); reader.session.move(to: passage.id); reader.session.play()
                                }
                            }
                    }
                }.padding()
            }
            .onScrollPhaseChange { _, phase in
                if phase == .interacting { reader.suspendFollowing() }
            }
            .onChange(of: reader.session.passageIndex) { _, index in
                if reader.followsReading { withAnimation { scroll.scrollTo(index, anchor: .center) } }
            }
            .onChange(of: reader.followsReading) { _, followsReading in
                if followsReading { withAnimation { scroll.scrollTo(reader.session.passageIndex, anchor: .center) } }
            }
        }
    }

    private func highlighted(_ passage: ReadAloudPassage) -> AttributedString {
        var attributed = AttributedString(passage.text)
        if passage.id == reader.session.passageIndex, let spokenRange = reader.session.spokenRange,
           let stringRange = Range(spokenRange, in: passage.text), let attributedRange = Range(stringRange, in: attributed) {
            attributed[attributedRange].backgroundColor = .yellow.opacity(0.55)
            attributed[attributedRange].foregroundColor = .black
        }
        return attributed
    }

    private var playbackControls: some View {
        HStack(spacing: 24) {
            Button("Previous Sentence", systemImage: "backward.end.fill") { preview.stop(); reader.session.moveToPreviousSentence() }
                .disabled(!reader.session.canMoveToPreviousSentence)
            Button(reader.session.state == .speaking ? "Pause" : "Play", systemImage: reader.session.state == .speaking ? "pause.fill" : "play.fill") {
                preview.stop()
                if reader.session.state == .speaking { reader.session.pause() } else { reader.session.play() }
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("readAloudPlayPause")
            Button("Next Sentence", systemImage: "forward.end.fill") { preview.stop(); reader.session.moveToNextSentence() }
                .disabled(!reader.session.canMoveToNextSentence)
            Button("Repeat Passage", systemImage: "repeat") { preview.stop(); reader.session.repeatPassage() }
            Button("Stop", systemImage: "stop.fill") { preview.stop(); reader.stop() }
        }
        .labelStyle(.iconOnly)
        .font(.title2)
        .padding()
        .disabled(reader.isPreparing || reader.session.document == nil || reader.errorMessage != nil)
    }

    private func previewVoice(usesCurrentPassage: Bool = false) {
        preview.stop()
        reader.session.pause()
        preview.refreshVoices()
        guard let voiceIdentifier = reader.session.selectedVoiceIdentifier else { return }
        preview.chooseVoice(voiceIdentifier)
        preview.setSpeed(reader.session.speed)
        do {
            let sample: ReadAloudDocument
            if usesCurrentPassage, let passage = reader.session.currentPassage {
                // This is already prepared speech, including expanded math. Do
                // not parse it as Markdown again or change the reading session.
                sample = try ReadAloudDocument.plainText(passage.text)
            } else {
                sample = try ReadAloudDocument.markdown("## A moment to study\n\nRead at a comfortable pace. Pause between ideas, and follow each word. For example, $x^2$ means x squared, and $\\frac{a+b}{c}$ is a fraction.")
            }
            preview.load(sample)
            preview.play()
        } catch { reader.session.pause() }
    }
}

struct ReadAloudSectionPicker: View {
    let source: String
    let choose: (ReadAloudSection, String) -> Void
    @State private var sections: [ReadAloudSection] = []
    @State private var isPreparing = true
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if isPreparing {
                    ProgressView("Finding sections…")
                } else if let errorMessage {
                    ContentUnavailableView("Cannot Read Sections", systemImage: "text.magnifyingglass", description: Text(errorMessage))
                } else if sections.isEmpty {
                    ContentUnavailableView("No Sections", systemImage: "text.alignleft", description: Text("This note has no headings. Choose Read Document or select a passage."))
                } else {
                    List(sections) { section in
                        Button {
                            choose(section, source)
                            dismiss()
                        } label: {
                            Text(section.title).padding(.leading, CGFloat(section.level - 1) * 12)
                        }
                        .accessibilityHint("Read this section and its subsections")
                    }
                }
            }
            .navigationTitle("Read a Section")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .task(id: source) {
                isPreparing = true
                errorMessage = nil
                let worker = Task.detached(priority: .userInitiated) { try ReadAloudSection.sections(in: source) }
                do {
                    let preparedSections = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
                    guard !Task.isCancelled else { return }
                    sections = preparedSections
                    isPreparing = false
                } catch {
                    guard !Task.isCancelled else { return }
                    errorMessage = error.localizedDescription
                    isPreparing = false
                }
            }
        }
        .frame(minWidth: 320, idealWidth: 480, minHeight: 320, idealHeight: 600)
    }
}

struct ReadAloudPDFRangePicker: View {
    let pageCount: Int
    let startingPageIndex: Int
    let read: (Int, Int) -> Void
    @State private var firstPage = 1
    @State private var lastPage = 1
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Stepper("First page: \(firstPage)", value: $firstPage, in: 1...max(1, pageCount))
                    .onChange(of: firstPage) { _, firstPage in if lastPage < firstPage { lastPage = firstPage } }
                Stepper("Last page: \(lastPage)", value: $lastPage, in: firstPage...max(firstPage, pageCount))
                Text("Uses page positions in the PDF, which may differ from printed page numbers. The reader loads one page at a time and stops if a page has no selectable text.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .navigationTitle("Read PDF Pages")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Continue") { dismiss(); read(firstPage - 1, lastPage - 1) }.disabled(pageCount == 0)
                }
            }
        }
        .onAppear { firstPage = min(max(1, startingPageIndex + 1), max(1, pageCount)); lastPage = max(firstPage, pageCount) }
        .frame(minWidth: 320, minHeight: 260)
    }
}

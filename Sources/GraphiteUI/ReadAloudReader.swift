import SwiftUI
import AVFoundation
import GraphiteCore
import GraphiteApple

struct ReadAloudReader: View {
    @Bindable var reader: ReadAloudController
    @State private var preview = ReadAloudSession()
    @State private var previewPreparation: Task<Void, Never>?
    @State private var previewPreparationIdentifier: UUID?
    @State private var previewError: String?
    @State private var showsScanReview = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

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
        .onDisappear { stopPreview() }
        .sheet(isPresented: $showsScanReview) {
            if let snapshot = reader.recognizedPDFPage, let identifier = reader.recognizedPageIdentifier {
                ReadAloudScanReview(snapshot: snapshot, initialWordRange: reader.recognizedWordRange) { corrections, words in
                    stopPreview()
                    reader.applyRecognizedPDFReview(corrections, words: words, pageIdentifier: identifier)
                }
            }
        }
        .onChange(of: reader.stopIdentifier) { _, _ in stopPreview() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { stopPreview() } }
        .onChange(of: reader.session.state) { _, state in if state == .speaking { stopPreview() } }
        .onReceive(NotificationCenter.default.publisher(for: AVSpeechSynthesizer.availableVoicesDidChangeNotification)) { _ in reader.session.refreshVoices() }
    }

    private var voiceControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(reader.scopeDescription).font(.subheadline).foregroundStyle(.secondary)
            HStack {
                Picker("Voice", selection: Binding(get: { reader.session.selectedVoiceIdentifier ?? "" }, set: { identifier in
                    stopPreview(); reader.session.chooseVoice(identifier)
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
                    if preview.state == .speaking || preview.state == .paused || previewPreparation != nil {
                        Button("Stop Preview", systemImage: "stop.fill") { stopPreview() }
                    }
                }
                .disabled(reader.session.selectedVoiceIdentifier == nil || reader.isPreparing)
            }
            Text("Uses installed Apple voices on this device. Premium and Enhanced are Apple’s quality labels. Preview a voice to judge how natural it sounds.")
                .font(.caption).foregroundStyle(.secondary)
            if preview.state == .speaking {
                Text("Playing voice preview. Your reading position is paused.").font(.caption).foregroundStyle(.secondary)
            } else if previewPreparation != nil {
                ProgressView("Preparing voice preview…").font(.caption)
            }
            Text("More voices can be downloaded in your device’s Accessibility settings. Math narration currently uses English. Cloud voices are not available yet.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Picker("Speed", selection: Binding(get: { reader.session.speed }, set: { speed in stopPreview(); reader.session.setSpeed(speed) })) {
                    ForEach([0.5, 0.75, 1.0, 1.25, 1.5], id: \.self) { speed in Text(speed.formatted() + "×").tag(speed) }
                }
                Toggle("Follow Reading", isOn: $reader.followsReading).toggleStyle(.switch)
            }
            if reader.sourcePageIndex == nil && reader.scopeDescription != "Selected PDF text" {
                Picker("Math Detail", selection: Binding(get: { reader.mathematicalStyle }, set: { style in
                    stopPreview(); reader.chooseMathematicalStyle(style)
                })) {
                    Text("Concise").tag(MathematicalSpeechStyle.concise)
                    Text("Detailed").tag(MathematicalSpeechStyle.detailed)
                }
                Text("Changing math detail prepares the chosen range again. Equations highlight as a whole.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if reader.sourcePageIndex != nil || reader.scopeDescription == "Selected PDF text" {
                if reader.recognizedPDFPage != nil {
                    Picker("Recognized Order", selection: Binding(get: { reader.pdfReadingOrder }, set: { readingOrder in
                        stopPreview(); reader.choosePDFReadingOrder(readingOrder)
                    })) {
                        Text("Page Layout").tag(PDFReadingOrder.layout)
                        Text("Line Order").tag(PDFReadingOrder.file)
                    }
                    Text("Changing order recognizes this page again, clears temporary corrections and chosen words, and waits for Play.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Review Recognized Words", systemImage: "text.magnifyingglass") {
                        stopPreview(); reader.session.pause(); showsScanReview = true
                    }
                    .disabled(reader.isPreparing || reader.recognizedPageIdentifier == nil)
                } else if reader.sourcePageIndex != nil {
                    Picker("Reading Order", selection: Binding(get: { reader.pdfReadingOrder }, set: { readingOrder in
                        stopPreview(); reader.choosePDFReadingOrder(readingOrder)
                    })) {
                        Text("Page Layout").tag(PDFReadingOrder.layout)
                        Text("File Order").tag(PDFReadingOrder.file)
                    }
                    Text("Check columns and equations in the transcript before playing. Changing reading order prepares this page again and waits for Play.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("The selected pieces are read in their selection order. Check equations in the transcript before playing.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Button("Show in PDF", systemImage: "doc.text.magnifyingglass") {
                    if reader.showPDFPassage() { dismiss() }
                }
                .disabled(!reader.canShowPDFPassage)
            }
            if let message = reader.session.message ?? preview.message ?? previewError {
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
                                    stopPreview(); reader.session.move(to: passage.id); reader.session.play()
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
            Button("Previous Sentence", systemImage: "backward.end.fill") { stopPreview(); reader.session.moveToPreviousSentence() }
                .disabled(!reader.session.canMoveToPreviousSentence)
            Button(reader.session.state == .speaking ? "Pause" : "Play", systemImage: reader.session.state == .speaking ? "pause.fill" : "play.fill") {
                stopPreview()
                if reader.session.state == .speaking { reader.session.pause() } else { reader.session.play() }
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("readAloudPlayPause")
            Button("Next Sentence", systemImage: "forward.end.fill") { stopPreview(); reader.session.moveToNextSentence() }
                .disabled(!reader.session.canMoveToNextSentence)
            Button("Repeat Passage", systemImage: "repeat") { stopPreview(); reader.session.repeatPassage() }
            Button("Stop", systemImage: "stop.fill") { stopPreview(); reader.stop() }
        }
        .labelStyle(.iconOnly)
        .font(.title2)
        .padding()
        .disabled(reader.isPreparing || reader.session.document == nil || reader.errorMessage != nil)
    }

    private func previewVoice(usesCurrentPassage: Bool = false) {
        stopPreview()
        reader.session.pause()
        preview.refreshVoices()
        guard let voiceIdentifier = reader.session.selectedVoiceIdentifier else { return }
        preview.chooseVoice(voiceIdentifier)
        preview.setSpeed(reader.session.speed)
        let passageText = usesCurrentPassage ? reader.session.currentPassage?.text : nil
        let identifier = UUID()
        previewPreparationIdentifier = identifier
        previewPreparation = Task {
            do {
                let sample: ReadAloudDocument
                if let passageText {
                    // This is already prepared speech, including expanded math.
                    sample = try ReadAloudDocument.plainText(passageText)
                } else {
                    sample = try await reader.prepareVoiceSample()
                }
                guard !Task.isCancelled, previewPreparationIdentifier == identifier else { return }
                preview.load(sample)
                preview.play()
            } catch {
                guard !Task.isCancelled, previewPreparationIdentifier == identifier else { return }
                previewError = error.localizedDescription
            }
            if previewPreparationIdentifier == identifier {
                previewPreparationIdentifier = nil
                previewPreparation = nil
            }
        }
    }

    private func stopPreview() {
        previewPreparation?.cancel()
        previewPreparation = nil
        previewPreparationIdentifier = nil
        previewError = nil
        preview.stop()
    }
}

struct ReadAloudScanReview: View {
    let snapshot: PDFReadAloudPage
    let initialWordRange: ClosedRange<Int>?
    let apply: ([Int: String], ClosedRange<Int>?) -> Void
    @State private var corrections: [Int: String] = [:]
    @State private var searchText = ""
    @State private var showsOnlyUncertainWords = false
    @State private var editingWordIndex: Int?
    @State private var replacementText = ""
    @State private var showsCorrection = false
    @State private var firstWordIndex: Int?
    @State private var lastWordIndex: Int?
    @Environment(\.dismiss) private var dismiss

    private var words: [PDFRecognizedReading.Word] { snapshot.recognition?.words ?? [] }

    private var selectedWords: ClosedRange<Int>? {
        guard let firstWordIndex, let lastWordIndex, firstWordIndex <= lastWordIndex else { return nil }
        return firstWordIndex...lastWordIndex
    }

    private var hasInvalidRange: Bool {
        (firstWordIndex != nil || lastWordIndex != nil) && selectedWords == nil
    }

    private func text(at wordIndex: Int) -> String {
        corrections[wordIndex] ?? (snapshot.text as NSString).substring(with: words[wordIndex].textRange)
    }

    private var visibleIndices: [Int] {
        words.indices.filter { wordIndex in
            (!showsOnlyUncertainWords || words[wordIndex].confidence < 0.85) &&
                (searchText.isEmpty || text(at: wordIndex).localizedStandardContains(searchText))
        }
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text("Check words against the PDF, especially numbers and equations. Corrections affect this reading only and keep the same word highlight on the page.")
                    .font(.callout).padding(.horizontal)
                VStack(alignment: .leading, spacing: 6) {
                    if let firstWordIndex, let lastWordIndex {
                        Text("Read words \(firstWordIndex + 1)–\(lastWordIndex + 1) on this page only.")
                        if hasInvalidRange { Text("Choose an end at or after the start.").foregroundStyle(.orange) }
                        Button("Use Whole Page") { self.firstWordIndex = nil; self.lastWordIndex = nil }
                    } else {
                        Text("Use a word’s menu to choose a start and end. A chosen passage stops on this page.")
                    }
                }.font(.callout).padding(.horizontal)
                Toggle("Show Less Certain Words Only", isOn: $showsOnlyUncertainWords).padding(.horizontal)
                List(visibleIndices, id: \.self) { wordIndex in
                    Button {
                        editingWordIndex = wordIndex
                        replacementText = text(at: wordIndex)
                        showsCorrection = true
                    } label: {
                        HStack {
                            Text("\(wordIndex + 1)").monospacedDigit().foregroundStyle(.secondary)
                            Text(text(at: wordIndex)).foregroundStyle(.primary)
                            Spacer()
                            if corrections[wordIndex] != nil || words[wordIndex].isCorrected {
                                Text("Corrected").font(.caption).foregroundStyle(.secondary)
                            } else if words[wordIndex].confidence < 0.85 {
                                Text("Review").font(.caption).foregroundStyle(.orange)
                            }
                        }
                    }
                    .accessibilityLabel("Word \(wordIndex + 1), \(text(at: wordIndex))")
                    .accessibilityHint("Correct this recognized word or short phrase. Its menu chooses the reading start or end.")
                    .contextMenu {
                        Button("Start Here") {
                            firstWordIndex = wordIndex
                            if lastWordIndex == nil { lastWordIndex = words.count - 1 }
                        }
                        Button("End Here") {
                            lastWordIndex = wordIndex
                            if firstWordIndex == nil { firstWordIndex = 0 }
                        }
                    }
                }
                .searchable(text: $searchText, prompt: "Find a recognized word")
                Text("Recognition can be wrong even for words marked confident. \(corrections.count) pending corrections.")
                    .font(.caption).foregroundStyle(.secondary).padding(.horizontal)
            }
            .padding(.vertical)
            .navigationTitle("Review Scanned Page")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") { apply(corrections, selectedWords); dismiss() }
                        .disabled(hasInvalidRange || (corrections.isEmpty && selectedWords == initialWordRange))
                }
            }
            .alert("Correct Recognized Word", isPresented: $showsCorrection) {
                TextField("Word or short phrase", text: $replacementText)
                Button("Cancel", role: .cancel) { editingWordIndex = nil }
                Button("Use Correction") {
                    if let wordIndex = editingWordIndex {
                        corrections[wordIndex] = replacementText.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                    editingWordIndex = nil
                }
                .disabled(replacementText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || replacementText.utf16.count > 256 || replacementText.contains("\n"))
            } message: {
                Text("Use up to 256 characters on one line. A short phrase highlights the original word’s whole region.")
            }
        }
        .onAppear { firstWordIndex = initialWordRange?.lowerBound; lastWordIndex = initialWordRange?.upperBound }
        .frame(minWidth: 320, idealWidth: 560, minHeight: 420, idealHeight: 680)
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

struct ReadAloudPDFSectionPicker: View {
    let entries: [PDFOutlineEntry]
    let pageCount: Int
    let read: (ClosedRange<Int>) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Text("Reads full pages from this outline entry through the next section’s starting page. Boundary pages may include neighboring sections. Select text in the PDF for exact boundaries.")
                    .font(.callout).foregroundStyle(.secondary)
                ForEach(entries) { entry in
                    if let pages = entry.readingPages(in: entries, pageCount: pageCount) {
                        Button {
                            read(pages); dismiss()
                        } label: {
                            VStack(alignment: .leading) {
                                Text(entry.label)
                                Text("Pages \(pages.lowerBound + 1)–\(pages.upperBound + 1)").font(.caption).foregroundStyle(.secondary)
                            }.padding(.leading, CGFloat(entry.depth) * 12)
                        }
                    }
                }
            }
            .navigationTitle("Read Section Pages")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
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
                Text("Uses page positions in the PDF, which may differ from printed page numbers. The reader loads one page at a time. Scanned pages pause for transcript review before Play.")
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

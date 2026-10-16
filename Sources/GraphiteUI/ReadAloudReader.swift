import SwiftUI
import AVFoundation
import GraphiteCore
import GraphiteApple

/// Reading Options: the voice, how this passage is read, and its transcript with the word
/// being spoken. Opened from the toolbar's reading controls, or by itself when a passage
/// cannot be read or a scanned page needs checking before it is read.
struct ReadAloudReader: View {
    @Bindable var reader: ReadAloudController
    @State private var showsScanReview = false
    @Environment(\.dismiss) private var dismiss

    private var isPDFPassage: Bool { reader.sourcePageIndex != nil || reader.pdfSourceIsSelection }

    var body: some View {
        NavigationStack {
            Group {
                if reader.isPreparing {
                    ProgressView("Preparing your passage…").frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let errorMessage = reader.errorMessage {
                    ContentUnavailableView("Cannot Read This Passage", systemImage: "speaker.slash", description: Text(errorMessage))
                } else {
                    options
                }
            }
            .navigationTitle(reader.title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .safeAreaInset(edge: .bottom) { playbackControls }
        }
        .frame(minWidth: 320, idealWidth: 560, minHeight: 480, idealHeight: 760)
        .sheet(isPresented: $showsScanReview) {
            if let snapshot = reader.recognizedPDFPage, let identifier = reader.recognizedPageIdentifier {
                ReadAloudScanReview(snapshot: snapshot, initialWordRange: reader.recognizedWordRange) { corrections, words in
                    reader.applyRecognizedPDFReview(corrections, words: words, pageIdentifier: identifier)
                }
            }
        }
    }

    private var options: some View {
        ScrollViewReader { scroll in
            Form {
                ReadAloudVoiceSettings(reader: reader)
                Section {
                    Toggle("Follow Reading", isOn: $reader.followsReading)
                    if !isPDFPassage {
                        Picker("Math", selection: Binding(get: { reader.mathematicalStyle }, set: { style in reader.chooseMathematicalStyle(style) })) {
                            Text("Concise").tag(MathematicalSpeechStyle.concise)
                            Text("Detailed").tag(MathematicalSpeechStyle.detailed)
                        }
                    } else if reader.sourcePageIndex != nil {
                        Picker(reader.recognizedPDFPage == nil ? "Reading Order" : "Recognized Order",
                               selection: Binding(get: { reader.pdfReadingOrder }, set: { readingOrder in reader.choosePDFReadingOrder(readingOrder) })) {
                            Text("Page Layout").tag(PDFReadingOrder.layout)
                            Text(reader.recognizedPDFPage == nil ? "File Order" : "Line Order").tag(PDFReadingOrder.file)
                        }
                    }
                    if reader.recognizedPDFPage != nil {
                        Button("Review Recognized Words", systemImage: "text.magnifyingglass") {
                            reader.session.pause(); showsScanReview = true
                        }
                        .disabled(reader.recognizedPageIdentifier == nil)
                    }
                    if isPDFPassage {
                        Button("Show in PDF", systemImage: "doc.text.magnifyingglass") {
                            if reader.showPDFPassage() { dismiss() }
                        }
                        .disabled(!reader.canShowPDFPassage)
                    }
                } header: {
                    Text(reader.scopeDescription.isEmpty ? "Reading" : reader.scopeDescription)
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        if !isPDFPassage { Text("Concise reads equations the way you would say them; Detailed names every part. Changing it prepares the passage again.") }
                        if let notice = reader.sourceHighlightNotice { Text(notice) }
                        ForEach(reader.session.document?.notices ?? [], id: \.self) { notice in Text(notice) }
                    }
                        .formFooterAlignment()
                }
                Section("Transcript") {
                    ForEach(reader.session.document?.passages ?? []) { passage in
                        Button {
                            reader.session.move(to: passage.id)
                            reader.session.play()
                        } label: {
                            Text(highlighted(passage))
                                .font(.body)
                                .foregroundStyle(.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(passage.id == reader.session.passageIndex ? Color.accentColor.opacity(0.12) : nil)
                        .accessibilityHint("Reads from this passage")
                        .id(passage.id)
                    }
                }
            }
            .onAppear { scroll.scrollTo(reader.session.passageIndex, anchor: .center) }
            .onChange(of: reader.session.passageIndex) { _, index in
                if reader.followsReading { withAnimation(GraphiteMotion.animation(.default)) { scroll.scrollTo(index, anchor: .center) } }
            }
        }
    }

    private func highlighted(_ passage: ReadAloudPassage) -> AttributedString {
        var attributed = AttributedString(passage.text)
        if passage.id == reader.session.passageIndex, let highlightRange = reader.session.highlightRange,
           let stringRange = Range(highlightRange, in: passage.text), let attributedRange = Range(stringRange, in: attributed) {
            attributed[attributedRange].backgroundColor = ReadAloudHighlightStyle.color
        }
        return attributed
    }

    private var playbackControls: some View {
        HStack(spacing: 28) {
            Button("Previous Sentence", systemImage: "backward.end.fill") { reader.session.moveToPreviousSentence() }
                .disabled(!reader.session.canMoveToPreviousSentence)
                .frame(minWidth: 44, minHeight: 44)
            ReadAloudPlayPauseButton(reader: reader, prominent: true)
            Button("Next Sentence", systemImage: "forward.end.fill") { reader.session.moveToNextSentence() }
                .disabled(!reader.session.canMoveToNextSentence)
                .frame(minWidth: 44, minHeight: 44)
            Button("Repeat Passage", systemImage: "repeat") { reader.session.repeatPassage() }
                .frame(minWidth: 44, minHeight: 44)
        }
        .labelStyle(.iconOnly)
        .font(.title2)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(.bar)
        .disabled(reader.isPreparing || reader.session.document == nil || reader.errorMessage != nil)
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

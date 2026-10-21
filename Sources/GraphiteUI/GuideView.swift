import SwiftUI

extension View {
    /// Presents the Guide in a sheet: page-sized on iPad and iPhone, window-sized on the Mac.
    func guide(isPresented: Binding<Bool>) -> some View {
        sheet(isPresented: isPresented) {
            GuideView(showsDoneButton: true)
                #if os(macOS)
                .frame(minWidth: 860, idealWidth: 1000, minHeight: 600, idealHeight: 720)
                #else
                .presentationSizing(.page)
                #endif
        }
    }
}

/// The Guide: the step-by-step how-to, from a first note to every feature. Its sections and
/// topics are a sidebar with a search field; the chosen topic's steps are the detail. On a
/// phone the two are one stack. On the Mac it is also a window of its own (Help › Graphite
/// Guide).
struct GuideView: View {
    /// A sheet has Done; the Mac's Guide window closes as windows do.
    let showsDoneButton: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accent) private var accent
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    /// Empty on a phone, so the Guide opens on its list of topics; where the list and a topic
    /// show side by side, the first topic is chosen when the Guide appears.
    @State private var selectedTopic: GuideTopic?
    @State private var query = ""
    @State private var columnVisibility = NavigationSplitViewVisibility.all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            topicList
                .navigationTitle("Guide")
                .searchable(text: $query, prompt: "Search the Guide")
                .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 360)
                .toolbar {
                    if showsDoneButton {
                        ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                    }
                }
        } detail: {
            if let selectedTopic {
                GuideTopicView(topic: selectedTopic) { nextTopic in self.selectedTopic = nextTopic }
            } else {
                ContentUnavailableView("Choose a Topic", systemImage: "book", description: Text("Start with The Basics, or search for what you want to do."))
            }
        }
        .tint(accent)
        .onAppear { if horizontalSizeClass != .compact && selectedTopic == nil { selectedTopic = .vaults } }
    }

    private var topicList: some View {
        List(selection: $selectedTopic) {
            ForEach(GuideSection.allCases) { section in
                let topics = section.topicsOnThisPlatform.filter { topic in topic.matches(query) }
                if !topics.isEmpty {
                    Section(section.title) {
                        ForEach(topics) { topic in
                            Label(topic.content.title, systemImage: topic.content.systemImage).tag(topic)
                        }
                    }
                }
            }
        }
        .overlay {
            if GuideSection.allCases.allSatisfy({ section in section.topicsOnThisPlatform.allSatisfy { topic in !topic.matches(query) } }) {
                ContentUnavailableView.search(text: query)
            }
        }
    }
}

/// One topic: its summary, its numbered steps with any Markdown to type, its tips, and a link
/// to the next topic so the Guide reads from start to end.
private struct GuideTopicView: View {
    let topic: GuideTopic
    let showTopic: (GuideTopic) -> Void

    private var content: GuideTopicContent { topic.content }

    /// The topic after this one on this platform, so the Guide can be read in order.
    private var nextTopic: GuideTopic? {
        let topics = GuideSection.allCases.flatMap(\.topicsOnThisPlatform)
        guard let index = topics.firstIndex(of: topic), index + 1 < topics.count else { return nil }
        return topics[index + 1]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(Array(content.steps.enumerated()), id: \.offset) { stepIndex, step in
                        GuideStepRow(number: stepIndex + 1, step: step)
                    }
                }
                if !content.tips.isEmpty { tips }
                if let nextTopic {
                    Button { showTopic(nextTopic) } label: {
                        Label("Next: \(nextTopic.content.title)", systemImage: "arrow.right")
                    }
                    .buttonStyle(.bordered)
                    .padding(.top, 8)
                }
            }
            .frame(maxWidth: 680, alignment: .leading)
            .padding(.horizontal, 28)
            .padding(.vertical, 28)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(content.title)
        #if canImport(UIKit)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .id(topic)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: content.systemImage)
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(.tint)
                .frame(width: 52, height: 52)
                .background(.tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .accessibilityHidden(true)
            Text(content.title).font(.largeTitle.weight(.bold)).accessibilityAddTraits(.isHeader)
            Text(content.summary).font(.title3).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var tips: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Tips", systemImage: "lightbulb").font(.headline).foregroundStyle(.tint)
            ForEach(content.tips, id: \.self) { tip in
                Text(GuideText.styled(tip)).font(.subheadline).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// A numbered step, and below it the Markdown it asks to type, selectable so it can be copied.
private struct GuideStepRow: View {
    let number: Int
    let step: GuideStep

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text("\(number)")
                .font(.subheadline.weight(.bold).monospacedDigit())
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(.tint, in: Circle())
                .accessibilityLabel("Step \(number)")
            VStack(alignment: .leading, spacing: 10) {
                Text(GuideText.styled(step.text)).font(.body).fixedSize(horizontal: false, vertical: true)
                if let example = step.example {
                    Text(verbatim: example)
                        .font(.callout.monospaced())
                        .textSelection(.enabled)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
        }
    }
}

/// The Guide's words with Markdown's inline styles, such as **bold** for the names of
/// controls. Text that does not parse is shown as written.
enum GuideText {
    static func styled(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}

import SwiftUI
import GraphiteCore
import GraphiteApple

/// Read Aloud's floating player, like Speak Screen's controller: a small bar in a corner of
/// the window that stays out of the way of what is read. It holds Play/Pause, Back and
/// Forward by sentence (and by section or page from their menus), speed, the sections of what
/// is read, the queue, Voice and Transcript, and Stop. Dragging it moves it to another
/// corner. While the person scrolls away from the reading position it shrinks to a pill and
/// offers "Read from Here" and "Back to Reading". Liquid Glass is used only for this floating
/// layer (HIG `liquid-glass.md` › functional layer).
struct ReadAloudFloatingPlayer: View {
    @Bindable var reader: ReadAloudController
    @Bindable var navigator: ReadAloudNavigator
    let accentColor: Color
    @AppStorage("GraphiteReadAloudPlayerCorner") private var cornerRawValue = PlayerCorner.bottomTrailing.rawValue
    @State private var dragOffset: CGSize = .zero
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    enum PlayerCorner: String, CaseIterable {
        case topLeading, topTrailing, bottomLeading, bottomTrailing

        var alignment: Alignment {
            switch self {
            case .topLeading: .topLeading
            case .topTrailing: .topTrailing
            case .bottomLeading: .bottomLeading
            case .bottomTrailing: .bottomTrailing
            }
        }
        var isTop: Bool { self == .topLeading || self == .topTrailing }
        var isLeading: Bool { self == .topLeading || self == .bottomLeading }
    }

    private var corner: PlayerCorner {
        let saved = PlayerCorner(rawValue: cornerRawValue) ?? .bottomTrailing
        // It never sits over the line being read: when the highlight is in its half of the
        // screen, it shows in the other half until the reading moves on.
        guard let highlight = navigator.highlightFrameInWindow, let window = navigator.windowBounds, window.height > 0 else { return saved }
        let highlightIsInTopHalf = highlight.midY < window.midY
        guard highlightIsInTopHalf == saved.isTop, isNear(highlight, window: window, top: saved.isTop) else { return saved }
        switch saved {
        case .topLeading: return .bottomLeading
        case .topTrailing: return .bottomTrailing
        case .bottomLeading: return .topLeading
        case .bottomTrailing: return .topTrailing
        }
    }

    /// Within the player's reach: the band it occupies at the top or bottom of the window.
    private func isNear(_ highlight: CGRect, window: CGRect, top: Bool) -> Bool {
        top ? highlight.minY < window.minY + Self.topInset + 80 : highlight.maxY > window.maxY - 110
    }

    /// Below the window's toolbar and the tab strip, which the player never covers.
    private static let topInset: CGFloat = 64

    /// 44 points, larger at accessibility text sizes.
    private var buttonSize: CGFloat { dynamicTypeSize.isAccessibilitySize ? 60 : 44 }

    /// Shrunk while the person has scrolled away from the reading position.
    private var isCompact: Bool { !reader.followsReading && reader.session.document != nil }

    var body: some View {
        VStack(alignment: corner.isLeading ? .leading : .trailing, spacing: 8) {
            if corner.isTop { player; scrollPills } else { scrollPills; player }
        }
        .padding(.horizontal, 16)
        .padding(.top, corner.isTop ? Self.topInset : 16)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: corner.alignment)
        .offset(dragOffset)
        .animation(reduceMotion ? nil : .snappy, value: corner)
        .animation(reduceMotion ? nil : .snappy, value: isCompact)
        .tint(accentColor)
    }

    // MARK: Player

    @ViewBuilder private var player: some View {
        Group {
            if isCompact { compactPlayer } else { fullPlayer }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .modifier(FloatingGlass())
        .onGeometryChange(for: CGRect.self) { geometry in geometry.frame(in: .global) } action: { frame in
            navigator.playerFrameInWindow = frame
        }
        .gesture(dragToCorner)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Read Aloud")
    }

    private var fullPlayer: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let note = statusNote {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .padding(.top, 4)
            }
            // At accessibility text sizes the controls take two rows instead of overlapping.
            let layout = dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 2)) : AnyLayout(HStackLayout(spacing: 2))
            layout {
                HStack(spacing: 2) {
                    backButton
                    ReadAloudPlayPauseButton(reader: reader, prominent: false)
                        .labelStyle(.iconOnly)
                        .font(.title2)
                        .frame(width: buttonSize + 4, height: buttonSize + 4)
                    forwardButton
                }
                HStack(spacing: 2) {
                    speedMenu
                    sectionsMenu
                    Button("Voice and Transcript", systemImage: "text.alignleft") { reader.showsReader = true }
                        .labelStyle(.iconOnly)
                        .frame(width: buttonSize, height: buttonSize)
                    Button("Stop Reading", systemImage: "xmark") { reader.clear() }
                        .labelStyle(.iconOnly)
                        .frame(width: buttonSize, height: buttonSize)
                }
            }
            .font(.title3)
            // Icons grow with the text size up to a point where they still fit their targets.
            .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        }
    }

    private var compactPlayer: some View {
        HStack(spacing: 4) {
            ReadAloudPlayPauseButton(reader: reader, prominent: false)
                .labelStyle(.iconOnly)
                .frame(width: 44, height: 44)
            Text(reader.title)
                .font(.subheadline)
                .lineLimit(1)
                .frame(maxWidth: 180)
            Button("Stop Reading", systemImage: "xmark") { reader.clear() }
                .labelStyle(.iconOnly)
                .frame(width: 44, height: 44)
        }
    }

    private var statusNote: String? {
        if navigator.rangeSelection == .awaitingStart { return "Tap where the passage starts" }
        if case .awaitingEnd = navigator.rangeSelection { return "Tap where the passage ends" }
        if reader.isPreparing { return "Preparing…" }
        if navigator.resumedFromRememberedPlace { return "Resumed where you left off · Start Over in the list" }
        if let next = navigator.queue.first { return "Next: \(next.title)" }
        return nil
    }

    /// Back: the previous sentence; its menu (a long press) goes to the previous section or
    /// page. A long press only adds a shortcut: the sections menu offers the same (HIG
    /// `gestures.md`: shortcut gestures supplement standard ones).
    private var backButton: some View {
        Button("Previous Sentence", systemImage: "backward.end.fill") { reader.session.moveToPreviousSentence() }
            .labelStyle(.iconOnly)
            .frame(width: buttonSize, height: buttonSize)
            .disabled(!reader.session.canMoveToPreviousSentence && !navigator.canSkipSection.backward)
            .contextMenu {
                Button(reader.readingPDF == nil ? "Previous Section" : "Previous Page", systemImage: "backward.fill") {
                    navigator.skipSection(forward: false)
                }
            }
            .accessibilityAction(named: reader.readingPDF == nil ? "Previous Section" : "Previous Page") { navigator.skipSection(forward: false) }
    }

    private var forwardButton: some View {
        Button("Next Sentence", systemImage: "forward.end.fill") { reader.session.moveToNextSentence() }
            .labelStyle(.iconOnly)
            .frame(width: buttonSize, height: buttonSize)
            .disabled(!reader.session.canMoveToNextSentence && !navigator.canSkipSection.forward)
            .contextMenu {
                Button(reader.readingPDF == nil ? "Next Section" : "Next Page", systemImage: "forward.fill") {
                    navigator.skipSection(forward: true)
                }
            }
            .accessibilityAction(named: reader.readingPDF == nil ? "Next Section" : "Next Page") { navigator.skipSection(forward: true) }
    }

    private var speedMenu: some View {
        Menu {
            Picker("Speed", selection: Binding(get: { reader.session.speed }, set: { speed in reader.session.setSpeed(speed) })) {
                ForEach(ReadAloudVoiceSettings.speeds, id: \.self) { speed in Text(speed.formatted() + "×").tag(speed) }
            }
        } label: {
            Text(reader.session.speed.formatted() + "×")
                .font(.subheadline.monospacedDigit().weight(.semibold))
                .frame(minWidth: buttonSize, minHeight: buttonSize)
        }
        .accessibilityLabel("Speed, \(reader.session.speed.formatted()) times")
        .disabled(reader.session.speedFollowsSystem)
    }

    private var sectionsMenu: some View {
        Menu {
            if reader.readingPDF == nil {
                Section("Sections") {
                    ForEach(navigator.sections, id: \.passageIndex) { section in
                        Button {
                            navigator.jump(toSection: section.passageIndex)
                        } label: {
                            if section.passageIndex == navigator.currentSectionIndex {
                                Label(section.title, systemImage: "checkmark")
                            } else {
                                Text(section.title)
                            }
                        }
                    }
                }
            } else {
                Button("Previous Page", systemImage: "backward.fill") { navigator.skipSection(forward: false) }
                    .disabled(!navigator.canSkipSection.backward)
                Button("Next Page", systemImage: "forward.fill") { navigator.skipSection(forward: true) }
                    .disabled(!navigator.canSkipSection.forward)
            }
            Section {
                Button("Start Over", systemImage: "backward.end.alt") { navigator.startOver() }
                if reader.readingPDF == nil {
                    Button("Read from One Point to Another", systemImage: "text.line.first.and.arrowtriangle.forward") {
                        navigator.beginRangeSelection()
                    }
                }
                Toggle("Repeat", systemImage: "repeat", isOn: $navigator.repeatsPassage)
            }
            if !navigator.queue.isEmpty || navigator.canGoToPreviousItem {
                Section("Up Next") {
                    ForEach(navigator.queue) { item in
                        Button(item.title, systemImage: "text.document") {
                            navigator.removeFromQueue(item)
                            navigator.playNext(item.path)
                            navigator.advance()
                        }
                    }
                    if navigator.canGoToPreviousItem {
                        Button("Previous Item", systemImage: "backward.end") { navigator.goToPreviousItem() }
                    }
                }
            }
        } label: {
            Image(systemName: "list.bullet")
                .frame(width: buttonSize, height: buttonSize)
        }
        // Sections in reading order, top to bottom, wherever the player sits.
        .menuOrder(.fixed)
        .accessibilityLabel("Sections and Queue")
    }

    // MARK: Scrolled away

    @ViewBuilder private var scrollPills: some View {
        if isCompact {
            HStack(spacing: 8) {
                // The page scrolls and these pills go away as reading moves; doing it a moment
                // after the tap ends keeps the lifted finger from landing on the page below.
                Button("Read from Here", systemImage: "text.line.first.and.arrowtriangle.forward") {
                    afterTheTap { navigator.readFromVisiblePosition() }
                }
                Button("Back to Reading", systemImage: "arrow.uturn.backward") {
                    afterTheTap { navigator.backToReading() }
                }
            }
            .font(.subheadline.weight(.semibold))
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .modifier(FloatingGlass())
        }
    }

    private func afterTheTap(_ action: @escaping @MainActor () -> Void) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            action()
        }
    }

    // MARK: Dragging

    private var dragToCorner: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in dragOffset = value.translation }
            .onEnded { value in
                let saved = PlayerCorner(rawValue: cornerRawValue) ?? .bottomTrailing
                let movesVertically = abs(value.predictedEndTranslation.height) > 120
                let movesHorizontally = abs(value.predictedEndTranslation.width) > 160
                let top = movesVertically ? value.predictedEndTranslation.height < 0 : saved.isTop
                let leading = movesHorizontally ? value.predictedEndTranslation.width < 0 : saved.isLeading
                let target: PlayerCorner = top ? (leading ? .topLeading : .topTrailing) : (leading ? .bottomLeading : .bottomTrailing)
                cornerRawValue = target.rawValue
                dragOffset = .zero
            }
    }
}

/// The floating layer's material: Liquid Glass where the system has it, otherwise the
/// regular material, in a capsule.
private struct FloatingGlass: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, macOS 26, *) {
            content.glassEffect(.regular, in: .capsule)
        } else {
            content.background(.regularMaterial, in: Capsule())
        }
    }
}

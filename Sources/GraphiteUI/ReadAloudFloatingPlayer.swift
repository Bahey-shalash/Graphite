import SwiftUI
import GraphiteCore
import GraphiteApple

/// Read Aloud's floating player, laid out like the system's Spoken Content controller (Speak
/// Screen): a dark rounded panel with what is read on top, and below it speed, back, Play or
/// Pause, Stop, forward and the page button, with a round close button on its top-left corner.
///
/// The panel is dark in both appearances, as the system's controller is, so its white labels
/// read the same over a white PDF page, a dark slide or a photo: a thick material dimmed with
/// black, opaque with Reduce Transparency, with a light edge and more dimming with Increase
/// Contrast (HIG `materials.md`: thicker materials give better contrast for text;
/// `liquid-glass.md` › Accessibility states). Labels use the system's label colors only.
///
/// It sits at the bottom center of the window, or where the person last dragged it, and moves
/// to the other edge while the line being read would be under it (`ReadAloudPlayerPlacement`).
/// When the person scrolls away from what is read, its top row offers "Back to Reading" and
/// "Read from Here" in place of the title.
struct ReadAloudFloatingPlayer: View {
    @Bindable var reader: ReadAloudController
    @Bindable var navigator: ReadAloudNavigator
    @AppStorage("GraphiteReadAloudPlayerCorner") private var savedPositionRawValue = ReadAloudPlayerPosition.bottom.rawValue
    /// Shown once: in a note, a tap on the text moves reading there.
    @AppStorage("GraphiteReadAloudTapHintShown") private var hasShownTapHint = false
    @State private var showsTapHint = false
    @State private var dragOffset: CGSize = .zero
    @State private var containerFrame: CGRect = .zero
    @State private var panelSize: CGSize = .zero
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @ScaledMetric(relativeTo: .body) private var textScale = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var savedPosition: ReadAloudPlayerPosition { ReadAloudPlayerPosition(rawValue: savedPositionRawValue) ?? .bottom }

    private var position: ReadAloudPlayerPosition {
        ReadAloudPlayerPlacement.position(saved: savedPosition, panelSize: panelSize, in: containerFrame,
                                          avoiding: navigator.highlightFrameInWindow,
                                          covered: navigator.coveredFrameInWindow.map { [$0] } ?? [])
    }

    /// Following is paused because the person scrolled away from what is read.
    private var hasScrolledAway: Bool { !reader.followsReading && reader.session.document != nil }

    var body: some View {
        Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onGeometryChange(for: CGRect.self) { geometry in geometry.frame(in: .global) } action: { frame in containerFrame = frame }
            .overlay(alignment: position.alignment) {
                panel
                    .padding(ReadAloudPlayerPlacement.insets(for: position))
                    .offset(dragOffset)
            }
            .animation(reduceMotion ? nil : .snappy, value: position)
            .onChange(of: hasScrolledAway) { _, scrolledAway in
                guard scrolledAway, !hasShownTapHint, reader.readingPDF == nil, navigator.supportsTapToRead else { return }
                hasShownTapHint = true
                showsTapHint = true
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(5))
                    showsTapHint = false
                }
            }
    }

    // MARK: Panel

    private var panel: some View {
        VStack(spacing: 4) {
            topRow
                .frame(maxWidth: .infinity, minHeight: 30)
                .padding(.horizontal, 6)
            controlsRow
        }
        .padding(.horizontal, 8)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .frame(width: ReadAloudPlayerPlacement.panelWidth(in: containerFrame.width))
        .background { ReadAloudPlayerBackground() }
        .overlay(alignment: .topLeading) { closeButton.offset(x: -14, y: -14) }
        // The system's controller is dark in both appearances, its controls white: menus
        // would otherwise take the app's accent.
        .tint(.white)
        .environment(\.colorScheme, .dark)
        // Controls grow a little with the text, then keep their size so all six fit; a long
        // press shows each one enlarged (Large Content Viewer), as the system's bars do.
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .onGeometryChange(for: CGRect.self) { geometry in geometry.frame(in: .global) } action: { frame in
            panelSize = frame.size
            navigator.playerFrameInWindow = frame
        }
        .gesture(dragToPlace)
        .animation(reduceMotion ? nil : .snappy, value: hasScrolledAway)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Read Aloud")
    }

    // MARK: Top row

    @ViewBuilder private var topRow: some View {
        if navigator.rangeSelection == .awaitingStart {
            statusText("Tap where the passage starts", systemImage: "text.line.first.and.arrowtriangle.forward")
        } else if case .awaitingEnd = navigator.rangeSelection {
            statusText("Tap where the passage ends", systemImage: "text.line.last.and.arrowtriangle.forward")
        } else if let error = reader.errorMessage, reader.session.document == nil, !reader.isPreparing {
            statusText(error, systemImage: "exclamationmark.triangle")
        } else if hasScrolledAway {
            if showsTapHint {
                statusText("Tap the text to read from there", systemImage: "hand.tap")
            } else {
                scrolledAwayButtons
            }
        } else if reader.isPreparing || reader.isWaitingForPreparedAudio {
            // A downloaded voice still rendering the passage reading waits for.
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(reader.isWaitingForPreparedAudio ? reader.preparingDescription : "Preparing…")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
        } else if navigator.isReadingPenSelection {
            HStack(spacing: 8) {
                Label("Reading Selection", systemImage: "text.line.first.and.arrowtriangle.forward")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Toggle(isOn: $navigator.repeatsPassage) {
                    Label("Repeat", systemImage: "repeat")
                }
                .toggleStyle(.button)
                .labelStyle(.iconOnly)
                .buttonBorderShape(.capsule)
                .tint(.white)
                .frame(minWidth: 44, minHeight: 30)
                .accessibilityLabel("Repeat Selection")
            }
        } else {
            titleRow
        }
    }

    /// The document's icon and name, then where in it reading is, which gives way first.
    /// (`ViewThatFits` here made a layout cycle that kept the note under it from loading.)
    private var titleRow: some View {
        HStack(spacing: 6) {
            documentIcon
            Text(reader.title).font(.subheadline.weight(.semibold)).lineLimit(1).layoutPriority(1)
            if let place = currentPlace, Self.placeFits(title: reader.title, place: place, textSize: dynamicTypeSize) {
                Text(place).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// Whether the name and the place fit on the row together, at about seven and a half
    /// points a character at the standard text size; otherwise the place is left out.
    static func placeFits(title: String, place: String, textSize: DynamicTypeSize) -> Bool {
        guard textSize <= .xLarge else { return false }
        let characters = textSize <= .large ? 38 : 32
        return title.count + place.count + 2 <= characters
    }

    private var documentIcon: some View {
        Image(systemName: reader.readingPDF == nil ? "doc.text" : "doc.richtext")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)
    }

    /// How far ahead a downloaded voice has prepared, while it still is; else the heading
    /// being read, or the page of a PDF.
    private var currentPlace: String? {
        if let share = reader.preparedAudioShare { return "Prepared \(Int((share * 100).rounded()))%" }
        if let pdf = reader.readingPDF, let page = reader.sourcePageIndex { return "Page \(page + 1) of \(pdf.pageCount)" }
        guard let index = navigator.currentSectionIndex else { return nil }
        return navigator.sections.first { section in section.passageIndex == index }?.title
    }

    /// Both as words while they fit; past the large text size, Read from Here is its icon.
    private var scrolledAwayButtons: some View {
        HStack(spacing: 6) {
            backToReadingButton
            readFromHereButton
                .labelStyle(dynamicTypeSize > .large || horizontalSizeClass == .compact ? AnyLabelStyle(.iconOnly) : AnyLabelStyle(.titleAndIcon))
        }
    }

    // The page scrolls under these buttons as they act; acting a moment after the tap ends
    // keeps the lifted finger from landing on the page below.
    private var backToReadingButton: some View {
        Button("Back to Reading", systemImage: "arrow.uturn.backward") { afterTheTap { navigator.backToReading() } }
            .modifier(ReadAloudChipStyle())
    }

    private var readFromHereButton: some View {
        Button("Read from Here", systemImage: "text.line.first.and.arrowtriangle.forward") { afterTheTap { navigator.readFromVisiblePosition() } }
            .modifier(ReadAloudChipStyle())
    }

    private func statusText(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.subheadline)
            .lineLimit(2)
            .multilineTextAlignment(.center)
    }

    // MARK: Controls row

    private var controlsRow: some View {
        HStack(spacing: 0) {
            speedMenu
            Spacer(minLength: 0)
            ReadAloudTransportButton(
                title: "Previous Sentence", systemImage: "gobackward",
                isEnabled: reader.session.canMoveToPreviousSentence || navigator.canSkipSection.backward,
                action: { reader.session.moveToPreviousSentence() },
                longPressTitle: reader.readingPDF == nil ? "Previous Section" : "Previous Page",
                longPress: { navigator.skipSection(forward: false) })
            Spacer(minLength: 0)
            playPauseButton
            Spacer(minLength: 0)
            ReadAloudTransportButton(
                title: "Stop", systemImage: "stop.fill",
                isEnabled: reader.session.document != nil,
                action: { navigator.stopAndRewind() })
            Spacer(minLength: 0)
            ReadAloudTransportButton(
                title: "Next Sentence", systemImage: "goforward",
                isEnabled: reader.session.canMoveToNextSentence || navigator.canSkipSection.forward,
                action: { reader.session.moveToNextSentence() },
                longPressTitle: reader.readingPDF == nil ? "Next Section" : "Next Page",
                longPress: { navigator.skipSection(forward: true) })
            Spacer(minLength: 0)
            pageMenu
        }
    }

    private var isSpeaking: Bool { reader.session.state == .speaking }

    private var playPauseButton: some View {
        ReadAloudTransportButton(
            title: isSpeaking ? "Pause" : "Play", systemImage: isSpeaking ? "pause.fill" : "play.fill", glyphSize: 30, width: 52,
            isEnabled: reader.session.document != nil && !reader.isPreparing,
            action: { if isSpeaking { reader.session.pause() } else { reader.session.play() } })
            .accessibilityIdentifier("readAloudPlayPause")
    }

    private var speedMenu: some View {
        Menu {
            Picker("Speed", selection: Binding(get: { reader.session.speed }, set: { speed in reader.session.setSpeed(speed) })) {
                ForEach(ReadAloudVoiceSettings.speeds, id: \.self) { speed in Text(speed.formatted() + "×").tag(speed) }
            }
        } label: {
            Text(reader.session.speed.formatted() + "×")
                .font(.subheadline.monospacedDigit().weight(.semibold))
                .foregroundStyle(reader.session.speedFollowsSystem ? .tertiary : .primary)
                .lineLimit(1)
                .fixedSize()
                .frame(minWidth: 50, minHeight: 44)
                .contentShape(Rectangle())
        }
        .menuOrder(.fixed)
        .accessibilityLabel("Speed")
        .accessibilityValue("\(reader.session.speed.formatted()) times")
        .accessibilityShowsLargeContentViewer { Text("Speed " + reader.session.speed.formatted() + "×") }
        .disabled(reader.session.speedFollowsSystem)
    }

    /// The page button: sections or pages, the transcript and voice, and the queue.
    private var pageMenu: some View {
        Menu {
            if hasScrolledAway {
                Button("Read from Here", systemImage: "text.line.first.and.arrowtriangle.forward") { navigator.readFromVisiblePosition() }
            }
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
                Button("Transcript and Voice", systemImage: "text.alignleft") { reader.showsReader = true }
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
            Image(systemName: "doc.plaintext")
                .font(.system(size: min(20 * textScale, 26), weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        // Sections in reading order, top to bottom, wherever the player sits.
        .menuOrder(.fixed)
        .accessibilityLabel("Sections and Transcript")
        .accessibilityShowsLargeContentViewer { Label("Sections and Transcript", systemImage: "doc.plaintext") }
    }

    /// The round close button on the panel's corner: stops reading and closes the player.
    private var closeButton: some View {
        Button {
            reader.clear()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.primary)
                .frame(width: 26, height: 26)
                .background { ReadAloudPlayerBackground(shape: .circle) }
                // 44 points to touch, around the small badge.
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Close Read Aloud")
        .accessibilityHint("Stops reading")
        .accessibilityShowsLargeContentViewer { Label("Close Read Aloud", systemImage: "xmark") }
    }

    private func afterTheTap(_ action: @escaping @MainActor () -> Void) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            action()
        }
    }

    // MARK: Dragging

    private var dragToPlace: some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .global)
            .onChanged { value in dragOffset = value.translation }
            .onEnded { value in
                let current = ReadAloudPlayerPlacement.frame(for: position, panelSize: panelSize, in: containerFrame)
                let dropped = CGPoint(x: current.midX + value.predictedEndTranslation.width, y: current.midY + value.predictedEndTranslation.height)
                savedPositionRawValue = ReadAloudPlayerPosition.nearest(to: dropped, in: containerFrame).rawValue
                dragOffset = .zero
            }
    }
}

// MARK: - Pieces

/// A control of the player's lower row: a glyph in a 44-point target, with an optional long
/// press that moves further (a section or page), also offered to VoiceOver as an action and
/// in the page button's menu, so it is only a shortcut (HIG `gestures.md`).
private struct ReadAloudTransportButton: View {
    let title: String
    let systemImage: String
    var glyphSize: CGFloat = 20
    var width: CGFloat = 44
    var isEnabled = true
    let action: () -> Void
    var longPressTitle: String?
    var longPress: (() -> Void)?
    @State private var isPressed = false
    /// The glyph grows with the text size, up to what still fits the row's 44-point targets.
    @ScaledMetric(relativeTo: .body) private var textScale = 1

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: min(glyphSize * textScale, glyphSize * 1.3), weight: .semibold))
            .foregroundStyle(isEnabled ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
            .frame(width: width, height: 44)
            .contentShape(Rectangle())
            .opacity(isPressed ? 0.45 : 1)
            .onTapGesture { if isEnabled { action() } }
            .onLongPressGesture(minimumDuration: 0.5) {
                if isEnabled, let longPress { longPress() }
            } onPressingChanged: { pressing in
                isPressed = pressing && isEnabled
            }
            .accessibilityElement()
            .accessibilityLabel(title)
            .accessibilityAddTraits(.isButton)
            .accessibilityRemoveTraits(isEnabled ? [] : .isButton)
            .accessibilityValue(isEnabled ? "" : "Dimmed")
            .accessibilityAction { if isEnabled { action() } }
            .accessibilityActions {
                if let longPressTitle, let longPress {
                    Button(longPressTitle) { longPress() }
                }
            }
            .accessibilityShowsLargeContentViewer { Label(title, systemImage: systemImage) }
    }
}

/// "Back to Reading" and "Read from Here" in the player's top row.
private struct ReadAloudChipStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.subheadline.weight(.semibold))
            .lineLimit(1)
            .foregroundStyle(.primary)
            .padding(.horizontal, 8)
            .frame(minHeight: 32)
            .background(Color.white.opacity(0.16), in: Capsule())
            .contentShape(Capsule())
            .buttonStyle(.plain)
            // A 44-point target around the 32-point chip.
            .padding(.vertical, 6)
            .contentShape(Rectangle())
    }
}

/// The player's dark panel: a thick material dimmed with black, opaque with Reduce
/// Transparency, and more opaque with a light edge with Increase Contrast.
struct ReadAloudPlayerBackground: View {
    enum Shape { case panel, circle }
    var shape: Shape = .panel
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    static let cornerRadius: CGFloat = 22
    /// The black over the material: enough that white labels keep 4.5:1 over a white page.
    static let dimming = 0.42
    static let increasedContrastDimming = 0.62
    /// The panel's color with Reduce Transparency, the system's dark grouped background.
    static let opaqueColor = Color(red: 0x1C / 255, green: 0x1C / 255, blue: 0x1E / 255)

    var body: some View {
        let isIncreased = contrast == .increased
        Group {
            switch shape {
            case .panel: fill(in: RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous), isIncreased: isIncreased)
            case .circle: fill(in: Circle(), isIncreased: isIncreased)
            }
        }
        .compositingGroup()
        .shadow(color: .black.opacity(0.28), radius: 14, y: 4)
    }

    @ViewBuilder private func fill<S: InsettableShape>(in shape: S, isIncreased: Bool) -> some View {
        if reduceTransparency {
            shape.fill(Self.opaqueColor)
                .overlay { shape.strokeBorder(Color.white.opacity(isIncreased ? 0.7 : 0.14), lineWidth: isIncreased ? 1 : 0.5) }
        } else {
            shape.fill(.thickMaterial)
                .overlay { shape.fill(Color.black.opacity(isIncreased ? Self.increasedContrastDimming : Self.dimming)) }
                .overlay { shape.strokeBorder(Color.white.opacity(isIncreased ? 0.7 : 0.14), lineWidth: isIncreased ? 1 : 0.5) }
        }
    }
}

/// A label style chosen at run time.
private struct AnyLabelStyle: LabelStyle {
    private let make: (Configuration) -> AnyView
    init<Style: LabelStyle>(_ style: Style) { make = { configuration in AnyView(style.makeBody(configuration: configuration)) } }
    func makeBody(configuration: Configuration) -> some View { make(configuration) }
}

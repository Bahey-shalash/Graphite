import SwiftUI

/// Undo and Redo for a document's toolbar. Every workspace puts them just before its
/// Read/Write control (the drawing editor, which has none, just before Insert or Done),
/// and they act on that document's own history.
///
/// A tap undoes or redoes one change; a long press offers "Move Through Changes…", which
/// opens a scrubber to go back or forward many changes with one drag.
struct UndoRedoButtons: View {
    let availability: UndoAvailability
    @State private var scrubberSource: ScrubberSource?

    private enum ScrubberSource { case undo, redo }

    var body: some View {
        Menu {
            moveThroughChangesButton(from: .undo)
        } label: {
            Label("Undo", systemImage: "arrow.uturn.backward")
        } primaryAction: {
            availability.undo()
        }
        .disabled(!availability.canUndo)
        .help(availability.undoActionName.isEmpty ? "Undo" : "Undo \(availability.undoActionName)")
        .accessibilityIdentifier("documentUndo")
        .popover(isPresented: scrubberIsPresented(from: .undo)) { scrubber }
        Menu {
            moveThroughChangesButton(from: .redo)
        } label: {
            Label("Redo", systemImage: "arrow.uturn.forward")
        } primaryAction: {
            availability.redo()
        }
        .disabled(!availability.canRedo)
        .help(availability.redoActionName.isEmpty ? "Redo" : "Redo \(availability.redoActionName)")
        .accessibilityIdentifier("documentRedo")
        .popover(isPresented: scrubberIsPresented(from: .redo)) { scrubber }
    }

    private func moveThroughChangesButton(from source: ScrubberSource) -> some View {
        Button("Move Through Changes…", systemImage: "clock.arrow.circlepath") { scrubberSource = source }
    }

    private func scrubberIsPresented(from source: ScrubberSource) -> Binding<Bool> {
        Binding(get: { scrubberSource == source }, set: { isPresented in if !isPresented { scrubberSource = nil } })
    }

    private var scrubber: some View {
        UndoHistoryScrubber(availability: availability)
            .presentationCompactAdaptation(.popover)
    }
}

/// Goes back or forward through a document's changes with one drag: each step of the drag
/// toward the leading side undoes a change, each step back redoes one, as far as the
/// history goes. Undo and Redo at its ends take one step.
struct UndoHistoryScrubber: View {
    let availability: UndoAvailability
    /// Changes redone (positive) or undone (negative) since the scrubber opened.
    @State private var stepsFromStart = 0
    @State private var stepsWhenDragStarted: Int?

    /// How far the finger or Pencil moves for one change.
    static let stepWidth: CGFloat = 22
    private static let trackWidth: CGFloat = 220

    /// The steps from the start a drag asks for: one per `stepWidth` of its translation,
    /// negative toward the leading side.
    static func requestedSteps(forDragOf translation: CGFloat, from startingSteps: Int) -> Int {
        guard translation.isFinite else { return startingSteps }
        return startingSteps + Int((translation / stepWidth).rounded())
    }

    var body: some View {
        VStack(spacing: 14) {
            Text(summary)
                .font(.callout)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            HStack(spacing: 14) {
                Button("Undo", systemImage: "arrow.uturn.backward") { move(to: stepsFromStart - 1) }
                    .disabled(!availability.canUndo)
                track
                Button("Redo", systemImage: "arrow.uturn.forward") { move(to: stepsFromStart + 1) }
                    .disabled(!availability.canRedo)
            }
            .labelStyle(.iconOnly)
        }
        .padding(18)
    }

    private var summary: String {
        switch stepsFromStart {
        case 0: "Drag to go back through your changes"
        case ..<0: stepsFromStart == -1 ? "1 change undone" : "\(-stepsFromStart) changes undone"
        default: stepsFromStart == 1 ? "1 change redone" : "\(stepsFromStart) changes redone"
        }
    }

    private var track: some View {
        let halfTrack = Self.trackWidth / 2
        let knobOffset = min(max(CGFloat(stepsFromStart) * Self.stepWidth, -halfTrack), halfTrack)
        return ZStack {
            Capsule().fill(.quaternary).frame(height: 6)
            HStack(spacing: Self.stepWidth - 1) {
                ForEach(0..<Int(Self.trackWidth / Self.stepWidth), id: \.self) { _ in
                    Capsule().fill(.tertiary).frame(width: 1, height: 10)
                }
            }
            Circle()
                .fill(.background)
                .shadow(radius: 2, y: 1)
                .overlay { Circle().strokeBorder(.tint, lineWidth: 2) }
                .frame(width: 26, height: 26)
                .offset(x: knobOffset)
        }
        .frame(width: Self.trackWidth + 26, height: 44)
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { drag in
                let startingSteps = stepsWhenDragStarted ?? stepsFromStart
                stepsWhenDragStarted = startingSteps
                move(to: Self.requestedSteps(forDragOf: drag.translation.width, from: startingSteps))
            }
            .onEnded { _ in stepsWhenDragStarted = nil })
        .accessibilityElement()
        .accessibilityLabel("Changes")
        .accessibilityValue(summary)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: move(to: stepsFromStart + 1)
            case .decrement: move(to: stepsFromStart - 1)
            @unknown default: break
            }
        }
    }

    private func move(to requestedSteps: Int) {
        guard requestedSteps != stepsFromStart else { return }
        stepsFromStart += availability.step(by: requestedSteps - stepsFromStart)
    }
}

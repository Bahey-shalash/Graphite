import SwiftUI
import Textual
import GraphiteCore

/// The note whose tasks a part of reading view shows, and what ticks one of them.
struct ReadingTaskContext {
    /// The note itself, or a note it embeds: a task of an embedded note is ticked in
    /// that note, as in Obsidian.
    let note: VaultPath
    /// Ticks or unticks the task at a place of a note. False when the note no longer has
    /// the task there, as after an edit reading view has not drawn yet.
    let toggle: @MainActor (VaultPath, ReadingTasks.Location) async -> Bool
}

extension EnvironmentValues {
    /// Nil where checkboxes are pictures, as in Live Preview's rendered blocks.
    @Entry var readingTaskContext: ReadingTaskContext? = nil
}

/// A task's status and its place in the note, kept on the character that stands for its
/// checkbox, where `ObsidianListItemStyle` finds it.
enum ReadingTaskAttribute: AttributedStringKey {
    typealias Value = ReadingTasks.MarkedTask
    static let name = "GraphiteReadingTask"
}

/// A task's checkbox in reading view, drawn where a list item's bullet would be. It is
/// a control where a tap can change the note, and a picture otherwise.
struct ReadingTaskCheckbox: View {
    let task: ReadingTasks.MarkedTask
    /// The task's text, which names the checkbox for VoiceOver.
    let label: String
    let pointSize: Double
    @Environment(\.readingTaskContext) private var context
    /// What a tap made of the checkbox, shown until the note is drawn again.
    @State private var isCheckedAfterTap: Bool?

    /// How far the tappable area reaches past the drawn checkbox, in points: into the
    /// margin before it, and less far after it, where the task's text starts and a tap
    /// must not tick the task.
    private static let touchTargetOutset = EdgeInsets(top: 7, leading: 20, bottom: 7, trailing: 6)

    var body: some View {
        let isChecked = isCheckedAfterTap ?? task.isChecked
        let checkbox = Image(systemName: isChecked ? "checkmark.square.fill" : "square")
            .font(.system(size: pointSize * 0.95))
            .foregroundStyle(isChecked ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            .frame(width: pointSize * 0.95, height: pointSize * 1.05)
        if let context, let location = task.location {
            Button {
                isCheckedAfterTap = !isChecked
                Task {
                    if await !context.toggle(context.note, location) { isCheckedAfterTap = nil }
                }
            } label: {
                checkbox
                    .padding(Self.touchTargetOutset)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            // The text selection overlay would otherwise take the tap.
            .textual.excludedFromTextInteraction()
            // The larger area takes touches without moving the text beside the checkbox.
            .padding(Self.touchTargetOutset.negated)
            .accessibilityLabel(label.isEmpty ? "Task" : label)
            .accessibilityValue(isChecked ? "Completed" : "Not completed")
            .accessibilityAddTraits(.isToggle)
            .onChange(of: task) { isCheckedAfterTap = nil }
        } else {
            checkbox.accessibilityLabel(isChecked ? "Completed task" : "Task")
        }
    }
}

extension EdgeInsets {
    fileprivate var negated: EdgeInsets { EdgeInsets(top: -top, leading: -leading, bottom: -bottom, trailing: -trailing) }
}

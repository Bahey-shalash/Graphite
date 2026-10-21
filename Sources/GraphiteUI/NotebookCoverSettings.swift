import SwiftUI
import GraphiteCore
import GraphiteApple

/// The New Notebook sheet's Cover row: a switch for a first page of one color with the notebook's
/// name, and the colors to choose from while it is on.
struct NotebookCoverSettings: View {
    @Binding var cover: NotebookCoverColor?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Cover", isOn: Binding(get: { cover != nil }, set: { isOn in cover = isOn ? (cover ?? .blue) : nil }))
            if let cover {
                HStack(spacing: 12) {
                    ForEach(NotebookCoverColor.allCases) { color in swatch(color, isChosen: color == cover) }
                }
                .accessibilityElement(children: .contain)
            }
        }
        .padding(.vertical, 10)
    }

    private func swatch(_ color: NotebookCoverColor, isChosen: Bool) -> some View {
        Button {
            cover = color
        } label: {
            Circle()
                .fill(Color(graphiteHex: color.colorHex) ?? .blue)
                .frame(width: 26, height: 26)
                .padding(3)
                .overlay { if isChosen { Circle().strokeBorder(Color.accentColor, lineWidth: 2) } }
                .frame(minWidth: 32, minHeight: 32)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(color.title)
        .accessibilityAddTraits(isChosen ? .isSelected : [])
    }
}

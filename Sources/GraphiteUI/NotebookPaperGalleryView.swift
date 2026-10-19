import SwiftUI
import GraphiteCore
import GraphiteApple

/// Every paper as a picture, in sections, as Goodnotes' "Paper Templates" shows them. A
/// tap chooses the paper; the dots under a picture choose its paper color.
struct NotebookPaperGalleryView: View {
    @Binding var options: NewNotebookOptions
    let pictures: NotebookPaperPictures
    @Environment(\.displayScale) private var displayScale

    private static let pictureWidthPoints: CGFloat = 112
    private let columns = [GridItem(.adaptive(minimum: pictureWidthPoints, maximum: 160), spacing: 20, alignment: .top)]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Paper Templates")
                .font(.title2.weight(.semibold))
            ForEach(NotebookPaperSection.allCases) { section in
                VStack(alignment: .leading, spacing: 12) {
                    Text(section.title)
                        .font(.headline)
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
                        ForEach(section.choices) { choice in tile(for: choice) }
                    }
                }
            }
        }
    }

    private func tile(for choice: NotebookPaperChoice) -> some View {
        let isChosen = options.paperChoice == choice
        return VStack(spacing: 8) {
            Button {
                options.choose(choice)
            } label: {
                NotebookPaperPicture(picture: pictures.galleryPictures[choice], pageSize: options.pageSize.pointSize, displayScale: displayScale)
                    .frame(height: Self.pictureWidthPoints * 1.15)
                    .overlay(alignment: .bottom) {
                        if isChosen {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.title2)
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, Color.accentColor)
                                .padding(.bottom, 8)
                        }
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(choice.title)
            .accessibilityAddTraits(isChosen ? .isSelected : [])
            Text(choice.title)
                .font(.subheadline)
                .lineLimit(1)
            colorDots(for: choice)
        }
    }

    /// The paper colors, the chosen one ringed; choosing one also chooses this paper.
    private func colorDots(for choice: NotebookPaperChoice) -> some View {
        let chosenColor = DrawingBackground.notebookPaperColor(hex: options.paperStyle.paperColorHex)
        return HStack(spacing: 6) {
            ForEach(DrawingBackground.notebookPaperColors) { paperColor in
                Button {
                    options.choose(choice)
                    options.paperStyle.paperColorHex = paperColor == .white ? nil : paperColor.colorHex
                } label: {
                    NotebookPaperColorSwatch(paperColor: paperColor)
                        .padding(2)
                        .overlay {
                            if options.paperChoice == choice, paperColor == chosenColor {
                                Circle().strokeBorder(Color.accentColor, lineWidth: 1.5)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(choice.title), \(paperColor.title)")
            }
        }
    }
}

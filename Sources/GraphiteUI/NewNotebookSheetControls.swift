import SwiftUI
import GraphiteCore
import GraphiteApple

/// The notebook's first page as it will be made, with the paper's name under it.
struct NotebookFirstPagePreview: View {
    let picture: CGImage?
    let pageSize: CGSize
    let title: String
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        VStack(spacing: 10) {
            NotebookPaperPicture(picture: picture, pageSize: pageSize, displayScale: displayScale)
                .frame(maxHeight: 260)
            Text(title)
                .font(.subheadline.weight(.medium))
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("First page: \(title)")
    }
}

/// A picture of paper at its page's proportions, or a plain sheet while it is drawn.
struct NotebookPaperPicture: View {
    let picture: CGImage?
    let pageSize: CGSize
    let displayScale: CGFloat

    var body: some View {
        Group {
            if let picture {
                Image(decorative: picture, scale: displayScale).resizable()
            } else {
                Color.white
            }
        }
        .aspectRatio(max(pageSize.width, 1) / max(pageSize.height, 1), contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
    }
}

/// Size and orientation in one menu, as Goodnotes has them: Portrait and Landscape above
/// the named sizes, and Custom below them.
struct NotebookPageSizeMenu: View {
    @Binding var pageSize: NotebookPageSizeChoice

    private enum SizeSelection: Hashable {
        case named(NotebookPageSize), custom
    }

    var body: some View {
        Menu {
            Picker("Orientation", selection: orientation) {
                ForEach(PageOrientation.allCases) { orientation in Text(orientation.title).tag(orientation) }
            }
            .pickerStyle(.inline)
            Picker("Size", selection: sizeSelection) {
                ForEach(NotebookPageSize.allCases) { size in Text(size.title).tag(SizeSelection.named(size)) }
                Text("Custom").tag(SizeSelection.custom)
            }
            .pickerStyle(.inline)
        } label: {
            LabeledContent("Size") {
                HStack(spacing: 4) {
                    Text(summary)
                    Image(systemName: "chevron.up.chevron.down").imageScale(.small)
                }
                .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 12)
    }

    private var summary: String {
        switch pageSize {
        case .named(let size, let orientation): "\(size.title), \(orientation.title)"
        case .custom: "Custom"
        }
    }

    private var orientation: Binding<PageOrientation> {
        Binding(get: { PageOrientation(of: pageSize.pointSize) }, set: { orientation in
            switch pageSize {
            case .named(let size, _): pageSize = .named(size, orientation)
            case .custom(let widthPoints, let heightPoints):
                let turnedSize = orientation.applied(to: CGSize(width: widthPoints, height: heightPoints))
                pageSize = .custom(widthPoints: turnedSize.width, heightPoints: turnedSize.height)
            }
        })
    }

    private var sizeSelection: Binding<SizeSelection> {
        Binding(get: {
            switch pageSize {
            case .named(let size, _): .named(size)
            case .custom: .custom
            }
        }, set: { selection in
            let currentOrientation = PageOrientation(of: pageSize.pointSize)
            switch selection {
            case .named(let size): pageSize = .named(size, currentOrientation)
            case .custom:
                // Custom starts from the size shown, to be edited from there.
                let currentSize = pageSize.pointSize
                pageSize = .custom(widthPoints: currentSize.width, heightPoints: currentSize.height)
            }
        })
    }
}

/// Width and height in points, shown only for a custom size.
struct NotebookCustomSizeFields: View {
    @Binding var pageSize: NotebookPageSizeChoice

    var body: some View {
        if case .custom(let widthPoints, let heightPoints) = pageSize {
            NotebookSettingsCard {
                TextField("Width in points", value: Binding(get: { widthPoints }, set: { width in
                    pageSize = .custom(widthPoints: width, heightPoints: heightPoints)
                }), format: .number)
                    .padding(.vertical, 12)
                Divider()
                TextField("Height in points", value: Binding(get: { heightPoints }, set: { height in
                    pageSize = .custom(widthPoints: widthPoints, heightPoints: height)
                }), format: .number)
                    .padding(.vertical, 12)
            }
            #if os(iOS)
            .keyboardType(.decimalPad)
            #endif
        }
    }
}

/// The paper's color, with a swatch of each color offered.
struct NotebookPaperColorMenu: View {
    @Binding var paperColorHex: String?

    var body: some View {
        Menu {
            Picker("Paper Color", selection: color) {
                ForEach(DrawingBackground.notebookPaperColors) { paperColor in
                    Label { Text(paperColor.title) } icon: { NotebookPaperColorSwatch(paperColor: paperColor) }.tag(paperColor)
                }
            }
            .pickerStyle(.inline)
        } label: {
            LabeledContent("Color") {
                HStack(spacing: 6) {
                    NotebookPaperColorSwatch(paperColor: color.wrappedValue)
                    Text(color.wrappedValue.title)
                    Image(systemName: "chevron.up.chevron.down").imageScale(.small)
                }
                .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 12)
    }

    private var color: Binding<DrawingBackground> {
        Binding(get: { DrawingBackground.notebookPaperColor(hex: paperColorHex) },
                set: { paperColor in paperColorHex = paperColor == .white ? nil : paperColor.colorHex })
    }
}

/// A small circle of a paper color, outlined so white shows on a light background.
struct NotebookPaperColorSwatch: View {
    let paperColor: DrawingBackground

    var body: some View {
        Circle()
            .fill(Color(graphiteHex: paperColor.colorHex ?? "#ffffff") ?? .white)
            .overlay(Circle().strokeBorder(.secondary.opacity(0.5), lineWidth: 0.5))
            .frame(width: 16, height: 16)
    }
}

/// Spacing, line color and line strength, folded away as Settings already chose them.
struct NotebookPaperStyleSettings: View {
    @Binding var paperStyle: PaperSpecification
    let showsLineSettings: Bool

    var body: some View {
        if showsLineSettings {
            DisclosureGroup("Lines") {
                NotebookSettingsCard {
                    Picker("Spacing", selection: $paperStyle.spacing) {
                        ForEach(NotebookPaperSpacing.choices, id: \.self) { spacing in Text(NotebookPaperSpacing.title(of: spacing)).tag(spacing) }
                    }
                    .padding(.vertical, 6)
                    Divider()
                    Picker("Line Color", selection: $paperStyle.lineColor) {
                        ForEach(DrawingPaperLineColor.allCases) { lineColor in Text(lineColor.title).tag(lineColor) }
                    }
                    .padding(.vertical, 6)
                    Divider()
                    Picker("Line Strength", selection: $paperStyle.lineStrength) {
                        ForEach(DrawingPaperLineStrength.allCases) { strength in Text(strength.title).tag(strength) }
                    }
                    .padding(.vertical, 6)
                }
                .padding(.top, 6)
            }
            .padding(.horizontal, 4)
            .padding(.top, 8)
        }
    }
}

extension DrawingBackground {
    /// The colors a notebook's paper can have: every paper color except none.
    static var notebookPaperColors: [DrawingBackground] {
        allCases.filter { paperColor in paperColor != .transparent }
    }

    /// The paper color stored as `hex`; white when it is none of the offered colors.
    static func notebookPaperColor(hex: String?) -> DrawingBackground {
        notebookPaperColors.first { paperColor in paperColor.colorHex == (hex ?? DrawingBackground.white.colorHex) } ?? .white
    }
}

extension NotebookPageSize {
    var title: String {
        switch self {
        case .a3: "A3"
        case .a4: "A4"
        case .a5: "A5"
        case .a6: "A6"
        case .a7: "A7 (iPhone)"
        case .letter: "Letter"
        case .tabloid: "Tabloid"
        }
    }
}

extension PageOrientation {
    var title: String {
        switch self {
        case .portrait: "Portrait"
        case .landscape: "Landscape"
        }
    }
}

extension NotebookPaperChoice {
    var title: String {
        switch self {
        case .blank: "Blank"
        case .dotted: "Dotted Paper"
        case .squared: "Squared Paper"
        case .ruledNarrow: "Ruled Narrow"
        case .ruledWide: "Ruled Wide"
        case .cornell: "Cornell"
        case .engineering: "Engineering"
        case .isometric: "Isometric"
        case .music: "Music Paper"
        }
    }
}

extension NotebookPaperSection {
    var title: String {
        switch self {
        case .essentials: "Essentials"
        case .study: "Study"
        case .music: "Music"
        }
    }
}

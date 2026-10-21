import SwiftUI
import UniformTypeIdentifiers
import CoreGraphics
import GraphiteCore
import GraphiteApple

/// Graphite's icon maker, in the spirit of Image2icon and built only from Apple's folder art
/// and public APIs: a large preview on a checkerboard, every template's live preview in a
/// column, the picture's offset, zoom, rotation and background in a settings popover, Remove
/// Background, Export as PNG, and Apply to the folder. A picture dropped on it replaces the
/// picture; on the Mac a folder dropped on it gets the icon.
struct FolderIconMaker: View {
    let folderName: String
    /// Apple's folder art in the folder's color, the back layer of the folder templates.
    let drawFolderArt: () async -> CGImage?
    /// Keeps the made picture for the folder, in the template's layout.
    let apply: (CGImage, FolderPictureLayout) -> Void
    @State private var picture: CGImage
    @State private var design = FolderIconDesign()
    @State private var renders = FolderIconMakerRenders()
    @State private var problem: FolderIconMakerProblem?
    @State private var exportedIcon: FolderIconPNGDocument?
    @State private var isRemovingBackground = false
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dismiss) private var dismiss

    init(picture: CGImage, folderName: String, drawFolderArt: @escaping () async -> CGImage?, apply: @escaping (CGImage, FolderPictureLayout) -> Void) {
        self.folderName = folderName
        self.drawFolderArt = drawFolderArt
        self.apply = apply
        _picture = State(initialValue: picture)
    }

    var body: some View {
        NavigationStack {
            arrangement
            .navigationTitle("Folder Icon")
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { toolbar }
            .task { renders.folderArt = await drawFolderArt() }
            .task(id: FolderIconMakerRenders.Key(design: design, picture: ObjectIdentifier(picture), hasFolderArt: renders.folderArt != nil)) {
                let drawn = await FolderIconMakerRenders.draw(design: design, picture: picture, folderArt: renders.folderArt)
                if !Task.isCancelled { renders.show(drawn) }
            }
            .dropDestination(for: URL.self) { locations, _ in
                guard let location = locations.first(where: \.isFileURL) else { return false }
                Task { await takeDroppedFile(at: location) }
                return true
            }
            .alert("Icon Not Made", isPresented: Binding(get: { problem != nil }, set: { isShown in if !isShown { problem = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(problem?.message ?? "")
            }
            .fileExporter(isPresented: Binding(get: { exportedIcon != nil }, set: { isShown in if !isShown { exportedIcon = nil } }),
                          document: exportedIcon, contentType: .png, defaultFilename: "\(folderName) Icon") { _ in }
        }
        .frame(minWidth: 520, minHeight: 560)
    }

    /// The editor beside the template column, or above a row of templates on a narrow screen.
    @ViewBuilder private var arrangement: some View {
        if horizontalSizeClass == .compact {
            VStack(spacing: 12) {
                editor
                templateList(axis: .horizontal)
            }
        } else {
            HStack(spacing: 0) {
                editor
                Divider()
                templateList(axis: .vertical).frame(width: 170)
            }
        }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
            Button("Apply") {
                guard let kept = FolderIconRenderer.keptPicture(design, picture: picture, folderArt: renders.folderArt) else { return problem = .notDrawn }
                apply(kept, design.template.layout)
                dismiss()
            }
        }
    }

    private var editor: some View {
        VStack(spacing: 14) {
            FolderIconMakerPreview(icon: renders.previewIcon, design: $design)
            Text(dropCaption).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
            HStack(spacing: 12) {
                Button("Export", systemImage: "square.and.arrow.up") { export() }
                FolderIconSettingsButton(design: $design)
                Button {
                    Task { await removeBackground() }
                } label: {
                    if isRemovingBackground { ProgressView() } else { Label("Remove Background", systemImage: "person.and.background.dotted") }
                }
                .disabled(isRemovingBackground)
            }
            .buttonStyle(.bordered)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var dropCaption: String {
        #if os(macOS)
        "Drop a picture to use it, or a folder to give it this icon."
        #else
        "Drop a picture here to use it."
        #endif
    }

    private func templateList(axis: Axis) -> some View {
        ScrollView(axis == .vertical ? .vertical : .horizontal) {
            let layout = axis == .vertical ? AnyLayout(VStackLayout(spacing: 10)) : AnyLayout(HStackLayout(spacing: 10))
            layout {
                ForEach(FolderIconTemplate.allCases) { template in
                    FolderIconTemplateButton(template: template, preview: renders.templatePreviews[template],
                                             isChosen: design.template == template) { design.template = template }
                }
            }
            .padding(12)
        }
    }

    private func export() {
        guard let icon = FolderIconRenderer.icon(design, picture: picture, folderArt: renders.folderArt, pixels: FolderIconMakerRenders.exportPixels),
              let pngData = try? FolderIconRenderer.pngData(of: icon) else { return problem = .notDrawn } // Reported below.
        exportedIcon = FolderIconPNGDocument(pngData: pngData)
    }

    private func removeBackground() async {
        isRemovingBackground = true
        defer { isRemovingBackground = false }
        let source = picture
        do {
            picture = try await Task.detached(priority: .userInitiated) { try PictureBackgroundRemoval.removingBackground(from: source) }.value
        } catch PictureBackgroundRemoval.Failure.noForeground {
            problem = .noForeground
        } catch {
            problem = .backgroundRemovalUnavailable
        }
    }

    /// A picture replaces the picture; on the Mac a folder gets the icon as Finder's custom icon.
    private func takeDroppedFile(at location: URL) async {
        let isDirectory = (try? location.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true // Unknown: taken as a file.
        if isDirectory {
            #if os(macOS)
            guard let icon = FolderIconRenderer.icon(design, picture: picture, folderArt: renders.folderArt, pixels: FolderIconMakerRenders.exportPixels) else {
                return problem = .notDrawn
            }
            do { try FinderFolderAttributes.setCustomIcon(icon, onFolderAt: location) } catch { problem = .folderNotChanged }
            #else
            problem = .foldersOnlyOnTheMac
            #endif
            return
        }
        do {
            let imageData = try await Task.detached(priority: .userInitiated) { try PickedImageFiles.imageData(at: location) }.value
            await usePicture(from: imageData)
        } catch {
            problem = .notAPicture
        }
    }

    private func usePicture(from imageData: Data) async {
        let decoded = await Task.detached(priority: .userInitiated) { FolderIconRenderer.decodedPicture(from: imageData) }.value
        guard let decoded else { return problem = .notAPicture }
        picture = decoded
        design.framing = .filling
    }
}

/// The large preview: the icon on a round checkerboard that shows what is transparent. A drag
/// moves the picture and a pinch zooms it, as the settings' sliders do.
private struct FolderIconMakerPreview: View {
    let icon: CGImage?
    @Binding var design: FolderIconDesign
    @State private var framingAtGestureStart: FolderPictureFraming?
    @Environment(\.displayScale) private var displayScale

    static let side: CGFloat = 300
    private static let iconSide: CGFloat = 250

    var body: some View {
        ZStack {
            CheckerboardCircle()
            if let icon {
                Image(decorative: icon, scale: displayScale)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: Self.iconSide, height: Self.iconSide)
            } else {
                ProgressView()
            }
        }
        .frame(width: Self.side, height: Self.side)
        .contentShape(Circle())
        .gesture(dragGesture.simultaneously(with: zoomGesture))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Preview of the icon")
        .accessibilityAddTraits(.isImage)
    }

    /// The picture's frame on screen, for turning a drag into frame widths.
    private var frameSize: CGSize {
        let unitFrame = design.template.pictureFrame
        return CGSize(width: unitFrame.width * Self.iconSide, height: unitFrame.height * Self.iconSide)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { drag in
                let start = framingAtGestureStart ?? design.framing
                framingAtGestureStart = start
                design.framing = start.moved(by: drag.translation, frameSize: frameSize)
            }
            .onEnded { _ in framingAtGestureStart = nil }
    }

    private var zoomGesture: some Gesture {
        MagnifyGesture()
            .onChanged { magnification in
                let start = framingAtGestureStart ?? design.framing
                framingAtGestureStart = start
                design.framing.zoom = start.zoom * magnification.magnification
            }
            .onEnded { _ in framingAtGestureStart = nil }
    }
}

/// A round checkerboard, as image editors show transparency.
private struct CheckerboardCircle: View {
    private static let squarePoints: CGFloat = 12

    var body: some View {
        Canvas { context, size in
            let columns = Int(size.width / Self.squarePoints) + 1
            let rows = Int(size.height / Self.squarePoints) + 1
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white))
            for row in 0..<rows {
                for column in 0..<columns where (row + column).isMultiple(of: 2) {
                    let square = CGRect(x: CGFloat(column) * Self.squarePoints, y: CGFloat(row) * Self.squarePoints,
                                        width: Self.squarePoints, height: Self.squarePoints)
                    context.fill(Path(square), with: .color(Color(white: 0.88)))
                }
            }
        }
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(.separator, lineWidth: 0.5))
        .accessibilityHidden(true)
    }
}

/// One template in the column, with the picture drawn in it.
private struct FolderIconTemplateButton: View {
    let template: FolderIconTemplate
    let preview: CGImage?
    let isChosen: Bool
    let choose: () -> Void
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Button(action: choose) {
            VStack(spacing: 4) {
                Group {
                    if let preview {
                        Image(decorative: preview, scale: displayScale).resizable().interpolation(.high)
                    } else {
                        Color.clear
                    }
                }
                .frame(width: 72, height: 72)
                Text(template.title).font(.caption).foregroundStyle(.primary)
            }
            .padding(8)
            .background {
                if isChosen { RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.accentColor.opacity(0.18)) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(template.title)
        .accessibilityAddTraits(isChosen ? .isSelected : [])
    }
}

/// The settings: offsets, zoom, rotation and background, with Reset All.
private struct FolderIconSettingsButton: View {
    @Binding var design: FolderIconDesign
    @State private var isShown = false
    @Environment(\.self) private var environment

    var body: some View {
        Button("Adjust", systemImage: "slider.horizontal.3") { isShown = true }
            .popover(isPresented: $isShown) {
                VStack(alignment: .leading, spacing: 14) {
                    slider("Horizontal Offset", value: $design.framing.horizontalOffset, range: Self.offsetRange)
                    slider("Vertical Offset", value: $design.framing.verticalOffset, range: Self.offsetRange)
                    slider("Zoom", value: $design.framing.zoom, range: FolderPictureFraming.minimumZoom...FolderPictureFraming.maximumZoom)
                    slider("Rotation", value: $design.framing.rotationDegrees, range: -180...180)
                    HStack {
                        Text("Background")
                        Spacer()
                        ColorPicker("Background", selection: backgroundSelection, supportsOpacity: false).labelsHidden()
                        Button("No Background", systemImage: "xmark.circle.fill") { design.background = nil }
                            .labelStyle(.iconOnly)
                            .foregroundStyle(.secondary)
                            .disabled(design.background == nil)
                    }
                    Button("Reset All") { design = FolderIconDesign(template: design.template) }
                        .frame(maxWidth: .infinity)
                }
                .padding(18)
                .frame(width: 300)
                .presentationCompactAdaptation(.popover)
            }
    }

    private static let offsetRange = -FolderPictureFraming.maximumOffset...FolderPictureFraming.maximumOffset

    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.subheadline)
            Slider(value: value, in: range)
                .accessibilityLabel(title)
        }
    }

    private var backgroundSelection: Binding<Color> {
        Binding(get: {
            design.background.map { color in Color(.sRGB, red: color.red, green: color.green, blue: color.blue) } ?? .clear
        }, set: { pickedColor in
            let resolved = pickedColor.resolve(in: environment)
            design.background = CGColorComponents(red: CGFloat(resolved.red), green: CGFloat(resolved.green), blue: CGFloat(resolved.blue))
        })
    }
}

/// The pictures the maker shows, drawn off the main actor after each change: the large
/// preview and every template's preview.
struct FolderIconMakerRenders {
    /// What a drawing depends on; a change of any part draws again.
    struct Key: Equatable {
        let design: FolderIconDesign
        let picture: ObjectIdentifier
        let hasFolderArt: Bool
    }

    static let previewPixels = 600
    static let templatePreviewPixels = 160
    /// Export and a folder dropped on the Mac get Finder's largest icon size.
    static let exportPixels = 1_024

    /// One drawing: the large preview and each template's.
    struct Drawn: Sendable {
        let previewIcon: CGImage?
        let templatePreviews: [FolderIconTemplate: CGImage]
    }

    var folderArt: CGImage?
    private(set) var previewIcon: CGImage?
    private(set) var templatePreviews: [FolderIconTemplate: CGImage] = [:]

    mutating func show(_ drawn: Drawn) {
        previewIcon = drawn.previewIcon
        templatePreviews = drawn.templatePreviews
    }

    static func draw(design: FolderIconDesign, picture: CGImage, folderArt: CGImage?) async -> Drawn {
        await Task.detached(priority: .userInitiated) {
            let preview = FolderIconRenderer.icon(design, picture: picture, folderArt: folderArt, pixels: Self.previewPixels)
            var templatePreviews: [FolderIconTemplate: CGImage] = [:]
            for template in FolderIconTemplate.allCases {
                var templateDesign = design
                templateDesign.template = template
                templatePreviews[template] = FolderIconRenderer.icon(templateDesign, picture: picture, folderArt: folderArt, pixels: Self.templatePreviewPixels)
            }
            return Drawn(previewIcon: preview, templatePreviews: templatePreviews)
        }.value
    }
}

/// Why the icon maker could not do what was asked, worded for its alert.
enum FolderIconMakerProblem: Error {
    case notDrawn, notAPicture, noForeground, backgroundRemovalUnavailable, folderNotChanged, foldersOnlyOnTheMac

    var message: String {
        switch self {
        case .notDrawn: "The icon could not be drawn."
        case .notAPicture: "This file is not a picture Graphite can read."
        case .noForeground: "No subject was found in front of a background in this picture."
        case .backgroundRemovalUnavailable: "Removing the background is not available on this device."
        case .folderNotChanged: "The folder's icon could not be changed."
        case .foldersOnlyOnTheMac: "Only the Mac lets an app give another folder an icon. Apply gives this folder the icon."
        }
    }
}

/// A made icon as a PNG file, for Export.
struct FolderIconPNGDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.png]
    let pngData: Data

    init(pngData: Data) {
        self.pngData = pngData
    }

    init(configuration: ReadConfiguration) throws {
        pngData = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: pngData)
    }
}

extension FolderIconTemplate {
    var title: String {
        switch self {
        case .folderFull: "Folder (Full)"
        case .folderCenter: "Folder (Center)"
        case .round: "Round"
        case .squircle: "Squircle"
        case .document: "Document"
        }
    }
}

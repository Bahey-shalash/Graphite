import SwiftUI
import QuickLook
import GraphiteCore
import GraphiteApple

#if canImport(UIKit)
typealias DecodedPlatformImage = UIImage
#else
typealias DecodedPlatformImage = NSImage
#endif

extension DecodedPlatformImage {
    /// Wraps pixels `ImageFileService.displayImage` has already decoded, at one image pixel
    /// per point, as the PNG data it replaces was read.
    convenience init(decodedImage: CGImage) {
        #if canImport(UIKit)
        self.init(cgImage: decodedImage)
        #else
        self.init(cgImage: decodedImage, size: CGSize(width: decodedImage.width, height: decodedImage.height))
        #endif
    }

    /// An image whose pixels are decoded away from the main thread on iOS. A plain
    /// `UIImage(data:)` decodes when it is first drawn, on the main thread: tens of
    /// milliseconds for a large photo.
    nonisolated static func preparedForDisplay(from imageData: Data) async -> sending DecodedPlatformImage? {
        guard let image = DecodedPlatformImage(data: imageData) else { return nil }
        #if canImport(UIKit)
        return await image.byPreparingForDisplay() ?? image
        #else
        return image
        #endif
    }
}

/// Shows an image or a Graphite drawing (PNG, PDF, or SVG) at full width.
struct ImagePane: View {
    let location: URL
    let path: VaultPath
    let drawingVersion: Int
    /// Whether this image's side of the split is focused; only then does the window's
    /// toolbar show its button.
    var isFocused = true
    let editDrawing: () -> Void
    /// Decoded once per file content, so a toolbar change does not hand the zooming view a
    /// new image and reset its zoom.
    @State private var image: DecodedPlatformImage?
    /// The version of the file `image` was decoded from.
    @State private var imageFileVersion: ImageFileVersion?
    /// The file the state above belongs to. The pane is reused when another file opens in
    /// the same tab.
    @State private var loadedLocation: URL?
    @State private var hasEditableStrokes = false
    @State private var message: String?
    @State private var previewLocation: URL?

    var body: some View {
        imageContent
        .toolbar {
            #if canImport(UIKit)
            if hasEditableStrokes && isFocused {
                ToolbarItem(placement: .primaryAction) {
                    Button("Edit Drawing", systemImage: "pencil.tip.crop.circle") { editDrawing() }.tint(.primary)
                }
            }
            #endif
        }
        .quickLookPreview($previewLocation)
        .task(id: "\(location.path)-\(drawingVersion)") {
            if loadedLocation != location {
                image = nil
                imageFileVersion = nil
                hasEditableStrokes = false
                message = nil
                loadedLocation = location
            }
            let content = await ImagePaneContent.load(from: location, fileExtension: path.fileExtension)
            guard !Task.isCancelled else { return }
            // A drawing version change after an unrelated external change leaves this file
            // as it was; keeping the same image keeps the user's zoom.
            if content.image == nil || content.fileVersion == nil || content.fileVersion != imageFileVersion {
                image = content.image.map(DecodedPlatformImage.init(decodedImage:))
                imageFileVersion = content.fileVersion
            }
            hasEditableStrokes = content.hasEditableStrokes
            message = content.message
        }
    }
}

/// The modification date and size of an image file, which tell a rewritten file from one
/// left as it was without comparing its pixels.
struct ImageFileVersion: Equatable, Sendable {
    let modificationDate: Date
    let byteCount: Int

    static func of(_ location: URL) -> ImageFileVersion? {
        guard let values = try? location.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
              let modificationDate = values.contentModificationDate, let byteCount = values.fileSize else { return nil }
        return ImageFileVersion(modificationDate: modificationDate, byteCount: byteCount)
    }
}

/// What the image pane shows for one file.
struct ImagePaneContent: Sendable {
    /// Already decoded, off the main actor.
    var image: CGImage?
    /// The file's version before it was decoded; nil when it could not be read.
    var fileVersion: ImageFileVersion?
    var message: String?
    var hasEditableStrokes = false

    static let maximumPixelDimension = 2600

    static func load(from location: URL, fileExtension: String) async -> ImagePaneContent {
        var content = ImagePaneContent()
        content.fileVersion = await Task.detached(priority: .userInitiated) { ImageFileVersion.of(location) }.value
        do {
            content.image = try await ImageFileService().displayImage(at: location, maximumPixelDimension: maximumPixelDimension)
        } catch {
            content.message = error.localizedDescription
        }
        guard DrawingFormat(fileExtension: fileExtension) != nil else { return content }
        // Answered from the chunk headers for an ordinary PNG, so a photo is not read twice.
        let reading = await Task.detached(priority: .userInitiated) { DrawingMetadataReader.readMetadata(at: location) }.value
        content.hasEditableStrokes = reading?.payload != nil
        // An SVG changed in another app cannot be drawn at all; its own error says so, and
        // claiming the image is intact over an empty pane would be wrong.
        if reading?.metadataWasDiscarded == true, content.image != nil {
            content.message = "This drawing was changed in another app. The image is intact, but its Pencil strokes can no longer be edited."
        }
        return content
    }
}

extension ImagePane {
    @ViewBuilder private var imageContent: some View {
        #if canImport(UIKit)
        // Pinch and double-tap zoom, as in Photos.
        VStack(spacing: 0) {
            if let image {
                ZoomableImageView(image: image)
            } else if message == nil {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Spacer()
            }
            if let message {
                Text(message).foregroundStyle(.secondary).multilineTextAlignment(.center).padding()
                if image == nil {
                    Button("Preview") { previewLocation = location }.buttonStyle(.borderedProminent).padding(.bottom)
                }
            }
            if image == nil && message != nil { Spacer() }
        }
        #else
        ScrollView([.horizontal, .vertical]) {
            VStack(spacing: 20) {
                if let image {
                    Image(nsImage: image).resizable().scaledToFit().frame(maxWidth: 1100)
                } else if message == nil {
                    ProgressView().padding(80)
                }
                if let message { Text(message).foregroundStyle(.secondary).multilineTextAlignment(.center) }
                if image == nil && message != nil {
                    Button("Preview") { previewLocation = location }.buttonStyle(.borderedProminent)
                }
            }
            .padding(32)
            .frame(maxWidth: .infinity)
        }
        #endif
    }
}

#if canImport(UIKit)
/// An image from a note shown full screen, to zoom into, as in Photos.
struct ImageViewer: View {
    let location: URL
    let title: String
    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?
    @State private var message: String?

    var body: some View {
        NavigationStack {
            Group {
                if let image {
                    ZoomableImageView(image: image)
                } else if let message {
                    ContentUnavailableView("Can't Show This Image", systemImage: "photo", description: Text(message))
                } else {
                    ProgressView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .preferredColorScheme(.dark)
        .task {
            do {
                let decodedImage = try await ImageFileService().displayImage(at: location, maximumPixelDimension: 4096)
                image = UIImage(decodedImage: decodedImage)
            } catch {
                message = error.localizedDescription
            }
        }
    }
}

/// An image that fits the view and zooms with a pinch, or to double size with a double tap.
struct ZoomableImageView: UIViewRepresentable {
    let image: UIImage
    static let maximumZoomFactor: CGFloat = 8

    func makeUIView(context: Context) -> ZoomingImageScrollView {
        let scrollView = ZoomingImageScrollView()
        scrollView.image = image
        return scrollView
    }

    func updateUIView(_ scrollView: ZoomingImageScrollView, context: Context) {
        if scrollView.image !== image { scrollView.image = image }
    }
}

final class ZoomingImageScrollView: UIScrollView, UIScrollViewDelegate {
    private let imageView = UIImageView()
    private var fittedBoundsSize: CGSize = .zero
    private static let margin: CGFloat = 24

    var image: UIImage? {
        get { imageView.image }
        set {
            // The zoom is a scale transform on the image view; a frame set under it would
            // show the new image at that scale times its pixel size, and the layout below
            // would see an unchanged zoom and never fit it again.
            zoomScale = 1
            imageView.image = newValue
            imageView.frame = CGRect(origin: .zero, size: newValue?.size ?? .zero)
            contentSize = imageView.frame.size
            fittedBoundsSize = .zero
            setNeedsLayout()
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        delegate = self
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        decelerationRate = .fast
        contentInsetAdjustmentBehavior = .never
        imageView.accessibilityIgnoresInvertColors = true
        addSubview(imageView)
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(toggleZoom(_:)))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)
    }

    required init?(coder: NSCoder) { nil }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let image, image.size.width > 0, image.size.height > 0, bounds.width > 0 else { return }
        if bounds.size != fittedBoundsSize {
            // Fit within the view, never enlarging a small image beyond its size.
            let availableSize = CGSize(width: max(bounds.width - 2 * Self.margin, 1), height: max(bounds.height - 2 * Self.margin, 1))
            let fittingScale = min(availableSize.width / image.size.width, availableSize.height / image.size.height, 1)
            let wasFitted = fittedBoundsSize == .zero || abs(zoomScale - minimumZoomScale) < 0.001
            minimumZoomScale = fittingScale
            maximumZoomScale = max(fittingScale * ZoomableImageView.maximumZoomFactor, 1)
            if wasFitted || zoomScale < fittingScale { zoomScale = fittingScale }
            fittedBoundsSize = bounds.size
        }
        centerImage()
    }

    /// Keeps a smaller-than-view image in the middle instead of the top-left corner.
    private func centerImage() {
        let horizontalInset = max((bounds.width - contentSize.width) / 2, 0)
        let verticalInset = max((bounds.height - contentSize.height) / 2, 0)
        contentInset = UIEdgeInsets(top: verticalInset, left: horizontalInset, bottom: verticalInset, right: horizontalInset)
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

    func scrollViewDidZoom(_ scrollView: UIScrollView) { centerImage() }

    @objc private func toggleZoom(_ recognizer: UITapGestureRecognizer) {
        if zoomScale > minimumZoomScale + 0.001 {
            setZoomScale(minimumZoomScale, animated: true)
        } else {
            let targetScale = min(minimumZoomScale * 2.5, maximumZoomScale)
            let point = recognizer.location(in: imageView)
            let size = CGSize(width: bounds.width / targetScale, height: bounds.height / targetScale)
            zoom(to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height), animated: true)
        }
    }
}
#endif

struct FilePreviewPane: View {
    let location: URL
    @State private var previewLocation: URL?
    var body: some View {
        ContentUnavailableView {
            Label(location.lastPathComponent, systemImage: "doc")
        } description: { Text("Open this attachment with the system preview.") } actions: {
            Button("Preview") { previewLocation = location }.buttonStyle(.borderedProminent)
            ShareLink(item: location)
        }.quickLookPreview($previewLocation)
    }
}

/// An image embedded in a note. A Graphite drawing opens for editing when tapped, as in
/// Goodnotes, and carries an Edit button so that is visible; any other image opens full
/// screen to zoom. Both are also in its menu.
struct EmbeddedImageView: View {
    /// What the embed was given to show.
    private enum ImageSource {
        /// Pixels already decoded away from the main thread, drawn as they are.
        case decoded(CGImage)
        /// Encoded image data, which the view decodes away from the main thread once.
        case encoded(Data)
    }

    private let imageSource: ImageSource
    let aspectRatio: CGFloat
    let displayWidth: CGFloat?
    /// Opens the drawing editor; nil for an image that is not an editable drawing.
    let edit: (() -> Void)?
    /// Shows the image full screen.
    let view: (() -> Void)?
    @State private var decodedImages = DecodedImageCache()

    /// Shows pixels already decoded at the size they are shown, off the main thread, so no
    /// evaluation of the body decodes anything and every one draws the same image.
    init(image: CGImage, aspectRatio: CGFloat, displayWidth: CGFloat?, edit: (() -> Void)?, view: (() -> Void)?) {
        self.init(imageSource: .decoded(image), aspectRatio: aspectRatio, displayWidth: displayWidth, edit: edit, view: view)
    }

    /// Shows encoded image data, decoded away from the main thread when the view appears.
    init(imageData: Data, aspectRatio: CGFloat, displayWidth: CGFloat?, edit: (() -> Void)?, view: (() -> Void)?) {
        self.init(imageSource: .encoded(imageData), aspectRatio: aspectRatio, displayWidth: displayWidth, edit: edit, view: view)
    }

    private init(imageSource: ImageSource, aspectRatio: CGFloat, displayWidth: CGFloat?, edit: (() -> Void)?, view: (() -> Void)?) {
        self.imageSource = imageSource
        self.aspectRatio = aspectRatio
        self.displayWidth = displayWidth
        self.edit = edit
        self.view = view
    }

    var body: some View {
        image
            .overlay(alignment: .topTrailing) {
                if let edit {
                    Button(action: edit) {
                        Label("Edit", systemImage: "pencil.tip.crop.circle")
                            .font(.callout.weight(.semibold))
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(.regularMaterial, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .padding(10)
                    .accessibilityLabel("Edit Drawing")
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { (edit ?? view)?() }
            .contextMenu {
                if let edit { Button("Edit Drawing", systemImage: "pencil.tip.crop.circle", action: edit) }
                if let view { Button("View Full Screen", systemImage: "arrow.up.left.and.arrow.down.right", action: view) }
                #if canImport(UIKit)
                Button("Copy Image", systemImage: "doc.on.doc") { copyImage() }
                #endif
            }
            .accessibilityAddTraits(.isButton)
            .accessibilityHint(edit != nil ? "Opens the drawing to edit" : "Opens the image to zoom")
    }

    #if canImport(UIKit)
    /// Copies the image as shown, so it can be pasted into another note or app.
    private func copyImage() {
        switch imageSource {
        case .decoded(let decodedImage):
            UIPasteboard.general.image = UIImage(cgImage: decodedImage)
        case .encoded(let imageData):
            guard let image = decodedImages.image(for: imageData) else { return }
            UIPasteboard.general.image = image
        }
    }
    #endif

    @ViewBuilder private var image: some View {
        switch imageSource {
        case .decoded(let decodedImage):
            sized(Image(decodedImage, scale: 1, label: Text("Image")).resizable())
        case .encoded(let imageData):
            decodingImage(from: imageData)
        }
    }

    /// The last decoded image stays on screen while changed data decodes, so an edited
    /// drawing does not blink; data that does not decode shows nothing.
    @ViewBuilder private func decodingImage(from imageData: Data) -> some View {
        if let decodedImage = decodedImages.latestImage {
            #if canImport(UIKit)
            decoding(imageData, in: sized(Image(uiImage: decodedImage).resizable()))
            #else
            decoding(imageData, in: sized(Image(nsImage: decodedImage).resizable()))
            #endif
        } else if !decodedImages.hasDecoded(imageData) {
            // Takes the image's place while it decodes, at its size, so the note does not
            // move when the image appears.
            decoding(imageData, in: sized(Rectangle().fill(.quaternary.opacity(0.4))))
        } else {
            // Takes no space, but stays to decode the next data the embed is given.
            decoding(imageData, in: Color.clear.frame(width: 0, height: 0))
        }
    }

    private func decoding(_ imageData: Data, in content: some View) -> some View {
        content.task(id: imageData) { await decodedImages.prepareImage(for: imageData) }
    }

    private func sized(_ content: some View) -> some View {
        content
            .aspectRatio(aspectRatio, contentMode: .fit)
            .frame(maxWidth: displayWidth ?? .infinity, alignment: .leading)
    }
}

/// Keeps the image last decoded from an embed's data. A note re-renders its embeds on many
/// changes, and a new image object would decode the whole bitmap again on the main thread.
@MainActor @Observable
final class DecodedImageCache {
    private var sourceData: Data?
    private var decodedImage: DecodedPlatformImage?

    /// The image last decoded, from the current data or from the data before it.
    var latestImage: DecodedPlatformImage? { decodedImage }

    /// Whether this data has been decoded, into an image or into nothing.
    func hasDecoded(_ imageData: Data) -> Bool {
        sourceData == imageData
    }

    /// Decodes the image away from the main thread, for drawing: a large photo takes tens
    /// of milliseconds to decode.
    func prepareImage(for imageData: Data) async {
        guard !hasDecoded(imageData) else { return }
        let preparedImage = await DecodedPlatformImage.preparedForDisplay(from: imageData)
        guard !Task.isCancelled else { return }
        sourceData = imageData
        decodedImage = preparedImage
    }

    /// Decodes on the calling thread when the image is needed at once, as for copying it.
    func image(for imageData: Data) -> DecodedPlatformImage? {
        if let sourceData, sourceData == imageData { return decodedImage }
        sourceData = imageData
        decodedImage = DecodedPlatformImage(data: imageData)
        return decodedImage
    }
}

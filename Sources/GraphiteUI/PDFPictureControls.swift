#if canImport(UIKit)
import SwiftUI
import UIKit
import PDFKit
import PhotosUI
import UniformTypeIdentifiers
import GraphiteCore
import GraphiteApple

/// Where an image to place on a PDF page comes from.
enum PDFPictureSource: Identifiable {
    case photoLibrary, file
    var id: Self { self }
}

/// The "Add Image" choices, for a menu of a PDF pane or an embedded PDF.
struct PDFAddImageMenuContent: View {
    let session: PDFSession
    @Binding var source: PDFPictureSource?

    var body: some View {
        Button("Photo Library…", systemImage: "photo.on.rectangle") { source = .photoLibrary }
        Button("Choose File…", systemImage: "folder") { source = .file }
        if UIPasteboard.general.hasImages {
            Button("Paste Image", systemImage: "doc.on.clipboard") {
                guard let imageData = UIPasteboard.general.image?.pngData() else { return }
                PDFPictureAdding.addPicture(imageData: imageData, to: session)
            }
        }
    }
}

/// Presents the photo picker or the file picker for `source`, and places what was picked
/// on the page in view.
struct PDFPictureAdding: ViewModifier {
    let session: PDFSession
    @Binding var source: PDFPictureSource?
    @State private var pickedPhoto: PhotosPickerItem?

    func body(content: Content) -> some View {
        content
            .photosPicker(isPresented: isPresenting(.photoLibrary), selection: $pickedPhoto, matching: .images)
            .fileImporter(isPresented: isPresenting(.file), allowedContentTypes: [.image]) { pickedFile in
                guard case .success(let location) = pickedFile else { return }
                Task {
                    do {
                        let imageData = try await Task.detached(priority: .userInitiated) { try PickedImageFiles.imageData(at: location) }.value
                        Self.addPicture(imageData: imageData, to: session)
                    } catch { session.errorMessage = error.localizedDescription }
                }
            }
            .onChange(of: pickedPhoto) { _, photo in
                guard let photo else { return }
                pickedPhoto = nil
                Task {
                    do {
                        guard let imageData = try await photo.loadTransferable(type: Data.self) else { throw GraphiteError.invalidFile("This photo could not be read.") }
                        Self.addPicture(imageData: imageData, to: session)
                    } catch { session.errorMessage = error.localizedDescription }
                }
            }
    }

    private func isPresenting(_ presentedSource: PDFPictureSource) -> Binding<Bool> {
        Binding(get: { source == presentedSource }, set: { isPresented in if !isPresented, source == presentedSource { source = nil } })
    }

    static func addPicture(imageData: Data, to session: PDFSession) {
        Task {
            do { try await session.addPicture(imageData: imageData) }
            catch { session.errorMessage = error.localizedDescription }
        }
    }
}

/// Shown while a picture on a PDF page is selected, where the Pencil palette otherwise is.
struct PDFPictureArrangementBar: View {
    let session: PDFSession

    var body: some View {
        HStack(spacing: 16) {
            Text("Drag the image to move it, or a corner to resize it.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer(minLength: 8)
            Button("Delete Image", systemImage: "trash", role: .destructive) {
                guard let selection = session.selectedPicture else { return }
                do { try session.removePicture(selection) } catch { session.errorMessage = error.localizedDescription }
            }
            .labelStyle(.iconOnly)
            Button("Done") { session.selectedPicture = nil }
                .fontWeight(.semibold)
                .tint(.primary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }
}

/// Shows the selection frame of the session's selected picture over a PDF view, follows the
/// page as it scrolls and zooms, and moves the picture when a drag ends.
@MainActor
final class PDFPictureSelectionController {
    private let session: PDFSession
    private weak var pdfView: PDFView?
    private var selectionView: PictureSelectionView?
    private var scrollObservation: NSKeyValueObservation?
    private var notificationObservers: [NSObjectProtocol] = []
    /// Scroll views that wait for the selection's drags, so a drag does not scroll the page.
    private var waitingScrollViews: Set<ObjectIdentifier> = []

    init(session: PDFSession, pdfView: PDFView) {
        self.session = session
        self.pdfView = pdfView
        let center = NotificationCenter.default
        // Zooming, page changes, and undo move the picture under the frame.
        for name in [Notification.Name.PDFViewScaleChanged, .PDFViewVisiblePagesChanged] {
            notificationObservers.append(center.addObserver(forName: name, object: pdfView, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.update() }
            })
        }
        for name in [Notification.Name.NSUndoManagerDidUndoChange, .NSUndoManagerDidRedoChange] {
            notificationObservers.append(center.addObserver(forName: name, object: session.undoManager, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.update() }
            })
        }
    }

    func stop() {
        for observer in notificationObservers { NotificationCenter.default.removeObserver(observer) }
        notificationObservers = []
        scrollObservation = nil
        selectionView?.removeFromSuperview()
        selectionView = nil
    }

    /// The selected picture and its page, while both still exist.
    private var selected: (picture: PDFPicture, page: PDFPage)? {
        guard let selection = session.selectedPicture, let page = selection.page.page, page.document === session.document,
              let picture = session.pictures(on: page).first(where: { picture in picture.name == selection.pictureName }) else { return nil }
        return (picture, page)
    }

    /// Shows, moves or hides the frame after the selection or the page under it changed.
    func update() {
        guard let pdfView, pdfView.window != nil, let (picture, page) = selected else {
            selectionView?.removeFromSuperview()
            selectionView = nil
            // A picture that is gone (undo, a deleted page) is not selected any more.
            if session.selectedPicture != nil, selected == nil { session.selectedPicture = nil }
            return
        }
        let selection = selectionView ?? makeSelectionView(in: pdfView)
        // Not while a drag moves the frame: the picture follows when the drag ends.
        guard !selection.dragRecognizers.contains(where: { recognizer in recognizer.state == .began || recognizer.state == .changed }) else { return }
        selection.frame = pdfView.convert(picture.bounds, from: page)
        selection.centerLimits = pdfView.convert(page.bounds(for: .cropBox), from: page)
        // The preview is the picture as placed; on a page turned since, only the frame moves.
        let pageTurns = ((page.rotation / 90) % 4 + 4) % 4
        selection.dragPreview = pageTurns == picture.quarterTurns ? UIImage(data: picture.imageData) : nil
    }

    private func makeSelectionView(in pdfView: PDFView) -> PictureSelectionView {
        let selection = PictureSelectionView(frame: .zero)
        selection.frameChangeDidEnd = { [weak self] frame in self?.selectionFrameChangeDidEnd(frame) }
        pdfView.addSubview(selection)
        selectionView = selection
        if let scrollView = Self.scrollView(in: pdfView) {
            if waitingScrollViews.insert(ObjectIdentifier(scrollView)).inserted {
                scrollObservation = scrollView.observe(\.contentOffset) { [weak self] _, _ in
                    MainActor.assumeIsolated { self?.update() }
                }
            }
            for recognizer in selection.dragRecognizers { scrollView.panGestureRecognizer.require(toFail: recognizer) }
        }
        return selection
    }

    private func selectionFrameChangeDidEnd(_ frame: CGRect) {
        guard let pdfView, let selection = session.selectedPicture, let page = selection.page.page else { return }
        do { try session.movePicture(selection, to: pdfView.convert(frame, to: page)) }
        catch { session.errorMessage = error.localizedDescription }
        update()
    }

    /// The picture at a point of the PDF view, with its page.
    func picture(at viewPoint: CGPoint) -> PDFPictureSelection? {
        guard let pdfView, let page = pdfView.page(for: viewPoint, nearest: false),
              let picture = session.picture(at: pdfView.convert(viewPoint, to: page), on: page) else { return nil }
        return PDFPictureSelection(pictureName: picture.name, page: session.historyPage(for: page))
    }

    /// The middle of what the view shows of the page in view, in that page's coordinates.
    func visiblePageCenter() -> (pageIndex: Int, center: CGPoint)? {
        guard let pdfView, let page = pdfView.currentPage else { return nil }
        let pageIndex = session.document.index(for: page)
        guard pageIndex != NSNotFound else { return nil }
        let visibleRegion = pdfView.convert(pdfView.bounds, to: page).intersection(page.bounds(for: .cropBox))
        guard !visibleRegion.isNull, visibleRegion.width > 0, visibleRegion.height > 0 else { return nil }
        return (pageIndex, CGPoint(x: visibleRegion.midX, y: visibleRegion.midY))
    }

    private static func scrollView(in view: UIView) -> UIScrollView? {
        for subview in view.subviews {
            if let scrollView = subview as? UIScrollView { return scrollView }
            if let scrollView = scrollView(in: subview) { return scrollView }
        }
        return nil
    }
}
#endif

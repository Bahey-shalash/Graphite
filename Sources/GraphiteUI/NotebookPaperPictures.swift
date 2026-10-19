import Foundation
import CoreGraphics
import Observation
import GraphiteCore
import GraphiteApple

/// The pictures of paper the New Notebook sheet shows: the chosen paper large, and every
/// paper of the gallery small, each drawn with the sheet's size and colors. Drawn off the
/// main thread; a newer request replaces one still drawing.
@MainActor @Observable
final class NotebookPaperPictures {
    /// The large picture's longer side, and a gallery picture's, in pixels.
    static let chosenPicturePixels = 640
    static let galleryPicturePixels = 320

    private(set) var chosenPicture: CGImage?
    private(set) var galleryPictures: [NotebookPaperChoice: CGImage] = [:]
    @ObservationIgnored private var drawingTask: Task<Void, Never>?
    @ObservationIgnored private var drawnOptions: NewNotebookOptions?

    /// Draws the pictures for these options, unless they are already drawn for them.
    func draw(for options: NewNotebookOptions) {
        guard options != drawnOptions else { return }
        let galleryOptions = galleryKey(of: options)
        let galleryNeedsDrawing = drawnOptions.map(galleryKey(of:)) != galleryOptions
        drawnOptions = options
        drawingTask?.cancel()
        drawingTask = Task { [weak self] in
            let chosen = await Self.picture(of: options.paper, longerSidePixels: Self.chosenPicturePixels)
            guard !Task.isCancelled else { return }
            self?.chosenPicture = chosen
            guard galleryNeedsDrawing else { return }
            var drawnPictures: [NotebookPaperChoice: CGImage] = [:]
            for choice in NotebookPaperChoice.allCases {
                drawnPictures[choice] = await Self.picture(of: options.choosing(choice).paper, longerSidePixels: Self.galleryPicturePixels)
                guard !Task.isCancelled else { return }
            }
            self?.galleryPictures = drawnPictures
        }
    }

    /// Stops drawing when the sheet closes.
    func stop() {
        drawingTask?.cancel()
        drawingTask = nil
    }

    /// The gallery shows every paper, so choosing another one does not change its pictures.
    private func galleryKey(of options: NewNotebookOptions) -> NewNotebookOptions {
        options.choosing(.blank)
    }

    /// Nil when the options make no valid paper; the sheet then shows the problem.
    private nonisolated static func picture(of paper: PaperSpecification, longerSidePixels: Int) async -> CGImage? {
        let drawing = Task.detached(priority: .userInitiated) { try PaperPreviewRenderer.image(of: paper, longerSidePixels: longerSidePixels) }
        return try? await drawing.value // A paper the generator refuses has no picture; the sheet says why.
    }
}

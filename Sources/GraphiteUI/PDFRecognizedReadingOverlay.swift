import PDFKit

#if canImport(UIKit)
import UIKit
typealias ReadingOverlayView = UIView
#else
import AppKit
typealias ReadingOverlayView = NSView
#endif

/// Empty, noninteractive container attached to PDFKit's scrolling document view.
/// Only small colored word views have backing contents; no page-sized bitmap or
/// PDF annotation is created. Scrolling carries the overlay with its source page.
@MainActor
final class PDFRecognizedReadingOverlay: ReadingOverlayView {
    private weak var pdfView: PDFView?
    private var highlights: [PDFReadAloudHighlight] = []
    private var wordViews: [ReadingOverlayView] = []

    #if canImport(UIKit)
    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        accessibilityElementsHidden = true
        isOpaque = false
        backgroundColor = .clear
        autoresizingMask = [.flexibleWidth, .flexibleHeight]
    }
    override func layoutSubviews() { super.layoutSubviews(); refreshFrames() }
    #else
    override var isFlipped: Bool { true }
    override init(frame: CGRect) {
        super.init(frame: frame)
        wantsLayer = true
        setAccessibilityElement(false)
        autoresizingMask = [.width, .height]
    }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func layout() { super.layout(); refreshFrames() }
    #endif

    convenience init() { self.init(frame: .zero) }
    required init?(coder: NSCoder) { nil }

    func update(_ highlights: [PDFReadAloudHighlight], in view: PDFView) {
        pdfView = view
        self.highlights = highlights
        let host = view.documentView ?? view
        if superview !== host {
            removeFromSuperview()
            frame = host.bounds
            host.addSubview(self)
        }
        while wordViews.count > highlights.count { wordViews.removeLast().removeFromSuperview() }
        while wordViews.count < highlights.count {
            let wordView = ReadingOverlayView(frame: .zero)
            #if canImport(UIKit)
            wordView.isUserInteractionEnabled = false
            wordView.backgroundColor = ReadAloudHighlightStyle.fill
            wordView.layer.cornerRadius = 2
            #else
            wordView.wantsLayer = true
            wordView.layer?.backgroundColor = ReadAloudHighlightStyle.fill.cgColor
            wordView.layer?.cornerRadius = 2
            wordView.setAccessibilityElement(false)
            #endif
            addSubview(wordView)
            wordViews.append(wordView)
        }
        refreshFrames()
    }

    private func refreshFrames() {
        guard let pdfView, let document = pdfView.document else { return }
        for (wordIndex, highlight) in highlights.enumerated() where wordViews.indices.contains(wordIndex) {
            let wordView = wordViews[wordIndex]
            guard let page = document.page(at: highlight.pageIndex), let bounds = highlight.pageBounds(in: document) else {
                wordView.isHidden = true
                continue
            }
            wordView.isHidden = false
            wordView.frame = convert(pdfView.convert(bounds, from: page), from: pdfView)
        }
    }
}

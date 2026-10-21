/**
 * File: NotePDFExport.swift
 * -------------------------
 * Layer: UI
 * Description: One note's Export to PDF: the options chosen, a preview of the first pages, the export with its
 *              progress and cancellation, and the finished PDF handed to the file exporter.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 21/10/2026
 */

import SwiftUI
import PDFKit
import GraphiteCore

/// A preview page of the PDF, drawn off the main thread.
struct NotePDFPreviewPage: Identifiable, Sendable {
    let pageIndex: Int
    let image: CGImage

    var id: Int { pageIndex }
}

/// What the Export to PDF sheet shows and does for one note. The note's file is only read;
/// the PDF exists in memory until the person saves it where they choose.
@MainActor @Observable
final class NotePDFExport {
    enum Phase {
        /// Choosing options, with a preview.
        case choosing
        case exporting(fractionDone: Double)
        /// The PDF is made and waits for the person to pick where it goes.
        case saving(PDFExportDocument)
        /// The PDF is made and waits for the print panel.
        case printing(NotePDF)
        case failed(message: String)
    }

    private(set) var phase = Phase.choosing
    private(set) var previewPages: [NotePDFPreviewPage] = []
    private(set) var isPreparingPreview = false
    /// The options shown; changing one makes a new preview.
    var options: NotePDFOptions {
        didSet { if options != oldValue { startPreview() } }
    }

    let purpose: NotePDFPurpose
    private let source: NotePDFSource
    private let defaults: NotePDFExportDefaults
    private var previewTask: Task<Void, Never>?
    private var exportTask: Task<Void, Never>?

    /// Pages the preview shows.
    nonisolated static let previewPageCount = 2
    /// The preview pages' height, in points, which they are drawn for.
    nonisolated static let previewPageHeight: CGFloat = 240

    init(source: NotePDFSource, defaults: NotePDFExportDefaults, purpose: NotePDFPurpose) {
        self.source = source
        self.defaults = defaults
        self.purpose = purpose
        options = defaults.options
    }

    var title: String { source.title }

    var isExporting: Bool {
        if case .exporting = phase { return true }
        return false
    }

    /// Whether a PDF made to print is ready, or stopped: the progress sheet then closes.
    var isFinishedPrinting: Bool {
        switch phase {
        case .printing: true
        case .choosing: purpose == .print && exportTask != nil
        case .exporting, .saving, .failed: false
        }
    }

    /// Draws the first pages again with the current options, replacing a preview in progress.
    func startPreview() {
        previewTask?.cancel()
        let renderer = NotePDFRenderer(source: source, options: options)
        isPreparingPreview = true
        previewTask = Task { [weak self] in
            do {
                let pdf = try await renderer.render(pageLimit: Self.previewPageCount) { _ in }
                let pages = await Self.previewPages(of: pdf.data)
                guard !Task.isCancelled else { return }
                self?.previewPages = pages
                self?.isPreparingPreview = false
            } catch is CancellationError {
            } catch {
                self?.isPreparingPreview = false
                self?.phase = .failed(message: Self.message(for: error))
            }
        }
    }

    /// Makes the whole PDF: to save, remembering the options for the next export on this
    /// device; to print, with the options last remembered.
    func export() {
        guard !isExporting else { return }
        if purpose == .save { defaults.remember(options) }
        previewTask?.cancel()
        let renderer = NotePDFRenderer(source: source, options: options)
        phase = .exporting(fractionDone: 0)
        exportTask = Task { [weak self] in
            do {
                let pdf = try await renderer.render { fraction in self?.phase = .exporting(fractionDone: fraction) }
                switch self?.purpose {
                case .save: self?.phase = .saving(PDFExportDocument(data: pdf.data))
                case .print: self?.phase = .printing(pdf)
                case nil: break
                }
            } catch is CancellationError {
                self?.phase = .choosing
            } catch {
                self?.phase = .failed(message: Self.message(for: error))
            }
        }
    }

    /// Stops the export; nothing was written, so nothing is left behind.
    func cancelExport() {
        exportTask?.cancel()
    }

    /// The file exporter closed: saved, cancelled or failed.
    func finishSaving(_ result: Result<URL, Error>?) {
        if case .failure(let error) = result {
            phase = .failed(message: Self.message(for: error))
        } else {
            phase = .choosing
        }
    }

    func dismissFailure() {
        phase = .choosing
    }

    /// Ends the preview and the export, as when the sheet closes.
    func stopAllWork() {
        previewTask?.cancel()
        exportTask?.cancel()
    }

    /// What the person is told when the PDF could not be made or saved.
    static func message(for error: any Error) -> String {
        switch error as? NotePDFExportError {
        case .drawingUnavailable, .drawnPDFUnreadable, .finishedPDFUnwritable:
            "The PDF could not be made. Try again, or export with other options."
        case .noNoteInFront, .noteNotText:
            "The note could not be read, so no PDF was made."
        case nil:
            (error as? LocalizedError)?.errorDescription ?? "The PDF could not be made or saved. Try again."
        }
    }

    /// Pictures of the PDF's first pages, drawn off the main thread.
    private nonisolated static func previewPages(of data: Data) async -> [NotePDFPreviewPage] {
        await Task.detached(priority: .userInitiated) {
            guard let document = PDFDocument(data: data) else { return [] }
            return (0..<min(document.pageCount, previewPageCount)).compactMap { pageIndex in
                guard let page = document.page(at: pageIndex) else { return nil }
                let pageSize = page.bounds(for: .cropBox).size
                guard pageSize.height > 0 else { return nil }
                let pictureSize = CGSize(width: pageSize.width / pageSize.height * previewPageHeight * 2, height: previewPageHeight * 2)
                return page.thumbnail(of: pictureSize, for: .cropBox).graphiteCGImage.map { image in NotePDFPreviewPage(pageIndex: pageIndex, image: image) }
            }
        }.value
    }
}

#if canImport(UIKit)
import UIKit

private extension UIImage {
    var graphiteCGImage: CGImage? { cgImage }
}
#else
import AppKit

private extension NSImage {
    var graphiteCGImage: CGImage? { cgImage(forProposedRect: nil, context: nil, hints: nil) }
}
#endif

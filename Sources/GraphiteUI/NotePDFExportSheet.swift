/**
 * File: NotePDFExportSheet.swift
 * ------------------------------
 * Layer: UI
 * Description: The Export to PDF sheet of a note: Obsidian's options (title, page size, orientation, margins,
 *              downscale, properties), a preview of the first pages, the export's progress, and the file exporter
 *              that saves the PDF where the person picks.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 21/10/2026
 */

import SwiftUI
import UniformTypeIdentifiers
import GraphiteCore

/// Exports one note to a PDF the person saves where they choose.
struct NotePDFExportSheet: View {
    let export: NotePDFExport
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            NotePDFOptionsForm(export: export)
            .disabled(export.isExporting)
            .navigationTitle("Export to PDF")
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        export.stopAllWork()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Export") { export.export() }.disabled(export.isExporting)
                }
            }
            .overlay {
                if case .exporting(let fractionDone) = export.phase {
                    NotePDFExportProgress(fractionDone: fractionDone) { export.cancelExport() }
                }
            }
        }
        .fileExporter(isPresented: isSaving, document: savingDocument, contentType: .pdf, defaultFilename: export.title) { result in
            export.finishSaving(result)
            if case .success = result { dismiss() }
        }
        .alert("The PDF could not be made", isPresented: isShowingFailure) {
            Button("OK") { export.dismissFailure() }
        } message: {
            if case .failed(let message) = export.phase { Text(message) }
        }
        .task { export.startPreview() }
        .onDisappear { export.stopAllWork() }
    }

    private var savingDocument: PDFExportDocument? {
        if case .saving(let document) = export.phase { return document }
        return nil
    }

    private var isSaving: Binding<Bool> {
        Binding(get: { savingDocument != nil }, set: { isShown in if !isShown, savingDocument != nil { export.finishSaving(nil) } })
    }

    private var isShowingFailure: Binding<Bool> {
        Binding(get: {
            if case .failed = export.phase { return true }
            return false
        }, set: { isShown in if !isShown { export.dismissFailure() } })
    }
}

/// A note's PDF being made to print, with a way to stop it; the print panel follows once it
/// closes (`NotePDFExportPresentation`).
struct NotePDFPrintProgressSheet: View {
    let export: NotePDFExport
    /// Takes the finished PDF before the sheet closes.
    let didFinish: (NotePDF) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            switch export.phase {
            case .failed(let message):
                Text(message).multilineTextAlignment(.center)
                Button("OK") { dismiss() }
            case .exporting(let fractionDone):
                ProgressView("Preparing “\(export.title)” to print…", value: fractionDone)
                Button("Stop", role: .cancel) { export.cancelExport() }
            case .choosing, .saving, .printing:
                ProgressView("Preparing “\(export.title)” to print…", value: 0)
                Button("Stop", role: .cancel) { dismiss() }
            }
        }
        .padding(24)
        .frame(minWidth: 320)
        .task { export.export() }
        .onChange(of: export.isFinishedPrinting) { _, isFinished in
            guard isFinished else { return }
            if case .printing(let pdf) = export.phase { didFinish(pdf) }
            dismiss()
        }
        .onDisappear { export.stopAllWork() }
    }
}

/// The preview and Obsidian's Export to PDF options.
private struct NotePDFOptionsForm: View {
    @Bindable var export: NotePDFExport

    var body: some View {
        Form {
            Section { NotePDFPreviewStrip(pages: export.previewPages, isPreparing: export.isPreparingPreview) }
            Section("Page") {
                Picker("Page Size", selection: $export.options.pageSize) {
                    ForEach(NotePDFPageSize.allCases) { size in Text(size.title).tag(size) }
                }
                Picker("Orientation", selection: $export.options.orientation) {
                    Text("Portrait").tag(PageOrientation.portrait)
                    Text("Landscape").tag(PageOrientation.landscape)
                }
                Picker("Margins", selection: $export.options.margins) {
                    ForEach(NotePDFMargins.allCases) { margins in Text(margins.title).tag(margins) }
                }
                Stepper(value: $export.options.downscalePercent, in: NotePDFOptions.downscalePercentRange, step: 5) {
                    LabeledContent("Downscale", value: "\(export.options.downscalePercent)%")
                }
            }
            Section("Content") {
                Toggle("Include File Name as Title", isOn: $export.options.includesFileNameAsTitle)
                Toggle("Include Properties", isOn: $export.options.includesProperties)
            }
        }
    }
}

/// The first pages of the PDF, small, side by side.
private struct NotePDFPreviewStrip: View {
    let pages: [NotePDFPreviewPage]
    let isPreparing: Bool

    var body: some View {
        HStack(spacing: 16) {
            if pages.isEmpty {
                ProgressView().frame(maxWidth: .infinity, minHeight: NotePDFExport.previewPageHeight)
            } else {
                ForEach(pages) { page in
                    Image(page.image, scale: 2, label: Text("Page \(page.pageIndex + 1)"))
                        .resizable().scaledToFit()
                        .frame(height: NotePDFExport.previewPageHeight)
                        .background(Color.white)
                        .shadow(color: .black.opacity(0.2), radius: 3, y: 1)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .opacity(isPreparing && !pages.isEmpty ? 0.5 : 1)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Preview of the first pages")
    }
}

/// How far the export is, with a way to stop it.
private struct NotePDFExportProgress: View {
    let fractionDone: Double
    let cancel: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            ProgressView("Making the PDF…", value: fractionDone)
            Button("Stop", role: .cancel, action: cancel)
        }
        .padding(24)
        .frame(maxWidth: 320)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}

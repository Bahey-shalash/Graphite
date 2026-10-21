/**
 * File: NotePDFPrinting.swift
 * ---------------------------
 * Layer: UI
 * Description: Hands a note's PDF to the system's print panel: NSPrintOperation on the Mac, where the panel's PDF
 *              menu also saves it, and UIPrintInteractionController on the iPad and iPhone.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 21/10/2026
 */

import Foundation
import PDFKit
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// The platform's print panel for a PDF made by `NotePDFRenderer`, which keeps its pages: the
/// paper is the PDF's page size, nothing is scaled.
@MainActor
enum NotePDFPrinting {
    static func showPrintPanel(for pdfData: Data, title: String) {
        #if canImport(UIKit)
        let printInfo = UIPrintInfo.printInfo()
        printInfo.jobName = title
        printInfo.outputType = .general
        let controller = UIPrintInteractionController.shared
        controller.printInfo = printInfo
        controller.printingItem = pdfData
        controller.present(animated: true)
        #else
        guard let document = PDFDocument(data: pdfData), let firstPage = document.page(at: 0) else { return }
        let printInfo = (NSPrintInfo.shared.copy() as? NSPrintInfo) ?? NSPrintInfo()
        let pageSize = firstPage.bounds(for: .cropBox).size
        printInfo.paperSize = pageSize
        printInfo.orientation = pageSize.width > pageSize.height ? .landscape : .portrait
        printInfo.topMargin = 0
        printInfo.bottomMargin = 0
        printInfo.leftMargin = 0
        printInfo.rightMargin = 0
        guard let operation = document.printOperation(for: printInfo, scalingMode: .pageScaleNone, autoRotate: true) else { return }
        operation.jobTitle = title
        operation.showsPrintPanel = true
        operation.showsProgressPanel = true
        if let window = NSApp.keyWindow ?? NSApp.mainWindow {
            operation.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
        } else {
            operation.run()
        }
        #endif
    }
}

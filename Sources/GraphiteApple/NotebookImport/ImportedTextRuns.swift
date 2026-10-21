import Foundation
import CoreText
import GraphiteCore
import NotebookImport
#if canImport(UIKit)
import UIKit
private typealias PlatformFont = UIFont
private typealias PlatformColor = UIColor
#else
import AppKit
private typealias PlatformFont = NSFont
private typealias PlatformColor = NSColor
#endif

/// An imported text's runs as Graphite's text runs (`PDFTextRun`), with what they could not keep: runs in a font this
/// device does not have (drawn in Helvetica, the font's name kept), and, for RTF, styles a text box does not draw.
struct ImportedTextRuns: Equatable {
    var runs: [PDFTextRun] = []
    var alignment: PDFTextAlignment = .left
    var fontsReplacedRunCount = 0
    var stylesNotKeptRunCount = 0

    init(runs: [PDFTextRun] = [], alignment: PDFTextAlignment = .left, fontsReplacedRunCount: Int = 0, stylesNotKeptRunCount: Int = 0) {
        self.runs = runs
        self.alignment = alignment
        self.fontsReplacedRunCount = fontsReplacedRunCount
        self.stylesNotKeptRunCount = stylesNotKeptRunCount
    }

    init(_ content: ImportedTextContent) {
        switch content {
        case .runs(let importedRuns): self.init(importedRuns)
        case .rtf(let rtf, let pointsPerUnit): self.init(rtf: rtf, pointsPerUnit: pointsPerUnit)
        }
    }

    init(_ importedRuns: [ImportedTextRun]) {
        for importedRun in importedRuns where !importedRun.text.isEmpty {
            let color = Self.textColor(importedRun.color)
            let attributes: PDFTextAttributes
            switch importedRun.font {
            case .family(let family):
                if !PDFTextBoxFonts.isAvailable(family: family) { fontsReplacedRunCount += 1 }
                attributes = PDFTextAttributes(fontFamily: family, fontSize: importedRun.sizeInPoints, color: color)
            case .postScriptName(let postScriptName):
                if !Self.isAvailable(postScriptName: postScriptName) { fontsReplacedRunCount += 1 }
                attributes = PDFTextBoxFonts.attributes(fromPostScriptName: postScriptName, size: importedRun.sizeInPoints, color: color)
            }
            runs.append(PDFTextRun(text: importedRun.text, attributes: PDFTextAttributes(
                fontFamily: attributes.fontFamily, fontSize: attributes.fontSize, color: color, isBold: attributes.isBold, isItalic: attributes.isItalic,
                isUnderlined: importedRun.isUnderlined, link: importedRun.link)))
        }
        runs = PDFTextRun.normalized(runs)
    }

    /// Goodnotes' older text boxes: Cocoa RTF read with the platform's RTF reader, its font sizes in Goodnotes units. A
    /// strike-through, raised or lowered text, a see-through colour, or a paragraph aligned otherwise than the first is a
    /// style not kept. RTF that does not read gives no runs.
    init(rtf: String, pointsPerUnit: Double) {
        guard let data = rtf.data(using: .utf8),
              let attributed = try? NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.rtf],
                                                       documentAttributes: nil) else { return } // RTF that does not read has no text to place
        let text = attributed.string as NSString
        var firstAlignment: NSTextAlignment?
        attributed.enumerateAttributes(in: NSRange(location: 0, length: attributed.length)) { attributes, range, _ in
            let runText = text.substring(with: range)
            guard !runText.isEmpty else { return }
            let font = attributes[.font] as? PlatformFont
            let color = (attributes[.foregroundColor] as? PlatformColor).flatMap(Self.importColor(of:))
            let isUnderlined = ((attributes[.underlineStyle] as? NSNumber)?.intValue ?? 0) != 0
            let alignment = (attributes[.paragraphStyle] as? NSParagraphStyle)?.alignment
            if firstAlignment == nil { firstAlignment = alignment ?? .natural }
            if ((attributes[.strikethroughStyle] as? NSNumber)?.intValue ?? 0) != 0 || ((attributes[.baselineOffset] as? NSNumber)?.doubleValue ?? 0) != 0
                || (color?.alpha ?? 1) < 1 || (alignment.map { alignment in alignment != firstAlignment } ?? false) {
                stylesNotKeptRunCount += 1
            }
            let link = (attributes[.link] as? URL) ?? (attributes[.link] as? String).flatMap(URL.init(string:))
            let postScriptName = font?.fontName ?? "Helvetica"
            let size = Double(font?.pointSize ?? 12) * pointsPerUnit
            let run = ImportedTextRun(text: runText, font: .postScriptName(postScriptName), sizeInPoints: size,
                                      color: color ?? NotebookImportColor(red: 0, green: 0, blue: 0, alpha: 1), isUnderlined: isUnderlined, link: link)
            let converted = ImportedTextRuns([run])
            runs += converted.runs
            fontsReplacedRunCount += converted.fontsReplacedRunCount
        }
        runs = PDFTextRun.normalized(runs)
        alignment = Self.alignment(firstAlignment)
    }

    var isEmpty: Bool { runs.allSatisfy { run in run.text.isEmpty } }

    /// Whether this device has a font of exactly this PostScript name; Core Text gives another font for a name it lacks.
    static func isAvailable(postScriptName: String) -> Bool {
        CTFontCopyPostScriptName(CTFontCreateWithName(postScriptName as CFString, 12, nil)) as String == postScriptName
    }

    private static func textColor(_ color: NotebookImportColor) -> PDFTextColor {
        PDFTextColor(red: color.red, green: color.green, blue: color.blue)
    }

    private static func importColor(of color: PlatformColor) -> NotebookImportColor? {
        guard let components = color.cgColor.converted(to: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                                       intent: .defaultIntent, options: nil)?.components, components.count >= 3 else { return nil }
        return NotebookImportColor(red: Double(components[0]), green: Double(components[1]), blue: Double(components[2]),
                                   alpha: components.count >= 4 ? Double(components[3]) : 1)
    }

    private static func alignment(_ alignment: NSTextAlignment?) -> PDFTextAlignment {
        switch alignment {
        case .center?: .center
        case .right?: .right
        case .justified?: .justified
        default: .left
        }
    }
}

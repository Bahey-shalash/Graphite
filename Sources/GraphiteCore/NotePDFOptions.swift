/**
 * File: NotePDFOptions.swift
 * --------------------------
 * Layer: Core
 * Description: The choices a note is exported to PDF with, as Obsidian's Export to PDF offers them (title, page size,
 *              orientation, margins, downscale, properties), and the page geometry they give.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 21/10/2026
 */

import CoreGraphics

/// The page sizes a note is exported on, as Obsidian's Export to PDF lists them.
public enum NotePDFPageSize: String, CaseIterable, Codable, Sendable, Identifiable {
    case a4, letter, a5, a3, legal, tabloid

    public var id: String { rawValue }

    /// Portrait size in PDF points (1/72 inch).
    public var portraitPointSize: CGSize {
        switch self {
        case .a4: NotebookPageSize.a4.portraitPointSize
        case .letter: NotebookPageSize.letter.portraitPointSize
        case .a5: NotebookPageSize.a5.portraitPointSize
        case .a3: NotebookPageSize.a3.portraitPointSize
        case .legal: CGSize(width: 612, height: 1008)
        case .tabloid: NotebookPageSize.tabloid.portraitPointSize
        }
    }

    public var title: String {
        switch self {
        case .a4: "A4"
        case .letter: "Letter"
        case .a5: "A5"
        case .a3: "A3"
        case .legal: "Legal"
        case .tabloid: "Tabloid"
        }
    }
}

/// The room left around the text of each page.
public enum NotePDFMargins: String, CaseIterable, Codable, Sendable, Identifiable {
    case standard, small, none

    public var id: String { rawValue }

    /// The margin on every side, in points: three quarters of an inch, about a third of
    /// an inch, or none.
    public var points: CGFloat {
        switch self {
        case .standard: 54
        case .small: 24
        case .none: 0
        }
    }

    public var title: String {
        switch self {
        case .standard: "Default"
        case .small: "Small"
        case .none: "None"
        }
    }
}

/// How a note is exported to PDF.
public struct NotePDFOptions: Codable, Equatable, Sendable {
    /// The note's name as a title above its text, as Obsidian's "Include file name as title".
    public var includesFileNameAsTitle = true
    public var pageSize = NotePDFPageSize.a4
    public var orientation = PageOrientation.portrait
    public var margins = NotePDFMargins.standard
    /// How large the note is drawn, from `downscalePercentRange`: 100 draws it at print size,
    /// lower values fit more on each page.
    public var downscalePercent = 100
    /// Whether the note's properties (frontmatter) are printed above its text; Obsidian leaves
    /// them out.
    public var includesProperties = false

    public static let downscalePercentRange = 50...100
    /// Screen points of the reading view drawn into one point of paper at 100 percent: a
    /// note's 16-point text prints at 12 points, as a browser prints a 16-pixel font.
    public static let printScale: CGFloat = 0.75
    /// The text size the note is laid out at before it is scaled to the paper.
    public static let layoutTextSize: Double = 16

    public init() {}

    /// Options kept by an earlier build may lack a later choice, which then takes its default.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = NotePDFOptions()
        includesFileNameAsTitle = try container.decodeIfPresent(Bool.self, forKey: .includesFileNameAsTitle) ?? defaults.includesFileNameAsTitle
        pageSize = try container.decodeIfPresent(NotePDFPageSize.self, forKey: .pageSize) ?? defaults.pageSize
        orientation = try container.decodeIfPresent(PageOrientation.self, forKey: .orientation) ?? defaults.orientation
        margins = try container.decodeIfPresent(NotePDFMargins.self, forKey: .margins) ?? defaults.margins
        downscalePercent = try container.decodeIfPresent(Int.self, forKey: .downscalePercent) ?? defaults.downscalePercent
        includesProperties = try container.decodeIfPresent(Bool.self, forKey: .includesProperties) ?? defaults.includesProperties
    }

    /// The page in points, turned for the orientation.
    public var pagePointSize: CGSize { orientation.applied(to: pageSize.portraitPointSize) }

    /// Where the text goes on each page, in points from the page's top left.
    public var contentRect: CGRect {
        CGRect(origin: .zero, size: pagePointSize).insetBy(dx: margins.points, dy: margins.points)
    }

    /// Points of paper per point of the laid-out note.
    public var layoutScale: CGFloat {
        let percent = min(max(downscalePercent, Self.downscalePercentRange.lowerBound), Self.downscalePercentRange.upperBound)
        return Self.printScale * CGFloat(percent) / 100
    }

    /// The width the note is laid out at, so that scaled by `layoutScale` it fills the text width.
    public var layoutWidth: CGFloat { contentRect.width / layoutScale }

    /// The height of one page's text in layout points.
    public var layoutPageHeight: CGFloat { contentRect.height / layoutScale }
}

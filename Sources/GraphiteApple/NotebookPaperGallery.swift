import Foundation
import GraphiteCore

/// One paper offered when creating a notebook: a template, and for ruled paper the line
/// spacing that makes it narrow or wide.
public enum NotebookPaperChoice: String, CaseIterable, Codable, Sendable, Identifiable {
    case blank, dotted, squared, ruledNarrow, ruledWide, cornell, engineering, isometric, music

    public var id: String { rawValue }

    public var template: PaperTemplate {
        switch self {
        case .blank: .blank
        case .dotted: .dotted
        case .squared: .grid
        case .ruledNarrow, .ruledWide: .ruled
        case .cornell: .cornell
        case .engineering: .engineering
        case .isometric: .isometric
        case .music: .music
        }
    }

    /// The spacing this choice sets, in points; nil when it keeps the chosen spacing.
    /// Narrow ruling is 6 mm and wide ruling 8 mm, both among the spacings Settings offers.
    public var spacingPoints: Double? {
        switch self {
        case .ruledNarrow: NotebookPaperGallery.ruledNarrowSpacingPoints
        case .ruledWide: NotebookPaperGallery.ruledWideSpacingPoints
        case .blank, .dotted, .squared, .cornell, .engineering, .isometric, .music: nil
        }
    }
}

/// The groups the New Notebook sheet shows its papers in.
public enum NotebookPaperSection: String, CaseIterable, Sendable, Identifiable {
    case essentials, study, music

    public var id: String { rawValue }

    public var choices: [NotebookPaperChoice] {
        switch self {
        case .essentials: [.blank, .dotted, .squared, .ruledNarrow, .ruledWide]
        case .study: [.cornell, .engineering, .isometric]
        case .music: [.music]
        }
    }
}

public enum NotebookPaperGallery {
    public static let ruledNarrowSpacingPoints = 17.01
    public static let ruledWideSpacingPoints = 22.68
}

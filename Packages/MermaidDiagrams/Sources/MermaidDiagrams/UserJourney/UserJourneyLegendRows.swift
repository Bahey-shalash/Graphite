import CoreGraphics

/// A user journey's legend arranged as Pele arranges it: one entry per actor, a dot then the name, side by side
/// 20 points apart, a new row 4 points below when the next entry would pass the row's width.
struct UserJourneyLegendRows {
    /// An entry and where it sits from the legend's top left corner.
    struct Entry {
        let seriesIndex: Int
        let text: DiagramTextBlock
        let offset: CGPoint
        let height: CGFloat
    }

    let entries: [Entry]
    /// The widest row's width and the rows' height.
    let size: CGSize

    /// From a dot's left edge to its name's.
    static let markWidth = 2 * UserJourneyGeometry.dotRadius + UserJourneyGeometry.dotTextGap

    /// The entries of `actorNames`, each name fitted within `rowWidth` less its dot.
    init(actorNames: [String], measurer: some DiagramTextMeasuring, rowWidth: CGFloat) {
        var entries: [Entry] = []
        var size = CGSize.zero
        var rowEnd: CGFloat = 0
        for (index, name) in actorNames.enumerated() {
            let text = TimelineTextFitting.fitted(DiagramLabelDecoder.label(from: name, form: .literal), measurer: measurer,
                                                  maximumWidth: rowWidth - Self.markWidth)
            let width = Self.markWidth + text.size.width
            if rowEnd > 0, rowEnd + width > rowWidth {
                rowEnd = 0
                size.height += UserJourneyGeometry.legendRowGap
            }
            let top = rowEnd > 0 ? entries.last?.offset.y ?? size.height : size.height
            let height = max(text.size.height, measurer.lineHeight)
            entries.append(Entry(seriesIndex: index, text: text, offset: CGPoint(x: rowEnd, y: top), height: height))
            rowEnd += width
            size.width = max(size.width, rowEnd)
            size.height = max(size.height, top + height)
            rowEnd += UserJourneyGeometry.legendEntryGap
        }
        self.entries = entries
        self.size = size
    }

    /// The entries with the legend's top left corner at `origin`, each dot and name centered on its entry's middle.
    func placed(at origin: CGPoint) -> [UserJourneyLegendEntry] {
        entries.map { entry in
            let middle = origin.y + entry.offset.y + entry.height / 2
            let left = origin.x + entry.offset.x
            var text = entry.text
            text.center = CGPoint(x: left + Self.markWidth + text.size.width / 2, y: middle)
            let dot = UserJourneyActorDot(center: CGPoint(x: left + UserJourneyGeometry.dotRadius, y: middle), seriesIndex: entry.seriesIndex)
            return UserJourneyLegendEntry(dot: dot, text: text)
        }
    }
}

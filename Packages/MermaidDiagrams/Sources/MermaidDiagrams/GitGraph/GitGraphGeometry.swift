import CoreGraphics

/// Pele's measurements of a Git graph, in points, and how its two axes lie on the page: the history runs along one,
/// the lanes stand side by side across it.
struct GitGraphGeometry {
    /// A commit dot's radius.
    static let dotRadius: CGFloat = 7
    /// The least distance between two commits along the history.
    static let commitStep: CGFloat = 44
    /// The least distance between two lanes.
    static let laneGap: CGFloat = 44
    /// How far a curve between lanes runs along the history: less than a step, so that it never runs through a commit
    /// on a lane it crosses.
    static let curveLength: CGFloat = 36
    /// The room kept between neighbours.
    static let gap: CGFloat = 8
    /// How far before the first commit a lane starts, its name's box ending there.
    static let laneLead: CGFloat = 20
    /// How far past the last commit a lane runs.
    static let laneTail: CGFloat = 20
    /// The length of a tag's point.
    static let tagPointLength: CGFloat = 7
    /// Between a tag's point and its text, and between its text and its end.
    static let tagTextLead: CGFloat = 4
    static let tagTextTail: CGFloat = 6
    /// Between a commit and its first tag.
    static let tagGap: CGFloat = 6
    /// Between two tags stacked above a commit, and between two tags in a row beside it.
    static let stackedTagGap: CGFloat = 3
    static let rowTagGap: CGFloat = 4
    /// Between a commit's dot and the corner of its turned id.
    static let labelOffset: CGFloat = 3
    /// The cosine and sine of an eighth of a turn, which a commit's id is turned by.
    static let eighthTurnCosine = CGFloat(0.5).squareRoot()
    /// Across a branch's name and down it, inside its box.
    static let nameBoxPadding = CGSize(width: 16, height: 4)
    /// Beyond a branch name's half width, how far the name reaches across a vertical graph's lane, and beyond its half
    /// height, across a horizontal one's.
    static let verticalNameReach: CGFloat = 8
    static let horizontalNameReach: CGFloat = 2
    /// How much wider than an id its patch is, and how much shorter.
    static let labelPatchOutset = CGSize(width: 4, height: -4)
    /// Beyond a commit's tags, how far before it a connector from a lane above joins its lane.
    static let tagClearance: CGFloat = 4
    /// The widest a name, an id or a tag is before it wraps: wide enough that it does not, as in Pele.
    static let wrappingWidth: CGFloat = 4_000

    let direction: GitGraphDirection

    var isVertical: Bool { direction != .leftToRight }

    /// The point `along` the history and `across` it: across runs right in a vertical graph and down in a horizontal
    /// one; along runs right, down, or up from the bottom.
    func point(along: CGFloat, across: CGFloat) -> CGPoint {
        switch direction {
        case .leftToRight: CGPoint(x: along, y: across)
        case .topToBottom: CGPoint(x: across, y: along)
        case .bottomToTop: CGPoint(x: across, y: -along)
        }
    }

    /// A tag's length: its point, its text and the room around the text.
    static func tagLength(_ text: DiagramTextBlock) -> CGFloat {
        tagPointLength + tagTextLead + text.size.width + tagTextTail
    }
}

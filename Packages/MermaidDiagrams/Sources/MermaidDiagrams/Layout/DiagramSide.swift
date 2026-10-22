/// A side of a node's bounding box.
enum DiagramSide: CaseIterable {
    case top, right, bottom, left

    var isHorizontal: Bool {
        switch self {
        case .top, .bottom: true
        case .right, .left: false
        }
    }
}

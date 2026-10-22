import CoreGraphics
@testable import MermaidDiagrams

extension DiagramPath {
    /// Every point the path is drawn through or pulled toward, for tests that check where a path goes.
    var allPoints: [CGPoint] {
        [start] + segments.flatMap { segment in
            switch segment {
            case .line(let end): [end]
            case .curve(let end, let firstControl, let secondControl): [firstControl, secondControl, end]
            }
        }
    }
}

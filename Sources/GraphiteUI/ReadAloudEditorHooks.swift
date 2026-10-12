import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// What the note editor does for Read Aloud: a tap while the note is read moves reading there
/// (or marks a range end), "Read from Here" in the edit menu starts reading at the cursor, and
/// the editor tells Read Aloud its first visible line and where the highlight is on screen.
struct ReadAloudEditorHooks {
    let isReadingThisNote: Bool
    let tapped: (Int) -> Void
    let readFromHere: (Int) -> Void
    let registerVisibleLocation: (@escaping () -> Int?) -> Void
    let reportHighlightFrame: (CGRect?, CGRect?) -> Void
}

#if canImport(UIKit)
/// Lets the reading tap be seen alongside the text view's own taps, which still place the
/// cursor and follow links.
final class SimultaneousTapDelegate: NSObject, UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { true }
}
#endif

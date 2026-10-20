#if canImport(UIKit)
import XCTest
import UIKit
@testable import GraphiteUI

/// The share sheet's "Add to Note" action: the activity type is the identifier other code
/// and the system's share sheet know it by.
@MainActor
final class AddToNoteActivityTypeTests: XCTestCase {
    func testTheActivityTypeIsTheAddToNoteIdentifierAndTheTitleNamesTheNote() {
        let destination = LassoNoteDestination(noteName: "Lecture 3", addImage: { _, _ in })
        let activity = AddToNoteActivity(destination: destination, image: UIImage(), name: "Lecture 3, page 4")
        XCTAssertEqual(activity.activityType?.rawValue, "com.graphite.study.addToNote")
        XCTAssertEqual(activity.activityTitle, "Add to “Lecture 3”")
        XCTAssertEqual(AddToNoteActivity.activityCategory, .action)
    }
}
#endif

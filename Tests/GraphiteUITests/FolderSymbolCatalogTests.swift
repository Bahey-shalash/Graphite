import XCTest
#if canImport(AppKit)
import AppKit
#else
import UIKit
#endif
@testable import GraphiteUI

final class FolderSymbolCatalogTests: XCTestCase {
    /// A name the system does not have would be a blank button in the popover.
    func testEverySymbolExistsOnThisSystem() {
        for section in FolderSymbolCatalog.sections {
            for symbolName in section.symbolNames {
                #if canImport(AppKit)
                let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
                #else
                let image = UIImage(systemName: symbolName)
                #endif
                XCTAssertNotNil(image, "\(symbolName) in \(section.title)")
            }
        }
    }

    func testEachSymbolIsListedOnce() {
        let symbolNames = FolderSymbolCatalog.sections.flatMap(\.symbolNames)
        XCTAssertEqual(Set(symbolNames).count, symbolNames.count)
    }

    func testFinderSectionsInFindersOrder() {
        XCTAssertEqual(FolderSymbolCatalog.sections.map(\.title),
                       ["People", "Animals & Nature", "Food & Drink", "Activity", "Travel & Places", "Objects", "Symbols"])
    }

    func testSpokenNamesLeaveOutTheFillVariant() {
        XCTAssertEqual(FolderSymbolCatalog.spokenName(of: "books.vertical.fill"), "books vertical")
        XCTAssertEqual(FolderSymbolCatalog.spokenName(of: "person.2.fill"), "person 2")
    }
}

import XCTest
import UniformTypeIdentifiers
import CoreTransferable
@testable import GraphiteUI

/// What a dragged vault item, tab or PDF page carries: JSON under the type Info.plist
/// declares, read back by the drop targets of the same build.
final class VaultItemTransferPersistedFormatTests: XCTestCase {
    func testAVaultItemIsTheJSONObjectWithItsPath() throws {
        let encoded = try JSONEncoder().encode(VaultItemTransfer(path: "Course/Week 1.md"))
        XCTAssertEqual(String(decoding: encoded, as: UTF8.self), #"{"path":"Course\/Week 1.md"}"#)
        XCTAssertEqual(try JSONDecoder().decode(VaultItemTransfer.self, from: Data(#"{"path":"Inbox.md"}"#.utf8)).path, "Inbox.md")
    }

    func testTheSwiftUIDragExportsTheSameBytesUnderTheVaultItemType() async throws {
        let item = VaultItemTransfer(path: "Course/Week 1.md")
        let exported = try await item.exported(as: .graphiteVaultItem)
        XCTAssertEqual(exported, try JSONEncoder().encode(item))
        XCTAssertEqual(try JSONDecoder().decode(VaultItemTransfer.self, from: exported).path, item.path)
    }

    func testATabAndAPDFPageAreExportedAsJSONUnderTheirOwnTypes() async throws {
        let tabIdentifier = try XCTUnwrap(UUID(uuidString: "11111111-2222-3333-4444-555555555555"))
        let tab = TabTransfer(tabID: tabIdentifier)
        let exportedTab = try await tab.exported(as: .graphiteTab)
        XCTAssertEqual(exportedTab, try JSONEncoder().encode(tab))
        XCTAssertEqual(try JSONSerialization.jsonObject(with: exportedTab) as? [String: String], ["tabID": "11111111-2222-3333-4444-555555555555"])

        let page = PDFPageDragItem(sessionIdentifier: tabIdentifier, pageIndex: 3)
        let exportedPage = try await page.exported(as: .graphitePDFPage)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: exportedPage) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["sessionIdentifier", "pageIndex"])
        XCTAssertEqual(object["sessionIdentifier"] as? String, "11111111-2222-3333-4444-555555555555")
        XCTAssertEqual(object["pageIndex"] as? Int, 3)
    }
}

#if os(macOS)
import AppKit
import GraphiteCore

/// The Mac's file tree writes the same bytes to the pasteboard that the SwiftUI sidebar drags.
@MainActor
final class MacFileTreeDragFormatTests: XCTestCase {
    func testARowIsWrittenToThePasteboardAsTheVaultItemTheSidebarDrags() throws {
        let controller = FileTreeController(workspace: WorkspaceModel())
        let node = FileTreeNode(entry: VaultEntry(path: try VaultPath("Course/Week 1.md"), isDirectory: false, size: 10, modified: .now), parent: nil)
        let writer = try XCTUnwrap(controller.outlineView(NSOutlineView(), pasteboardWriterForItem: node) as? NSPasteboardItem)

        XCTAssertEqual(FileTreeController.vaultItemType.rawValue, "com.graphite.study.vault-item")
        XCTAssertEqual(writer.types, [FileTreeController.vaultItemType])
        XCTAssertEqual(writer.data(forType: FileTreeController.vaultItemType), try JSONEncoder().encode(VaultItemTransfer(path: "Course/Week 1.md")))
    }
}
#endif

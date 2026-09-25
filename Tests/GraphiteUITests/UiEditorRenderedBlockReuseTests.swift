import XCTest
import GraphiteCore
import GraphiteIndex
@testable import GraphiteUI

/// Reusing rendered blocks' views (P8), refreshing only the blocks that read the index
/// after a save (P39), and heights shared between editors (P43).
@MainActor
final class UiEditorRenderedBlockReuseTests: XCTestCase {
    private let note = """
    ---
    title: Reuse
    ---
    | a | b |
    | - | - |
    | 1 | 2 |

    $$
    x^2
    $$

    ![[Diagram.png]]

    ![[Lecture.m4a]]

    > [!note] Callout
    > Body

    ```base
    views: []
    ```

    ---
    """ as NSString

    private var blocks: [LivePreviewBlock] { LivePreviewBlockScanner.blocks(in: note) }

    private func key(ofBlockAt index: Int) -> LivePreviewBlockKey {
        LivePreviewBlockKey.keys(for: blocks)[index]
    }

    private var databaseDirectory: URL?

    override func tearDown() async throws {
        if let databaseDirectory { try? FileManager.default.removeItem(at: databaseDirectory) }
        databaseDirectory = nil
        try await super.tearDown()
    }

    private func environment(indexVersion: Int = 0, textSize: Double = 17, isIndexComplete: Bool = false) throws -> LivePreviewEnvironment {
        let root = FileManager.default.temporaryDirectory
        let directory = databaseDirectory ?? root.appendingPathComponent("Index-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        databaseDirectory = directory
        let index = try VaultIndex(databaseURL: directory.appendingPathComponent("Index-\(UUID().uuidString).sqlite"))
        let context = BaseEmbedContext(store: VaultStore(root: root), index: index, embeddingNote: try VaultPath("Note.md"),
                                       contentVersion: indexVersion, isIndexComplete: isIndexComplete, open: { _ in })
        return LivePreviewEnvironment(root: root, textSize: textSize, colorsEnabled: true, paletteHexByName: ["red": "#ff0000"], drawingVersion: 0,
                                      resolve: { _, _ in nil }, open: { _ in }, follow: { _, _ in }, updateProperties: { _ in },
                                      baseContext: context, indexVersion: indexVersion)
    }

    // MARK: Refreshing after a save (P39)

    func testASaveChangesOnlyTheIndexPartOfTheSignature() throws {
        let beforeSave = LivePreviewWidgetSignature(environment: try environment(indexVersion: 4), accentHex: "#7c3aed", notePath: "Note.md")
        let afterSave = LivePreviewWidgetSignature(environment: try environment(indexVersion: 5), accentHex: "#7c3aed", notePath: "Note.md")
        XCTAssertEqual(beforeSave.appearance, afterSave.appearance)
        XCTAssertNotEqual(beforeSave.index, afterSave.index)

        let indexComplete = LivePreviewWidgetSignature(environment: try environment(indexVersion: 4, isIndexComplete: true), accentHex: "#7c3aed", notePath: "Note.md")
        XCTAssertEqual(beforeSave.appearance, indexComplete.appearance)
        XCTAssertNotEqual(beforeSave.index, indexComplete.index)
    }

    func testTextSizeAccentAndRenamingChangeTheAppearance() throws {
        let signature = LivePreviewWidgetSignature(environment: try environment(), accentHex: "#7c3aed", notePath: "Note.md")
        XCTAssertNotEqual(signature.appearance, LivePreviewWidgetSignature(environment: try environment(textSize: 20), accentHex: "#7c3aed", notePath: "Note.md").appearance)
        XCTAssertNotEqual(signature.appearance, LivePreviewWidgetSignature(environment: try environment(), accentHex: "#0ea5e9", notePath: "Note.md").appearance)
        XCTAssertNotEqual(signature.appearance, LivePreviewWidgetSignature(environment: try environment(), accentHex: "#7c3aed", notePath: "Renamed.md").appearance)
        XCTAssertEqual(LivePreviewWidgetSignature(environment: nil, accentHex: "#7c3aed", notePath: "Note.md"),
                       LivePreviewWidgetSignature(environment: nil, accentHex: "#0ea5e9", notePath: "Other.md"))
    }

    /// Bases and embeds read the index, and a callout can contain either; tables, math,
    /// properties, and rules do not.
    func testOnlyBasesEmbedsAndCalloutsReadTheIndex() {
        let readingKinds = blocks.map { block in LivePreviewWidgetSignature.readsIndex(block.kind) }
        XCTAssertEqual(blocks.count, 8)
        XCTAssertEqual(readingKinds, [false, false, false, true, true, true, true, false])
    }

    // MARK: Views kept off screen (P8)

    func testAViewTakenOffScreenIsShownAgain() {
        var pool = DetachedWidgetPool<String>(budgetMegabytes: 24)
        pool.keep("table view", for: key(ofBlockAt: 1), estimatedMegabytes: 6)
        XCTAssertEqual(pool.host(for: key(ofBlockAt: 1)), "table view")
        XCTAssertEqual(pool.take(key(ofBlockAt: 1)), "table view")
        XCTAssertNil(pool.take(key(ofBlockAt: 1)))
        XCTAssertTrue(pool.isEmpty)
    }

    func testTheViewsTakenOffLongestAgoGoFirstPastTheBudget() {
        var pool = DetachedWidgetPool<String>(budgetMegabytes: 12)
        pool.keep("properties", for: key(ofBlockAt: 0), estimatedMegabytes: 4)
        pool.keep("table", for: key(ofBlockAt: 1), estimatedMegabytes: 6)
        pool.keep("math", for: key(ofBlockAt: 2), estimatedMegabytes: 1)
        XCTAssertEqual(pool.keys, [key(ofBlockAt: 0), key(ofBlockAt: 1), key(ofBlockAt: 2)])

        pool.keep("image", for: key(ofBlockAt: 3), estimatedMegabytes: 6)
        XCTAssertEqual(pool.keys, [key(ofBlockAt: 2), key(ofBlockAt: 3)])
        XCTAssertNil(pool.host(for: key(ofBlockAt: 0)))

        // A view kept again moves to the end instead of being counted twice.
        pool.keep("math", for: key(ofBlockAt: 2), estimatedMegabytes: 1)
        pool.keep("callout", for: key(ofBlockAt: 5), estimatedMegabytes: 1)
        XCTAssertEqual(pool.keys, [key(ofBlockAt: 3), key(ofBlockAt: 2), key(ofBlockAt: 5)])
    }

    func testViewsOfBlocksNoLongerInTheNoteAreDropped() {
        var pool = DetachedWidgetPool<String>(budgetMegabytes: 24)
        pool.keep("table", for: key(ofBlockAt: 1), estimatedMegabytes: 6)
        pool.keep("math", for: key(ofBlockAt: 2), estimatedMegabytes: 1)
        pool.removeHosts(notIn: [key(ofBlockAt: 2)])
        XCTAssertEqual(pool.keys, [key(ofBlockAt: 2)])
        pool.removeAll()
        XCTAssertTrue(pool.isEmpty)
    }

    /// A player kept off screen could go on playing, so audio and video are built again.
    func testPlayersAreNeverKept() {
        let estimates = blocks.map { block in DetachedWidgetPool<String>.estimatedMegabytes(of: block.kind) }
        XCTAssertNotNil(estimates[3], "image embed")
        XCTAssertNil(estimates[4], "audio embed")
        XCTAssertTrue(estimates.enumerated().allSatisfy { index, estimate in index == 4 || estimate != nil })
    }

    // MARK: Heights shared between editors (P43)

    func testHeightsHoldForOneWidthAndTextSize() throws {
        var cache = MeasuredBlockHeightCache(capacity: 10)
        let measuredKey = try XCTUnwrap(MeasuredBlockHeightCache.Key(blockKey: key(ofBlockAt: 1), columnWidth: 684.4, textSize: 17))
        cache.record(212, for: measuredKey)
        XCTAssertEqual(cache.height(for: try XCTUnwrap(MeasuredBlockHeightCache.Key(blockKey: key(ofBlockAt: 1), columnWidth: 684, textSize: 17))), 212)
        XCTAssertNil(cache.height(for: try XCTUnwrap(MeasuredBlockHeightCache.Key(blockKey: key(ofBlockAt: 1), columnWidth: 500, textSize: 17))))
        XCTAssertNil(cache.height(for: try XCTUnwrap(MeasuredBlockHeightCache.Key(blockKey: key(ofBlockAt: 1), columnWidth: 684, textSize: 20))))
        XCTAssertNil(cache.height(for: try XCTUnwrap(MeasuredBlockHeightCache.Key(blockKey: key(ofBlockAt: 2), columnWidth: 684, textSize: 17))))
    }

    func testAWidthBeforeLayoutHasNoKey() {
        XCTAssertNil(MeasuredBlockHeightCache.Key(blockKey: key(ofBlockAt: 1), columnWidth: .nan, textSize: 17))
        XCTAssertNil(MeasuredBlockHeightCache.Key(blockKey: key(ofBlockAt: 1), columnWidth: .infinity, textSize: 17))
        XCTAssertNil(MeasuredBlockHeightCache.Key(blockKey: key(ofBlockAt: 1), columnWidth: -40, textSize: 17))
        XCTAssertNil(MeasuredBlockHeightCache.Key(blockKey: key(ofBlockAt: 1), columnWidth: 0, textSize: 17))
    }

    func testTheCacheStaysWithinItsCapacityDroppingTheOldestHeights() throws {
        var cache = MeasuredBlockHeightCache(capacity: 8)
        let keys = try (1...40).map { width in try XCTUnwrap(MeasuredBlockHeightCache.Key(blockKey: key(ofBlockAt: 1), columnWidth: CGFloat(width), textSize: 17)) }
        for (index, measuredKey) in keys.enumerated() {
            cache.record(CGFloat(index + 100), for: measuredKey)
            XCTAssertLessThanOrEqual(cache.count, 8)
        }
        XCTAssertEqual(cache.height(for: keys[39]), 139)
        XCTAssertNil(cache.height(for: keys[0]))

        // Recording a height again updates it without growing the cache.
        let countBefore = cache.count
        cache.record(500, for: keys[39])
        XCTAssertEqual(cache.count, countBefore)
        XCTAssertEqual(cache.height(for: keys[39]), 500)
    }
}

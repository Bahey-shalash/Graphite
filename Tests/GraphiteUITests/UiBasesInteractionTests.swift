import XCTest
import MapKit
import Observation
import ImageIO
import UniformTypeIdentifiers
import GraphiteCore
import GraphiteIndex
@testable import GraphiteUI

@MainActor
final class UiBasesInteractionTests: XCTestCase {
    private var vault: URL!
    private var index: VaultIndex!
    private var store: VaultStore!

    override func setUp() async throws {
        vault = FileManager.default.temporaryDirectory.appendingPathComponent("UiBasesInteractionVault-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        index = try VaultIndex(databaseURL: vault.appendingPathExtension("cache").appendingPathComponent("index.sqlite"))
        store = VaultStore(root: vault)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: vault)
        try? FileManager.default.removeItem(at: vault.appendingPathExtension("cache"))
    }

    private func write(_ text: String, to relativePath: String) throws {
        let location = vault.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: location.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: location)
    }

    private func loadedModel(basePath: String) async throws -> BaseDocumentModel {
        _ = try await index.reconcile(root: vault)
        let path = try VaultPath(basePath)
        let model = BaseDocumentModel(source: .file(path), contextPath: path, store: store, index: index)
        await model.reload()
        XCTAssertNil(model.loadErrorMessage)
        return model
    }

    private func cellValue(_ model: BaseDocumentModel, row rowName: String, column property: BasePropertyIdentifier) -> BaseValue? {
        guard let result = model.result, let columnPosition = result.columns.firstIndex(where: { column in column.property == property }),
              let row = result.rows.first(where: { row in row.path.name == rowName }) else { return nil }
        return row.cells[columnPosition].value
    }

    // MARK: Checkboxes

    func testASecondQuickCheckboxTapUndoesTheFirst() async throws {
        try write("---\ndone: false\n---\nBody\n", to: "Tasks/Task.md")
        try write("filters: 'file.inFolder(\"Tasks\")'\nviews:\n  - type: table\n    name: Table\n    order: [file.name, note.done]\n", to: "Tasks.base")
        let model = try await loadedModel(basePath: "Tasks.base")
        let request = BaseEditRequest(path: try VaultPath("Tasks/Task.md"), property: .note("done"), displayName: "done", kind: .checkbox,
                                      currentValue: .boolean(false))

        let firstTap = Task { await model.toggleCheckbox(request, shownValue: false) }
        while model.requestedCheckboxValues[request.id] == nil { await Task.yield() }
        XCTAssertEqual(model.requestedCheckboxValues[request.id], true)
        // The cell still shows the stored value while the first save runs.
        let secondTap = Task { await model.toggleCheckbox(request, shownValue: false) }
        await firstTap.value
        await secondTap.value

        let noteText = try String(contentsOf: vault.appendingPathComponent("Tasks/Task.md"), encoding: .utf8)
        XCTAssertTrue(noteText.contains("done: false"), noteText)
        XCTAssertTrue(model.requestedCheckboxValues.isEmpty)
        XCTAssertNil(model.actionErrorMessage)
        XCTAssertEqual(cellValue(model, row: "Task.md", column: .note("done")), .boolean(false))
    }

    // MARK: Reloading

    func testAReloadWithUnchangedContentDoesNotPublishTheResultAgain() async throws {
        try write("---\nstatus: open\n---\n", to: "Notes/A.md")
        try write("---\nstatus: done\n---\n", to: "Notes/B.md")
        try write("filters: 'file.inFolder(\"Notes\")'\nviews:\n  - type: table\n    name: Table\n    order: [file.name, note.status]\n", to: "Notes.base")
        let model = try await loadedModel(basePath: "Notes.base")

        let resultChanges = ChangeCounter()
        withObservationTracking { _ = model.result } onChange: { MainActor.assumeIsolated { resultChanges.count += 1 } }
        try write("unrelated", to: "Elsewhere.md")
        try await index.refresh(paths: [VaultPath("Elsewhere.md")], root: vault)
        await model.reload()
        await Task.yield()
        XCTAssertEqual(resultChanges.count, 0, "An unchanged result is not published again.")

        try write("---\nstatus: blocked\n---\n", to: "Notes/A.md")
        try await index.refresh(paths: [VaultPath("Notes/A.md")], root: vault)
        await model.reload()
        await Task.yield()
        XCTAssertEqual(resultChanges.count, 1)
        XCTAssertEqual(cellValue(model, row: "A.md", column: .note("status")), .string("blocked"))
    }

    func testDeclaredTypesAreFoundWhateverTheirCapitalization() async throws {
        try write("{\"types\": {\"Rating\": \"number\"}}", to: ".obsidian/types.json")
        try write("---\nrating: \"4\"\n---\n", to: "Book.md")
        try write("views:\n  - type: table\n    name: Table\n", to: "Books.base")
        let model = try await loadedModel(basePath: "Books.base")
        XCTAssertEqual(model.editorKind(for: .note("rating"), currentValue: .string("4")), .number)
        XCTAssertEqual(model.editorKind(for: .note("Rating"), currentValue: .string("4")), .number)
        XCTAssertEqual(model.editorKind(for: .note("title"), currentValue: .string("Dune")), .text)
    }

    func testTheEmbeddedModelCacheKeepsRecentModelsUpToItsCapacity() throws {
        let cache = EmbeddedBaseModelCache()
        let note = try VaultPath("Note.md")
        func identity(_ number: Int) -> EmbeddedBaseView.EmbedIdentity {
            EmbeddedBaseView.EmbedIdentity(source: .inline("views: []\n# \(number)"), embeddingNote: note, viewName: nil)
        }
        func makeModel(_ number: Int) -> BaseDocumentModel {
            BaseDocumentModel(source: .inline("views: []\n# \(number)"), contextPath: note, store: store, index: index)
        }
        let firstModel = cache.model(for: identity(0)) { makeModel(0) }
        XCTAssertTrue(cache.model(for: identity(0)) { makeModel(0) } === firstModel)
        for number in 1...8 { _ = cache.model(for: identity(number)) { makeModel(number) } }
        XCTAssertFalse(cache.model(for: identity(0)) { makeModel(0) } === firstModel, "The least recently used model is dropped.")
    }

    // MARK: Tags

    func testHexLookingTagsShowAsTagsWhereValuesAreTags() {
        XCTAssertFalse(BaseValueView.isTag("#cafe"), "Outside tag lists a short hex string is taken for a color.")
        XCTAssertFalse(BaseValueView.isTag("#ff0000"))
        XCTAssertTrue(BaseValueView.isTag("#cafe", isKnownTag: true))
        XCTAssertTrue(BaseValueView.isTag("#bad", isKnownTag: true))
        XCTAssertTrue(BaseValueView.isTag("#lecture/recorded"))
        XCTAssertTrue(BaseValueView.isTag("#y2024"))
        XCTAssertFalse(BaseValueView.isTag("##"))
        XCTAssertFalse(BaseValueView.isTag("#1"))
        XCTAssertFalse(BaseValueView.isTag("#2024", isKnownTag: true), "Obsidian tags need a character other than a digit.")
        XCTAssertFalse(BaseValueView.isTag("#two words"))
        XCTAssertTrue(BasePropertyIdentifier.file("tags").holdsTags)
        XCTAssertFalse(BasePropertyIdentifier.note("tags").holdsTags)
    }

    // MARK: Map camera

    func testMarkersAcrossTheAntimeridianCenterOnIt() {
        let center = BaseMapView.centerCoordinate(of: [CLLocationCoordinate2D(latitude: -17, longitude: 179.5), CLLocationCoordinate2D(latitude: -19, longitude: -179.5)])
        XCTAssertEqual(center.latitude, -18, accuracy: 0.000_1)
        XCTAssertEqual(abs(center.longitude), 180, accuracy: 0.000_1)
        let ordinaryCenter = BaseMapView.centerCoordinate(of: [CLLocationCoordinate2D(latitude: 46, longitude: 6), CLLocationCoordinate2D(latitude: 48, longitude: 2)])
        XCTAssertEqual(ordinaryCenter.latitude, 47, accuracy: 0.000_1)
        XCTAssertEqual(ordinaryCenter.longitude, 4, accuracy: 0.000_1)
        let pacificCenter = BaseMapView.centerCoordinate(of: [CLLocationCoordinate2D(latitude: 0, longitude: 170), CLLocationCoordinate2D(latitude: 0, longitude: -160)])
        XCTAssertEqual(pacificCenter.longitude, -175, accuracy: 0.000_1)
    }

    func testALowZoomInALargeViewStaysWithinTheGlobe() {
        let paris = CLLocationCoordinate2D(latitude: 48.85, longitude: 2.35)
        for zoom in [0.0, 1, 2] {
            let region = BaseMapView.region(center: paris, zoom: zoom, size: CGSize(width: 1180, height: 820))
            XCTAssertLessThanOrEqual(region.span.latitudeDelta, 180)
            XCTAssertLessThanOrEqual(region.span.longitudeDelta, 360)
            XCTAssertGreaterThan(region.span.latitudeDelta, 0)
        }
        let cityRegion = BaseMapView.region(center: paris, zoom: 12, size: CGSize(width: 1180, height: 820))
        let unclampedCityRegion = MKCoordinateRegion(center: paris, latitudinalMeters: 156_543.033_92 * cos(48.85 * .pi / 180) / 4_096 * 820,
                                                     longitudinalMeters: 156_543.033_92 * cos(48.85 * .pi / 180) / 4_096 * 1180)
        XCTAssertEqual(cityRegion.span.latitudeDelta, unclampedCityRegion.span.latitudeDelta, accuracy: 0.000_001)
        XCTAssertEqual(cityRegion.span.longitudeDelta, unclampedCityRegion.span.longitudeDelta, accuracy: 0.000_001)
    }

    // MARK: Remote images

    func testImagesFromURLsAreDownsampledLikeVaultImages() async throws {
        let location = vault.appendingPathComponent("Large.png")
        try Self.pngData(width: 2_000, height: 1_000).write(to: location)
        let thumbnail = try await BaseThumbnailStore.downloadedThumbnail(at: location, maximumDimension: 640)
        XCTAssertEqual(thumbnail.width, 640)
        XCTAssertEqual(thumbnail.height, 320)
        XCTAssertThrowsError(try BaseThumbnailStore.downsampledImage(from: Data("not an image".utf8), maximumDimension: 640))
    }

    private static func pngData(width: Int, height: Int) throws -> Data {
        let colorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try XCTUnwrap(context.makeImage())
        let output = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return output as Data
    }
}

@MainActor
private final class ChangeCounter {
    var count = 0
}

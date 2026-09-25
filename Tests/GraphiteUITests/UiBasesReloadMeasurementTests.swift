import XCTest
import GraphiteCore
import GraphiteIndex
@testable import GraphiteUI

@MainActor
final class UiBasesReloadMeasurementTests: XCTestCase {
    func testMeasureRepeatedReloadOfLargeBase() async throws {
        guard ProcessInfo.processInfo.environment["GRAPHITE_MEASURE_BASES"] != nil else { throw XCTSkip("Set GRAPHITE_MEASURE_BASES to measure.") }
        let vault = FileManager.default.temporaryDirectory.appendingPathComponent("MeasureVault-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault.appendingPathComponent("Books"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault); try? FileManager.default.removeItem(at: vault.appendingPathExtension("cache")) }
        for noteNumber in 0..<5_000 {
            try Data("---\nstatus: reading\nrating: \(noteNumber % 5)\nauthor: Author \(noteNumber)\n---\nBody \(noteNumber)\n".utf8)
                .write(to: vault.appendingPathComponent("Books/Book \(noteNumber).md"))
        }
        try Data("views:\n  - type: table\n    name: Table\n    order: [file.name, note.status, note.rating, note.author]\n    sort:\n      - property: note.rating\n        direction: DESC\n".utf8)
            .write(to: vault.appendingPathComponent("Books.base"))
        let index = try VaultIndex(databaseURL: vault.appendingPathExtension("cache").appendingPathComponent("index.sqlite"))
        _ = try await index.reconcile(root: vault)
        let store = VaultStore(root: vault)
        let basePath = try VaultPath("Books.base")
        let model = BaseDocumentModel(source: .file(basePath), contextPath: basePath, store: store, index: index)
        let clock = ContinuousClock()
        let firstDuration = await clock.measure { await model.reload() }
        var repeatedDurations: [Duration] = []
        for _ in 0..<5 { repeatedDurations.append(await clock.measure { await model.reload() }) }
        let definition = try XCTUnwrap(model.definition)
        let environment = BaseEvaluationEnvironment(now: .now, calendar: BaseDateFormatting.displayCalendar, declaredTypes: [:])
        let thisRecord = BaseFileRecord(path: basePath, size: 0, createdDate: .now, modifiedDate: .now)
        let provider = index.baseRecordProvider
        let prefilter = BaseRecordPrefilter.extract(from: [], definition: definition, environment: environment, thisRecord: thisRecord, provider: provider)
        var batch: BaseRecordBatch?
        let loadDuration = await clock.measure { batch = try? await index.baseRecords(matching: prefilter) }
        let records = try XCTUnwrap(batch).records
        let evaluationDuration = clock.measure { _ = BaseQueryEngine(definition: definition, environment: environment, thisRecord: thisRecord, provider: provider).run(viewIndex: 0, records: records, sortOverride: nil) }
        print("MEASURE load \(loadDuration) evaluate \(evaluationDuration)")
        print("MEASURE first reload \(firstDuration) repeated \(repeatedDurations)")
        XCTAssertEqual(model.result?.displayedCount, 5_000)
    }
}

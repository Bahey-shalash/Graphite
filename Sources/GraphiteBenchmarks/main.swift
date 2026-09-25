import Foundation
import GraphiteCore
import GraphiteIndex

@main
struct GraphiteBenchmarks {
    static let defaultRecordCount = 10_000
    static let allowedRecordCounts = 1...1_000_000
    /// Results `VaultIndex.search` returns on its first page.
    static let searchPageSize = 50
    static let usage = "Usage: GraphiteBenchmarks [record count, a whole number from 1 to 1000000; default 10000]"

    /// A query timed against the synthetic notes, with the notes it must find, so a query
    /// that silently stops matching cannot report a fast time.
    struct TimedQuery {
        let text: String
        let matchesNote: @Sendable (_ noteNumber: Int) -> Bool
    }

    // Queries the index answers alone, and ones whose candidates are checked one by one.
    static let timedQueries: [TimedQuery] = [
        TimedQuery(text: "-quantization") { _ in false },
        TimedQuery(text: "quantization OR nothing") { _ in true },
        TimedQuery(text: "path:\"Course 7/\" sampling") { noteNumber in noteNumber % 100 == 7 },
        TimedQuery(text: "\"sampling theorem\"") { _ in true },
        TimedQuery(text: "line:(quantization sampling)") { _ in true },
        TimedQuery(text: "line:(quantization engineering)") { _ in true },
        // A note's text names its own lecture and links the one before it.
        TimedQuery(text: "/Lecture 9\\d+/") { noteNumber in
            isNineFollowedByDigits(noteNumber) || isNineFollowedByDigits(max(0, noteNumber - 1))
        }
    ]

    static func main() async throws {
        guard let requestedCount = recordCount(fromArguments: Array(CommandLine.arguments.dropFirst())) else {
            FileHandle.standardError.write(Data((usage + "\n").utf8))
            exit(EX_USAGE)
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("GraphiteBenchmark-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let index = try VaultIndex(databaseURL: directory.appendingPathComponent("index.sqlite"))
        let clock = ContinuousClock()
        let started = clock.now
        for batchStart in stride(from: 0, to: requestedCount, by: 64) {
            var files: [IndexedFile] = []
            for noteNumber in batchStart..<min(batchStart + 64, requestedCount) {
                let path = try VaultPath("Course \(noteNumber % 100)/Lecture \(noteNumber).md")
                files.append(IndexedFile(path: path, size: 200, modified: .now, markdown: "# Lecture \(noteNumber)\n\nQuantization signal processing sampling theorem. #engineering\n\nSee [[Lecture \(max(0, noteNumber - 1))]]."))
            }
            try await index.update(files, generation: "benchmark")
        }
        let indexingDuration = started.duration(to: clock.now)
        var searchDurations: [Double] = []
        for _ in 0..<100 {
            let searchStart = clock.now
            let results = try await index.search("quantization").results
            guard results.count == min(searchPageSize, requestedCount) else { throw GraphiteError.invalidFile("Unexpected search count.") }
            searchDurations.append(milliseconds(searchStart.duration(to: clock.now)))
        }
        searchDurations.sort()
        print("Synthetic index records: \(requestedCount)")
        print("Indexing: \(indexingDuration)")
        for query in timedQueries {
            let expectedCount = min(searchPageSize, (0..<requestedCount).count(where: query.matchesNote))
            var durations: [Double] = []
            for _ in 0..<10 {
                let queryStart = clock.now
                let resultCount = try await index.search(query.text).results.count
                durations.append(milliseconds(queryStart.duration(to: clock.now)))
                guard resultCount == expectedCount else {
                    throw GraphiteError.invalidFile("Search \(query.text) found \(resultCount) results; expected \(expectedCount).")
                }
            }
            durations.sort()
            print("Search \(query.text): p50 \(percentile(50, ofAscending: durations)) ms; max \(percentile(100, ofAscending: durations)) ms")
        }
        print("Search p50: \(percentile(50, ofAscending: searchDurations)) ms; p95: \(percentile(95, ofAscending: searchDurations)) ms")
        // The graph view reads every link and resolves each once per folder.
        let graphStart = clock.now
        let graph = try await index.linkGraph()
        print("Graph: \(graph.nodes.count) nodes, \(graph.edges.count) links in \(graphStart.duration(to: clock.now))")
        var layout = GraphLayout(graph: graph)
        let layoutStart = clock.now
        for _ in 0..<10 { layout.step() }
        print("Graph layout: 10 steps in \(layoutStart.duration(to: clock.now))")
        print("This measures an index on this Mac, not iPad/cloud/PDF performance.")
    }

    /// The record count the arguments ask for: the default without an argument, nil for
    /// anything that is not one whole number in `allowedRecordCounts` (such as "100k").
    static func recordCount(fromArguments arguments: [String]) -> Int? {
        guard let argument = arguments.first else { return defaultRecordCount }
        guard arguments.count == 1, let count = Int(argument), allowedRecordCounts.contains(count) else { return nil }
        return count
    }

    /// The nearest-rank percentile: the smallest sample that at least `percent` percent of
    /// the samples do not exceed. For 100 samples, p95 is the 95th smallest.
    static func percentile(_ percent: Int, ofAscending sortedSamples: [Double]) -> Double {
        precondition(!sortedSamples.isEmpty && (1...100).contains(percent), "Percentiles need samples and a percent from 1 to 100.")
        let rank = (percent * sortedSamples.count + 99) / 100
        return sortedSamples[rank - 1]
    }

    static func milliseconds(_ duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds) * 1000 + Double(components.attoseconds) / 1e15
    }

    /// Whether the number is written as a 9 followed by at least one more digit, the notes
    /// `/Lecture 9\d+/` finds.
    static func isNineFollowedByDigits(_ number: Int) -> Bool {
        let digits = String(number)
        return digits.count >= 2 && digits.hasPrefix("9")
    }
}

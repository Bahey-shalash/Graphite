import Foundation

/// The XY chart inputs of the benchmark: Mermaid's 8 documentation examples, as Pele collects them
/// (`tests/corpus/xychart-docs.json`), and charts of bars and lines generated with the seed of Pele's generated graphs.
enum XYChartCorpus {
    static func documentationExamples() throws -> [String] {
        guard let location = Bundle.module.url(forResource: "xychart-docs", withExtension: "json", subdirectory: "Resources") else {
            throw FlowchartCorpus.MissingResource()
        }
        return try JSONDecoder().decode([String].self, from: Data(contentsOf: location))
    }

    /// A chart of `categoryCount` categories and `seriesCount` series, bars and lines in turn, each value from 0 to 999
    /// from the same linear congruential generator and seed as `FlowchartCorpus.mesh`.
    static func generated(categoryCount: Int, seriesCount: Int) -> String {
        var seed: UInt32 = 7
        let categories = (0..<categoryCount).map { category in "c\(category)" }.joined(separator: ", ")
        var source = "xychart\n  title \"Generated\"\n  x-axis \"Category\" [\(categories)]\n  y-axis \"Value\"\n"
        for series in 0..<seriesCount {
            let values = (0..<categoryCount).map { _ in
                seed = seed &* 1_664_525 &+ 1_013_904_223
                return String(Int(Double(seed) / 4_294_967_296 * 1_000))
            }
            source += "  \(series.isMultiple(of: 2) ? "bar" : "line") \"Series \(series)\" [\(values.joined(separator: ", "))]\n"
        }
        return source
    }
}

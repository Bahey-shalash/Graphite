import Foundation

/// The quadrant charts the benchmark times: Mermaid's three documentation examples, as Pele's corpus collects them
/// (`tests/corpus/quadrant-docs.json`), and charts of many points placed with the seed of Pele's generated graphs.
enum QuadrantChartCorpus {
    static func documentationExamples() throws -> [String] {
        guard let location = Bundle.module.url(forResource: "quadrant-docs", withExtension: "json", subdirectory: "Resources") else {
            throw FlowchartCorpus.MissingResource()
        }
        return try JSONDecoder().decode([String].self, from: Data(contentsOf: location))
    }

    /// A chart with a title, both axes, the four quadrants' texts and `pointCount` points, each coordinate from 0.01 to
    /// 0.99 from the same linear congruential generator and seed as `FlowchartCorpus.mesh`.
    static func generated(pointCount: Int) -> String {
        var seed: UInt32 = 7
        func nextCoordinate() -> String {
            seed = seed &* 1_664_525 &+ 1_013_904_223
            let hundredths = 1 + Int(Double(seed) / 4_294_967_296 * 98)
            return "0." + String(format: "%02d", hundredths)
        }
        var source = """
        quadrantChart
          title Generated points
          x-axis Low effort --> High effort
          y-axis Low impact --> High impact
          quadrant-1 Plan
          quadrant-2 Do first
          quadrant-3 Drop
          quadrant-4 Delegate

        """
        for point in 0..<pointCount { source += "  Item \(point + 1): [\(nextCoordinate()), \(nextCoordinate())]\n" }
        return source
    }
}

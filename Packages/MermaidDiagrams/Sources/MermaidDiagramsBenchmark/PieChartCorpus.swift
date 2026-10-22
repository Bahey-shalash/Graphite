import Foundation

/// The pie charts the benchmark times: Mermaid's two documentation examples, as Pele's corpus collects them
/// (`tests/corpus/pie-docs.json`), and pies of many slices generated with the seed of Pele's generated graphs.
enum PieChartCorpus {
    static func documentationExamples() throws -> [String] {
        guard let location = Bundle.module.url(forResource: "pie-docs", withExtension: "json", subdirectory: "Resources") else {
            throw FlowchartCorpus.MissingResource()
        }
        return try JSONDecoder().decode([String].self, from: Data(contentsOf: location))
    }

    /// A pie chart of `sliceCount` slices, each value from 1 to 100 with two decimals, from the same linear
    /// congruential generator and seed as `FlowchartCorpus.mesh`.
    static func pie(sliceCount: Int) -> String {
        var seed: UInt32 = 7
        var source = "pie showData title Generated slices\n"
        for slice in 0..<sliceCount {
            seed = seed &* 1_664_525 &+ 1_013_904_223
            let hundredths = 100 + Int(Double(seed) / 4_294_967_296 * 9_900)
            source += "  \"Slice \(slice)\" : \(hundredths / 100).\(String(format: "%02d", hundredths % 100))\n"
        }
        return source
    }
}

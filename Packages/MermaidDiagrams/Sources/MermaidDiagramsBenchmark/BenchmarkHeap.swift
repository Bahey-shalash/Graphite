/// The memory the mindmap's and the timeline's layouts hold.
enum BenchmarkHeap {
    /// The growth of the heap's bytes in use while `MermaidDiagramsBenchmark.keptLayoutCount` values that `make` makes
    /// are kept, per value.
    static func growth<Value>(perValueOf make: () -> Value) -> Int {
        var kept: [Value] = []
        kept.reserveCapacity(MermaidDiagramsBenchmark.keptLayoutCount)
        let before = MermaidDiagramsBenchmark.heapBytesInUse()
        for _ in 0..<MermaidDiagramsBenchmark.keptLayoutCount { kept.append(make()) }
        let growth = MermaidDiagramsBenchmark.heapBytesInUse() - before
        return kept.isEmpty ? 0 : growth / kept.count
    }
}

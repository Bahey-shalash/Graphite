import CoreGraphics

/// The nondecreasing sequence closest to a sequence of targets in weighted least squares, by pooling adjacent
/// violators: each target starts a block, and a block whose mean falls below the one before merges with it. Its
/// buffers are kept between uses, so that placing rank after rank allocates nothing once they have grown.
struct IsotonicPooling {
    private var blockMeans: [CGFloat] = []
    private var blockWeights: [CGFloat] = []
    private var blockCounts: [Int] = []
    /// The fit of the targets added since the last `reset()`, after `finish()`.
    private(set) var fitted: [CGFloat] = []

    init(capacity: Int) {
        blockMeans.reserveCapacity(capacity)
        blockWeights.reserveCapacity(capacity)
        blockCounts.reserveCapacity(capacity)
        fitted.reserveCapacity(capacity)
    }

    mutating func reset() {
        blockMeans.removeAll(keepingCapacity: true)
        blockWeights.removeAll(keepingCapacity: true)
        blockCounts.removeAll(keepingCapacity: true)
        fitted.removeAll(keepingCapacity: true)
    }

    mutating func add(target: CGFloat, weight: CGFloat) {
        var mean = target
        var totalWeight = weight
        var count = 1
        while let previousMean = blockMeans.last, previousMean > mean {
            let previousWeight = blockWeights.removeLast()
            mean = (previousMean * previousWeight + mean * totalWeight) / (previousWeight + totalWeight)
            totalWeight += previousWeight
            count += blockCounts.removeLast()
            blockMeans.removeLast()
        }
        blockMeans.append(mean)
        blockWeights.append(totalWeight)
        blockCounts.append(count)
    }

    /// Writes the fit, one value per target added, into `fitted`.
    mutating func finish() {
        fitted.removeAll(keepingCapacity: true)
        for (mean, count) in zip(blockMeans, blockCounts) {
            for _ in 0..<count { fitted.append(mean) }
        }
    }
}

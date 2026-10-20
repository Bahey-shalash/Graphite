import XCTest
import GraphiteTestSupport

/// The scaling check tells work that grows in proportion to its input from work that grows with its square.
final class ScalingChecksTests: XCTestCase {
    /// Keeps the compiler from removing the busy work.
    private var sink = 0

    private func busyWork(iterations: Int) {
        var total = 0
        for index in 0..<iterations { total &+= index ^ (total >> 3) }
        sink &+= total
    }

    func testWorkInProportionToItsInputPasses() {
        ScalingChecks.assertScalesLinearly(smallSize: 4_000, largeSize: 16_000, "linear busy work", fastEnoughSeconds: 0.001, smallestMeaningfulSeconds: 0.002) { size in
            busyWork(iterations: size * 100)
        }
    }

    func testWorkThatGrowsWithTheSquareOfItsInputFails() {
        XCTExpectFailure("Quadratic work is the case the check exists for.") {
            ScalingChecks.assertScalesLinearly(smallSize: 200, largeSize: 800, "quadratic busy work", fastEnoughSeconds: 0.001, smallestMeaningfulSeconds: 0.002) { size in
                for _ in 0..<size { busyWork(iterations: size * 4) }
            }
        }
    }

    func testWorkThatEndsQuicklyPassesWhateverItsRatio() {
        ScalingChecks.assertScalesLinearly(smallSize: 10, largeSize: 40, "tiny work") { size in
            busyWork(iterations: size * size)
        }
    }

    func testWorkMuchSlowerThanAPlainPassFailsAndOneNearItPasses() {
        ScalingChecks.assertNoSlowerThan(factor: 50, reference: { busyWork(iterations: 40_000) }, "near the plain pass", fastEnoughSeconds: 0.001) {
            busyWork(iterations: 400_000)
        }
        XCTExpectFailure("Work 200 times the plain pass is over a limit of 50.") {
            ScalingChecks.assertNoSlowerThan(factor: 50, reference: { busyWork(iterations: 40_000) }, "far from the plain pass") {
                busyWork(iterations: 8_000_000)
            }
        }
    }
}

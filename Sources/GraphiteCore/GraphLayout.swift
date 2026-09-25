import Foundation

/// Places a graph's nodes as Obsidian's graph view does: links pull their ends together,
/// every node pushes the others away, and a weak pull keeps the graph centered. It is the
/// force simulation of d3 (which Obsidian uses), stepped until it settles. Repulsion is
/// approximated with a Barnes–Hut quadtree, so a large vault stays fast.
public struct GraphLayout: Sendable {
    /// Obsidian's graph "Forces" settings.
    public struct Forces: Equatable, Sendable {
        /// How long links try to be, in points.
        public var linkDistance = 60.0
        /// How strongly links pull, as a multiple of d3's default.
        public var linkStrength = 1.0
        /// How strongly nodes push each other away.
        public var repelStrength = 120.0
        /// How strongly nodes are pulled toward the middle.
        public var centerStrength = 0.06

        public init(linkDistance: Double = 60, linkStrength: Double = 1, repelStrength: Double = 120, centerStrength: Double = 0.06) {
            self.linkDistance = linkDistance
            self.linkStrength = linkStrength
            self.repelStrength = repelStrength
            self.centerStrength = centerStrength
        }
    }

    private struct Link: Sendable {
        let source: Int
        let target: Int
        /// How much of the correction moves the target rather than the source.
        let bias: Double
        let strength: Double
    }

    public let identifiers: [String]
    public private(set) var positions: [SIMD2<Double>]
    private var velocities: [SIMD2<Double>]
    private let links: [Link]
    private var pinnedPositions: [Int: SIMD2<Double>] = [:]
    public var forces: Forces
    /// How much the simulation still moves; it stops below `minimumAlpha`.
    public private(set) var alpha = 1.0
    private let indexByIdentifier: [String: Int]

    static let minimumAlpha = 0.001
    /// d3's decay: from 1 to the minimum in 300 steps.
    static let alphaDecay = 1 - pow(minimumAlpha, 1.0 / 300)
    /// The share of velocity lost at each step.
    static let velocityDecay = 0.4
    /// Barnes–Hut accuracy: cells seen smaller than this, relative to their distance,
    /// count as one body.
    static let approximationThreshold = 0.9

    /// - Parameter previousPositions: Where nodes were in an earlier layout, so a graph
    ///   that changes keeps its shape. New nodes start beside a placed neighbor.
    public init(graph: LinkGraph, forces: Forces = Forces(), previousPositions: [String: SIMD2<Double>] = [:]) {
        self.forces = forces
        identifiers = graph.nodes.map(\.id)
        var indexByIdentifier: [String: Int] = [:]
        for (index, identifier) in identifiers.enumerated() { indexByIdentifier[identifier] = index }
        self.indexByIdentifier = indexByIdentifier
        let linkCounts = graph.linkCounts
        links = graph.edges.compactMap { edge in
            guard let source = indexByIdentifier[edge.source], let target = indexByIdentifier[edge.target] else { return nil }
            let sourceCount = Double(linkCounts[edge.source] ?? 1), targetCount = Double(linkCounts[edge.target] ?? 1)
            return Link(source: source, target: target, bias: sourceCount / (sourceCount + targetCount), strength: 1 / min(sourceCount, targetCount))
        }
        var neighbors: [Int: [Int]] = [:]
        for link in links {
            neighbors[link.source, default: []].append(link.target)
            neighbors[link.target, default: []].append(link.source)
        }
        var positions: [SIMD2<Double>?] = identifiers.map { identifier in previousPositions[identifier] }
        let hasPreviousLayout = positions.contains { position in position != nil }
        for index in positions.indices where positions[index] == nil {
            if hasPreviousLayout, let placedNeighbor = neighbors[index]?.lazy.compactMap({ neighbor in positions[neighbor] }).first {
                positions[index] = placedNeighbor + Self.offset(for: index) * forces.linkDistance / 3
            } else {
                // d3's phyllotaxis: an even spiral, the same for the same graph every time.
                let radius = 10 * (0.5 + Double(index)).squareRoot()
                let angle = Double(index) * Double.pi * (3 - 5.0.squareRoot())
                positions[index] = SIMD2(radius * cos(angle), radius * sin(angle))
            }
        }
        self.positions = positions.map { position in position ?? .zero }
        velocities = Array(repeating: .zero, count: identifiers.count)
        // A graph laid out before only needs to adjust.
        if hasPreviousLayout { alpha = 0.3 }
    }

    public var isSettled: Bool { alpha < Self.minimumAlpha }

    public func position(of identifier: String) -> SIMD2<Double>? {
        indexByIdentifier[identifier].map { index in positions[index] }
    }

    public var positionsByIdentifier: [String: SIMD2<Double>] {
        Dictionary(uniqueKeysWithValues: zip(identifiers, positions))
    }

    /// Holds a node where it is dragged; the others move around it.
    public mutating func pin(_ identifier: String, at position: SIMD2<Double>) {
        guard let index = indexByIdentifier[identifier] else { return }
        pinnedPositions[index] = position
        positions[index] = position
        velocities[index] = .zero
    }

    public mutating func unpin(_ identifier: String) {
        guard let index = indexByIdentifier[identifier] else { return }
        pinnedPositions[index] = nil
    }

    /// Wakes the simulation, as when a node is dragged or a setting changes.
    public mutating func reheat(to targetAlpha: Double = 0.3) {
        alpha = max(alpha, targetAlpha)
    }

    /// Advances the simulation by one step.
    public mutating func step() {
        guard !positions.isEmpty else { alpha = 0; return }
        alpha += (0 - alpha) * Self.alphaDecay
        applyLinkForce()
        applyRepulsion()
        for index in positions.indices {
            // Centering, as d3's x and y forces toward the origin.
            velocities[index] -= positions[index] * forces.centerStrength * alpha
        }
        for index in positions.indices {
            if let pinned = pinnedPositions[index] {
                positions[index] = pinned
                velocities[index] = .zero
                continue
            }
            velocities[index] *= 1 - Self.velocityDecay
            positions[index] += velocities[index]
        }
    }

    /// Steps until settled, or at most `maximumSteps` times.
    public mutating func settle(maximumSteps: Int = 1_000) {
        var steps = 0
        while !isSettled, steps < maximumSteps {
            step()
            steps += 1
        }
    }

    /// The smallest rectangle around every node, as origin and size; nil without nodes.
    public var bounds: (origin: SIMD2<Double>, size: SIMD2<Double>)? {
        guard var lower = positions.first else { return nil }
        var upper = lower
        for position in positions {
            lower = pointwiseMin(lower, position)
            upper = pointwiseMax(upper, position)
        }
        return (lower, upper - lower)
    }

    // MARK: Forces

    private mutating func applyLinkForce() {
        let strengthScale = forces.linkStrength
        for link in links {
            var delta = positions[link.target] + velocities[link.target] - positions[link.source] - velocities[link.source]
            if delta == .zero { delta = Self.offset(for: link.target) * 1e-6 }
            let length = (delta * delta).sum().squareRoot()
            let correction = (length - forces.linkDistance) / length * alpha * link.strength * strengthScale
            delta *= correction
            velocities[link.target] -= delta * link.bias
            velocities[link.source] += delta * (1 - link.bias)
        }
    }

    private mutating func applyRepulsion() {
        guard positions.count > 1, forces.repelStrength > 0 else { return }
        let tree = RepulsionTree(positions: positions)
        let strength = -forces.repelStrength * alpha
        for index in positions.indices {
            velocities[index] += tree.force(on: index, positions: positions, strength: strength, threshold: Self.approximationThreshold)
        }
    }

    /// A small offset that differs from node to node but not from run to run, to separate
    /// nodes in the same place.
    static func offset(for index: Int) -> SIMD2<Double> {
        let angle = Double((index &* 2_654_435_761) % 360) * Double.pi / 180
        return SIMD2(cos(angle), sin(angle))
    }
}

/// A quadtree over the nodes, each cell knowing how many nodes it holds and their center,
/// so a far group of nodes can push as one (Barnes–Hut).
struct RepulsionTree {
    private struct Cell {
        var origin: SIMD2<Double>
        var size: Double
        var positionSum = SIMD2<Double>.zero
        var count = 0
        /// The first of four children, or -1 for a leaf.
        var firstChild = -1
        /// The node in a leaf, or -1.
        var body = -1
        /// Nodes in the same place as `body`, kept together once cells are too small to split.
        var otherBodies: [Int] = []
    }

    private var cells: [Cell] = []
    private static let maximumDepth = 40

    init(positions: [SIMD2<Double>]) {
        guard var lower = positions.first else { return }
        var upper = lower
        for position in positions {
            lower = pointwiseMin(lower, position)
            upper = pointwiseMax(upper, position)
        }
        let size = max((upper - lower).max(), 1) * 1.000_001
        cells.reserveCapacity(positions.count * 2)
        cells.append(Cell(origin: lower, size: size))
        for index in positions.indices { insert(index, at: positions[index], positions: positions) }
    }

    private func quadrant(of position: SIMD2<Double>, in cell: Cell) -> Int {
        let half = cell.size / 2
        return (position.x >= cell.origin.x + half ? 1 : 0) + (position.y >= cell.origin.y + half ? 2 : 0)
    }

    private mutating func insert(_ index: Int, at position: SIMD2<Double>, positions: [SIMD2<Double>]) {
        var cellIndex = 0
        var depth = 0
        while true {
            cells[cellIndex].count += 1
            cells[cellIndex].positionSum += position
            if cells[cellIndex].firstChild >= 0 {
                cellIndex = cells[cellIndex].firstChild + quadrant(of: position, in: cells[cellIndex])
                depth += 1
                continue
            }
            if cells[cellIndex].body < 0 {
                cells[cellIndex].body = index
                return
            }
            if depth >= Self.maximumDepth {
                cells[cellIndex].otherBodies.append(index)
                return
            }
            // Split the leaf and move its node down.
            let cell = cells[cellIndex]
            let half = cell.size / 2
            let firstChild = cells.count
            for quadrantIndex in 0..<4 {
                let origin = cell.origin + SIMD2(quadrantIndex & 1 == 1 ? half : 0, quadrantIndex & 2 == 2 ? half : 0)
                cells.append(Cell(origin: origin, size: half))
            }
            let existing = cell.body
            cells[cellIndex].body = -1
            cells[cellIndex].firstChild = firstChild
            let existingCell = firstChild + quadrant(of: positions[existing], in: cell)
            cells[existingCell].body = existing
            cells[existingCell].count = 1
            cells[existingCell].positionSum = positions[existing]
            cellIndex = firstChild + quadrant(of: position, in: cell)
            depth += 1
        }
    }

    /// The push on node `index` from all others: `strength` over the squared distance,
    /// negative to repel. With `threshold` 0 every node counts on its own.
    func force(on index: Int, positions: [SIMD2<Double>], strength: Double, threshold: Double) -> SIMD2<Double> {
        guard !cells.isEmpty else { return .zero }
        let position = positions[index]
        let thresholdSquared = threshold * threshold
        var total = SIMD2<Double>.zero
        func push(from body: Int) {
            guard body >= 0, body != index else { return }
            var delta = positions[body] - position
            if delta == .zero { delta = GraphLayout.offset(for: body &+ index) * 1e-3 }
            total += delta * (strength / max((delta * delta).sum(), 1))
        }
        var stack: [Int] = [0]
        stack.reserveCapacity(64)
        while let cellIndex = stack.popLast() {
            let cell = cells[cellIndex]
            guard cell.count > 0 else { continue }
            if cell.firstChild >= 0 {
                let center = cell.positionSum / Double(cell.count)
                let delta = center - position
                let distanceSquared = (delta * delta).sum()
                if distanceSquared > 0, cell.size * cell.size < thresholdSquared * distanceSquared {
                    total += delta * (strength * Double(cell.count) / max(distanceSquared, 1))
                } else {
                    for child in cell.firstChild..<(cell.firstChild + 4) { stack.append(child) }
                }
                continue
            }
            push(from: cell.body)
            for body in cell.otherBodies { push(from: body) }
        }
        return total
    }
}

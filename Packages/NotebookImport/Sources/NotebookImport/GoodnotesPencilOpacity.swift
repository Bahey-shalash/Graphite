import Foundation

/// How dark Goodnotes draws its pencil for the Apple Pencil's force, as one opacity per stroke (BUG-IMPORT-04).
///
/// Goodnotes draws the pencil as a texture that grows darker with force. Its export of the "fountain, brush, pencil and
/// highlighter" sample, written with a mouse (force 0 at every point), draws the pencil as an image whose alpha, summed
/// over the stroke and spread over a band of the stroke's width, is 0.048: the opacity at no force. How much darker a
/// press makes it is not in any export of the samples (the Pencil test is not on the samples branch), so the opacity
/// rises in a straight line to full colour at an ordinary press, a force of 1 (UIKit's average touch), and stays there.
/// PencilKit draws a stored pencil point the same at any force (measured on macOS 27 at forces 0 to 4.17), so the
/// opacity is carried in the stroke's colour, which both the canvas and the PDF appearance draw.
enum GoodnotesPencilOpacity {
    /// Measured on the export at force 0, rounded.
    static let opacityAtNoForce = 0.05
    /// The force at which the pencil draws its full colour.
    static let forceOfFullColor = 1.0

    /// The opacity for a stroke's forces: their mean, a stroke without finite forces drawn at full colour.
    static func opacity(forForces forces: [Double]) -> Double {
        let finiteForces = forces.filter { force in force.isFinite && force >= 0 }
        guard !finiteForces.isEmpty else { return 1 }
        let meanForce = finiteForces.reduce(0, +) / Double(finiteForces.count)
        return min(1, opacityAtNoForce + (1 - opacityAtNoForce) * meanForce / forceOfFullColor)
    }
}

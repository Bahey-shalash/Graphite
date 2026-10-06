import SwiftUI
import GraphiteCore
import GraphiteIndex

/// The colors of a canvas. Presets 1 to 6 are Obsidian's default palette, which has
/// its own shades for light and dark appearance.
enum CanvasPalette {
    private static let lightPresets: [(red: Double, green: Double, blue: Double)] = [
        (233, 49, 71), (236, 117, 0), (224, 172, 0), (8, 185, 78), (0, 191, 188), (120, 82, 238),
    ]
    private static let darkPresets: [(red: Double, green: Double, blue: Double)] = [
        (251, 70, 76), (233, 151, 63), (224, 222, 113), (68, 207, 110), (83, 223, 221), (168, 130, 255),
    ]

    static func color(_ canvasColor: CanvasColor, colorScheme: ColorScheme) -> Color {
        switch canvasColor {
        case .preset(let presetNumber):
            let presets = colorScheme == .dark ? darkPresets : lightPresets
            let preset = presets[min(max(presetNumber, 1), presets.count) - 1]
            return Color(.sRGB, red: preset.red / 255, green: preset.green / 255, blue: preset.blue / 255)
        case .custom(let red, let green, let blue):
            return Color(.sRGB, red: Double(red) / 255, green: Double(green) / 255, blue: Double(blue) / 255)
        }
    }

    #if canImport(UIKit)
    static let board = Color(uiColor: .systemGroupedBackground)
    static let card = Color(uiColor: .secondarySystemGroupedBackground)
    #else
    static let board = Color(nsColor: .windowBackgroundColor)
    static let card = Color(nsColor: .textBackgroundColor)
    #endif
    /// The outline of a card or group without a color, and a connection without one.
    static let neutralLine = Color.primary.opacity(0.28)
    /// How strongly a card's color tints its background.
    static let cardTintOpacity = 0.12
    static let groupTintOpacity = 0.08
    static let cardCornerRadius: CGFloat = 8
    static let cardBorderWidth: CGFloat = 2
}

/// What the cards of a canvas need from the app to show notes, images and links.
struct CanvasCardEnvironment {
    let canvasPath: VaultPath
    let root: URL
    let index: VaultIndex
    /// How Markdown in cards reads, as in reading view.
    let configuration: ReadingConfiguration
    let renderCache: CanvasCardRenderCache
    /// Follows a link written in the file `source`: the canvas for a text card, the note
    /// for a note card.
    let follow: (_ target: String, _ isWiki: Bool, _ source: VaultPath) -> Void
    let open: (VaultPath) -> Void
    let openPDF: (VaultPath, Int) -> Void
    let baseContext: BaseEmbedContext?
    let imageActions: ReadingImageActions?
}

/// The board of a canvas: the grid, groups and connections drawn as one picture, the
/// cards in view as views of their own, and the selection drawn over them. Only what is
/// in view is drawn, so a board of thousands of cards costs what its visible part costs.
struct CanvasBoardView: View {
    let session: CanvasSession
    let environment: CanvasCardEnvironment
    @Environment(\.accessibilityVoiceOverEnabled) private var isVoiceOverEnabled
    @Environment(\.accessibilitySwitchControlEnabled) private var isSwitchControlEnabled
    /// Shows the list of cards for assistive technologies whatever the settings; for tests.
    var alwaysShowsAccessibilityElements = false

    var body: some View {
        let describesCards = isVoiceOverEnabled || isSwitchControlEnabled || alwaysShowsAccessibilityElements
        ZStack(alignment: .topLeading) {
            CanvasBackdropLayer(session: session, environment: environment)
            CanvasCardsLayer(session: session, environment: environment, describesCards: describesCards)
            CanvasSelectionLayer(session: session)
            if describesCards { CanvasAccessibilityLayer(session: session, environment: environment) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(CanvasPalette.board)
        .clipped()
        .onGeometryChange(for: CGSize.self) { geometry in geometry.size } action: { size in session.viewSize = size }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Canvas")
        .accessibilityIdentifier("canvasBoard")
    }
}

// MARK: Grid, groups, connections and distant cards

/// Everything beneath the cards, drawn as one picture at every pan and zoom: the dot
/// grid, groups, connections, and the cards too small or too many to show their content.
private struct CanvasBackdropLayer: View {
    let session: CanvasSession
    let environment: CanvasCardEnvironment
    @Environment(\.colorScheme) private var colorScheme
    @ScaledMetric(relativeTo: .headline) private var groupLabelSize = 20.0
    @ScaledMetric(relativeTo: .callout) private var edgeLabelSize = 14.0
    @State private var groupBackgrounds = CanvasGroupBackgrounds()

    /// A label smaller than this on screen cannot be read, so it is not drawn.
    private static let smallestLegibleTextSize: CGFloat = 7
    private static let arrowheadLength: CGFloat = 14
    private static let arrowheadHalfWidth: CGFloat = 6

    var body: some View {
        // The renderer runs outside the body, where reads are not observed, so everything
        // it draws from is read here.
        let viewport = session.viewport
        let nodes = session.shownNodes
        let file = session.file
        let previewFrames = session.previewFrames
        let detailedIdentifiers = Set(session.detailedNodes.map(\.id))
        let backgroundImages = groupBackgrounds.images
        Canvas { context, size in
            let visibleFrame = viewport.visibleBoardFrame(viewSize: size)
            drawGrid(in: &context, viewport: viewport, size: size)
            var labelFrames: [String: CGRect] = [:]
            for group in nodes where group.isGroup && group.frame.insetBy(dx: -40 / viewport.scale, dy: -60 / viewport.scale).intersects(visibleFrame) {
                labelFrames[group.id] = draw(group, in: &context, viewport: viewport, backgroundImages: backgroundImages)
            }
            session.groupLabelFrames = labelFrames
            drawEdges(of: file, previewFrames: previewFrames, in: &context, viewport: viewport, visibleFrame: visibleFrame)
            drawPlaceholders(for: nodes.filter { node in !node.isGroup && !detailedIdentifiers.contains(node.id) && node.frame.intersects(visibleFrame) },
                             in: &context, viewport: viewport)
        }
        .task(id: session.changeVersion) { await groupBackgrounds.load(for: session.file.nodes, root: environment.root) }
        .accessibilityHidden(true)
    }

    /// Obsidian's dot grid. The dots thin out as the board shrinks, so they never crowd.
    private func drawGrid(in context: inout GraphicsContext, viewport: CanvasViewport, size: CGSize) {
        var spacing = CanvasGeometry.gridSpacing
        while spacing * viewport.scale < 18 { spacing *= 2 }
        let visibleFrame = viewport.visibleBoardFrame(viewSize: size)
        let firstColumn = (visibleFrame.minX / spacing).rounded(.down), firstRow = (visibleFrame.minY / spacing).rounded(.down)
        let columnCount = Int((visibleFrame.width / spacing).rounded(.up)) + 1, rowCount = Int((visibleFrame.height / spacing).rounded(.up)) + 1
        guard columnCount * rowCount < 20_000 else { return }
        var dots = Path()
        for row in 0...rowCount {
            for column in 0...columnCount {
                let point = viewport.viewPoint(forBoardPoint: CGPoint(x: (firstColumn + CGFloat(column)) * spacing, y: (firstRow + CGFloat(row)) * spacing))
                dots.addRect(CGRect(x: point.x - 0.75, y: point.y - 0.75, width: 1.5, height: 1.5))
            }
        }
        context.fill(dots, with: .color(.primary.opacity(0.14)))
    }

    /// Draws a group and returns where its label is, on the board.
    private func draw(_ group: CanvasNode, in context: inout GraphicsContext, viewport: CanvasViewport, backgroundImages: [String: CGImage]) -> CGRect? {
        guard case .group(let label, let background, let backgroundStyle) = group.content else { return nil }
        let viewFrame = viewport.viewFrame(forBoardFrame: group.frame)
        let shape = Path(roundedRect: viewFrame, cornerRadius: max(CanvasPalette.cardCornerRadius * viewport.scale, 1))
        let tint = group.color.map { color in CanvasPalette.color(color, colorScheme: colorScheme) }
        context.fill(shape, with: .color((tint ?? .primary).opacity(tint == nil ? 0.04 : CanvasPalette.groupTintOpacity)))
        if let background, let image = backgroundImages[background] {
            draw(image, style: backgroundStyle, in: viewFrame, clippedTo: shape, context: &context, scale: viewport.scale)
        }
        context.stroke(shape, with: .color(tint ?? CanvasPalette.neutralLine), lineWidth: max(CanvasPalette.cardBorderWidth * viewport.scale, 1))
        let textSize = groupLabelSize * viewport.scale
        guard let label, textSize >= Self.smallestLegibleTextSize else { return nil }
        let text = context.resolve(Text(label).font(.system(size: textSize, weight: .semibold)).foregroundStyle(.primary))
        let textFrameSize = text.measure(in: CGSize(width: max(viewFrame.width, textSize * 8), height: textSize * 3))
        let padding = textSize * 0.35
        let labelFrame = CGRect(x: viewFrame.minX, y: viewFrame.minY - textFrameSize.height - 2 * padding - 4 * viewport.scale,
                                width: textFrameSize.width + 2 * padding, height: textFrameSize.height + 2 * padding)
        context.fill(Path(roundedRect: labelFrame, cornerRadius: padding), with: .color((tint ?? .primary).opacity(tint == nil ? 0.08 : 0.22)))
        context.draw(text, in: labelFrame.insetBy(dx: padding, dy: padding))
        return CGRect(origin: viewport.boardPoint(forViewPoint: labelFrame.origin), size: CGSize(width: labelFrame.width / viewport.scale, height: labelFrame.height / viewport.scale))
    }

    private func draw(_ image: CGImage, style: CanvasGroupBackgroundStyle, in viewFrame: CGRect, clippedTo shape: Path, context: inout GraphicsContext, scale: CGFloat) {
        guard image.width > 0, image.height > 0 else { return }
        var clipped = context
        clipped.clip(to: shape)
        let imageSize = CGSize(width: image.width, height: image.height)
        let picture = Image(decorative: image, scale: 1)
        switch style {
        case .cover, .ratio:
            let fitScale = style == .cover ? max(viewFrame.width / imageSize.width, viewFrame.height / imageSize.height)
                : min(viewFrame.width / imageSize.width, viewFrame.height / imageSize.height)
            let drawnSize = CGSize(width: imageSize.width * fitScale, height: imageSize.height * fitScale)
            clipped.draw(picture, in: CGRect(x: viewFrame.midX - drawnSize.width / 2, y: viewFrame.midY - drawnSize.height / 2, width: drawnSize.width, height: drawnSize.height))
        case .repeat:
            // One image pixel is one board pixel; tiles too small to see are not drawn one by one.
            let tileSize = CGSize(width: max(imageSize.width * scale, 24), height: max(imageSize.height * scale, 24))
            var tileOriginY = viewFrame.minY
            while tileOriginY < viewFrame.maxY {
                var tileOriginX = viewFrame.minX
                while tileOriginX < viewFrame.maxX {
                    clipped.draw(picture, in: CGRect(origin: CGPoint(x: tileOriginX, y: tileOriginY), size: tileSize))
                    tileOriginX += tileSize.width
                }
                tileOriginY += tileSize.height
            }
        }
    }

    /// Connections of one color are stroked together: a board zoomed far out can have
    /// thousands in view.
    private func drawEdges(of file: CanvasFile, previewFrames: [String: CGRect], in context: inout GraphicsContext, viewport: CanvasViewport, visibleFrame: CGRect) {
        var curvesByColor: [CanvasColor?: Path] = [:]
        var arrowheadsByColor: [CanvasColor?: Path] = [:]
        var labels: [(text: String, position: CGPoint, color: CanvasColor?)] = []
        // A curve stays within this distance of the frame around its two cards.
        let reach = CanvasGeometry.maximumControlDistance + 24 / viewport.scale
        // Far out, a connection is a few points long: it is drawn straight, without arrows.
        let drawsDetails = viewport.scale >= CanvasSession.minimumDetailScale / 2
        for edge in file.edges {
            guard let fromNode = file.node(named: edge.fromNode), let toNode = file.node(named: edge.toNode) else { continue }
            let fromFrame = previewFrames[fromNode.id] ?? fromNode.frame, toFrame = previewFrames[toNode.id] ?? toNode.frame
            guard fromFrame.union(toFrame).insetBy(dx: -reach, dy: -reach).intersects(visibleFrame) else { continue }
            let route = CanvasGeometry.route(from: fromFrame, to: toFrame, fromSide: edge.fromSide, toSide: edge.toSide)
            var curve = curvesByColor[edge.color] ?? Path()
            curve.move(to: viewport.viewPoint(forBoardPoint: route.start))
            if drawsDetails {
                curve.addCurve(to: viewport.viewPoint(forBoardPoint: route.end), control1: viewport.viewPoint(forBoardPoint: route.startControl),
                               control2: viewport.viewPoint(forBoardPoint: route.endControl))
            } else {
                curve.addLine(to: viewport.viewPoint(forBoardPoint: route.end))
            }
            curvesByColor[edge.color] = curve
            guard drawsDetails else { continue }
            for (end, isAtStart) in [(edge.fromEnd, true), (edge.toEnd, false)] where end == .arrow {
                var arrowheads = arrowheadsByColor[edge.color] ?? Path()
                let corners = route.arrowhead(atStart: isAtStart, length: Self.arrowheadLength, halfWidth: Self.arrowheadHalfWidth).map(viewport.viewPoint(forBoardPoint:))
                arrowheads.addLines(corners)
                arrowheads.closeSubpath()
                arrowheadsByColor[edge.color] = arrowheads
            }
            if let label = edge.label, !label.isEmpty { labels.append((label, viewport.viewPoint(forBoardPoint: route.midpoint), edge.color)) }
        }
        let lineWidth = max(2.5 * viewport.scale, 0.75)
        for (canvasColor, curve) in curvesByColor {
            context.stroke(curve, with: .color(lineColor(canvasColor)), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
        }
        for (canvasColor, arrowheads) in arrowheadsByColor { context.fill(arrowheads, with: .color(lineColor(canvasColor))) }
        let textSize = edgeLabelSize * viewport.scale
        guard textSize >= Self.smallestLegibleTextSize else { return }
        for label in labels {
            let text = context.resolve(Text(label.text).font(.system(size: textSize)).foregroundStyle(.primary))
            let textFrameSize = text.measure(in: CGSize(width: 320 * viewport.scale, height: textSize * 6))
            let padding = textSize * 0.4
            let labelFrame = CGRect(x: label.position.x - textFrameSize.width / 2 - padding, y: label.position.y - textFrameSize.height / 2 - padding,
                                    width: textFrameSize.width + 2 * padding, height: textFrameSize.height + 2 * padding)
            let shape = Path(roundedRect: labelFrame, cornerRadius: padding)
            context.fill(shape, with: .color(CanvasPalette.board))
            context.stroke(shape, with: .color(lineColor(label.color)), lineWidth: max(viewport.scale, 0.5))
            context.draw(text, in: labelFrame.insetBy(dx: padding, dy: padding))
        }
    }

    private func lineColor(_ canvasColor: CanvasColor?) -> Color {
        canvasColor.map { color in CanvasPalette.color(color, colorScheme: colorScheme) } ?? CanvasPalette.neutralLine
    }

    /// Cards without their content, as Obsidian shows them from afar: shapes in the
    /// cards' colors, filled and outlined together by color.
    private func drawPlaceholders(for nodes: [CanvasNode], in context: inout GraphicsContext, viewport: CanvasViewport) {
        guard !nodes.isEmpty else { return }
        var shapesByColor: [CanvasColor?: Path] = [:]
        let cornerRadius = CanvasPalette.cardCornerRadius * viewport.scale
        // Corners too small to see are left square, which is much cheaper to fill.
        let roundsCorners = cornerRadius >= 1
        for node in nodes {
            let viewFrame = viewport.viewFrame(forBoardFrame: node.frame)
            if roundsCorners {
                shapesByColor[node.color, default: Path()].addRoundedRect(in: viewFrame, cornerSize: CGSize(width: cornerRadius, height: cornerRadius))
            } else {
                shapesByColor[node.color, default: Path()].addRect(viewFrame)
            }
        }
        let borderWidth = max(CanvasPalette.cardBorderWidth * viewport.scale, 0.75)
        for (canvasColor, shapes) in shapesByColor {
            // The tint is mixed into the card's color, so each group of shapes is filled once.
            let fill = canvasColor.map { color in CanvasPalette.card.mix(with: CanvasPalette.color(color, colorScheme: colorScheme), by: CanvasPalette.cardTintOpacity) }
            context.fill(shapes, with: .color(fill ?? CanvasPalette.card))
            context.stroke(shapes, with: .color(lineColor(canvasColor)), lineWidth: borderWidth)
        }
    }
}

/// The background images of a canvas's groups, decoded off the main thread.
@MainActor @Observable
final class CanvasGroupBackgrounds {
    /// By the path the group names.
    private(set) var images: [String: CGImage] = [:]
    /// A board with a background on every group still decodes only this many.
    private static let maximumImageCount = 24

    func load(for nodes: [CanvasNode], root: URL) async {
        var paths: [String] = []
        for node in nodes {
            if case .group(_, let background?, _) = node.content, !paths.contains(background) { paths.append(background) }
        }
        var loadedImages: [String: CGImage] = [:]
        for path in paths.prefix(Self.maximumImageCount) {
            if let image = images[path] { loadedImages[path] = image; continue }
            guard let vaultPath = try? VaultPath(path), DocumentKind(path: vaultPath) == .image, let location = try? vaultPath.url(in: root),
                  let thumbnail = try? await ReadingImageCache.shared.thumbnail(for: location, kind: .block) else { continue }
            loadedImages[path] = thumbnail.image
        }
        if Task.isCancelled { return }
        if Set(loadedImages.keys) != Set(images.keys) { images = loadedImages }
    }
}

// MARK: Cards

/// The cards that show their content, magnified and moved as one: a pan or a pinch
/// changes this view's transform, not the cards inside it.
private struct CanvasCardsLayer: View {
    let session: CanvasSession
    let environment: CanvasCardEnvironment
    /// Whether each card is an element with a name for assistive technologies.
    let describesCards: Bool
    @Environment(\.displayScale) private var displayScale

    /// Card positions are kept relative to a nearby multiple of this, so the numbers the
    /// layout works with stay small however far from the board's origin the view is.
    private static let anchorSpacing: CGFloat = 4096

    var body: some View {
        let viewport = session.viewport
        let anchor = CGPoint(x: (viewport.origin.x / Self.anchorSpacing).rounded(.down) * Self.anchorSpacing,
                             y: (viewport.origin.y / Self.anchorSpacing).rounded(.down) * Self.anchorSpacing)
        CanvasCardsContent(session: session, environment: environment, anchor: anchor, describesCards: describesCards)
            // Text is drawn for the pixels it covers when magnified, in whole steps, so it
            // stays sharp without being drawn again at every frame of a pinch.
            .environment(\.displayScale, displayScale * max(viewport.scale.rounded(.up), 1))
            .scaleEffect(viewport.scale, anchor: .topLeading)
            .offset(x: (anchor.x - viewport.origin.x) * viewport.scale, y: (anchor.y - viewport.origin.y) * viewport.scale)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct CanvasCardsContent: View {
    let session: CanvasSession
    let environment: CanvasCardEnvironment
    let anchor: CGPoint
    let describesCards: Bool

    var body: some View {
        let isWriting = session.isWriting
        let editedIdentifier = session.textEdit?.nodeIdentifier
        let focusedIdentifier = session.focusedNodeIdentifier
        let readingPositions = describesCards ? session.readingPositions : [:]
        let file = session.file
        ZStack(alignment: .topLeading) {
            ForEach(session.detailedNodes) { node in
                CanvasCardView(node: node, session: session, environment: environment, isWriting: isWriting,
                               isEdited: editedIdentifier == node.id, isFocused: focusedIdentifier == node.id,
                               accessibility: readingPositions[node.id].map { position in
                                   let description = CanvasCardDescription(node: node, file: file)
                                   return CanvasCardAccessibility(label: description.label, value: description.connections, sortPriority: Double(file.nodes.count - position))
                               })
                    .frame(width: node.frame.width, height: node.frame.height)
                    .offset(x: node.frame.minX - anchor.x, y: node.frame.minY - anchor.y)
            }
        }
        .frame(width: 1, height: 1, alignment: .topLeading)
    }
}

// MARK: Selection

/// What is drawn over the cards while writing: the selection with its handles, the
/// lines a dragged card snaps to, the selection rectangle, and a connection being drawn.
/// A selection is marked by a heavier outline and its handles, not by color alone.
private struct CanvasSelectionLayer: View {
    let session: CanvasSession
    @Environment(\.accent) private var accent
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let viewport = session.viewport
        let selectedNodes = session.selectedNodes.map { node in session.frame(of: node) }
        let selectedRoutes = session.selectedEdges.compactMap { edge in session.route(of: edge) }
        let handledFrame = session.nodeWithHandles.map { node in session.frame(of: node) }
        let focusedFrame = session.focusedNodeIdentifier.flatMap { identifier in session.file.node(withIdentifier: identifier) }.map { node in session.frame(of: node) }
        let guides = session.snapGuides
        let selectionRectangle = session.selectionRectangle
        let pendingConnection = session.pendingConnection
        let pendingSourceFrame = pendingConnection.flatMap { connection in session.file.node(withIdentifier: connection.fromNodeIdentifier) }.map { node in session.frame(of: node) }
        let pendingTargetFrame = pendingConnection?.targetNodeIdentifier.flatMap { identifier in session.file.node(withIdentifier: identifier) }.map { node in session.frame(of: node) }
        Canvas { context, size in
            let cornerRadius = max(CanvasPalette.cardCornerRadius * viewport.scale, 1)
            for frame in selectedNodes + [focusedFrame].compactMap({ frame in frame }) {
                let outline = Path(roundedRect: viewport.viewFrame(forBoardFrame: frame).insetBy(dx: -2, dy: -2), cornerRadius: cornerRadius + 2)
                context.stroke(outline, with: .color(accent), lineWidth: 3)
            }
            for route in selectedRoutes {
                var curve = Path()
                curve.move(to: viewport.viewPoint(forBoardPoint: route.start))
                curve.addCurve(to: viewport.viewPoint(forBoardPoint: route.end), control1: viewport.viewPoint(forBoardPoint: route.startControl),
                               control2: viewport.viewPoint(forBoardPoint: route.endControl))
                context.stroke(curve, with: .color(accent), style: StrokeStyle(lineWidth: max(2.5 * viewport.scale, 0.75) + 3, lineCap: .round))
                for endPoint in [route.start, route.end] { drawHandle(at: viewport.viewPoint(forBoardPoint: endPoint), in: &context, isRound: true) }
            }
            if let handledFrame {
                let viewFrame = viewport.viewFrame(forBoardFrame: handledFrame)
                for handle in CanvasResizeHandle.allCases { drawHandle(at: handle.position(on: viewFrame), in: &context, isRound: false) }
                for side in CanvasSide.allCases { drawHandle(at: session.connectionDotPosition(for: side, ofViewFrame: viewFrame), in: &context, isRound: true) }
            }
            if let verticalGuide = guides.vertical {
                let position = viewport.viewPoint(forBoardPoint: CGPoint(x: verticalGuide, y: 0)).x
                context.stroke(Path { path in path.move(to: CGPoint(x: position, y: 0)); path.addLine(to: CGPoint(x: position, y: size.height)) },
                               with: .color(accent), style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
            }
            if let horizontalGuide = guides.horizontal {
                let position = viewport.viewPoint(forBoardPoint: CGPoint(x: 0, y: horizontalGuide)).y
                context.stroke(Path { path in path.move(to: CGPoint(x: 0, y: position)); path.addLine(to: CGPoint(x: size.width, y: position)) },
                               with: .color(accent), style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
            }
            if let selectionRectangle {
                let shape = Path(viewport.viewFrame(forBoardFrame: selectionRectangle))
                context.fill(shape, with: .color(accent.opacity(0.12)))
                context.stroke(shape, with: .color(accent), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            }
            if let pendingConnection, let pendingSourceFrame {
                if let pendingTargetFrame {
                    context.stroke(Path(roundedRect: viewport.viewFrame(forBoardFrame: pendingTargetFrame).insetBy(dx: -3, dy: -3), cornerRadius: cornerRadius + 3),
                                   with: .color(accent), style: StrokeStyle(lineWidth: 3, dash: [8, 5]))
                }
                let start = CanvasGeometry.anchor(of: pendingSourceFrame, side: pendingConnection.fromSide)
                let endSide = pendingTargetFrame.map { targetFrame in CanvasGeometry.nearestSide(of: targetFrame, to: pendingConnection.endPoint) } ?? Self.oppositeSide(of: pendingConnection.fromSide)
                let end = pendingTargetFrame.map { targetFrame in CanvasGeometry.anchor(of: targetFrame, side: endSide) } ?? pendingConnection.endPoint
                let route = CanvasGeometry.route(from: start, fromSide: pendingConnection.fromSide, to: end, toSide: endSide)
                var curve = Path()
                curve.move(to: viewport.viewPoint(forBoardPoint: route.start))
                curve.addCurve(to: viewport.viewPoint(forBoardPoint: route.end), control1: viewport.viewPoint(forBoardPoint: route.startControl),
                               control2: viewport.viewPoint(forBoardPoint: route.endControl))
                context.stroke(curve, with: .color(accent), style: StrokeStyle(lineWidth: max(2.5 * viewport.scale, 1.5), lineCap: .round))
                drawHandle(at: viewport.viewPoint(forBoardPoint: route.end), in: &context, isRound: true)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private static func oppositeSide(of side: CanvasSide) -> CanvasSide {
        switch side {
        case .top: .bottom
        case .right: .left
        case .bottom: .top
        case .left: .right
        }
    }

    /// Resize handles are squares and connection dots are circles, so the two are told
    /// apart by shape.
    private func drawHandle(at position: CGPoint, in context: inout GraphicsContext, isRound: Bool) {
        let frame = CGRect(x: position.x - 6, y: position.y - 6, width: 12, height: 12)
        let shape = isRound ? Path(ellipseIn: frame) : Path(roundedRect: frame, cornerRadius: 2)
        context.fill(shape, with: .color(isRound ? accent : CanvasPalette.card))
        context.stroke(shape, with: .color(isRound ? CanvasPalette.card : accent), lineWidth: 2)
    }
}

// MARK: Assistive technologies

/// The cards that do not show their content (groups, cards out of view, and cards too
/// small to read) as elements for VoiceOver and Switch Control. With the cards that do,
/// every card is an element, in reading order: rows from the top, each from the left, a
/// group before the cards inside it. Moving to a card out of view brings it into view.
private struct CanvasAccessibilityLayer: View {
    let session: CanvasSession
    let environment: CanvasCardEnvironment
    @AccessibilityFocusState private var focusedIdentifier: String?
    private static let anchorSpacing: CGFloat = 4096

    var body: some View {
        let viewport = session.viewport
        let anchor = CGPoint(x: (viewport.origin.x / Self.anchorSpacing).rounded(.down) * Self.anchorSpacing,
                             y: (viewport.origin.y / Self.anchorSpacing).rounded(.down) * Self.anchorSpacing)
        CanvasAccessibilityElements(session: session, environment: environment, anchor: anchor, focusedIdentifier: $focusedIdentifier)
            .scaleEffect(viewport.scale, anchor: .topLeading)
            .offset(x: (anchor.x - viewport.origin.x) * viewport.scale, y: (anchor.y - viewport.origin.y) * viewport.scale)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .onChange(of: focusedIdentifier) { _, identifier in
                guard let identifier, let node = session.file.node(withIdentifier: identifier) else { return }
                let viewFrame = session.viewport.viewFrame(forBoardFrame: node.frame)
                if !CGRect(origin: .zero, size: session.viewSize).intersects(viewFrame) { session.zoom(toNodeWithIdentifier: identifier) }
            }
    }
}

private struct CanvasAccessibilityElements: View {
    let session: CanvasSession
    let environment: CanvasCardEnvironment
    let anchor: CGPoint
    var focusedIdentifier: AccessibilityFocusState<String?>.Binding
    @Environment(\.openURL) private var openURL
    /// A board with more cards than this lists the first ones in reading order; the rest
    /// are reached by moving the board.
    private static let maximumElementCount = 1_000

    var body: some View {
        let file = session.file
        let readingPositions = session.readingPositions
        let detailedIdentifiers = Set(session.detailedNodes.map(\.id))
        let describedNodes = file.nodes.filter { node in
            !detailedIdentifiers.contains(node.id) && (readingPositions[node.id] ?? .max) < Self.maximumElementCount
        }
        let isWriting = session.isWriting
        let selectedIdentifiers = session.selectedNodeIdentifiers
        ZStack(alignment: .topLeading) {
            ForEach(describedNodes) { node in
                let description = CanvasCardDescription(node: node, file: file)
                Color.clear
                    .frame(width: node.frame.width, height: node.frame.height)
                    .contentShape(Rectangle())
                    .accessibilityElement()
                    .accessibilityLabel(description.label)
                    .accessibilityValue(description.content + (description.content.isEmpty || description.connections.isEmpty ? "" : ". ") + description.connections)
                    .accessibilityHint(isWriting ? "Selects the card" : "Zooms to the card")
                    .accessibilityAddTraits(selectedIdentifiers.contains(node.id) ? [.isButton, .isSelected] : .isButton)
                    // Higher priorities are read first.
                    .accessibilitySortPriority(Double(file.nodes.count - (readingPositions[node.id] ?? 0)))
                    .accessibilityFocused(focusedIdentifier, equals: node.id)
                    .accessibilityIdentifier("canvasCard-" + node.id)
                    .accessibilityAction {
                        if isWriting { session.selectedNodeIdentifiers = [node.id]; session.selectedEdgeIdentifiers = [] }
                        session.zoom(toNodeWithIdentifier: node.id)
                    }
                    .accessibilityActions {
                        if case .file(let path, _) = node.content, let vaultPath = try? VaultPath(path) {
                            Button("Open File") { environment.open(vaultPath) }
                        }
                        if case .link(let address) = node.content, let location = CanvasSession.browsableLocation(of: address) {
                            Button("Open in Browser") { openURL(location) }
                        }
                    }
                    .offset(x: node.frame.minX - anchor.x, y: node.frame.minY - anchor.y)
            }
        }
        .frame(width: 1, height: 1, alignment: .topLeading)
    }
}

/// What a card is called when read aloud: its kind, its color by name, what it shows,
/// and the cards it is connected to.
struct CanvasCardDescription {
    let label: String
    /// What the card shows, for a card whose content is not itself on screen.
    let content: String
    /// The cards it is connected to; empty for none.
    let connections: String
    private static let maximumSpokenTextLength = 400

    init(node: CanvasNode, file: CanvasFile) {
        let colorName = node.color.map { color in color.name + " " } ?? ""
        var spokenContent = ""
        switch node.content {
        case .text(let text):
            label = colorName + "Text card"
            spokenContent = String(text.prefix(Self.maximumSpokenTextLength))
        case .file(let path, let subpath):
            let kind = (try? VaultPath(path)).map(DocumentKind.init(path:)) ?? .other
            label = colorName + (kind == .markdown ? "Note card" : kind == .image ? "Image card" : kind == .pdf ? "PDF card" : "File card")
            spokenContent = Self.fileTitle(path: path, subpath: subpath)
        case .link(let address):
            label = colorName + "Web link card"
            spokenContent = address
        case .group(let groupLabel, _, _):
            label = colorName + "Group"
            spokenContent = groupLabel ?? "No name"
        case .unknown(let type):
            label = colorName + "Card"
            spokenContent = type.isEmpty ? "Of a kind Graphite does not know" : "Of the kind “\(type)”, which Graphite does not know"
        }
        let connectedTitles = file.edges.compactMap { edge -> String? in
            let otherName = edge.fromNode == node.identifierInFile ? edge.toNode : edge.toNode == node.identifierInFile ? edge.fromNode : nil
            guard let otherName, let otherNode = file.node(named: otherName) else { return nil }
            return Self.shortTitle(of: otherNode) + (edge.label.map { edgeLabel in " (\(edgeLabel))" } ?? "")
        }
        content = spokenContent
        connections = connectedTitles.isEmpty ? "" : "Connected to " + connectedTitles.prefix(8).joined(separator: ", ")
    }

    /// A file card's name as shown above it: the file's name, without `.md` for a note,
    /// and the heading, block or page it shows.
    static func fileTitle(path: String, subpath: String?) -> String {
        let name = (path as NSString).lastPathComponent
        let title = name.lowercased().hasSuffix(".md") ? String(name.dropLast(3)) : name
        guard let subpath, subpath.count > 1 else { return title }
        return title + " > " + subpath.dropFirst()
    }

    private static func shortTitle(of node: CanvasNode) -> String {
        switch node.content {
        case .text(let text): String((text.split(whereSeparator: \.isNewline).first ?? "Empty card").prefix(60))
        case .file(let path, let subpath): fileTitle(path: path, subpath: subpath)
        case .link(let address): address
        case .group(let label, _, _): label ?? "Group"
        case .unknown: "Card"
        }
    }
}

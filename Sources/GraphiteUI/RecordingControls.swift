import SwiftUI
import AVFoundation
import GraphiteCore
import GraphiteApple

// MARK: Toolbar control

/// The recording control in the window's toolbar: starts an audio or a video recording,
/// then shows its time with every action in one menu.
struct RecordingControl: View {
    @Bindable var workspace: WorkspaceModel
    @State private var showsDiscardConfirmation = false
    @Environment(\.openURL) private var openURL

    private var controller: RecordingController { workspace.recording }

    var body: some View {
        control
            .confirmationDialog("Delete this recording?", isPresented: $showsDiscardConfirmation, titleVisibility: .visible) {
                Button("Delete Recording", role: .destructive) { controller.discardRecoveredRecording() }
            } message: {
                Text("It could not be saved into the vault, and this is its only copy.")
            }
    }

    @ViewBuilder private var control: some View {
        if controller.canStartRecording && controller.message == nil {
            Menu("Record Lecture", systemImage: "mic") { startItems }
                .accessibilityIdentifier("recordLecture")
        } else {
            // One menu, not a row of buttons: a toolbar gives a custom view one narrow slot,
            // which cut the row's Pause and Stop buttons off.
            Menu {
                if let message = controller.message { Text(message) }
                if let accessProblem = controller.accessProblem, accessProblem.canBeChangedInSettings {
                    Button("Open Settings", systemImage: "gear") { openURL(RecordingControlModel.settingsLocation) }
                }
                if controller.state == .recording { Button("Pause", systemImage: "pause.fill") { controller.pause() } }
                if controller.state.canResume { Button("Resume", systemImage: "record.circle") { controller.resume() } }
                if controller.state.canStop { Button("Stop and Save", systemImage: "stop.fill") { controller.stop() } }
                if controller.state == .requestingPermission { Button("Cancel", systemImage: "xmark") { controller.cancelStart() } }
                if controller.kind == .video && controller.state.canStop { videoItems }
                if controller.state == .failed && controller.recoveryURL != nil {
                    Button("Try Saving Again") { Task { await workspace.retryRecordingPublication() } }
                    Button("Discard Recording…", systemImage: "trash", role: .destructive) { showsDiscardConfirmation = true }
                }
                if RecordingControlModel.canDismissMessage(state: controller.state, message: controller.message, hasRecordingToSave: controller.recoveryURL != nil) {
                    Button("Dismiss Message", systemImage: "xmark.circle") { controller.dismissMessage() }
                }
                // A recording waiting to be saved or discarded is the only copy of its lecture.
                if controller.canStartRecording {
                    Divider()
                    startItems
                }
            } label: {
                HStack(spacing: 6) {
                    if controller.state.canStart {
                        Image(systemName: "exclamationmark.circle").foregroundStyle(.orange)
                    } else {
                        Circle().fill(controller.state == .recording ? Color.red : Color.orange).frame(width: 8, height: 8)
                        switch controller.state {
                        case .requestingPermission: Text("Starting…")
                        case .finalizing: Text("Saving…")
                        default:
                            TimelineView(.periodic(from: .now, by: 1)) { _ in
                                Text(Duration.seconds(controller.elapsedSeconds).formatted(.time(pattern: .hourMinuteSecond))).monospacedDigit()
                            }
                        }
                        // Something happened that the menu explains, such as a video
                        // that paused while Graphite was off screen.
                        if controller.message != nil { Image(systemName: "exclamationmark.circle").foregroundStyle(.orange) }
                    }
                }
                .font(.callout)
            }
            .accessibilityLabel(RecordingControlModel.accessibilityDescription(state: controller.state, kind: controller.kind, hasMessage: controller.message != nil))
            .accessibilityIdentifier("recordingControl")
        }
    }

    @ViewBuilder private var startItems: some View {
        Button("Record Audio", systemImage: "mic") { Task { await workspace.startRecording(.audio) } }
        Button("Record Video", systemImage: "video") { Task { await workspace.startRecording(.video) } }
        Picker("Camera", systemImage: "arrow.triangle.2.circlepath.camera", selection: Binding(get: { workspace.preferences.recordingCamera },
                                                                                                set: { camera in workspace.preferences.recordingCamera = camera })) {
            ForEach(CameraPosition.allCases, id: \.self) { camera in Text(RecordingControlModel.title(of: camera)).tag(camera) }
        }
        .pickerStyle(.menu)
    }

    @ViewBuilder private var videoItems: some View {
        if let otherCamera = RecordingControlModel.cameraToSwitchTo(from: controller.camera, available: controller.availableCameras), controller.state != .interrupted {
            Button("Use \(RecordingControlModel.title(of: otherCamera))", systemImage: "arrow.triangle.2.circlepath.camera") {
                controller.switchCamera(to: otherCamera)
                workspace.preferences.recordingCamera = otherCamera
            }
        }
        Button(workspace.showsRecordingPreview ? "Hide Camera Preview" : "Show Camera Preview", systemImage: workspace.showsRecordingPreview ? "eye.slash" : "eye") {
            workspace.showsRecordingPreview.toggle()
        }
    }
}

/// What the recording control shows, apart from its views.
enum RecordingControlModel {
    /// Graphite's page in the system's settings, where camera and microphone access are changed.
    static var settingsLocation: URL {
        #if canImport(UIKit)
        URL(string: UIApplication.openSettingsURLString) ?? URL(fileURLWithPath: "/")
        #else
        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") ?? URL(fileURLWithPath: "/")
        #endif
    }

    static func title(of camera: CameraPosition) -> String {
        switch camera {
        case .back: "Back Camera"
        case .front: "Front Camera"
        }
    }

    /// The camera a recording can change to; nil when the device has only the one in use.
    static func cameraToSwitchTo(from camera: CameraPosition, available: [CameraPosition]) -> CameraPosition? {
        available.first { availableCamera in availableCamera != camera }
    }

    /// A message can be dismissed when it only reports what happened: while recording goes
    /// on, after a recording was saved, or when one could not start. One about a recording
    /// that waits for a decision stays.
    static func canDismissMessage(state: RecordingState, message: String?, hasRecordingToSave: Bool) -> Bool {
        guard message != nil else { return false }
        switch state {
        case .recording, .idle: return true
        case .failed: return !hasRecordingToSave
        case .requestingPermission, .paused, .interrupted, .finalizing: return false
        }
    }

    static func accessibilityDescription(state: RecordingState, kind: RecordingKind, hasMessage: Bool) -> String {
        let subject = kind == .video ? "Video recording" : "Recording"
        switch state {
        case .requestingPermission: return "\(subject) is starting"
        case .recording: return hasMessage ? "\(subject), with a message" : subject
        case .paused, .interrupted: return "\(subject) paused"
        case .finalizing: return "Saving the recording"
        case .idle, .failed: return hasMessage ? "Recording message" : "Recording problem"
        }
    }
}

// MARK: Camera preview

/// The camera's picture while a video is recorded, floating over the documents: it can be
/// dragged anywhere, resized from its corner, and hidden. The recording does not depend on it.
struct RecordingPreviewOverlay: View {
    @Bindable var workspace: WorkspaceModel
    /// Where the preview's middle is, as fractions of the space it floats in, so it keeps
    /// its place when the window changes size.
    @State private var position = UnitPoint(x: 1, y: 1)
    @State private var width = RecordingPreviewLayout.defaultWidth
    @State private var positionWhenDragBegan: UnitPoint?
    @State private var widthWhenResizeBegan: CGFloat?

    private var controller: RecordingController { workspace.recording }

    var body: some View {
        GeometryReader { geometry in
            if RecordingPreviewLayout.isShown(kind: controller.kind, state: controller.state, showsPreview: workspace.showsRecordingPreview) {
                let size = RecordingPreviewLayout.size(width: width, aspectRatio: controller.videoAspectRatio, in: geometry.size)
                let panelCenter = RecordingPreviewLayout.center(at: position, size: size, in: geometry.size)
                panel(size: size)
                    .position(panelCenter)
                    .gesture(DragGesture(minimumDistance: 2, coordinateSpace: .named(RecordingPreviewLayout.coordinateSpaceName))
                        .onChanged { drag in
                            let startPosition = positionWhenDragBegan ?? position
                            positionWhenDragBegan = startPosition
                            position = RecordingPreviewLayout.position(startPosition, movedBy: drag.translation, size: size, in: geometry.size)
                        }
                        .onEnded { _ in positionWhenDragBegan = nil })
            }
        }
        .coordinateSpace(.named(RecordingPreviewLayout.coordinateSpaceName))
    }

    private func panel(size: CGSize) -> some View {
        ZStack {
            Color.black
            CameraPreviewView(controller: controller)
                // A front camera is shown as a mirror; the file is not mirrored.
                .scaleEffect(x: controller.camera == .front ? -1 : 1)
            if controller.state != .recording {
                Color.black.opacity(0.55)
                Label("Paused", systemImage: "pause.fill").font(.callout.weight(.semibold)).foregroundStyle(.white)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(0.25)))
        .shadow(color: .black.opacity(0.3), radius: 10, y: 4)
        .overlay(alignment: .topLeading) { recordingStatus }
        .overlay(alignment: .topTrailing) {
            Button("Hide Camera Preview", systemImage: "xmark") { workspace.showsRecordingPreview = false }
                .labelStyle(.iconOnly).font(.caption.weight(.bold)).foregroundStyle(.white)
                .frame(width: 28, height: 28).background(.black.opacity(0.5), in: Circle())
                .contentShape(Circle().inset(by: -8))
                .buttonStyle(.plain)
                .padding(6)
                .help("Hide the preview. The recording goes on.")
        }
        .overlay(alignment: .bottomTrailing) { resizeHandle }
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Camera preview")
        .accessibilityIdentifier("recordingPreview")
    }

    private var recordingStatus: some View {
        HStack(spacing: 5) {
            Circle().fill(controller.state == .recording ? Color.red : Color.orange).frame(width: 7, height: 7)
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                Text(Duration.seconds(controller.elapsedSeconds).formatted(.time(pattern: .hourMinuteSecond))).monospacedDigit()
            }
        }
        .font(.caption.weight(.medium)).foregroundStyle(.white)
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(.black.opacity(0.5), in: Capsule())
        .padding(6)
        .accessibilityElement(children: .combine)
    }

    private var resizeHandle: some View {
        Image(systemName: "arrow.up.left.and.arrow.down.right")
            .font(.caption.weight(.bold)).foregroundStyle(.white)
            .frame(width: 28, height: 28).background(.black.opacity(0.5), in: Circle())
            .contentShape(Circle().inset(by: -8))
            .padding(6)
            .highPriorityGesture(DragGesture(minimumDistance: 1, coordinateSpace: .named(RecordingPreviewLayout.coordinateSpaceName))
                .onChanged { drag in
                    let startWidth = widthWhenResizeBegan ?? width
                    widthWhenResizeBegan = startWidth
                    width = RecordingPreviewLayout.clampedWidth(startWidth + drag.translation.width)
                }
                .onEnded { _ in widthWhenResizeBegan = nil })
            .accessibilityLabel("Resize camera preview")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: width = RecordingPreviewLayout.clampedWidth(width + RecordingPreviewLayout.accessibilityWidthStep)
                case .decrement: width = RecordingPreviewLayout.clampedWidth(width - RecordingPreviewLayout.accessibilityWidthStep)
                @unknown default: break
                }
            }
    }
}

/// Where the camera preview is and how large, kept apart from its view.
enum RecordingPreviewLayout {
    static let coordinateSpaceName = "RecordingPreview"
    static let defaultWidth: CGFloat = 240
    static let minimumWidth: CGFloat = 140
    static let maximumWidth: CGFloat = 640
    static let accessibilityWidthStep: CGFloat = 60
    /// Kept between the preview and the edges of the space it floats in.
    static let margin: CGFloat = 16
    /// The picture's shape until the camera's first frame tells it.
    static let defaultAspectRatio = 16.0 / 9.0

    static func isShown(kind: RecordingKind, state: RecordingState, showsPreview: Bool) -> Bool {
        kind == .video && showsPreview && state.canStop
    }

    static func clampedWidth(_ width: CGFloat) -> CGFloat {
        min(max(width, minimumWidth), maximumWidth)
    }

    /// The preview's size: the chosen width in the camera's shape, made smaller where the
    /// space has no room for it.
    static func size(width: CGFloat, aspectRatio: Double?, in container: CGSize) -> CGSize {
        let aspectRatio = CGFloat(aspectRatio.flatMap { ratio in ratio > 0 ? ratio : nil } ?? defaultAspectRatio)
        let availableWidth = max(container.width - 2 * margin, 1), availableHeight = max(container.height - 2 * margin, 1)
        let fittedWidth = min(clampedWidth(width), availableWidth, availableHeight * aspectRatio)
        return CGSize(width: fittedWidth, height: fittedWidth / aspectRatio)
    }

    /// The middle of a preview of `size` at `position`, which is (0, 0) in the top leading
    /// corner of the space and (1, 1) in the bottom trailing one, inside the margin.
    static func center(at position: UnitPoint, size: CGSize, in container: CGSize) -> CGPoint {
        let horizontalRoom = max(container.width - size.width - 2 * margin, 0), verticalRoom = max(container.height - size.height - 2 * margin, 0)
        return CGPoint(x: margin + size.width / 2 + horizontalRoom * min(max(position.x, 0), 1),
                       y: margin + size.height / 2 + verticalRoom * min(max(position.y, 0), 1))
    }

    /// The position after a drag by `translation`, kept inside the space.
    static func position(_ position: UnitPoint, movedBy translation: CGSize, size: CGSize, in container: CGSize) -> UnitPoint {
        let horizontalRoom = container.width - size.width - 2 * margin, verticalRoom = container.height - size.height - 2 * margin
        return UnitPoint(x: horizontalRoom > 0 ? min(max(position.x + translation.width / horizontalRoom, 0), 1) : position.x,
                         y: verticalRoom > 0 ? min(max(position.y + translation.height / verticalRoom, 0), 1) : position.y)
    }
}

/// Shows the frames of the video being recorded. The layer's renderer is given to the
/// recording while the view is on screen.
#if canImport(UIKit)
private struct CameraPreviewView: UIViewRepresentable {
    let controller: RecordingController

    func makeCoordinator() -> CameraPreviewCoordinator { CameraPreviewCoordinator(controller: controller) }

    func makeUIView(context: Context) -> CameraPreviewLayerView {
        let view = CameraPreviewLayerView()
        if let displayLayer = view.layer as? AVSampleBufferDisplayLayer { context.coordinator.show(in: displayLayer) }
        return view
    }

    func updateUIView(_ view: CameraPreviewLayerView, context: Context) {}

    static func dismantleUIView(_ view: CameraPreviewLayerView, coordinator: CameraPreviewCoordinator) {
        coordinator.stopShowing()
    }
}

/// A view whose layer shows the camera's frames.
final class CameraPreviewLayerView: UIView {
    override static var layerClass: AnyClass { AVSampleBufferDisplayLayer.self }
}
#else
private struct CameraPreviewView: NSViewRepresentable {
    let controller: RecordingController

    func makeCoordinator() -> CameraPreviewCoordinator { CameraPreviewCoordinator(controller: controller) }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        let displayLayer = AVSampleBufferDisplayLayer()
        view.layer = displayLayer
        view.wantsLayer = true
        context.coordinator.show(in: displayLayer)
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {}

    static func dismantleNSView(_ view: NSView, coordinator: CameraPreviewCoordinator) {
        coordinator.stopShowing()
    }
}
#endif

/// Gives a preview layer's renderer to the recording, and takes it back when the view goes.
@MainActor
private final class CameraPreviewCoordinator {
    private let controller: RecordingController
    private var renderer: AVSampleBufferVideoRenderer?

    init(controller: RecordingController) {
        self.controller = controller
    }

    func show(in displayLayer: AVSampleBufferDisplayLayer) {
        displayLayer.videoGravity = .resizeAspect
        renderer = displayLayer.sampleBufferRenderer
        controller.showPreview(in: displayLayer.sampleBufferRenderer)
    }

    func stopShowing() {
        // A newer preview may already show the camera; it keeps it.
        if let renderer { controller.stopShowingPreview(in: renderer) }
        renderer = nil
    }
}

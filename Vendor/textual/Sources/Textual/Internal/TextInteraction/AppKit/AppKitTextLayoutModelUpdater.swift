#if TEXTUAL_ENABLE_TEXT_SELECTION && canImport(AppKit) && !targetEnvironment(macCatalyst)
  import SwiftUI

  // MARK: - Overview
  //
  // Graphite patch: `AppKitTextLayoutModelUpdater` passes the text's latest layout collection to
  // the `TextSelectionModel`.
  //
  // SwiftUI calls a representable's `updateNSView` at every update with the latest values, so
  // the model always holds the layouts on screen. An `onChange` action runs at most once per
  // frame and misses the later changes of a frame. The view it hosts is hidden and takes no
  // clicks; it exists for its update.

  typealias PlatformTextLayoutModelUpdater = AppKitTextLayoutModelUpdater

  struct AppKitTextLayoutModelUpdater: NSViewRepresentable {
    let model: TextSelectionModel
    let coordinator: TextSelectionCoordinator?
    let layoutCollection: any TextLayoutCollection

    func makeNSView(context: Context) -> NSView {
      let view = NSView()
      view.isHidden = true
      updateModel()
      return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
      updateModel()
    }

    private func updateModel() {
      model.setCoordinator(coordinator)
      model.setLayoutCollection(layoutCollection)
    }
  }
#endif

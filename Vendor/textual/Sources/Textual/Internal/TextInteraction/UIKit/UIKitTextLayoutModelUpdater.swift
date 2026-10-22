#if TEXTUAL_ENABLE_TEXT_SELECTION && canImport(UIKit)
  import SwiftUI

  // MARK: - Overview
  //
  // Graphite patch: `UIKitTextLayoutModelUpdater` passes the text's latest layout collection to
  // the `TextSelectionModel`.
  //
  // SwiftUI calls a representable's `updateUIView` at every update with the latest values, so
  // the model always holds the layouts on screen. An `onChange` action runs at most once per
  // frame and misses the later changes of a frame. The view it hosts is hidden and takes no
  // touches; it exists for its update.

  typealias PlatformTextLayoutModelUpdater = UIKitTextLayoutModelUpdater

  struct UIKitTextLayoutModelUpdater: UIViewRepresentable {
    let model: TextSelectionModel
    let coordinator: TextSelectionCoordinator?
    let layoutCollection: any TextLayoutCollection

    func makeUIView(context: Context) -> UIView {
      let view = UIView()
      view.isHidden = true
      view.isUserInteractionEnabled = false
      updateModel()
      return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
      updateModel()
    }

    private func updateModel() {
      model.setCoordinator(coordinator)
      model.setLayoutCollection(layoutCollection)
    }
  }
#endif

import UIKit
import SwiftUI
import ShareInbox

/// The share extension's entry point (`NSExtensionPrincipalClass`): shows the share sheet
/// and ends the request when the person saves or cancels. It never reaches a vault; a saved
/// share waits in the App Group's inbox for the app.
final class ShareViewController: UIViewController {
    private lazy var model = ShareComposeModel(inbox: Self.inbox())

    override func viewDidLoad() {
        super.viewDidLoad()
        let host = UIHostingController(rootView: ShareComposeView(model: model, cancel: { [weak self] in self?.cancel() },
                                                                  save: { [weak self] in self?.save() }))
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor), host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor), host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        host.didMove(toParent: self)
        let extensionItems = extensionContext?.inputItems.compactMap { item in item as? NSExtensionItem } ?? []
        Task { await model.load(extensionItems, sharedAt: .now) }
    }

    /// The inbox in the App Group named in this extension's `Info.plist`; nil when the
    /// extension is not entitled to it.
    private static func inbox() -> ShareInbox? {
        guard let groupIdentifier = Bundle.main.object(forInfoDictionaryKey: "GraphiteApplicationGroup") as? String,
              let container = ShareInbox.applicationGroupContainer(identifier: groupIdentifier) else { return nil }
        return ShareInbox(containerFolder: container)
    }

    private func save() {
        do {
            try model.save(sharedAt: .now)
            extensionContext?.completeRequest(returningItems: nil)
        } catch {
            let alert = UIAlertController(title: "Couldn't Save", message: error.localizedDescription, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
        }
    }

    private func cancel() {
        model.discard()
        extensionContext?.cancelRequest(withError: CocoaError(.userCancelled))
    }
}

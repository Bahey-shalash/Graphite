import SwiftUI

/// Gives the views below the window's templates and keeps them on the open vault: the New
/// Notebook sheets read `MyTemplatesModel` from the environment.
struct MyTemplatesEnvironment: ViewModifier {
    let model: MyTemplatesModel
    let vaultIdentifier: UUID?
    let source: MyTemplatesModel.Source?

    func body(content: Content) -> some View {
        content
            .environment(model)
            .task(id: vaultIdentifier) { model.use(source) }
    }
}

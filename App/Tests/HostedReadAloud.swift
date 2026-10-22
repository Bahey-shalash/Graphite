#if os(iOS)
@testable import GraphiteUI

extension WorkspaceModel {
    /// The reader of a workspace whose Read Aloud plugin these tests turned on.
    var activeReadAloud: ReadAloudController {
        guard let readAloud else { preconditionFailure("The Read Aloud core plugin was turned on when the workspace was made.") }
        return readAloud
    }

    var activeReadAloudNavigator: ReadAloudNavigator {
        guard let readAloudNavigator else { preconditionFailure("The Read Aloud core plugin was turned on when the workspace was made.") }
        return readAloudNavigator
    }
}
#endif

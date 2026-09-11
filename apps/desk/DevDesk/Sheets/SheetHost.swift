import DeskCore
import SwiftUI

struct SheetHost: View {
    @Bindable var model: ProjectWindowModel
    let kind: SheetKind

    var body: some View {
        EmptyStateView(title: "Sheet", message: "")
    }
}

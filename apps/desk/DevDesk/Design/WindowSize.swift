import SwiftUI

/// The window's own size, for the things that have to fit inside it. A sheet is not in the window's view
/// hierarchy geometry, so it cannot measure the window it covers — it inherits this instead, and clamps
/// itself rather than being clipped.
private struct DeskWindowSizeKey: EnvironmentKey {
    static let defaultValue = CGSize(width: DeskMetric.dialogWidth + DeskMetric.dialogWindowInset,
                                     height: DeskMetric.dialogHeight + DeskMetric.dialogWindowInset)
}

extension EnvironmentValues {
    var deskWindowSize: CGSize {
        get { self[DeskWindowSizeKey.self] }
        set { self[DeskWindowSizeKey.self] = newValue }
    }
}

extension CGSize {
    /// What a panel of this ideal size may actually take here: never wider than the window minus its inset.
    func clamped(to ideal: CGSize) -> CGSize {
        CGSize(width: min(ideal.width, max(width - DeskMetric.dialogWindowInset, 320)),
               height: min(ideal.height, max(height - DeskMetric.dialogWindowInset, 320)))
    }
}

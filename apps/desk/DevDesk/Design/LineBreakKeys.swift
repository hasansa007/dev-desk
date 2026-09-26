import AppKit
import SwiftUI

/// ⇧↩, ⌥↩, ⌃↩ and ⌘↩ break the line in a multi-line field, the keys a session's terminal answers the same way. A
/// vertical `TextField` gives a bare ↩ to the sheet's default button, and with a modifier ↩ went nowhere useful:
/// ⌘↩ is Start Task in the menu, and the rest did nothing a person could see.
///
/// A local monitor, for the reason the terminal has one: it runs before AppKit dispatches the key, so the menu's
/// ⌘↩ cannot take it first. It exists only while the field has focus, so everywhere else ⌘↩ is still Start Task.
/// The break goes in through the field editor at the caret, never appended to the bound string.
private struct LineBreakKeys: ViewModifier {
    @FocusState private var isFocused: Bool
    @State private var monitor: Any?

    func body(content: Content) -> some View {
        content
            .focused($isFocused)
            .onChange(of: isFocused) { _, focused in focused ? start() : stop() }
            .onDisappear { stop() }
    }

    private func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard event.keyCode == 36, !modifiers.isDisjoint(with: [.shift, .option, .control, .command]),
                  let editor = event.window?.firstResponder as? NSTextView else { return event }
            editor.insertNewlineIgnoringFieldEditor(nil)
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}

extension View {
    /// Modified ↩ breaks the line here instead of confirming the sheet or starting a task.
    func lineBreakKeys() -> some View { modifier(LineBreakKeys()) }
}

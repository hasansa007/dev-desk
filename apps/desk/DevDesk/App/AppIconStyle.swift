import AppKit
import SwiftUI

/// Applies the chosen app icon to the running app and to the bundle on disk.
///
/// The choice is two preferences deep. `AppIconChoice` says light, dark, or system; `system` defers
/// to `AppearanceChoice`, which itself may say system and defer to the OS. `resolve` walks that chain
/// once and lands on a concrete `.light` or `.dark`.
///
/// Applying it has two halves because they refresh at different speeds. `NSApp.applicationIconImage`
/// changes the running Dock tile this instant but dies with the process. `NSWorkspace.setIcon`
/// writes a custom icon onto the bundle so Finder and the next launch see it too — but a reinstall
/// `ditto`s a fresh bundle over this one (see install.sh) and wipes that custom icon. So neither half
/// is enough alone, and `apply` is called again at every launch from `QuitGuard`: the on-disk icon is
/// re-asserted after an install wiped it, and the session icon is set for the run either way.
///
/// The running tile is always set to a concrete image, never `nil`. Assigning `nil` for the light
/// case looks right — it should mean "fall back to the bundle icon" — but AppKit does not repaint a
/// running Dock tile on that assignment, so switching Dark→Light left the dark tile up until relaunch.
/// Handing it the actual shipped-icon image forces the repaint now.
///
/// `setIcon` returns false on a read-only or unwritable bundle. That is not fatal — the session icon
/// is already applied, so the Dock still reflects the choice for this run — so the failure is logged
/// once and left there, never retried in a spin.
@MainActor
enum AppIconStyle {
    /// The concrete artwork a pair of preferences resolves to right now.
    enum Resolved {
        case light, dark
    }

    static let darkImageName = "AppIconDark"

    /// Read both preferences and the OS appearance and decide which artwork to wear.
    ///
    /// The app icon preference decides first. Only its `system` defers, and it defers to the
    /// appearance preference: an explicit Light/Dark there settles it, and only that preference's own
    /// `system` hands the question to `NSApp.effectiveAppearance`.
    static func resolve() -> Resolved {
        let defaults = UserDefaults.standard
        let icon = defaults.string(forKey: PreferenceKey.appIcon)
            .flatMap(AppIconChoice.init(rawValue:)) ?? .system
        switch icon {
        case .light: return .light
        case .dark: return .dark
        case .system:
            let appearance = defaults.string(forKey: PreferenceKey.appearance)
                .flatMap(AppearanceChoice.init(rawValue:)) ?? .system
            switch appearance {
            case .light: return .light
            case .dark: return .dark
            case .system: return systemIsDark() ? .dark : .light
            }
        }
    }

    /// The image the current choice resolves to, at native size, for a Settings preview or the Dock.
    /// Never reads `NSApp.applicationIconImage`, which holds whatever was last applied and would show
    /// the dark art as the "light" preview right after a switch.
    static func resolvedImage() -> NSImage? {
        switch resolve() {
        case .light: return lightImage()
        case .dark: return NSImage(named: darkImageName)
        }
    }

    /// The shipped light icon, loaded from the asset catalog. `applicationIconName` is the fallback
    /// for when the named asset cannot be found; it reads the bundle's actual app icon.
    static func lightImage() -> NSImage? {
        NSImage(named: "AppIcon") ?? NSImage(named: NSImage.applicationIconName)
    }

    /// Apply the resolved icon to both the running app and the bundle on disk.
    static func apply() {
        switch resolve() {
        case .light:
            // Pass nil to setIcon to remove any custom icon and let the bundle's shipped AppIcon show
            // through on disk. But the running Dock tile gets the concrete light image, not nil:
            // assigning nil does not repaint a live tile, so a Dark→Light switch stayed dark until
            // relaunch. Handing it the image forces the repaint now.
            setBundleIcon(nil)
            NSApp.applicationIconImage = lightImage()
        case .dark:
            let image = NSImage(named: darkImageName)
            if image == nil {
                NSLog("AppIconStyle: dark icon image '\(darkImageName)' not found; keeping shipped icon")
            }
            setBundleIcon(image)
            NSApp.applicationIconImage = image
        }
    }

    private static func systemIsDark() -> Bool {
        NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }

    private static func setBundleIcon(_ image: NSImage?) {
        let ok = NSWorkspace.shared.setIcon(image, forFile: Bundle.main.bundlePath, options: [])
        if !ok {
            NSLog("AppIconStyle: could not write the app icon onto \(Bundle.main.bundlePath) "
                  + "(read-only or unwritable bundle); the session Dock icon is still applied")
        }
    }
}

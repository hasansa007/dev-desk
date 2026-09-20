import AppKit
import DeskCore
import SwiftUI

extension Color {
    /// Resolves per appearance, so both the system setting and `.preferredColorScheme` apply.
    static func desk(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                           green: CGFloat((hex >> 8) & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255,
                           alpha: 1)
        })
    }
}

struct ToneColors {
    let foreground, fill, border, dot, body: Color
}

enum DeskColor {
    /// Console, 2026-09-20: every pair is the same hex twice, so light renders dark until a light palette
    /// is drawn (redesign decision 3). The `desk(_:_:)` shape stays so reintroducing one touches no call site.
    static let accent = Color.desk(0x9CC0FF, 0x9CC0FF)
    static let accentHover = Color.desk(0x7AA2F7, 0x7AA2F7)
    /// Three grounds over the page (#0F1114), one colour each — the Console rewrite of the 2026-09-19 rule:
    /// strip + dock (#0B0D10) · bar, which the rail and the title bar share (#14171B) · surface, the tiles
    /// and cards (#16191E). Anything else here is a state or a detail, never a fourth ground.
    static let surface = Color.desk(0x16191E, 0x16191E)
    static let canvas = Color.desk(0x0F1114, 0x0F1114)
    /// The rail and the title bar. It was the strip's near-black, which made the two one unbroken column
    /// with the strip's divider invisible inside it (2026-09-20, on screen).
    static let sidebar = Color.desk(0x14171B, 0x14171B)
    /// The floor of the window: the project strip and the dock behind its tiles, a step below everything.
    static let strip = Color.desk(0x0B0D10, 0x0B0D10)
    static let inspector = Color.desk(0x0B0D10, 0x0B0D10)
    static let headerFill = Color.desk(0x14171B, 0x14171B)
    static let border = Color.desk(0x343A44, 0x343A44)
    static let controlBorder = Color.desk(0x454A53, 0x454A53)
    static let divider = Color.desk(0x262B33, 0x262B33)
    /// The hairline under a bar, one step quieter than a divider between panes.
    static let rowDivider = Color.desk(0x1E2228, 0x1E2228)
    static let ink = Color.desk(0xE4E7EB, 0xE4E7EB)
    static let navInk = Color.desk(0xC9CDD4, 0xC9CDD4)
    static let secondaryInk = Color.desk(0xB8BEC8, 0xB8BEC8)
    static let mutedInk = Color.desk(0x8E96A3, 0x8E96A3)
    static let faintInk = Color.desk(0x7C8796, 0x7C8796)
    static let disabledDot = Color.desk(0x5A606A, 0x5A606A)
    /// A raised control on a surface, and the same control hovered.
    static let neutralChipFill = Color.desk(0x1B1F25, 0x1B1F25)
    static let neutralChipFill2 = Color.desk(0x262B33, 0x262B33)
    static let titlebarFill = Color.desk(0x14171B, 0x14171B)
    static let titlebarBorder = Color.desk(0x343A44, 0x343A44)
    /// Ink on a filled accent, green or amber control — the Console never puts white on a colour.
    static let onColorInk = Color.desk(0x0F1114, 0x0F1114)

    /// Deliberately a muted green, not the running green: a diff hunk is not a run (redesign decision 4).
    static let diffAddFill = Color.desk(0x16301F, 0x16301F)
    static let diffAddInk = Color.desk(0x9FDDB2, 0x9FDDB2)
    static let diffDeleteFill = Color.desk(0x331A1A, 0x331A1A)
    static let diffDeleteInk = Color.desk(0xF3A6A6, 0xF3A6A6)

    /// A terminal is one step below the surface behind it, and borrows the rest of the palette so a tile
    /// stops reading as another app pasted into the window (2026-09-20).
    static let terminalGround = Color.desk(0x14161A, 0x14161A)
    static let terminalInk = Color.desk(0xD7DBE0, 0xD7DBE0)
    static let terminalBar = Color.desk(0x14171B, 0x14171B)
    static let terminalDim = Color.desk(0x7C8796, 0x7C8796)
    static let terminalDim2 = Color.desk(0x9BA3AE, 0x9BA3AE)
    static let terminalOK = Color.desk(0x7FD19B, 0x7FD19B)
    static let terminalError = Color.desk(0xF19A9A, 0xF19A9A)
    static let terminalControlFill = Color.desk(0x1B1F25, 0x1B1F25)
    static let terminalControlBorder = Color.desk(0x343A44, 0x343A44)
    /// Was black, which cut a trench between tiles no other edge in the window has.
    static let terminalPaneBorder = Color.desk(0x262B33, 0x262B33)

    static func tone(_ tone: StatusTone) -> ToneColors {
        switch tone {
        case .running: return running
        case .waiting: return waiting
        case .failed: return failed
        case .info: return info
        case .neutral: return neutral
        case .ended: return ended
        }
    }

    /// Green is running and amber is waiting, and nothing else may borrow either (redesign decision 4):
    /// `info` is the blue accent, `neutral` and `ended` stay grey and differ only in their dot.
    private static let running = ToneColors(
        foreground: .desk(0x7FD19B, 0x7FD19B), fill: .desk(0x16301F, 0x16301F),
        border: .desk(0x245C38, 0x245C38), dot: .desk(0x7FD19B, 0x7FD19B), body: .desk(0x9FDDB2, 0x9FDDB2))
    private static let waiting = ToneColors(
        foreground: .desk(0xE7C067, 0xE7C067), fill: .desk(0x33280F, 0x33280F),
        border: .desk(0x5C4718, 0x5C4718), dot: .desk(0xE7C067, 0xE7C067), body: .desk(0xD9C79A, 0xD9C79A))
    private static let failed = ToneColors(
        foreground: .desk(0xF19A9A, 0xF19A9A), fill: .desk(0x331A1A, 0x331A1A),
        border: .desk(0x5E2B2B, 0x5E2B2B), dot: .desk(0xF19A9A, 0xF19A9A), body: .desk(0xE0B4B4, 0xE0B4B4))
    private static let info = ToneColors(
        foreground: .desk(0x9CC0FF, 0x9CC0FF), fill: .desk(0x1B2A45, 0x1B2A45),
        border: .desk(0x2F4B7C, 0x2F4B7C), dot: accent, body: ink)
    private static let neutral = ToneColors(
        foreground: secondaryInk, fill: neutralChipFill, border: border, dot: disabledDot, body: secondaryInk)
    private static let ended = ToneColors(
        foreground: secondaryInk, fill: neutralChipFill, border: border, dot: faintInk, body: secondaryInk)
}

/// The Console is monospaced throughout; the one place the prototype is not is the count inside a project
/// badge, which is too small for a mono digit and carries its own face there.
enum DeskFont {
    static let title = Font.system(size: 16, weight: .semibold, design: .monospaced)
    static let section = Font.system(size: 15, weight: .semibold, design: .monospaced)
    static let body = Font.system(size: 13, design: .monospaced)
    static let secondary = Font.system(size: 12, design: .monospaced)
    static let small = Font.system(size: 11.5, design: .monospaced)
    /// `SectionLabel` adds the uppercase and 0.66pt tracking a `Font` cannot carry.
    static let label = Font.system(size: 11, weight: .bold, design: .monospaced)

    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

enum DeskMetric {
    /// Every tab's header row, and the optional controls row under it (ADR 0046 decision 14).
    static let screenHeaderHeight: CGFloat = 48
    /// Sessions' tab row under its header.
    static let screenBarHeight: CGFloat = 44
    /// Every chip in a second row (ADR 0046 decision 15).
    static let chipHeight: CGFloat = 28
    static let sidebarWidth: CGFloat = 236
    /// Icons only, tooltips carrying the titles. The window's floor was 1100 pt, which an 11" iPad as a
    /// display fits with no margin and a half-screen MacBook does not fit at all.
    static let sidebarRailWidth: CGFloat = 64
    /// Below this the sidebar becomes the rail by itself; above it, the choice is the developer's again.
    static let railBreakpoint: CGFloat = 1100
    /// The floor the window can be dragged or tiled to, so a quarter of a common display still opens it;
    /// the board scrolls its columns long before here.
    static let windowMinWidth: CGFloat = 360
    static let windowMinHeight: CGFloat = 620
    static let inspectorWidth: CGFloat = 262
    /// Runs is the bottom edge of the window: deep enough for a terminal, shallow enough to leave the work visible.
    static let runsPanelHeight: CGFloat = 300
    /// Deep enough for a terminal, and never so deep the work behind it disappears.
    static let runsHeightRange: ClosedRange<Double> = 140...760
    /// Files is the right edge: a tree over a viewer, so it is narrow.
    static let filesPanelWidth: CGFloat = 420
    static let filesWidthRange: ClosedRange<Double> = 260...900
    static let boardColumnWidth: CGFloat = 300
    /// Every small control shares these: search fields, toggles and the toolbar's pill. Buttons carry their own table in `DeskButtonStyle.Size`.
    static let controlHeight: CGFloat = 26
    static let controlRadius: CGFloat = 6
    static let cardRadius: CGFloat = 8
    /// Inside a board card, on every side; the ⋯ and Start overlays sit on the same inset.
    static let cardPadding: CGFloat = 16
    /// A board card is one block whatever it holds, so a column reads as a column and not as a ragged list.
    /// Two lines of title, meta, ratings, then one bottom band shared by the note and the action.
    static let cardContentHeight: CGFloat = 132
    /// Room the title leaves for the ⋮ overlay, which takes no layout space of its own.
    static let cardMenuInset: CGFloat = 30
    static let cardTitleHeight: CGFloat = 38
    /// One height for a column's header, so a long title truncates instead of dropping its own column a row.
    static let columnHeaderHeight: CGFloat = 18
    static let pillRadius: CGFloat = 10
    static let sheetRadius: CGFloat = 12
    /// Every dialog is exactly this size, so opening one never changes shape under you. A sheet cannot
    /// choose its own: `SheetChrome` takes neither a width nor a height, and its body scrolls instead.
    static let dialogWidth: CGFloat = 900
    static let dialogHeight: CGFloat = 660
    static let confirmWidth: CGFloat = 600
    /// A dialog is a maximum, not a size (ADR 0021, amended): it clamps to the window rather than being
    /// clipped by it. The inset is what keeps it reading as a dialog over the board at every width.
    static let dialogWindowInset: CGFloat = 40
    /// A tile in Terminals: two or four up gets a working height, one up gets the room a single session wants.
    static let terminalTileHeight: CGFloat = 360
    static let terminalTileTallHeight: CGFloat = 620
}

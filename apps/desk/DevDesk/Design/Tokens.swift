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
    static let accent = Color.desk(0x2F6FEB, 0x3B7BF0)
    static let accentHover = Color.desk(0x2A63D2, 0x2A63D2)
    static let surface = Color.desk(0xFFFFFF, 0x1E2025)
    static let canvas = Color.desk(0xFBFBFC, 0x17191D)
    static let sidebar = Color.desk(0xF1F2F5, 0x202329)
    static let inspector = Color.desk(0xF7F8F9, 0x1B1D22)
    static let headerFill = Color.desk(0xF4F5F7, 0x23262C)
    static let border = Color.desk(0xDCDFE4, 0x34383F)
    static let controlBorder = Color.desk(0xC9CDD4, 0x454A53)
    static let divider = Color.desk(0xE3E6EA, 0x2C3036)
    static let rowDivider = Color.desk(0xEEF0F3, 0x282B31)
    static let ink = Color.desk(0x16181D, 0xE6E8EC)
    static let navInk = Color.desk(0x3C4149, 0xC9CDD4)
    static let secondaryInk = Color.desk(0x4B5563, 0xAEB4BD)
    static let mutedInk = Color.desk(0x6B7280, 0x969CA6)
    static let faintInk = Color.desk(0x8A9099, 0x7D838D)
    static let disabledDot = Color.desk(0xB9BEC6, 0x5A606A)
    static let neutralChipFill = Color.desk(0xEEF0F3, 0x2A2D33)
    static let neutralChipFill2 = Color.desk(0xF2F3F5, 0x292C32)
    static let titlebarFill = Color.desk(0xEDEFF2, 0x2A2D33)
    static let titlebarBorder = Color.desk(0xD3D7DD, 0x3A3E45)

    static let diffAddFill = Color.desk(0xE7F6EC, 0x17301F)
    static let diffAddInk = Color.desk(0x1F5C36, 0x9FDDB2)
    static let diffDeleteFill = Color.desk(0xFDEAEA, 0x3A1C1E)
    static let diffDeleteInk = Color.desk(0x8A1F1F, 0xF3A6A6)

    static let terminalGround = Color.desk(0x14161A, 0x14161A)
    static let terminalInk = Color.desk(0xD7DBE0, 0xD7DBE0)
    static let terminalBar = Color.desk(0x1C1F25, 0x1C1F25)
    static let terminalDim = Color.desk(0x7C8796, 0x7C8796)
    static let terminalDim2 = Color.desk(0x9BA3AE, 0x9BA3AE)
    static let terminalOK = Color.desk(0x7ED492, 0x7ED492)
    static let terminalError = Color.desk(0xF08A8A, 0xF08A8A)
    static let terminalControlFill = Color.desk(0x242830, 0x242830)
    static let terminalControlBorder = Color.desk(0x343A44, 0x343A44)
    static let terminalPaneBorder = Color.desk(0x000000, 0x000000)

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

    private static let running = ToneColors(
        foreground: .desk(0x1F6B41, 0x7FD19B), fill: .desk(0xE4F4EA, 0x16301F),
        border: .desk(0xBFE3CD, 0x245C38), dot: .desk(0x1F8B4C, 0x1F8B4C), body: .desk(0x1F5C36, 0x9FDDB2))
    private static let waiting = ToneColors(
        foreground: .desk(0x8A6114, 0xE7C067), fill: .desk(0xFBF2DE, 0x33280F),
        border: .desk(0xEBDAAE, 0x5C4718), dot: .desk(0xB7791F, 0xB7791F), body: .desk(0x5C4A1A, 0xD9C79A))
    private static let failed = ToneColors(
        foreground: .desk(0x8A1F1F, 0xF19A9A), fill: .desk(0xFDF6F6, 0x331A1A),
        border: .desk(0xF0CFCF, 0x5E2B2B), dot: .desk(0xC0392B, 0xC0392B), body: .desk(0x6B2020, 0xE0B4B4))
    private static let info = ToneColors(
        foreground: .desk(0x1F4FB0, 0x9CC0FF), fill: .desk(0xE7EFFD, 0x1B2A45),
        border: .desk(0xC3D7F8, 0x2F4B7C), dot: accent, body: ink)
    private static let neutral = ToneColors(
        foreground: secondaryInk, fill: neutralChipFill, border: border, dot: disabledDot, body: secondaryInk)
    private static let ended = ToneColors(
        foreground: secondaryInk, fill: neutralChipFill, border: border, dot: faintInk, body: secondaryInk)
}

enum DeskFont {
    static let title = Font.system(size: 16, weight: .semibold)
    static let section = Font.system(size: 15, weight: .semibold)
    static let body = Font.system(size: 13)
    static let secondary = Font.system(size: 12)
    static let small = Font.system(size: 11.5)
    /// `SectionLabel` adds the uppercase and 0.66pt tracking a `Font` cannot carry.
    static let label = Font.system(size: 11, weight: .bold)

    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

enum DeskMetric {
    static let sidebarWidth: CGFloat = 236
    static let inspectorWidth: CGFloat = 262
    /// Runs is the bottom edge of the window: deep enough for a terminal, shallow enough to leave the work visible.
    static let runsPanelHeight: CGFloat = 300
    /// Files is the right edge: a tree over a viewer, so it is narrow.
    static let filesPanelWidth: CGFloat = 420
    static let boardColumnWidth: CGFloat = 246
    /// Every small control shares these: search fields, toggles and the toolbar's pill. Buttons carry their own table in `DeskButtonStyle.Size`.
    static let controlHeight: CGFloat = 26
    static let controlRadius: CGFloat = 6
    static let cardRadius: CGFloat = 8
    /// A board card is one block whatever it holds, so a column reads as a column and not as a ragged list.
    /// Two lines of title, meta, ratings, then one bottom band shared by the note and the action.
    static let cardContentHeight: CGFloat = 117
    static let cardTitleHeight: CGFloat = 34
    static let pillRadius: CGFloat = 10
    static let sheetRadius: CGFloat = 12
    /// Every dialog is exactly this size, so opening one never changes shape under you. A sheet cannot
    /// choose its own: `SheetChrome` takes neither a width nor a height, and its body scrolls instead.
    static let dialogWidth: CGFloat = 900
    static let dialogHeight: CGFloat = 660
}

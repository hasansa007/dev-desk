import DeskCore
import SwiftUI

struct Sidebar: View {
    let model: ProjectWindowModel
    /// Icons only. A narrow window takes this by itself; above the breakpoint it is the developer's choice.
    var isRail = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            openProjectButton
            // The name and path are the window's own title and subtitle; the sidebar repeated them.
            Color.clear.frame(height: 8)
            if model.snapshot != nil {
                destinations
                Spacer(minLength: 12)
                // Connections used to live here as four permanent rows. Settings → Accounts holds the same
                // four with their identity and their sign-in, so the sidebar copy was a screen you visit
                // twice a year, kept open, with an email address on it (decision 14 made it redundant).
                settingsRow
            } else {
                Spacer(minLength: 0)
            }
        }
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .topLeading)
        .background(DeskColor.sidebar)
        .overlay(alignment: .trailing) {
            Rectangle().fill(DeskColor.border).frame(width: 1)
        }
    }

    /// The one action that is not about this project, so it sits above everything that is — where a
    /// sidebar's primary action belongs, rather than in the toolbar beside the panel toggles.
    private var openProjectButton: some View {
        Button { model.present(.openProject) } label: {
            HStack(spacing: 7) {
                Image(systemName: "plus.circle")
                    .font(.system(size: 20))
                    .frame(width: 24)
                if !isRail {
                    Text("Open project")
                        .font(DeskFont.body.weight(.medium))
                }
            }
            .foregroundStyle(DeskColor.ink)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(DeskColor.surface, in: RoundedRectangle(cornerRadius: DeskMetric.controlRadius))
            .overlay(RoundedRectangle(cornerRadius: DeskMetric.controlRadius).strokeBorder(DeskColor.border))
            .contentShape(RoundedRectangle(cornerRadius: DeskMetric.controlRadius))
        }
        .buttonStyle(.plain)
        .help(isRail ? "Open project (⌘O)" : "⌘O")
        .accessibilityLabel("Open project")
        .padding(.horizontal, isRail ? 8 : 12)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    private var destinations: some View {
        VStack(spacing: 2) {
            ForEach(Destination.sidebar, id: \.self) { destination in
                destinationButton(destination)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
    }

    /// Settings is a dialog, not a place: it sits at the bottom and opens over whatever you were looking at.
    private var settingsRow: some View {
        Button { model.present(.settings) } label: {
            HStack(spacing: 10) {
                Image(systemName: "gearshape").font(.system(size: 20)).frame(width: 24)
                if !isRail {
                    Text("Settings")
                    Spacer(minLength: 4)
                }
            }
            .font(DeskFont.body)
            .foregroundStyle(DeskColor.navInk)
            .padding(.vertical, 10)
            .padding(.horizontal, isRail ? 0 : 10)
            .frame(maxWidth: .infinity)
            .contentShape(RoundedRectangle(cornerRadius: DeskMetric.controlRadius))
        }
        .buttonStyle(.plain)
        .help(isRail ? "Settings" : "")
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
    }

    private func destinationButton(_ destination: Destination) -> some View {
        let isSelected = model.destination == destination
        let badge = badge(for: destination)
        return Button { model.go(destination) } label: {
            HStack(spacing: 10) {
                Image(systemName: symbol(for: destination))
                    .font(.system(size: 20))
                    .frame(width: 24)
                    // A rail still has to show that something needs you: the count becomes a dot on the icon.
                    .overlay(alignment: .topTrailing) {
                        if isRail, let badge, badge.isPending {
                            Circle()
                                .fill(DeskColor.tone(.waiting).dot)
                                .frame(width: 6, height: 6)
                                .offset(x: 5, y: -3)
                        }
                    }
                if !isRail {
                    Text(destination.title)
                    Spacer(minLength: 4)
                    if let badge {
                        Text("\(badge.count)")
                            .font(.system(size: 11, weight: badge.isPending ? .bold : .regular))
                            .foregroundStyle(badgeColor(isPending: badge.isPending, isSelected: isSelected))
                            .opacity(badge.isPending ? 1 : 0.75)
                    }
                }
            }
            .font(DeskFont.body)
            .foregroundStyle(isSelected ? Color.white : DeskColor.navInk)
            .padding(.vertical, 10)
            .padding(.horizontal, isRail ? 0 : 10)
            .frame(maxWidth: .infinity)
            .background(isSelected ? DeskColor.accent : Color.clear, in: RoundedRectangle(cornerRadius: 6))
            .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .help(isRail ? (badge.map { "\(destination.title) · \($0.count)" } ?? destination.title) + " — " + destination.hint
              : destination.hint)
        .accessibilityLabel(badge.map { "\(destination.title), \($0.count)" } ?? destination.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// The board count shows only when the board could be read, so an unavailable board never reads as zero.
    private func badge(for destination: Destination) -> (count: Int, isPending: Bool)? {
        switch destination {
        case .board:
            return model.snapshot?.board.value == nil ? nil : (model.openTaskCount, false)
        case .terminals:
            let live = SessionRow.all(in: model).filter(\.isLive).count
            return live > 0 ? (live, true) : nil
        case .findings:
            guard let count = model.findingsCount, count > 0 else { return nil }
            return (count, false)
        case .ideation:
            guard let count = model.ideationCount, count > 0 else { return nil }
            return (count, false)
        case .roadmap, .diagrams:
            return nil
        }
    }

    private func badgeColor(isPending: Bool, isSelected: Bool) -> Color {
        if isSelected { return .white }
        return isPending ? DeskColor.tone(.waiting).dot : DeskColor.navInk
    }

    private func symbol(for destination: Destination) -> String {
        switch destination {
        case .board: return "square.grid.3x2"
        case .terminals: return "apple.terminal"
        case .roadmap: return "map"
        case .findings: return "scope"
        case .ideation: return "lightbulb"
        case .diagrams: return "rectangle.3.group"
        }
    }

}

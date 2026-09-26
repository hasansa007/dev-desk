import DeskCore
import SwiftUI

struct Sidebar: View {
    let context: ProjectContext
    /// Icons only. A narrow window takes this by itself; above the breakpoint it is the developer's choice.
    var isRail = false
    @State private var isPickingIcon = false

    private var model: ProjectWindowModel { context.model }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            projectIcon
            // The project is not one of the places below it, so a line separates who you are in from where you go.
            Divider().overlay(DeskColor.border).padding(.horizontal, 8).padding(.top, 10).padding(.bottom, 4)
            if model.snapshot != nil {
                destinations
            }
            // Settings left the foot of this rail for the foot of the strip: it is a dialog every screen can
            // open, and a rail exists only inside a project, so Home had no way to reach it but ⌘,.
            Spacer(minLength: 0)
            // The mic (⇧⌘D) is the project's, at the foot of its rail: it types into one of this project's
            // sessions, and on Home — where there is none to type into — it was only ever a dimmed button.
            micButton
        }
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .topLeading)
        .background(DeskColor.sidebar)
        .overlay(alignment: .trailing) {
            Rectangle().fill(DeskColor.border).frame(width: 1)
        }
    }

    /// Which project you are in, at the top of its own rail. It was `+ Open project` — redundant the moment
    /// the strip grew a `+` of its own — and the rail had nothing on it saying which project it belonged to.
    /// Click it to change the project's image, its colour, or to put its initials back.
    private var projectIcon: some View {
        Button { isPickingIcon = true } label: {
            HStack(spacing: 10) {
                ProjectBadge(ref: context.ref, name: context.name, size: 32)
                if !isRail {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(context.name)
                            .font(DeskFont.body.weight(.medium))
                            .foregroundStyle(DeskColor.ink)
                            .lineLimit(1)
                        if !context.branch.isEmpty {
                            Text(context.branch)
                                .font(DeskFont.small)
                                .foregroundStyle(DeskColor.mutedInk)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 4)
                }
            }
            .frame(maxWidth: .infinity, alignment: isRail ? .center : .leading)
            // The same vertical padding and spacing a destination row has, so the two are one size in the rail.
            .padding(.vertical, 8)
            .padding(.horizontal, isRail ? 0 : 8)
            .contentShape(RoundedRectangle(cornerRadius: DeskMetric.controlRadius))
        }
        .buttonStyle(.plain)
        .help("\(context.name) — change its icon")
        .accessibilityLabel("\(context.name), change its icon")
        .popover(isPresented: $isPickingIcon, arrowEdge: .trailing) {
            ProjectIconPicker(ref: context.ref, name: context.name)
        }
        .padding(.horizontal, isRail ? 8 : 12)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    private var destinations: some View {
        VStack(spacing: 6) {
            ForEach(Destination.sidebar, id: \.self) { destination in
                destinationButton(destination)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
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
                    .overlay(alignment: .bottomLeading) { KeyHint(key: String(destination.key)).offset(x: -7, y: 6) }
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
            .foregroundStyle(isSelected ? DeskColor.ink : DeskColor.navInk)
            .padding(.vertical, 10)
            .padding(.horizontal, isRail ? 0 : 10)
            .frame(maxWidth: .infinity)
            // A raised control, not an accent fill: the Console marks the place you are standing with a
            // lighter ground and full-strength ink, and keeps the accent for things you can act on.
            .background(isSelected ? DeskColor.neutralChipFill : Color.clear, in: RoundedRectangle(cornerRadius: 6))
            .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .help((isRail ? (badge.map { "\(destination.title) · \($0.count)" } ?? destination.title) + " — " + destination.hint
               : destination.hint) + " (⌘\(destination.key.uppercased()))")
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
        if isSelected { return isPending ? DeskColor.tone(.waiting).dot : DeskColor.ink }
        return isPending ? DeskColor.tone(.waiting).dot : DeskColor.navInk
    }

    /// Accent while it listens. Dimmed when this project has no session running, but never while listening,
    /// so it can always be stopped.
    private var micButton: some View {
        let dictation = Dictation.shared
        let listening = dictation.voice.isListening
        let available = dictation.isBusy || dictation.candidate(in: context) != nil
        return Button { dictation.toggle(in: context) } label: {
            HStack(spacing: 10) {
                // In its own circle, as it was over the terminal: a bare glyph at the rail's foot read as a label.
                Image(systemName: listening ? "mic.fill" : "mic")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(listening ? DeskColor.onColorInk : DeskColor.navInk)
                    .frame(width: 38, height: 38)
                    .background(listening ? DeskColor.accent : DeskColor.neutralChipFill, in: Circle())
                    .overlay(Circle().strokeBorder(listening ? DeskColor.accent : DeskColor.controlBorder))
                    .overlay(alignment: .bottomLeading) { KeyHint(key: "d", modifiers: "⇧⌘").offset(x: -7, y: 6) }
                if !isRail {
                    Text(listening ? "Listening…" : "Dictate")
                        .foregroundStyle(DeskColor.navInk)
                    Spacer(minLength: 4)
                }
            }
            .font(DeskFont.body)
            .opacity(available ? 1 : 0.4)
            .padding(.vertical, 6)
            .padding(.horizontal, isRail ? 0 : 6)
            .frame(maxWidth: .infinity)
            .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .disabled(!available)
        .help(listening ? "Stop dictating and type what was heard (⇧⌘D)"
              : available ? "Dictate into the session in front (⇧⌘D)" : "Dictate (⇧⌘D) — needs a running session")
        .accessibilityLabel(listening ? "Stop dictating" : "Dictate")
        .padding(.horizontal, 8)
        .padding(.bottom, 24)
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

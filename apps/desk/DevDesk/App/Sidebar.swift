import DeskCore
import SwiftUI

struct Sidebar: View {
    let model: ProjectWindowModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if let snapshot = model.snapshot {
                destinations
                Spacer(minLength: 12)
                settingsRow
                connections(snapshot)
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

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("Project")
            Text(model.snapshot?.project.name ?? model.ref.displayName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(DeskColor.ink)
                .padding(.top, 4)
            if let project = model.snapshot?.project {
                Text(project.remote ?? project.displayPath)
                    .font(DeskFont.mono(11))
                    .foregroundStyle(DeskColor.faintInk)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.top, 2)
            }
        }
        .padding(.top, 14)
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
    }

    private var destinations: some View {
        VStack(spacing: 2) {
            ForEach(Destination.allCases.filter { $0 != .settings }, id: \.self) { destination in
                destinationButton(destination)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
    }

    /// Settings sits at the bottom, away from the destinations that answer "what is happening"; its ⌘ shortcut is unchanged.
    private var settingsRow: some View {
        destinationButton(.settings)
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
    }

    private func destinationButton(_ destination: Destination) -> some View {
        let isSelected = model.destination == destination
        let badge = badge(for: destination)
        return Button { model.go(destination) } label: {
            HStack(spacing: 9) {
                Image(systemName: symbol(for: destination))
                    .frame(width: 16)
                Text(destination.title)
                Spacer(minLength: 4)
                if let badge {
                    Text("\(badge.count)")
                        .font(.system(size: 11, weight: badge.isPending ? .bold : .regular))
                        .foregroundStyle(badgeColor(isPending: badge.isPending, isSelected: isSelected))
                        .opacity(badge.isPending ? 1 : 0.75)
                }
            }
            .font(DeskFont.body)
            .foregroundStyle(isSelected ? Color.white : DeskColor.navInk)
            .padding(.vertical, 7)
            .padding(.horizontal, 10)
            .background(isSelected ? DeskColor.accent : Color.clear, in: RoundedRectangle(cornerRadius: 6))
            .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(badge.map { "\(destination.title), \($0.count)" } ?? destination.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// The board count shows only when the board could be read, so an unavailable board never reads as zero.
    private func badge(for destination: Destination) -> (count: Int, isPending: Bool)? {
        switch destination {
        case .board:
            return model.snapshot?.board.value == nil ? nil : (model.openTaskCount, false)
        case .findings:
            guard let count = model.findingsCount, count > 0 else { return nil }
            return (count, false)
        case .ideation:
            guard let count = model.ideationCount, count > 0 else { return nil }
            return (count, false)
        case .decisions:
            return model.pendingDecisionCount > 0 ? (model.pendingDecisionCount, true) : nil
        case .roadmap, .settings:
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
        case .roadmap: return "map"
        case .findings: return "scope"
        case .ideation: return "lightbulb"
        case .decisions: return "questionmark.diamond"
        case .settings: return "gearshape"
        }
    }

    private func connections(_ snapshot: ProjectSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Connections")
            ForEach(snapshot.connections) { connection in
                connectionRow(connection)
            }
            if !snapshot.connectionsNote.isEmpty {
                Text(snapshot.connectionsNote)
                    .font(.system(size: 11))
                    .foregroundStyle(DeskColor.faintInk)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) {
            Rectangle().fill(DeskColor.border).frame(height: 1)
        }
    }

    private func connectionRow(_ connection: Connection) -> some View {
        let style = style(for: connection.state)
        return HStack(spacing: 8) {
            StatusDot(tone: style.tone)
            Text(connection.name)
            Spacer(minLength: 4)
            Text(connection.label)
                .font(.system(size: 11))
                .foregroundStyle(style.label)
        }
        .font(DeskFont.secondary)
        .foregroundStyle(style.text)
        .accessibilityElement(children: .combine)
    }

    private func style(for state: ConnectionState) -> (tone: StatusTone, text: Color, label: Color) {
        switch state {
        case .connected: return (.running, DeskColor.navInk, DeskColor.faintInk)
        case .detected: return (.info, DeskColor.navInk, DeskColor.faintInk)
        case .notConnected, .missing: return (.neutral, DeskColor.faintInk, DeskColor.faintInk)
        case .unavailable:
            let failed = DeskColor.tone(.failed).dot
            return (.failed, failed, failed)
        }
    }
}

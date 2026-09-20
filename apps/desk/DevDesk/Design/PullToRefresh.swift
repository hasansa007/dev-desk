import DeskCore
import SwiftUI

/// Pull the top of a screen down to reload it.
///
/// macOS has no pull-to-refresh: `.refreshable` compiles here but draws no control and offers no
/// gesture, so the reload lived in the toolbar as a countdown ring — a control that spent its life
/// explaining a wait nobody had asked about. The gesture people already try is the one that works on
/// every list they use elsewhere, so this is built on the thing macOS does give: elastic overscroll.
///
/// A sentinel at the top of the scrolled content reports where it sits in the scroll view's own
/// coordinate space. Past the threshold the reload fires once, and it re-arms only after the content
/// has gone back to rest — otherwise one long drag reloads a dozen times.
struct PullToRefresh: ViewModifier {
    let isRefreshing: Bool
    let action: () async -> Void

    @State private var offset: CGFloat = 0
    @State private var armed = true

    /// How far the content has to come down before the reload fires.
    private static let threshold: CGFloat = 64
    private static let space = "desk.pullToRefresh"

    func body(content: Content) -> some View {
        content
            .background(alignment: .top) {
                GeometryReader { proxy in
                    Color.clear.preference(key: PullOffsetKey.self,
                                           value: proxy.frame(in: .named(Self.space)).minY)
                }
                .frame(height: 0)
            }
            .overlay(alignment: .top) { indicator }
            .onPreferenceChange(PullOffsetKey.self) { value in
                offset = value
                guard armed, !isRefreshing, value > Self.threshold else {
                    if value <= 1 { armed = true }
                    return
                }
                armed = false
                Task { await action() }
            }
    }

    /// It appears in the space the drag opens, so nothing moves when there is no drag.
    @ViewBuilder private var indicator: some View {
        if isRefreshing || offset > 6 {
            HStack(spacing: 7) {
                if isRefreshing {
                    ProgressView().controlSize(.small)
                    Text("Reloading…")
                } else {
                    Image(systemName: offset > Self.threshold ? "arrow.clockwise" : "arrow.down")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                    Text(offset > Self.threshold ? "Release to reload" : "Pull to reload")
                }
            }
            .font(DeskFont.secondary)
            .foregroundStyle(DeskColor.mutedInk)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(DeskColor.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(DeskColor.border))
            .padding(.top, 6)
            .transition(.opacity)
            .allowsHitTesting(false)
        }
    }
}

private struct PullOffsetKey: SwiftUI.PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

extension View {
    /// Applied to the content **inside** a ScrollView; the scroll view itself carries the coordinate space.
    func pullToRefresh(isRefreshing: Bool, action: @escaping () async -> Void) -> some View {
        modifier(PullToRefresh(isRefreshing: isRefreshing, action: action))
    }

    /// Applied to the ScrollView, so the sentinel above has something to measure against.
    func pullToRefreshSpace() -> some View {
        coordinateSpace(name: "desk.pullToRefresh")
    }
}

import DeskCore
import SwiftUI

/// Every tab's header, and the only one (ADR 0046 decision 14): the title and its ⓘ, one status line, then the tools
/// and at most one primary button — always last, so it sits at the far right on every tab. It spans the content's
/// full width; a tab's inner list (milestones, diagram kinds, ideas) starts below it, so the title
/// never moves when that list is there or collapsed. A tab's own controls go in `ScreenBar` directly under it.
struct ScreenHeader<Status: View, Tools: View>: View {
    let title: String
    let guide: ScreenGuideButton
    @ViewBuilder var status: () -> Status
    @ViewBuilder var tools: () -> Tools

    init(_ destination: Destination, extra: String? = nil,
         @ViewBuilder status: @escaping () -> Status, @ViewBuilder tools: @escaping () -> Tools) {
        self.title = destination.title
        self.guide = ScreenGuideButton(destination: destination, extra: extra)
        self.status = status
        self.tools = tools
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(DeskFont.section)
                .foregroundStyle(DeskColor.ink)
                .fixedSize()
                .accessibilityAddTraits(.isHeader)
            guide
            status()
                .font(DeskFont.secondary)
                .foregroundStyle(DeskColor.mutedInk)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.leading, 2)
                .layoutPriority(-1)
            Spacer(minLength: 8)
            tools()
        }
        .padding(.horizontal, 16)
        .frame(height: DeskMetric.screenHeaderHeight)
        .frame(maxWidth: .infinity)
        .background(DeskColor.canvas)
        .overlay(alignment: .bottom) { Rectangle().fill(DeskColor.divider).frame(height: 1) }
    }
}

/// The optional second row: a tab's own controls — chip groups (`FilterChip`), session tabs — full width, under
/// the header. The leading groups scroll sideways on a narrow window rather than squeezing a chip's words; the
/// trailing ones (Findings' Group, a filter row's Clear) stay pinned right. A tab with nothing here shows none.
struct ScreenBar<Content: View, Trailing: View>: View {
    @ViewBuilder var content: () -> Content
    @ViewBuilder var trailing: () -> Trailing

    init(@ViewBuilder content: @escaping () -> Content, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.content = content
        self.trailing = trailing
    }

    var body: some View {
        HStack(spacing: 10) {
            ScrollView(.horizontal) {
                HStack(spacing: 6) { content() }
                    .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)
            HStack(spacing: 6) { trailing() }.fixedSize()
        }
        .padding(.horizontal, 16)
        .frame(minHeight: DeskMetric.screenBarHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DeskColor.canvas)
        .overlay(alignment: .bottom) { Rectangle().fill(DeskColor.divider).frame(height: 1) }
    }
}

extension ScreenBar where Trailing == EmptyView {
    init(@ViewBuilder content: @escaping () -> Content) {
        self.init(content: content, trailing: { EmptyView() })
    }
}

import SwiftUI

/// One launcher row's styled label — the single source of truth for how an app
/// name renders. Shared by the home-screen widget and the in-app preview.
/// Tappability (Link / widgetURL) is added by the caller; this is purely visual.
struct LauncherRowLabel: View {
    let name: String
    let theme: Theme
    var dimmed: Bool = false
    var lineLimit: Int = 1

    /// Letter spacing, in points. Proportional faces are drawn with tracking
    /// tuned for body copy, so at these display sizes they read loose; -2% is
    /// the usual approximation of the tightening SF's optical sizing applies.
    /// Monospaced gets 0 deliberately: its fixed advance width is the reason to
    /// choose it, and tracking would shift every glyph off that grid.
    ///
    /// TWIN: `trackingFor` in `src/theme/tokens.ts` computes the same number.
    private var tracking: CGFloat {
        theme.font == .monospaced ? 0 : -theme.size.widgetPointSize * 0.02
    }

    var body: some View {
        Text(name)
            .font(theme.widgetFont)
            .fontWeight(.semibold)
            .tracking(tracking)
            .foregroundStyle(theme.textColor.opacity(dimmed ? 0.5 : 1))
            .lineLimit(lineLimit)
            .minimumScaleFactor(0.5)
            .multilineTextAlignment(theme.alignment.textAlignment)
            .frame(maxWidth: .infinity, alignment: theme.alignment.frameAlignment)
    }
}

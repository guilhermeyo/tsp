import SwiftUI

/// One launcher row's styled label — the single source of truth for how an app
/// name renders. Shared by the home-screen widget and the in-app preview.
/// Tappability (Link / widgetURL) is added by the caller; this is purely visual.
struct LauncherRowLabel: View {
    let name: String
    let theme: Theme
    var dimmed: Bool = false
    var lineLimit: Int = 1

    var body: some View {
        Text(name)
            .font(theme.widgetFont)
            .fontWeight(.semibold)
            .foregroundStyle(theme.textColor.opacity(dimmed ? 0.5 : 1))
            .lineLimit(lineLimit)
            .minimumScaleFactor(0.5)
            .multilineTextAlignment(theme.alignment.textAlignment)
            .frame(maxWidth: .infinity, alignment: theme.alignment.frameAlignment)
    }
}

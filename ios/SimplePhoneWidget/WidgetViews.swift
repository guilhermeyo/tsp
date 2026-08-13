import SwiftUI
import WidgetKit

struct LauncherWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: LauncherEntry

    private var theme: Theme { entry.theme }

    var body: some View {
        content
            .containerBackground(for: .widget) { theme.backgroundColor }
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .systemSmall:
            smallView
        case .systemLarge:
            listView(limit: 6)
        default:
            listView(limit: 3)
        }
    }

    private var smallView: some View {
        Group {
            if let first = entry.apps.first {
                LauncherRowLabel(name: first.name, theme: theme)
            } else {
                emptyLabel
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: theme.alignment.frameAlignment)
        .padding()
        .widgetURL(entry.apps.first.map { DeepLink.launchURL(for: $0) })
    }

    private func listView(limit: Int) -> some View {
        VStack(alignment: theme.alignment.horizontalAlignment, spacing: 16) {
            if entry.apps.isEmpty {
                emptyLabel
            } else {
                ForEach(entry.apps.prefix(limit)) { app in
                    Link(destination: DeepLink.launchURL(for: app)) {
                        LauncherRowLabel(name: app.name, theme: theme)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: theme.alignment.frameAlignment)
        .padding()
    }

    private var emptyLabel: some View {
        LauncherRowLabel(
            name: Self.emptyMessage(language: entry.language),
            theme: theme,
            dimmed: true,
            lineLimit: 2)
    }

    /// The DECLARED TWIN of `src/components/WidgetPreviewCard.tsx`, which draws
    /// the same sentence in the in-app preview from the JS catalog. All four
    /// must match word for word, or the preview on the Appearance screen
    /// disagrees with the widget sitting on the home screen behind it.
    ///
    /// It lives in Swift rather than in that catalog because the extension's
    /// `Bundle.main` is the .appex: this process cannot read the app bundle's
    /// quotes.json. Same primary-subtag matching as
    /// `WeatherWidgetView.emptyMessage`, and for the same reasons — see the
    /// comment there for why it is `prefix(2)` and not `hasPrefix`.
    ///
    /// "Simple Phone" is the brand and is not translated in any of the four.
    private static func emptyMessage(language: String) -> String {
        switch language.lowercased().prefix(2) {
        case "pt": return "Adicione apps no Simple Phone"
        case "es": return "Añade apps en Simple Phone"
        case "ja": return "Simple Phoneでアプリを追加"
        default: return "Add apps in Simple Phone"
        }
    }
}

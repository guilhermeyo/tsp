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
        LauncherRowLabel(name: "Add apps in Simple Phone", theme: theme, dimmed: true, lineLimit: 2)
    }
}

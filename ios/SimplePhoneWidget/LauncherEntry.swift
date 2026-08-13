import WidgetKit

struct LauncherEntry: TimelineEntry {
    let date: Date
    let apps: [LauncherApp]
    let theme: Theme
}

import WidgetKit

struct LauncherProvider: TimelineProvider {
    func placeholder(in context: Context) -> LauncherEntry {
        let config = LauncherConfig.default
        return LauncherEntry(date: Date(), apps: config.apps, theme: config.theme)
    }

    func getSnapshot(in context: Context, completion: @escaping (LauncherEntry) -> Void) {
        completion(makeEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<LauncherEntry>) -> Void) {
        completion(Timeline(entries: [makeEntry()], policy: .never))
    }

    private func makeEntry() -> LauncherEntry {
        let config = ConfigStore.load()
        return LauncherEntry(date: Date(), apps: config.apps, theme: config.theme)
    }
}

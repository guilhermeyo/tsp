import WidgetKit

struct LauncherProvider: TimelineProvider {
    func placeholder(in context: Context) -> LauncherEntry {
        let config = LauncherConfig.default
        // `.default` and not `ConfigStore.load()` here is deliberate and is
        // called out in AGENTS.md as a thing not to "fix". Its `language` is
        // seeded from `Locale.autoupdatingCurrent.identifier`, so the gallery
        // placeholder speaks the device's language — the best available guess
        // when there may be no config to read at all.
        return LauncherEntry(
            date: Date(),
            apps: config.apps,
            theme: config.theme,
            language: config.language)
    }

    func getSnapshot(in context: Context, completion: @escaping (LauncherEntry) -> Void) {
        completion(makeEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<LauncherEntry>) -> Void) {
        completion(Timeline(entries: [makeEntry()], policy: .never))
    }

    private func makeEntry() -> LauncherEntry {
        let config = ConfigStore.load()
        // The STORED tag wins over the device locale unconditionally. A user who
        // put the app in English on a Japanese phone gets an English widget.
        return LauncherEntry(
            date: Date(),
            apps: config.apps,
            theme: config.theme,
            language: config.language)
    }
}

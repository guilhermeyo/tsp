import WidgetKit

struct LauncherEntry: TimelineEntry {
    let date: Date
    let apps: [LauncherApp]
    let theme: Theme
    /// BCP-47, from `config.language`, and copied in for the same reason `apps`
    /// and `theme` are: a view that read the store at draw time would render
    /// whatever the config says THEN, not what the entry was built from.
    ///
    /// The only string this widget owns is its empty label, so this field does
    /// nothing until the user has no apps at all. It is still an entry value
    /// rather than a lookup inside the view, because the empty label is the one
    /// thing a brand-new install sees first.
    let language: String
}

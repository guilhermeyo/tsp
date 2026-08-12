import Foundation

/// One launchable row on the widget: a display name and the exact URL string
/// we hand to `UIApplication.open` (e.g. "instagram://", "https://news.ycombinator.com").
struct LauncherApp: Identifiable, Codable, Equatable, Hashable {
    var id: UUID
    var name: String
    var urlString: String

    init(id: UUID = UUID(), name: String, urlString: String) {
        self.id = id
        self.name = name
        self.urlString = urlString
    }
}

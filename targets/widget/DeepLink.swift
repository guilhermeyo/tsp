import Foundation

/// The relay contract shared by the widget and the host app.
///
/// A widget row links to `launchURL(for:)` — NEVER to the third-party scheme
/// directly, because iOS always delivers a widget tap to the widget's OWN host
/// app. The host parses the link in `onOpenURL` and opens the real target.
enum DeepLink {
    static let scheme = "simplephone"
    static let host = "open"
    private static let queryKey = "u"

    /// `simplephone://open?u=<app url>` — what a widget row points at.
    static func launchURL(for app: LauncherApp) -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.queryItems = [URLQueryItem(name: queryKey, value: app.urlString)]
        return components.url!
    }

    /// The third-party URL to open, or nil if `url` isn't one of ours.
    static func target(from url: URL) -> URL? {
        guard url.scheme == scheme,
              url.host == host,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let raw = components.queryItems?.first(where: { $0.name == queryKey })?.value,
              let target = URL(string: raw)
        else { return nil }
        return target
    }
}

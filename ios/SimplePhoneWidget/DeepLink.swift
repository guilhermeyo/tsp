import Foundation

/// The relay contract shared by the widget and the host app.
///
/// A widget row links to `launchURL(for:)` — NEVER to the third-party scheme
/// directly, because iOS always delivers a widget tap to the widget's OWN host
/// app. The host parses the link in `onOpenURL` and opens the real target.
enum DeepLink {
    /// Deliberately NOT "simplephone": the original Swift app is still installed
    /// on the same device and claims that scheme. Two installed apps registering
    /// the same scheme is undefined behaviour — iOS picks one, and which one is
    /// not something we get to decide. Keep this distinct from the old app's
    /// scheme for as long as both can coexist on a device.
    static let scheme = "simplephonern"
    static let host = "open"
    private static let queryKey = "u"

    /// RFC 3986 unreserved characters, and nothing else.
    ///
    /// Spelled out as literal ASCII rather than built from `.alphanumerics`,
    /// because `.alphanumerics` is the full Unicode letter/digit set: it would
    /// leave "é" in a target URL unescaped, and a non-ASCII byte assigned to
    /// `percentEncodedQuery` makes `components.url` return nil, which the force
    /// unwrap below turns into a crash inside the widget extension.
    private static let unreserved = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
    )

    /// `simplephonern://weather` — what the weather widget points at.
    ///
    /// A new HOST on the same scheme, never a new scheme. `target(from:)` and
    /// its twin in the app both require `host == "open"`, so this one is not a
    /// relay: the app's handler returns false, the URL falls through to
    /// `RCTLinkingManager`, and Expo Router routes it to /weather. Adding a
    /// second scheme would instead mean a second entry in Info.plist and
    /// another chance to collide with the old Swift app.
    static let weatherURL = URL(string: "\(scheme)://weather")!

    /// `simplephonern://open?u=<percent-encoded app url>` — what a widget row points at.
    static func launchURL(for app: LauncherApp) -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = host

        // Not `queryItems`. That path encodes with `.urlQueryAllowed`, which
        // permits ? & and = to pass through literally, so a target that carries
        // its own query string (https://x.com/search?q=a&b=c) serialises into a
        // query the parser can no longer split unambiguously and `target(from:)`
        // hands back a truncated URL. Encoding every reserved character by hand
        // leaves exactly one `=` and zero `&` in the string we produce.
        let encoded = app.urlString.addingPercentEncoding(withAllowedCharacters: unreserved) ?? ""
        components.percentEncodedQuery = "\(queryKey)=\(encoded)"

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

import Foundation

/// The single serialized unit of shared state: the chosen apps, the theme, the
/// weather settings and the language everything is read in.
struct LauncherConfig: Codable, Equatable {
    var apps: [LauncherApp]
    var theme: Theme
    var weather: WeatherSettings
    /// A BCP-47 tag the app resolved once and now owns: "pt-BR" or "en".
    ///
    /// A plain String rather than an enum, and that is the point. This value is
    /// only ever handed to `Locale(identifier:)`, which accepts anything and
    /// falls back sensibly, so a tag this build has never seen costs nothing.
    /// An enum would throw on it, and a throw here is how configs die.
    var language: String

    static let `default` = LauncherConfig(apps: BundledDefaults.apps, theme: .default)

    init(
        apps: [LauncherApp],
        theme: Theme,
        weather: WeatherSettings = .default,
        language: String = Locale.autoupdatingCurrent.identifier
    ) {
        self.apps = apps
        self.theme = theme
        self.weather = weather
        self.language = language
    }

    /// Hand-written, and it MUST stay hand-written.
    ///
    /// This type used to rely on the synthesized decoder, which throws
    /// `keyNotFound` for any stored property the payload does not carry. Every
    /// config already on a device was written before `weather` and `language`
    /// existed, so adding them as stored properties with the synthesized
    /// decoder in place would have thrown on the very first load, been swallowed
    /// by `try?` in `ConfigStore.load()`, and reset the user's entire app list
    /// to `BundledDefaults` — with no crash, no log and no way to get it back.
    /// A new field must never be able to take the apps with it.
    ///
    /// `apps` is the one exception: it is decoded with `try`, because a payload
    /// with no apps array is not a config at all, and `.default` is the right
    /// answer for that. Every other field degrades to its own default.
    ///
    /// `(try? c.decode(...))` and NOT `decodeIfPresent`. `decodeIfPresent`
    /// returns nil only for an absent or null key; it THROWS on a wrong type
    /// (the JS `true` arriving as `1`, if config ever crossed as an object) and
    /// on an unknown enum raw value. Those throws escape and lose everything.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        apps = try c.decode([LauncherApp].self, forKey: .apps)
        theme = (try? c.decode(Theme.self, forKey: .theme)) ?? .default
        weather = (try? c.decode(WeatherSettings.self, forKey: .weather)) ?? .default
        // Absent only in a config written before this feature. The system
        // locale is a better guess than a hardcoded language, and the app
        // rewrites the key with a resolved tag on its next launch anyway.
        language = (try? c.decode(String.self, forKey: .language))
            ?? Locale.autoupdatingCurrent.identifier
    }
}

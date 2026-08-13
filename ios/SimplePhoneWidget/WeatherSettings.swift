import Foundation

/// Celsius or Fahrenheit, resolved by the app and stored concretely.
///
/// There is no `.system` case on purpose. The app reads the region once, on
/// first run, and writes the answer; the widget never has to resolve anything.
/// It is the same rule `quotes.durationMs` follows: whatever can be decided in
/// one place is decided in the app, so this side stays a reader.
///
/// The forecast is always FETCHED in Celsius and converted at render, so
/// changing this costs no network round trip and cannot invalidate a good
/// cache.
enum TemperatureUnit: String, Codable, CaseIterable {
    case celsius
    case fahrenheit

    var isFahrenheit: Bool { self == .fahrenheit }
}

/// The weather half of the shared config. Mirrors `Weather` in src/domain/types.ts.
///
/// Everything here is optional-with-a-default on the way in, because this
/// struct decodes payloads written before it existed. See `init(from:)`.
struct WeatherSettings: Codable, Equatable {
    /// Whether the user wants the weather widget to show anything at all.
    var enabled: Bool
    /// Nil until a city is picked. The two coordinates are only ever written
    /// together; a lone latitude is not a location.
    var latitude: Double?
    var longitude: Double?
    /// The label the user chose in the app, shown verbatim. Not localized here:
    /// the geocoding request in the app already asked for it in their language.
    var placeName: String
    var unit: TemperatureUnit

    /// Deliberately has NO city. A forecast for a place the user never chose is
    /// worse than a widget that says it needs configuring, and the app seeds a
    /// real place the moment they pick one.
    static let `default` = WeatherSettings(
        enabled: true,
        latitude: nil,
        longitude: nil,
        placeName: "",
        unit: .celsius
    )

    /// The compiled-in city, and the ONLY place a hardcoded location is
    /// acceptable.
    ///
    /// This plays exactly the role `BundledDefaults.apps` plays for the
    /// launcher: on a free personal team the App Group entitlement may not be
    /// signed, in which case this extension reads its own empty sandbox and can
    /// never see what the user configured. Rendering a real forecast for a real
    /// place is a better failure than rendering an empty box forever, and it is
    /// immediately obvious that it is not their city.
    ///
    /// A tuple rather than a `WeatherSettings`, so it is impossible to
    /// accidentally treat it as a stored configuration and write it back.
    static let fallbackPlace: (latitude: Double, longitude: Double, name: String) =
        (latitude: -23.5475, longitude: -46.6361, name: "São Paulo")

    init(
        enabled: Bool = true,
        latitude: Double? = nil,
        longitude: Double? = nil,
        placeName: String = "",
        unit: TemperatureUnit = .celsius
    ) {
        self.enabled = enabled
        self.latitude = latitude
        self.longitude = longitude
        self.placeName = placeName
        self.unit = unit
    }

    /// Per-field resilience, and `try?` rather than `decodeIfPresent` on every
    /// one of them.
    ///
    /// `decodeIfPresent` returns nil only for an ABSENT or NULL key. It THROWS
    /// on a value of the wrong type, and on a raw value no enum case matches —
    /// so the day `TemperatureUnit` gains a case that an older build has never
    /// heard of, `decodeIfPresent(TemperatureUnit.self, ...)` throws
    /// `dataCorrupted` and takes this whole struct with it. `try?` turns each
    /// of those into "use the default for this one field".
    ///
    /// `LauncherConfig` wraps this decode in a `try?` of its own, so even a
    /// total failure here costs only the weather settings and never the app
    /// list. This init is the second line of that defence, not the first.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = (try? c.decode(Bool.self, forKey: .enabled)) ?? true
        latitude = try? c.decode(Double.self, forKey: .latitude)
        longitude = try? c.decode(Double.self, forKey: .longitude)
        placeName = (try? c.decode(String.self, forKey: .placeName)) ?? ""
        unit = (try? c.decode(TemperatureUnit.self, forKey: .unit)) ?? .celsius
    }

    /// The location to fetch, or nil when there is nothing to fetch.
    ///
    /// One accessor rather than three checks scattered through the provider:
    /// "weather is on AND a city was picked" is a single question, and every
    /// caller asks it the same way.
    var place: (latitude: Double, longitude: Double, name: String)? {
        guard enabled, let latitude, let longitude else { return nil }
        return (latitude: latitude, longitude: longitude, name: placeName)
    }
}

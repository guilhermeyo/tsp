import Foundation

/// A WMO 4677 weather code, reduced to the handful of shapes SF Symbols can draw.
///
/// Open-Meteo returns ~28 distinct codes. Rendered at ~22pt in a column about
/// 65pt wide, most of those distinctions are invisible: "light drizzle" and
/// "moderate drizzle" are the same glyph. So the codes collapse into buckets
/// here, once, and nothing downstream ever sees an integer again.
///
/// Stored by raw value in the cache, so the case names are part of the on-disk
/// format — renaming one silently invalidates every cached snapshot (see
/// `init(from:)`, which makes that cost a default icon rather than a decode
/// failure).
enum WeatherCondition: String, Codable {
    case clear
    case partlyCloudy
    case cloudy
    case fog
    case drizzle
    case sleet
    case rain
    case heavyRain
    case rainShowers
    case snow
    case snowGrains
    case thunderstorm
    case thunderstormHail

    /// The bucketing table. Anything unlisted becomes `.cloudy`, which is the
    /// least wrong thing to draw when we do not know: it claims nothing about
    /// precipitation and it is never alarming.
    init(wmoCode code: Int) {
        switch code {
        case 0: self = .clear
        case 1, 2: self = .partlyCloudy
        case 3: self = .cloudy
        case 45, 48: self = .fog
        case 51, 53, 55: self = .drizzle
        case 56, 57, 66, 67: self = .sleet
        case 61, 63: self = .rain
        case 65, 82: self = .heavyRain
        case 80, 81: self = .rainShowers
        case 71, 73, 75, 85, 86: self = .snow
        case 77: self = .snowGrains
        case 95: self = .thunderstorm
        case 96, 99: self = .thunderstormHail
        default: self = .cloudy
        }
    }

    /// Outline variants only, never `.fill`.
    ///
    /// The reference is Apple's own forecast widget, and an outline is what
    /// survives being drawn in a single colour on black: a filled cloud at this
    /// size is a solid blob. Day variants only, because every column summarises
    /// a whole day and a moon over Thursday would be a lie.
    ///
    /// All of these names predate iOS 15, so no `@available` check is needed.
    /// An unknown symbol name does not crash — it draws a "?" box — which is
    /// the other reason to keep the list to old, boring glyphs.
    var symbolName: String {
        switch self {
        case .clear: return "sun.max"
        case .partlyCloudy: return "cloud.sun"
        case .cloudy: return "cloud"
        case .fog: return "cloud.fog"
        case .drizzle: return "cloud.drizzle"
        case .sleet: return "cloud.sleet"
        case .rain: return "cloud.rain"
        case .heavyRain: return "cloud.heavyrain"
        case .rainShowers: return "cloud.sun.rain"
        case .snow: return "cloud.snow"
        case .snowGrains: return "snowflake"
        case .thunderstorm: return "cloud.bolt.rain"
        case .thunderstormHail: return "cloud.hail"
        }
    }

    /// Resilient by the same rule the config types follow: an unknown raw value
    /// falls back instead of throwing.
    ///
    /// The synthesized decoder throws `dataCorrupted` on a case it has never
    /// heard of, and that throw would take the whole cached snapshot with it —
    /// so the day this enum gains a case, an older build reading a newer
    /// build's cache would show nothing at all rather than one wrong icon.
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = WeatherCondition(rawValue: raw) ?? .cloudy
    }
}

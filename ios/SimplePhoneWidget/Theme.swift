import SwiftUI

enum FontChoice: String, Codable, CaseIterable, Identifiable {
    case monospaced
    case system
    case rounded
    case serif

    var id: String { rawValue }

    var label: String {
        switch self {
        case .monospaced: return "Monospaced"
        case .system: return "System"
        case .rounded: return "Rounded"
        case .serif: return "Serif"
        }
    }

    private var design: Font.Design {
        switch self {
        case .monospaced: return .monospaced
        case .system: return .default
        case .rounded: return .rounded
        case .serif: return .serif
        }
    }

    func font(_ style: Font.TextStyle) -> Font {
        .system(style, design: design)
    }

    func font(size: CGFloat) -> Font {
        .system(size: size, design: design)
    }
}

/// Horizontal alignment of the launcher rows, user-configurable.
enum RowAlignment: String, Codable, CaseIterable, Identifiable {
    case leading
    case center
    case trailing

    var id: String { rawValue }

    var label: String {
        switch self {
        case .leading: return "Left"
        case .center: return "Center"
        case .trailing: return "Right"
        }
    }

    var textAlignment: TextAlignment {
        switch self {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }

    var frameAlignment: Alignment {
        switch self {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }

    var horizontalAlignment: HorizontalAlignment {
        switch self {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }
}

/// Overall text size of the launcher rows, user-configurable.
enum TextSize: String, Codable, CaseIterable, Identifiable {
    case small
    case medium
    case large
    case extraLarge

    var id: String { rawValue }

    var label: String {
        switch self {
        case .small: return "Small"
        case .medium: return "Medium"
        case .large: return "Large"
        case .extraLarge: return "Extra Large"
        }
    }

    /// Point size for the home-screen widget rows.
    var widgetPointSize: CGFloat {
        switch self {
        case .small: return 20
        case .medium: return 28
        case .large: return 36
        case .extraLarge: return 44
        }
    }

    /// Point size for the in-app list rows (a bit tighter than the widget).
    var listPointSize: CGFloat {
        switch self {
        case .small: return 17
        case .medium: return 22
        case .large: return 28
        case .extraLarge: return 34
        }
    }
}

struct Theme: Codable, Equatable {
    var isDark: Bool
    var font: FontChoice
    var alignment: RowAlignment
    var size: TextSize

    static let `default` = Theme(isDark: true, font: .monospaced, alignment: .center, size: .large)

    init(isDark: Bool, font: FontChoice, alignment: RowAlignment = .center, size: TextSize = .large) {
        self.isDark = isDark
        self.font = font
        self.alignment = alignment
        self.size = size
    }

    // Resilient decoding: older saved configs (before alignment/size existed) still
    // decode, falling back to defaults instead of wiping the whole LauncherConfig.
    //
    // The three enum fields use `try?` rather than `decodeIfPresent`, and the
    // difference is not stylistic. `decodeIfPresent` returns nil only for an
    // ABSENT or NULL key — for a raw value no case matches it THROWS
    // `dataCorrupted`, and that throw escapes this init, gets swallowed by
    // `try?` in `ConfigStore.load()`, and resets the whole config. Which means
    // that with `decodeIfPresent` here, the day any of these enums gains a case
    // (a new font, say) is the day every older build wipes the user's app list
    // on first read of a config written by a newer one. Nothing about the
    // change would look dangerous.
    //
    // `isDark` keeps `decodeIfPresent` because it is the documented canary for
    // failure mode #1 in AGENTS.md: if config ever crosses as a bridged object,
    // a JS `true` arrives as `1` and this line throws. `LauncherConfig` now
    // catches that throw and keeps the apps, so the cost is a wrong theme
    // rather than lost data.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        isDark = try c.decodeIfPresent(Bool.self, forKey: .isDark) ?? true
        font = (try? c.decode(FontChoice.self, forKey: .font)) ?? .monospaced
        alignment = (try? c.decode(RowAlignment.self, forKey: .alignment)) ?? .center
        size = (try? c.decode(TextSize.self, forKey: .size)) ?? .large
    }

    var colorScheme: ColorScheme { isDark ? .dark : .light }

    var textColor: Color { isDark ? .white : .black }

    var backgroundColor: Color { isDark ? .black : .white }

    /// Font for the home-screen widget rows (large by default).
    var widgetFont: Font { font.font(size: size.widgetPointSize) }

    /// Font for the in-app list rows.
    var listFont: Font { font.font(size: size.listPointSize) }

    /// Resolve the chosen font family at a given text style.
    func resolvedFont(_ style: Font.TextStyle) -> Font { font.font(style) }
}

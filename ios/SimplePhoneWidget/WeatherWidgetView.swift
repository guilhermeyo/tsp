import SwiftUI
import WidgetKit

/// Five columns, one line, no colour.
///
/// The whole layout is one `HStack` of equal fractions. Nothing here is sized
/// in absolute points except the type, so when the midnight entry drops the
/// first column the remaining four redistribute on their own.
struct WeatherWidgetView: View {
    let entry: WeatherEntry

    private var theme: Theme { entry.theme }

    var body: some View {
        content
            .containerBackground(for: .widget) { theme.backgroundColor }
            // A new HOST on the existing scheme. `Relay.target(from:)` in the
            // app requires host == "open" and returns nil for anything else, so
            // this URL falls straight through to Expo Router and lands on the
            // /weather screen instead of being treated as an app to launch.
            .widgetURL(DeepLink.weatherURL)
    }

    @ViewBuilder
    private var content: some View {
        if let snapshot = entry.snapshot, !snapshot.days(from: entry.date).isEmpty {
            strip(snapshot: snapshot)
        } else {
            emptyLabel
        }
    }

    private func strip(snapshot: WeatherSnapshot) -> some View {
        let metrics = ColumnMetrics.forSize(theme.size)
        let days = Array(snapshot.days(from: entry.date).prefix(5))
        // Built once for the whole strip. A `DateFormatter` is expensive to
        // construct and this one is identical for all five columns.
        let formatter = Self.weekdayFormatter(language: entry.language, timeZone: snapshot.timeZone)

        return HStack(alignment: .top, spacing: 0) {
            ForEach(days.indices, id: \.self) { index in
                column(
                    day: days[index],
                    isToday: index == 0,
                    snapshot: snapshot,
                    metrics: metrics,
                    formatter: formatter)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // `contentMarginsDisabled()` means the system adds none, so these are
        // the widget's only margins.
        .padding(.horizontal, 12)
        .padding(.vertical, 14)
    }

    private func column(
        day: WeatherDay,
        isToday: Bool,
        snapshot: WeatherSnapshot,
        metrics: ColumnMetrics,
        formatter: DateFormatter
    ) -> some View {
        VStack(spacing: metrics.spacing) {
            Text(weekday(for: day.date, formatter: formatter))
                .font(theme.font.font(size: metrics.weekday))
                .foregroundStyle(theme.textColor.opacity(0.55))

            Image(systemName: day.condition.symbolName)
                // EXPLICIT, and not a default worth trusting: several of these
                // symbols ship a multicolour variant, and a yellow sun is the
                // one thing this product cannot have.
                .symbolRenderingMode(.monochrome)
                // SF Symbols take a weight but not a `Font.Design`, so the
                // user's font choice reaches the text and never the glyphs.
                // `.light` is what matches the thin outline drawing.
                .font(.system(size: metrics.symbol, weight: .light))
                .foregroundStyle(theme.textColor)

            Text(temperature(for: day, isToday: isToday, snapshot: snapshot))
                .font(theme.font.font(size: metrics.temperature))
                // Even under a monospaced design: serif and rounded have
                // proportional digits, and without this the whole strip shifts
                // sideways as values cross from 9 to 21.
                .monospacedDigit()
                .foregroundStyle(theme.textColor)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .frame(maxWidth: .infinity)
    }

    private var emptyLabel: some View {
        // Not `LauncherRowLabel`: that type is the launcher's row, sized from
        // `theme.widgetPointSize`, and borrowing it here would tie two
        // unrelated layouts together.
        Text(Self.emptyMessage(language: entry.language))
            .font(theme.font.font(size: 15))
            .foregroundStyle(theme.textColor.opacity(0.55))
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.6)
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// The abbreviated weekday, in the language the config chose.
    ///
    /// `setLocalizedDateFormatFromTemplate` rather than `dateFormat = "EEE"`,
    /// because CLDR abbreviations are not all three letters: pt-BR yields
    /// "qui." with the period, which is what the reference screenshot shows and
    /// what a Brazilian reader expects.
    ///
    /// The locale is set EXPLICITLY from `entry.language` and never left to
    /// default. A widget extension's default locale is the device's, so the
    /// default would give Portuguese weekdays to someone who deliberately put
    /// the app in English.
    private static func weekdayFormatter(language: String, timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: language)
        formatter.timeZone = timeZone
        formatter.setLocalizedDateFormatFromTemplate("EEE")
        return formatter
    }

    /// Lowercased with the same locale that produced it — Turkish dotted I is
    /// the reason `lowercased()` alone is not good enough. Lowercase because
    /// that is TSP's voice: the bundled rows are "mensagens", "ajustes".
    private func weekday(for date: Date, formatter: DateFormatter) -> String {
        formatter.string(from: date).lowercased(with: formatter.locale)
    }

    /// The day's high, except for today, where the CURRENT reading is the
    /// number anyone actually wants — but only while it still belongs to the
    /// day on screen. The icon stays the day's shape either way, because the
    /// column is a day.
    ///
    /// A bare degree sign and no `MeasurementFormatter`: that would append the
    /// unit and, in some locales, a non-breaking space before it, which is
    /// three glyphs a 65pt column does not have.
    ///
    /// `Int(value.rounded())` and not `String(format: "%.0f")`, which prints
    /// "-0" for anything between -0.5 and 0.
    private func temperature(for day: WeatherDay, isToday: Bool, snapshot: WeatherSnapshot) -> String {
        var celsius = day.highC
        if isToday, snapshot.currentIsValid(at: entry.date), let current = snapshot.currentC {
            celsius = current
        }

        let value = entry.unit.isFahrenheit ? celsius * 9 / 5 + 32 : celsius
        return "\(Int(value.rounded()))°"
    }

    /// Two strings, chosen by prefix rather than by exact tag, so "pt-BR",
    /// "pt-PT" and a bare "pt" all read Portuguese. Everything else, including
    /// a tag this build has never seen, reads English.
    private static func emptyMessage(language: String) -> String {
        language.lowercased().hasPrefix("pt") ? "defina sua cidade no TSP" : "set your city in TSP"
    }
}

/// The strip's OWN type scale, deliberately not `theme.widgetFont`.
///
/// The launcher's table runs 20/28/36/44, sized for one line across the whole
/// widget. A column here is about 65pt wide and carries three stacked elements,
/// so 44pt would obliterate it. Same user preference, different budget.
private struct ColumnMetrics {
    let weekday: CGFloat
    let symbol: CGFloat
    let temperature: CGFloat
    let spacing: CGFloat

    static func forSize(_ size: TextSize) -> ColumnMetrics {
        switch size {
        case .small: return ColumnMetrics(weekday: 11, symbol: 17, temperature: 13, spacing: 6)
        case .medium: return ColumnMetrics(weekday: 12, symbol: 20, temperature: 15, spacing: 7)
        case .large: return ColumnMetrics(weekday: 13, symbol: 22, temperature: 17, spacing: 8)
        case .extraLarge: return ColumnMetrics(weekday: 15, symbol: 26, temperature: 19, spacing: 9)
        }
    }
}

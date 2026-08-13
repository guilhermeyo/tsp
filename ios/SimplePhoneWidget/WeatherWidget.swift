import SwiftUI
import WidgetKit

struct WeatherWidget: Widget {
    var body: some WidgetConfiguration {
        // A NEW kind, never a rename of "SimplePhoneLauncher". WidgetKit
        // persists the kind for widgets already placed on a home screen, and
        // reusing or renaming one blanks every placement permanently, on every
        // device, with no migration API. See AGENTS.md.
        StaticConfiguration(kind: "SimplePhoneWeather", provider: WeatherProvider()) { entry in
            WeatherWidgetView(entry: entry)
        }
        .configurationDisplayName("TSP - Weather")
        .description("Five days, in one line.")
        // Medium only. Five columns need about 365pt to breathe; a small family
        // fits three, which is a different layout with its own metrics and its
        // own testing for something nobody asked for.
        .supportedFamilies([.systemMedium])
        .contentMarginsDisabled()
    }
}

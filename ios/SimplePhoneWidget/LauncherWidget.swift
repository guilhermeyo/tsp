import SwiftUI
import WidgetKit

struct LauncherWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "SimplePhoneLauncher", provider: LauncherProvider()) { entry in
            LauncherWidgetView(entry: entry)
        }
        .configurationDisplayName("Simple Phone RN")
        .description("Your apps as a calm text list.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

import Foundation

/// The single serialized unit of shared state: the chosen apps plus the theme.
struct LauncherConfig: Codable, Equatable {
    var apps: [LauncherApp]
    var theme: Theme

    static let `default` = LauncherConfig(apps: BundledDefaults.apps, theme: .default)
}

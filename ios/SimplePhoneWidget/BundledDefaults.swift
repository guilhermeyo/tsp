import Foundation

/// Read-only defaults compiled into BOTH targets.
///
/// On a free Apple personal team the App Group entitlement can't be signed, so
/// `UserDefaults(suiteName:)` is unavailable to the widget and it renders THESE
/// (it can't see edits the user makes in the app). With a paid team + App Group
/// enabled, this list is only the first-run seed.
enum BundledDefaults {
    static let apps: [LauncherApp] = [
        LauncherApp(name: "mensagens", urlString: "messages://"),
        LauncherApp(name: "whatsapp", urlString: "whatsapp://"),
        LauncherApp(name: "waze", urlString: "waze://"),
        LauncherApp(name: "música", urlString: "music://"),
        LauncherApp(name: "ajustes", urlString: "App-Prefs://"),
    ]
}

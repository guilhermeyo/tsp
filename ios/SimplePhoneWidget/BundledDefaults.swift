import Foundation

/// Read-only defaults compiled into BOTH targets.
///
/// On a free Apple personal team the App Group entitlement can't be signed, so
/// `UserDefaults(suiteName:)` is unavailable to the widget and it renders THESE
/// (it can't see edits the user makes in the app). With a paid team + App Group
/// enabled, this list is only the first-run seed.
///
/// ENGLISH ONLY, deliberately, while `src/domain/bundledDefaults.ts` carries all
/// four languages. This list is reached exactly when the shared container can't
/// be read, and the chosen language lives IN that container — so the only tag
/// available here would be the system's, which is a different value. The app
/// deliberately stores a concrete language rather than following the phone, so
/// guessing from the system here would render a Japanese widget beside a
/// Spanish app. A fallback that is consistently English is easier to recognise
/// as a fallback than one that is confidently wrong.
///
/// `whatsapp-consumer://`, not `whatsapp://`: the plain scheme is claimed by
/// both WhatsApp and WhatsApp Business, and iOS resolves that collision by
/// picking one, which on the test device was Business.
enum BundledDefaults {
    static let apps: [LauncherApp] = [
        LauncherApp(name: "messages", urlString: "ichat://"),
        LauncherApp(name: "whatsapp", urlString: "whatsapp-consumer://"),
        LauncherApp(name: "waze", urlString: "waze://"),
        LauncherApp(name: "music", urlString: "music://"),
        LauncherApp(name: "settings", urlString: "App-Prefs://"),
    ]
}

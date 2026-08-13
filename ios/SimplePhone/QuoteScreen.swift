import UIKit

/// The interstitial shown during the relay: one line, held for a beat, while
/// the target app is asked to open.
///
/// UIKit, not SwiftUI and certainly not React Native. This runs inside
/// `application(_:open:options:)` and inside `didFinishLaunchingWithOptions`,
/// which on a cold launch is BEFORE React Native has a bridge, let alone a
/// rendered view. A UIWindow put up here paints immediately, over the launch
/// image. Anything on the JS side would appear only after Hermes, the bundle
/// and Expo Router were done, by which point the target app is already opening
/// and the phrase would flash in behind it, or not at all.
///
/// It reads the SAME App Group config the widget reads, so the language, the
/// phrases and the dark/light choice all come from what the user set in the
/// app. It carries no catalog of its own: `quotes.items` arrives already
/// resolved, which is what keeps this file short.
enum QuoteScreen {
  private static let appGroupId = "group.com.guilherme44.simple-phone"
  private static let configKey = "launcher_config"

  /// Its own window rather than a view controller pushed into the app's.
  /// On a cold launch there is no root view controller to present from yet, and
  /// a separate window at a higher level is also what keeps the phrase above
  /// whatever React Native puts on screen while it finishes booting.
  private static var window: UIWindow?

  /// True from the moment the phrase goes up until the target app has been
  /// asked to open.
  ///
  /// Load-bearing: `didBecomeActiveNotification` fires on the app's OWN launch,
  /// not only when the user comes back, so on a cold widget tap the dismiss
  /// observer would tear the phrase down in the same runloop it appeared. This
  /// makes dismissal a no-op until the handoff has actually happened.
  private static var isHolding = false

  /// Returns how long to hold before opening the target, or nil when there is
  /// nothing to show and the caller should open immediately.
  static func present(in appWindow: UIWindow?) -> TimeInterval? {
    guard let config = loadConfig(),
          config.enabled,
          let quote = config.items.randomElement()
    else { return nil }

    guard let scene = appWindow?.windowScene
            ?? UIApplication.shared.connectedScenes.first as? UIWindowScene
    else { return nil }

    let overlay = UIWindow(windowScene: scene)
    // Above the app's own window, below system alerts.
    overlay.windowLevel = .normal + 1
    overlay.backgroundColor = config.isDark ? .black : .white

    let label = UILabel()
    label.text = quote
    label.textColor = config.isDark ? .white : .black
    label.font = font(for: config)
    label.numberOfLines = 0
    label.textAlignment = .center
    label.adjustsFontSizeToFitWidth = true
    label.minimumScaleFactor = 0.6
    label.translatesAutoresizingMaskIntoConstraints = false

    let controller = UIViewController()
    controller.view.backgroundColor = overlay.backgroundColor
    controller.view.addSubview(label)
    NSLayoutConstraint.activate([
      label.centerYAnchor.constraint(equalTo: controller.view.centerYAnchor),
      label.leadingAnchor.constraint(equalTo: controller.view.leadingAnchor, constant: 32),
      label.trailingAnchor.constraint(equalTo: controller.view.trailingAnchor, constant: -32),
    ])

    overlay.rootViewController = controller
    overlay.makeKeyAndVisible()
    window = overlay
    isHolding = true

    // Held, not animated in. A fade would eat a slice of the time the phrase
    // has, and the point is to be readable, not to be a transition.
    return config.holdSeconds
  }

  /// Torn down when the app comes back to the foreground, which is the moment
  /// the user returns from the target app. Leaving it up would show a stale
  /// phrase over the list.
  static func dismiss() {
    guard !isHolding else { return }
    window?.isHidden = true
    window = nil
  }

  /// Called once the target app has been asked to open. From here on the phrase
  /// is stale and the next foregrounding should clear it.
  static func releaseHold() {
    isHolding = false
  }

  /// Mirrors the widget's `Theme.widgetFont`: same family choice, one size
  /// down, because this is a full screen holding one line rather than a widget
  /// holding six.
  private static func font(for config: Config) -> UIFont {
    let size: CGFloat = 30
    let base = UIFont.systemFont(ofSize: size, weight: .semibold)
    let design: UIFontDescriptor.SystemDesign
    switch config.font {
    case "monospaced": design = .monospaced
    case "rounded": design = .rounded
    case "serif": design = .serif
    default: return base
    }
    guard let descriptor = base.fontDescriptor.withDesign(design) else { return base }
    return UIFont(descriptor: descriptor, size: size)
  }

  struct Config {
    let enabled: Bool
    let items: [String]
    let isDark: Bool
    let font: String
    /// Resolved by the app from its named durations, so this side never carries
    /// the label table. Clamped on read: a corrupt payload must not be able to
    /// freeze the launcher on a phrase.
    let holdSeconds: TimeInterval
  }

  /// Hand-rolled rather than Codable structs: this needs four fields out of a
  /// payload that belongs to the JS side, and a synthesized decoder would fail
  /// the whole parse over any key it did not expect. A miss here must degrade
  /// to "no phrase", never to "no launch".
  private static func loadConfig() -> Config? {
    guard let defaults = UserDefaults(suiteName: appGroupId) else { return nil }
    let data = defaults.data(forKey: configKey)
      ?? defaults.string(forKey: configKey)?.data(using: .utf8)
    guard let data,
          let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let quotes = root["quotes"] as? [String: Any],
          let enabled = quotes["enabled"] as? Bool,
          let items = quotes["items"] as? [String]
    else { return nil }

    let theme = root["theme"] as? [String: Any]
    let ms = quotes["durationMs"] as? Double ?? 1800
    return Config(
      enabled: enabled,
      items: items,
      isDark: theme?["isDark"] as? Bool ?? true,
      font: theme?["font"] as? String ?? "monospaced",
      holdSeconds: min(max(ms / 1000, 0.4), 8))
  }
}

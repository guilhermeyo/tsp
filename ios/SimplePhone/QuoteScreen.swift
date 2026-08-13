import QuartzCore
import UIKit

/// The cover shown during the relay: an opaque screen in the user's theme,
/// carrying one line, while the target app is asked to open.
///
/// THE CONTRACT IS THE COVER, NOT THE PHRASE. Every relay puts this up, always,
/// before the target is asked to open. A missing config, a corrupt payload,
/// phrases switched off, an empty list, no window scene: none of those may
/// degrade to "show nothing", because "nothing" means the app list, which is
/// the one thing this exists to hide. They degrade to a plain themed screen
/// instead. `cover(in:)` has no failure return for that reason.
///
/// UIKit, not SwiftUI and certainly not React Native. This runs inside
/// `application(_:open:options:)` and inside `didFinishLaunchingWithOptions`,
/// which on a cold launch is BEFORE React Native has a bridge, let alone a
/// rendered view. A UIWindow put up here paints immediately, over the launch
/// image. Anything on the JS side would appear only after Hermes, the bundle
/// and Expo Router were done, by which point the target app is already opening
/// and the phrase would flash in behind it, or not at all.
///
/// THE SNAPSHOT. The other half of the job, and the half no overlay can do on
/// its own. When iOS foregrounds a warm app it replays the snapshot it took at
/// the last backgrounding, for the whole open animation, before any of this
/// code runs. If the app was last backgrounded showing the list, that is what
/// the user watches during the relay no matter how fast the cover goes up. So
/// the cover also goes up on `didEnterBackground`, which makes the snapshot
/// itself the phrase. Accepted side effect: the app-switcher card and a plain
/// icon launch show a phrase too. iOS gives no way to know at snapshot time
/// which path the next foreground will take.
///
/// It reads the SAME App Group config the widget reads, so the language, the
/// phrases and the dark/light choice all come from what the user set in the
/// app. When there is no config yet it falls back to `quotes.json`, the very
/// file `src/domain/quotes.ts` imports, copied into the app bundle by the app
/// target's Resources phase.
enum QuoteScreen {
  private static let appGroupId = "group.com.guilherme44.simple-phone"
  private static let configKey = "launcher_config"

  /// Its own window rather than a view controller pushed into the app's.
  /// On a cold launch there is no root view controller to present from yet, and
  /// a separate window at a higher level is also what keeps the phrase above
  /// whatever React Native puts on screen while it finishes booting.
  private static var window: UIWindow?

  /// The app's own window. Weak: it is owned by the app delegate.
  private static weak var hostWindow: UIWindow?

  /// A second, identical copy of the cover, added as a plain subview of the
  /// app's own window.
  ///
  /// Belt and braces for the snapshot. QA1838 describes hiding sensitive
  /// content by changing VIEWS in the existing window; whether a separate
  /// UIWindow raised during `didEnterBackground` always makes it into the
  /// snapshot is not documented. If it does, this is invisible underneath and
  /// costs nothing. If it does not, the snapshot is still the phrase instead of
  /// the list.
  private static var shade: UIView?

  /// True from the moment a relay URL is recognised until the app has actually
  /// LEFT (or the open has failed).
  ///
  /// Load-bearing: `didBecomeActiveNotification` fires on the app's own launch
  /// and again on the foregrounding that precedes the relay, not only when the
  /// user comes back, so the dismiss observer would otherwise tear the cover
  /// down in the same runloop it appeared. Set synchronously, before any
  /// main-queue hop, so there is no gap for an activation to slip through.
  private static var relayInFlight = false

  /// True once a frame containing the cover has demonstrably been committed.
  /// Survives a backgrounding, which is what lets a warm relay open the target
  /// with no frame wait at all: the cover has been on screen since before the
  /// app was even foregrounded.
  private static var isComposited = false

  /// Called once, at launch, so the background observer does not need to reach
  /// back into the app delegate.
  static func attach(hostWindow window: UIWindow?) {
    hostWindow = window
  }

  static func beginRelay() {
    relayInFlight = true
  }

  /// The relay is over when the app has left, not when `open` was called.
  /// Releasing at the call site left the handoff itself -- the exact interval
  /// the phrase exists to cover -- unguarded.
  static func endRelay() {
    relayInFlight = false
  }

  /// Puts the cover up and returns how long to hold before opening the target.
  ///
  /// Not optional, and it cannot fail. Called for every relay, and also from
  /// `didEnterBackground` with `forSnapshot: true` so the system snapshot
  /// carries the phrase.
  @discardableResult
  static func cover(in appWindow: UIWindow? = nil, forSnapshot: Bool = false) -> TimeInterval {
    let config = loadConfig()
    // A cover already on screen is KEPT exactly as it is. It is what the
    // snapshot captured at the last backgrounding and what the user is looking
    // at right now during the foreground animation; re-rolling the phrase here
    // would swap the text under them mid-transition.
    if window == nil {
      show(config, phrase: phrase(for: config), in: appWindow ?? hostWindow, forSnapshot: forSnapshot)
    }
    return config.holdSeconds
  }

  /// Torn down when the app comes back to the foreground, which is the moment
  /// the user returns from the target app. Leaving it up would show a stale
  /// phrase over the list.
  static func dismiss() {
    guard !relayInFlight else { return }
    frameLink?.invalidate()
    frameLink = nil
    framesLeft = 0
    onPresented = nil
    isComposited = false
    shade?.removeFromSuperview()
    shade = nil
    window?.isHidden = true
    window = nil
    // The cover took key status. Handing it back matters: without it the app
    // can sit with no key window, which shows up as a text field that will not
    // take focus on the first tap after a relay.
    hostWindow?.makeKey()
  }

  /// Forced teardown for the one case that must not wait for a foregrounding:
  /// the target refused to open, so the app is staying put and the alert has to
  /// be visible and tappable.
  static func dismissForFailure() {
    relayInFlight = false
    dismiss()
  }

  /// Where the failure alert should be presented from. The cover is normally
  /// gone by then (`dismissForFailure`), so this is the app's own root; the
  /// cover's own controller is the fallback for the cold path, where React
  /// Native's root view may not be in a hierarchy yet.
  static func failurePresenter() -> UIViewController? {
    hostWindow?.rootViewController ?? window?.rootViewController
  }

  // MARK: - Presentation

  private static func show(_ config: Config, phrase: String?, in appWindow: UIWindow?, forSnapshot: Bool) {
    if let appWindow {
      hostWindow = appWindow
    }

    let overlay: UIWindow
    if let scene = windowScene(preferring: appWindow) {
      overlay = UIWindow(windowScene: scene)
    } else {
      // No scene yet. This app has no `UIApplicationSceneManifest`, so it runs
      // the legacy app-delegate lifecycle and this initialiser is valid -- it
      // is the same one the app's own window uses in AppDelegate. Never return
      // without a cover just because the scene set was not populated yet.
      overlay = UIWindow(frame: UIScreen.main.bounds)
    }
    // Above the app's own window (.normal, 0) and above React Native's debug
    // chrome in a Debug build (RCTDevLoadingView sits at .statusBar + 1), while
    // staying well below .alert so system alerts still reach the user.
    overlay.windowLevel = .statusBar + 2

    let controller = UIViewController()
    fill(controller.view, config: config, phrase: phrase)
    overlay.backgroundColor = controller.view.backgroundColor
    overlay.rootViewController = controller
    overlay.makeKeyAndVisible()

    if let host = appWindow ?? hostWindow, host !== overlay {
      let copy = UIView(frame: host.bounds)
      copy.autoresizingMask = [.flexibleWidth, .flexibleHeight]
      fill(copy, config: config, phrase: phrase)
      shade?.removeFromSuperview()
      host.addSubview(copy)
      shade = copy
    }

    window = overlay

    // Forced synchronously. `makeKeyAndVisible` and `layoutIfNeeded` only mark
    // the window as needing display; CoreAnimation commits at the END of the
    // runloop turn, and with a zero hold the target is opened in this same
    // turn. `CATransaction.flush()` commits now, which is what makes the frame
    // wait below one tick rather than two.
    controller.view.layoutIfNeeded()
    shade?.layoutIfNeeded()
    CATransaction.flush()

    // Backgrounding is the one case where the commit IS the whole story: the
    // system renders this and snapshots it before anything else runs, and no
    // display link ticks while the app is away. Treating it as composited is
    // what lets the next warm relay open with no frame wait whatsoever -- the
    // cover has been in front of the user since before the app was foregrounded.
    isComposited = forSnapshot
  }

  /// Paints `container` as the cover. No phrase means a plain themed field --
  /// deliberately, because that is still not the app list.
  private static func fill(_ container: UIView, config: Config, phrase: String?) {
    let background: UIColor = config.isDark ? .black : .white
    container.backgroundColor = background
    container.isOpaque = true
    guard let phrase, !phrase.isEmpty else { return }

    let label = UILabel()
    label.text = phrase
    label.textColor = config.isDark ? .white : .black
    label.font = font(for: config)
    label.numberOfLines = 0
    label.textAlignment = .center
    label.adjustsFontSizeToFitWidth = true
    label.minimumScaleFactor = 0.6
    label.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(label)
    NSLayoutConstraint.activate([
      label.centerYAnchor.constraint(equalTo: container.centerYAnchor),
      label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 32),
      label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -32),
    ])
  }

  /// `connectedScenes` is an unordered Set, so the old
  /// `connectedScenes.first as? UIWindowScene` cast an ARBITRARY element and
  /// yielded nil whenever that element happened not to be a window scene, even
  /// with a perfectly good one in the set.
  private static func windowScene(preferring appWindow: UIWindow?) -> UIWindowScene? {
    if let scene = appWindow?.windowScene { return scene }
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    return scenes.first { $0.activationState == .foregroundActive }
      ?? scenes.first { $0.activationState == .foregroundInactive }
      ?? scenes.first
  }

  // MARK: - Waiting for the frame, and nothing else

  private static var frameLink: CADisplayLink?
  private static var framesLeft = 0
  private static var onPresented: (() -> Void)?

  /// Runs `completion` once the cover has actually been PUT ON SCREEN.
  ///
  /// This is the whole difference between a phrase that covers the handoff and
  /// one nobody ever sees. Opening the target in the same runloop pass beat
  /// CoreAnimation's commit, so the cover was never composited and the user
  /// watched the app list slide away instead.
  ///
  /// This is the only wait in the relay and it is not a duration: it is the
  /// next frame boundary. When the cover is already on screen -- the warm case,
  /// where it has been up since the last backgrounding -- there is nothing to
  /// wait for and the completion runs immediately.
  static func afterPresented(_ completion: @escaping () -> Void) {
    guard !isComposited else {
      completion()
      return
    }
    frameLink?.invalidate()
    // One tick, because `show` already flushed the transaction. The tick proves
    // the render server has been through a frame with the cover in it.
    framesLeft = 1
    onPresented = completion
    let link = CADisplayLink(target: Proxy.shared, selector: #selector(Proxy.tick))
    link.add(to: .main, forMode: .common)
    frameLink = link

    // A safety net, not a delay: it changes nothing on the normal path. A
    // display link stops ticking when the app stops rendering, and the open
    // must never be reachable ONLY through a signal that can stop -- that would
    // be worse than a visible list, it would be a launcher that launches
    // nothing.
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { fire() }
  }

  fileprivate static func tick() {
    framesLeft -= 1
    guard framesLeft <= 0 else { return }
    fire()
  }

  private static func fire() {
    frameLink?.invalidate()
    frameLink = nil
    guard let completion = onPresented else { return }
    onPresented = nil
    isComposited = true
    completion()
  }

  /// CADisplayLink retains its target, so the enum cannot be one.
  private final class Proxy: NSObject {
    static let shared = Proxy()
    @objc func tick() { QuoteScreen.tick() }
  }

  // MARK: - Content

  private static func phrase(for config: Config) -> String? {
    guard config.enabled else { return nil }
    return config.items.randomElement()
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

  /// Hand-rolled rather than Codable structs: this needs five fields out of a
  /// payload that belongs to the JS side, and a synthesized decoder would fail
  /// the whole parse over any key it did not expect.
  ///
  /// NEVER FAILS, by design. Every field defaults independently, exactly as
  /// `decodeTheme` does on the TypeScript side and for the same reason. The old
  /// version returned nil for the whole config if any one of five things was
  /// missing, and the caller turned that nil into "open with nothing on
  /// screen".
  private static func loadConfig() -> Config {
    // `?? .standard` matches ConfigStore.swift and LauncherNativeModule.swift.
    // On a build whose App Group entitlement did not sign, the app writes to
    // .standard, and reading the same place is better than reading nothing.
    let defaults = UserDefaults(suiteName: appGroupId) ?? .standard
    let data = defaults.data(forKey: configKey)
      ?? defaults.string(forKey: configKey)?.data(using: .utf8)
    let root = data.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
    let quotes = root?["quotes"] as? [String: Any]
    let theme = root?["theme"] as? [String: Any]

    let language = quotes?["language"] as? String
    let stored = (quotes?["items"] as? [String])?
      .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? []

    return Config(
      enabled: quotes?["enabled"] as? Bool ?? true,
      // An empty or absent list is "never seeded", not "the user deleted every
      // line". Deleting the last phrase is what the `enabled` switch is for.
      items: stored.isEmpty ? bundledItems(language: language) : stored,
      isDark: theme?["isDark"] as? Bool ?? true,
      font: theme?["font"] as? String ?? "monospaced",
      // Absent means 0, not some invented default: `instant` is the app's own
      // first-run duration, and inventing a wait here would be exactly the
      // artificial delay this feature is not allowed to add.
      holdSeconds: min(max((quotes?["durationMs"] as? Double ?? 0) / 1000, 0), 8))
  }

  /// The full catalog, read from the same `quotes.json` the TypeScript side
  /// imports. Used only when the shared config has nothing usable -- a fresh
  /// install, a config written before quotes existed, an unsigned App Group.
  /// Without it, the cover on those paths would be a blank coloured screen.
  private static let bundledCatalog: [String: Any] = {
    guard let url = Bundle.main.url(forResource: "quotes", withExtension: "json"),
          let data = try? Data(contentsOf: url),
          let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return [:] }
    return root
  }()

  private static func bundledItems(language: String?) -> [String] {
    // The default language lives in the catalog rather than being re-decided
    // here, so Swift cannot drift from `DEFAULT_QUOTES.language`.
    let fallback = bundledCatalog["defaultLanguage"] as? String ?? "pt-BR"
    if let language, let items = bundledCatalog[language] as? [String], !items.isEmpty {
      return items
    }
    return bundledCatalog[fallback] as? [String] ?? []
  }
}

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

  /// A SECOND key in the same suite, and this file is its only writer.
  ///
  /// The exact mirror of `launcher_config`, whose only writer is the app's
  /// TypeScript side and which this file only ever reads. Counting inside that
  /// blob would make Swift a writer of the payload holding every app the user
  /// added, and a backgrounding can land in the middle of a JS save: last
  /// writer wins on the whole payload, so an increment could cost the user
  /// their list. The widget's `weather_cache` established the same separation
  /// for the same reason.
  ///
  /// Duplicated in `modules/launcher-native/ios/LauncherNativeModule.swift`,
  /// which reads it for the Phrases screen. Two copies of a string with
  /// nothing enforcing agreement; a drift shows up as counters frozen at zero
  /// with no error anywhere.
  private static let quoteStatsKey = "quote_stats"

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

  /// True once THIS process has drawn a line of its own.
  ///
  /// The only thing that tells a genuinely cold relay -- where the image iOS
  /// is replaying was painted by a process that no longer exists -- from a warm
  /// one whose cover merely happened to be dismissed. See `restoreOrRoll`.
  private static var rolledThisLaunch = false

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
  ///
  /// BACKGROUNDING IS THE ONE ROLL POINT, and that asymmetry is the whole of
  /// the fix for a phrase that never changed.
  ///
  /// Keeping the cover on the foreground path is right, and stays: it is the
  /// image the user is looking at during the open animation, and re-rolling
  /// there would swap the text under them mid-transition. The bug was that
  /// `window` is only ever cleared by `dismiss`, which returns early for the
  /// entire length of a relay -- so "keep it" also applied to the backgrounding
  /// that ENDS the relay, and the process lived out its whole life on the first
  /// line it ever drew.
  ///
  /// Rolling here instead is what lets the line change between launches while
  /// the snapshot and the first live frame stay identical, because this is
  /// exactly the moment iOS takes that snapshot and exactly the moment nobody
  /// is looking at the screen. It is also the only path with no frame deadline,
  /// which is why every read and write of the counters lives on it.
  @discardableResult
  static func cover(in appWindow: UIWindow? = nil, forSnapshot: Bool = false) -> TimeInterval {
    let config = loadConfig()

    if forSnapshot {
      let next = roll(config)
      if window == nil {
        show(config, phrase: next, in: appWindow ?? hostWindow, forSnapshot: true)
      } else {
        refill(config, phrase: next)
      }
    } else if window == nil {
      // Reachable only on a COLD relay: a warm one always finds the cover the
      // last backgrounding left standing. See `restoreOrRoll`.
      show(config, phrase: restoreOrRoll(config), in: appWindow ?? hostWindow, forSnapshot: false)
    }
    // Anything else: the cover already on screen is KEPT exactly as it is, and
    // this call reads nothing but the config it already needed.

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

  /// Repaints the cover that is ALREADY up, in place.
  ///
  /// Not `show` again: `show` builds a fresh UIWindow and assigns it, which
  /// would drop the current one without ever hiding it, and would add a second
  /// shade to the host window. This only touches the two containers `fill`
  /// painted.
  ///
  /// Synchronous, and flushed inside the `didEnterBackground` callout, for the
  /// same reason `show` flushes: iOS snapshots as soon as that callout returns.
  /// An uncommitted repaint would put the OLD line in the snapshot while the
  /// next foreground came back to the new one -- which is precisely the
  /// mid-transition swap the keep-rule exists to prevent, reintroduced by the
  /// fix for it.
  private static func refill(_ config: Config, phrase: String?) {
    guard let overlay = window else { return }

    if let root = overlay.rootViewController {
      root.view.subviews.forEach { $0.removeFromSuperview() }
      fill(root.view, config: config, phrase: phrase)
      overlay.backgroundColor = root.view.backgroundColor
      root.view.layoutIfNeeded()
    }
    if let shade = shade {
      shade.subviews.forEach { $0.removeFromSuperview() }
      fill(shade, config: config, phrase: phrase)
      shade.layoutIfNeeded()
    }
    CATransaction.flush()

    // Same reasoning as the tail of `show`: the render server goes through this
    // frame before the app is suspended, so the next warm relay still opens
    // with no frame wait at all.
    isComposited = true
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

  /// Draws the line for the NEXT cover, counts it, and remembers it.
  ///
  /// The one place a phrase is ever chosen. Counting AT THE DRAW rather than
  /// when the line is retired is what keeps the number honest: a line is put
  /// up exactly once per draw, so one draw is one increment, with no second
  /// write anywhere and nothing to reconcile if the process is killed while
  /// backgrounded.
  ///
  /// The number therefore means "times this line was put up as a cover", which
  /// includes the app-switcher card and a plain icon launch. That is not a
  /// rounding error, it is the same accepted side effect the header of this
  /// file already documents: iOS gives no way to know at snapshot time which
  /// path the next foreground will take.
  private static func roll(_ config: Config) -> String? {
    rolledThisLaunch = true
    guard config.enabled else { return nil }

    var stats = loadStats()
    guard let next = pick(from: config.items, counts: stats.counts, excluding: stats.current) else {
      return nil
    }
    stats.counts[next, default: 0] += 1
    stats.current = next
    saveStats(stats, items: config.items)
    return next
  }

  /// The cold relay, and the one case where NOT rolling is the right answer.
  ///
  /// The process was killed while backgrounded, so the image iOS is replaying
  /// over this launch was painted by a process that is gone. Restoring the line
  /// that snapshot carries is what keeps the first live frame equal to it;
  /// rolling a new one would swap the text under an image already on screen, on
  /// the path where the swap is most visible. This is a hole in the
  /// snapshot-matching guarantee that predates the counters and that the stored
  /// `current` closes for free.
  ///
  /// `rolledThisLaunch` is what makes it safe. Once this process has drawn a
  /// line of its own, the stored one is merely the line it just took down, and
  /// putting it back up would be the repeat this whole change is about.
  ///
  /// Costs one extra key read on a path that is already booting all of React
  /// Native, and no write at all unless there is nothing stored yet -- which is
  /// once per install.
  private static func restoreOrRoll(_ config: Config) -> String? {
    guard config.enabled else { return nil }
    if !rolledThisLaunch, let current = loadStats().current, config.items.contains(current) {
      rolledThisLaunch = true
      return current
    }
    return roll(config)
  }

  /// Uniform over the least-shown tier, never the line just taken down.
  ///
  /// A bag shuffle whose bag is RECOMPUTED from the counts instead of stored,
  /// so the number the user reads in the Phrases screen IS the algorithm's
  /// entire state. Nothing to invalidate when a phrase is added, deleted or the
  /// language flips: an item with no entry reads as zero and lands in the
  /// bottom tier, which is exactly where a new line belongs.
  ///
  /// Excluding `current` is the only part of this anyone will ever perceive.
  /// A back-to-back repeat was already just 1 in 101 with `randomElement`; this
  /// makes it impossible, which matters because it is the ONE repeat a person
  /// actually notices. The rest is a real but unobservable improvement to the
  /// long tail, and it should be described that way -- the phrase that never
  /// changed was the stuck window, not the draw.
  ///
  /// THE FLOOR is the part that is not obvious. Strict least-shown-first would
  /// take a freshly added line (count 0, alone at the bottom of the ranking)
  /// and show it on every single backgrounding until it caught up with the rest
  /// -- forty in a row on a list that has been in use a month, manufacturing
  /// precisely the repetitiveness this exists to remove. Widening the tier to
  /// at least `max(5, count / 8)` candidates (12 at the bundled 101) keeps a
  /// new line arriving within a handful of relays, takes it out of the running
  /// for two in a row, and still draws from the strict minimum for most of a
  /// cycle, because the tier only widens once the minimum tier runs thin.
  private static func pick(from items: [String], counts: [String: Int], excluding current: String?) -> String? {
    guard items.count > 1 else { return items.first }

    // The fallback covers a config that somehow holds nothing but duplicates of
    // the current line; the contract is the cover, so this may not return nil
    // for a list that has items in it.
    let pool = items.filter { $0 != current }
    let candidates = pool.isEmpty ? items : pool

    // Sorting 101 strings, on the backgrounding path, with no frame deadline
    // and nobody watching. The deterministic tie-break keeps the ranking stable
    // between draws; the randomness comes from the pick within the tier.
    let ranked = candidates.sorted { lhs, rhs in
      let left = counts[lhs] ?? 0
      let right = counts[rhs] ?? 0
      return left == right ? lhs < rhs : left < right
    }
    guard let first = ranked.first else { return nil }

    let lowest = counts[first] ?? 0
    let floor = min(ranked.count, max(5, items.count / 8))
    var tier = ranked.prefix { (counts[$0] ?? 0) == lowest }
    if tier.count < floor {
      tier = ranked.prefix(floor)
    }
    return tier.randomElement()
  }

  /// How many times each line has been put up, and which one the last snapshot
  /// carries.
  ///
  /// Keyed by the phrase TEXT, not by index: `removeQuoteAt` splices, so every
  /// count past a deleted row would silently slide onto the wrong line.
  /// `addQuote` already refuses an exact duplicate, so the text is a unique,
  /// stable key with no id scheme and no migration for the 202 bundled lines.
  /// The consequence worth knowing: a future edit-a-phrase UI would zero that
  /// line's history. Nothing edits today -- the screen adds and removes only.
  private struct Stats {
    var counts: [String: Int] = [:]
    var current: String?
  }

  /// Resilient in the same way `loadConfig` is, and for the same reason: a
  /// corrupt payload here must degrade to "no history", never to a throw on the
  /// path that puts the cover up.
  private static func loadStats() -> Stats {
    let defaults = UserDefaults(suiteName: appGroupId) ?? .standard
    let data = defaults.data(forKey: quoteStatsKey)
      ?? defaults.string(forKey: quoteStatsKey)?.data(using: .utf8)
    let root = data.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]

    // Element-wise rather than a blanket `as? [String: Int]`, so one junk value
    // costs that entry and not the whole table.
    var counts: [String: Int] = [:]
    for (key, value) in (root?["counts"] as? [String: Any]) ?? [:] {
      guard let number = value as? NSNumber else { continue }
      counts[key] = number.intValue
    }
    return Stats(counts: counts, current: root?["current"] as? String)
  }

  private static func saveStats(_ stats: Stats, items: [String]) {
    var counts = stats.counts
    // Keys for lines no longer in rotation are KEPT on purpose. It is what
    // makes a language round trip non-destructive (the two catalogs are
    // disjoint, so pruning would zero the other one permanently), and a count
    // is only ever looked up for an item that is in the list right now, so a
    // stale key cannot reach the draw. The bound exists only so that pasting in
    // a very large list cannot grow a blob that is rewritten on every
    // backgrounding.
    if counts.count > 500 {
      let live = Set(items)
      counts = counts.filter { live.contains($0.key) }
    }

    var payload: [String: Any] = ["counts": counts]
    if let current = stats.current {
      payload["current"] = current
    }
    guard let data = try? JSONSerialization.data(withJSONObject: payload),
          let json = String(data: data, encoding: .utf8)
    else { return }

    // Written as a String so the module reads it back with a plain
    // `string(forKey:)`, matching how the app writes `launcher_config`.
    // `loadStats` accepts both forms anyway.
    (UserDefaults(suiteName: appGroupId) ?? .standard).set(json, forKey: quoteStatsKey)
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

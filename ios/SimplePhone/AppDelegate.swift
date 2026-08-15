internal import Expo
import React
import ReactAppDependencyProvider
import UIKit
import WidgetKit

/// The relay, handled in Swift before React Native exists.
///
/// A widget tap ALWAYS launches the widget's own host app; iOS offers no way
/// around that, so this app appearing for a moment is unavoidable. How LONG it
/// appears is not.
///
/// Handling the URL in JavaScript meant the whole React Native cold start --
/// Hermes, the bundle, Expo Router mounting, an effect firing -- had to finish
/// before the target app was even asked to open. The SwiftUI original had no
/// such tax: `onOpenURL` fires almost immediately. The port made the flash
/// worse, and this puts it back.
///
/// Both entry points are covered here, and JavaScript no longer opens anything,
/// so there is exactly one opener and no way to fire twice:
///   - cold launch: the URL arrives in `launchOptions`
///   - already running: `application(_:open:options:)`
private enum Relay {
  static let scheme = "simplephonern"
  static let host = "open"
  static let queryKey = "u"

  /// Twin of `DeepLink.target(from:)` in the widget. Parses the RAW url: the
  /// payload is percent-encoded and carries its own query, so anything that
  /// decodes twice or splits on `&` mangles it.
  static func target(from url: URL) -> URL? {
    guard url.scheme == scheme,
          url.host == host,
          let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
          let raw = components.queryItems?.first(where: { $0.name == queryKey })?.value,
          let target = URL(string: raw)
    else { return nil }
    return target
  }

  /// Returns true when `url` was ours, whether or not the target opened.
  @discardableResult
  static func handle(_ url: URL, window: UIWindow?) -> Bool {
    guard let target = target(from: url) else { return false }

    // BOTH of these are synchronous, before any main-queue hop, and that is the
    // point. `beginRelay` closes the window in which a `didBecomeActive` could
    // tear the cover down, and the cover itself is up before this callout
    // returns -- painted by UIKit over the launch image on a cold start, with
    // React Native still booting behind it. Doing any of it in JavaScript would
    // have meant waiting out the whole cold start before the user saw a word.
    QuoteScreen.beginRelay()
    let hold = QuoteScreen.cover(in: window)

    // The OPEN is what waits a runloop turn: this also runs during
    // `didFinishLaunchingWithOptions`, where opening synchronously is too early
    // for LaunchServices.
    DispatchQueue.main.async {
      // "Instant" means the moment the cover is actually on screen, not zero.
      // On a warm relay the cover has been up since the last backgrounding, so
      // `afterPresented` fires immediately and there is no wait at all.
      QuoteScreen.afterPresented {
        // The hold is timed from the frame, not from before it, so the number
        // the user picked is the number of seconds they actually get. Zero is
        // not special-cased here any more: `scheduleOpen` ticks synchronously
        // for it, so the instant path is as fast as it ever was and still
        // stops under a finger.
        QuoteScreen.scheduleOpen(after: hold, target: target) {
          open(target, window: window)
        }
      }
    }
    return true
  }

  private static func open(_ target: URL, window: UIWindow?) {
    // Free refresh for the weather widget, and the highest-leverage one
    // available. WidgetKit's daily budget is only charged for reloads requested
    // while the app is in the BACKGROUND, and a relay means the user just
    // tapped a widget, so the app is foregrounded right now. Every launcher tap
    // therefore nudges the forecast along at no cost to the 45-minute schedule.
    //
    // The kind string is spelled out because `DeepLink` lives in the widget
    // target and is not compiled into the app. It must match
    // WeatherWidget.swift exactly; a typo here fails silently, which is the
    // worst that can happen — this is an accelerator, not a correctness
    // requirement, and it can be deleted without breaking anything.
    WidgetCenter.shared.reloadTimelines(ofKind: "SimplePhoneWeather")

    // No `releaseHold` here. The relay is released when the app has actually
    // LEFT (`didEnterBackground`), or below when the open failed. Releasing at
    // the call site left the handoff itself unguarded, so an activation landing
    // mid-handoff could pull the cover down and show the list.
    UIApplication.shared.open(target, options: [:]) { success in
      guard !success else { return }
      // The app is staying put, so the cover has to come down: it is above the
      // window the alert is presented into, and nothing else would ever remove
      // it -- no backgrounding means no foregrounding means no dismiss.
      QuoteScreen.dismissForFailure()
      presentFailure(target, window: window)
    }
  }

  /// The original swallowed failure, so a row for an app you do not have simply
  /// did nothing. That silence is indistinguishable from opening the wrong app
  /// or from a scheme Apple changed, and diagnosing it costs hours.
  private static func presentFailure(_ target: URL, window: UIWindow?) {
    // The copy comes from the relay block in `quotes.json`, which is already a
    // resource of this target, rather than from a JavaScript catalog: this runs
    // on a cold launch where React Native may not have a bridge yet, so there is
    // nothing on the JS side to ask.
    //
    // The URL is SUBSTITUTED into the sentence, not concatenated around it. The
    // Japanese line puts the whole explanation before the URL, which no amount
    // of prefix-plus-suffix can express.
    let strings = QuoteScreen.relayStrings(language: QuoteScreen.configuredLanguage())
    let alert = UIAlertController(
      title: strings["title"],
      message: strings["body"]?.replacingOccurrences(of: "%@", with: target.absoluteString),
      preferredStyle: .alert)
    // The only literal left, and it is the one that has to survive a missing
    // resource: an action with no title is a button the user cannot read, on an
    // alert with no other way out.
    alert.addAction(UIAlertAction(title: strings["ok"] ?? "OK", style: .default))

    var presenter = window?.rootViewController ?? QuoteScreen.failurePresenter()
    while let presented = presenter?.presentedViewController {
      presenter = presented
    }
    presenter?.present(alert, animated: true)
  }
}

@main
class AppDelegate: ExpoAppDelegate {
  var window: UIWindow?

  var reactNativeDelegate: ExpoReactNativeFactoryDelegate?
  var reactNativeFactory: RCTReactNativeFactory?

  public override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
  ) -> Bool {
    let delegate = ReactNativeDelegate()
    let factory = ExpoReactNativeFactory(delegate: delegate)
    delegate.dependencyProvider = RCTAppDependencyProvider()

    reactNativeDelegate = delegate
    reactNativeFactory = factory

#if os(iOS) || os(tvOS)
    window = UIWindow(frame: UIScreen.main.bounds)
    QuoteScreen.attach(hostWindow: window)

    // Cold launch FROM a widget tap. `application(_:open:options:)` is not
    // called in this case -- the URL rides in launchOptions -- so the relay has
    // to be read here or the target never opens on a cold start.
    //
    // BEFORE `startReactNative`, deliberately. Window level is what decides
    // z-order, so both orders composite correctly, but starting React Native
    // can spin nested runloop turns in a Debug build (Metro fetch, the dev
    // loading view, LogBox) and each of those is a chance to commit a frame.
    // Covering first closes that gap for free.
    if let url = launchOptions?[.url] as? URL {
      Relay.handle(url, window: window)
    }

    factory.startReactNative(
      withModuleName: "main",
      in: window,
      launchOptions: launchOptions)
#endif

    // The cover has to come down when the user comes BACK, otherwise a stale
    // line sits over the app list. Foregrounding is the right moment: it covers
    // returning from the target app, and it also covers the case where the
    // target never opened. `dismiss` is a no-op while a relay is in flight.
    NotificationCenter.default.addObserver(
      forName: UIApplication.didBecomeActiveNotification,
      object: nil,
      queue: .main
    ) { _ in
      // Not `dismiss` any more: a return that follows a handoff keeps the line
      // on screen so a phrase nobody got to read is not simply lost.
      QuoteScreen.activate()
    }

    // The other half of the fix, and the half no overlay can do on its own.
    //
    // UIKit takes a snapshot of the UI once this callout returns, and iOS
    // REPLAYS that image for the whole open animation the next time the app is
    // foregrounded -- before `application(_:open:options:)`, before any of our
    // code. Whatever was on screen at the last backgrounding is therefore what
    // the user watches during the next widget tap. Putting the cover up here
    // makes the snapshot the phrase instead of the app list.
    //
    // No animation is started, per QA1838: the snapshot is taken immediately
    // and would catch a half-finished one.
    NotificationCenter.default.addObserver(
      forName: UIApplication.didEnterBackgroundNotification,
      object: nil,
      queue: .main
    ) { _ in
      // Leaving IS the successful end of a relay. Released here rather than at
      // the `open` call so the guard covers the handoff itself.
      QuoteScreen.endRelay()
      QuoteScreen.cover(forSnapshot: true)
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // Linking API
  public override func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]
  ) -> Bool {
    // Ours: open the target now and return WITHOUT forwarding to
    // RCTLinkingManager. Forwarding would hand the same URL to JavaScript,
    // which would open the target a second time.
    if Relay.handle(url, window: window) {
      return true
    }

    return super.application(app, open: url, options: options) || RCTLinkingManager.application(app, open: url, options: options)
  }

  // Universal Links
  public override func application(
    _ application: UIApplication,
    continue userActivity: NSUserActivity,
    restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void
  ) -> Bool {
    let result = RCTLinkingManager.application(application, continue: userActivity, restorationHandler: restorationHandler)
    return super.application(application, continue: userActivity, restorationHandler: restorationHandler) || result
  }
}

class ReactNativeDelegate: ExpoReactNativeFactoryDelegate {
  // Extension point for config-plugins

  override func sourceURL(for bridge: RCTBridge) -> URL? {
    // needed to return the correct URL for expo-dev-client.
    bridge.bundleURL ?? bundleURL()
  }

  override func bundleURL() -> URL? {
#if DEBUG
    return RCTBundleURLProvider.sharedSettings().jsBundleURL(forBundleRoot: ".expo/.virtual-metro-entry")
#else
    return Bundle.main.url(forResource: "main", withExtension: "jsbundle")
#endif
  }
}

internal import Expo
import React
import ReactAppDependencyProvider
import UIKit

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

    // Async on the main queue because this also runs during
    // `didFinishLaunchingWithOptions`, where opening synchronously is too early
    // for LaunchServices.
    DispatchQueue.main.async {
      // The phrase is on screen NOW, painted by UIKit over the launch image,
      // with React Native still booting behind it. Doing this in JavaScript
      // would have meant waiting out the whole cold start before the user saw
      // a single word. The hold comes from the user's own setting.
      guard let hold = QuoteScreen.present(in: window) else {
        open(target, window: window)
        return
      }
      // A zero hold opens NOW, in this same pass. The phrase has already been
      // forced to draw, so it covers the handoff without adding a millisecond
      // to it. Scheduling even a zero-delay timer would cost a runloop turn for
      // nothing.
      guard hold > 0 else {
        open(target, window: window)
        return
      }
      DispatchQueue.main.asyncAfter(deadline: .now() + hold) {
        open(target, window: window)
      }
    }
    return true
  }

  private static func open(_ target: URL, window: UIWindow?) {
    QuoteScreen.releaseHold()
    UIApplication.shared.open(target, options: [:]) { success in
      guard !success else { return }
      presentFailure(target, window: window)
    }
  }

  /// The original swallowed failure, so a row for an app you do not have simply
  /// did nothing. That silence is indistinguishable from opening the wrong app
  /// or from a scheme Apple changed, and diagnosing it costs hours.
  private static func presentFailure(_ target: URL, window: UIWindow?) {
    let alert = UIAlertController(
      title: "Could not open this",
      message: "iOS refused to open:\n\n\(target.absoluteString)\n\n"
        + "No installed app handles it, or the scheme changed.",
      preferredStyle: .alert)
    alert.addAction(UIAlertAction(title: "OK", style: .default))

    var presenter = window?.rootViewController
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
    factory.startReactNative(
      withModuleName: "main",
      in: window,
      launchOptions: launchOptions)
#endif

    // The phrase window has to come down when the user comes BACK, otherwise a
    // stale line sits over the app list. Foregrounding is the right moment: it
    // covers returning from the target app, and it also covers the case where
    // the target never opened and the alert was shown on top.
    NotificationCenter.default.addObserver(
      forName: UIApplication.didBecomeActiveNotification,
      object: nil,
      queue: .main
    ) { _ in
      QuoteScreen.dismiss()
    }

    // Cold launch FROM a widget tap. `application(_:open:options:)` is not
    // called in this case -- the URL rides in launchOptions -- so the relay has
    // to be read here or the target never opens on a cold start.
    if let url = launchOptions?[.url] as? URL {
      Relay.handle(url, window: window)
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

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

  /// Holds the handoff while a finger is on the cover. See `RelayGate` for the
  /// rule and `scripts/test-relay-gate` for what it is required to do.
  private static let gate = RelayGate()

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

  /// Called once, at launch, so the background observer does not need to reach
  /// back into the app delegate.
  static func attach(hostWindow window: UIWindow?) {
    hostWindow = window
    listenForTouches(on: window)
  }

  /// A SECOND place the finger can be heard, on the app's own window.
  ///
  /// The cover is its own UIWindow above everything, and `CoverView` picks up
  /// touches that land on it. That is not enough. A warm relay arrives while
  /// the system is still animating the app in, and during that stretch the
  /// overlay is not necessarily the window UIKit hands the touch to even though
  /// it is the one being drawn. A touch that lands the instant the phrase
  /// appears was going nowhere: the user was told to hold, held, and watched
  /// the app leave anyway.
  ///
  /// A recogniser on the host window catches that case without taking anything
  /// away from anyone: `cancelsTouchesInView` stays false so React Native still
  /// sees every touch, and it only speaks to the gate while a relay is actually
  /// in flight.
  private static func listenForTouches(on window: UIWindow?) {
    guard let window else { return }
    let recognizer = UILongPressGestureRecognizer(target: Proxy.shared,
                                                  action: #selector(Proxy.hostTouch(_:)))
    recognizer.minimumPressDuration = 0
    recognizer.cancelsTouchesInView = false
    recognizer.delaysTouchesBegan = false
    recognizer.delaysTouchesEnded = false
    recognizer.delegate = Proxy.shared
    window.addGestureRecognizer(recognizer)
  }

  /// What the phrase you missed was, and whether you are owed it back.
  private static var pendingReturn = RelayReturn()

  /// The line that was on the cover when THIS relay started.
  ///
  /// Captured here and not read back later, because backgrounding rolls the
  /// next phrase to paint into the snapshot: by the time anyone comes back, the
  /// stored `current` is a different line and the card would offer a phrase the
  /// user never saw.
  private static var relayPhrase: String?

  static func beginRelay() {
    relayInFlight = true
    relayPhrase = nil
    clearCoverGestures()
    // A card still owed when a new relay starts was never collected: the user
    // launched something else instead of tapping the breadcrumb, so that line
    // is one they chose not to read.
    if pendingReturn.isPending {
      rollOwed = true
      pendingReturn.clear()
    }
  }

  /// Set when a return went uncollected, and honoured at the next exit.
  ///
  /// An exit ending a relay someone may still come back to keeps its line; the
  /// exit after one they walked away from rolls. Why it cannot simply always
  /// roll, or always keep: `docs/native-notes.md`, "One paint, two audiences".
  private static var rollOwed = false

  /// The line already on the cover, neither re-drawn nor re-counted.
  ///
  /// Falls back to the stored `current` because `relayPhrase` lives only as long
  /// as the process, and repainting the cover blank would be worse than
  /// repainting it the same.
  private static func keptQuote(_ config: QuoteCatalog.Config) -> QuoteCatalog.Quote? {
    guard let text = relayPhrase ?? QuoteCatalog.loadStats().current else { return nil }
    return config.items.first { $0.text == text }
  }

  /// Strips the recognisers a pinned cover or a return card left behind.
  ///
  /// The window outlives any one relay, so these accumulate, and a pan among
  /// them cancels the touches the view uses to detect a hold. Every recogniser
  /// also sets `cancelsTouchesInView = false`; either half alone hides the
  /// other. See `docs/native-notes.md`, "Touches on the cover".
  private static func clearCoverGestures() {
    guard let root = window?.rootViewController?.view else { return }
    root.gestureRecognizers?.forEach(root.removeGestureRecognizer)
  }

  /// Called the instant the target is asked to open, which is the moment the
  /// phrase becomes something the user might not have finished reading.
  private static func recordHandoff(target: URL) {
    pendingReturn.handedOff(phrase: relayPhrase, target: target,
                            at: Date().timeIntervalSince1970)
  }

  /// The app is being activated. Either the user is coming back from a relay
  /// they did not get to read, or they are opening the app to use it.
  static func activate() {
    guard !relayInFlight else { return }
    if let missed = pendingReturn.consume(at: Date().timeIntervalSince1970), window != nil {
      presentCard(missed)
      return
    }
    dismiss()
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
    let config = QuoteCatalog.loadConfig()

    if forSnapshot {
      let next: QuoteCatalog.Quote?
      if rollOwed || !pendingReturn.isPending {
        next = QuoteCatalog.roll(config)
        rollOwed = false
      } else {
        // Keeping what is already there: this exit ends a relay whose line the
        // user can still come back for, so the snapshot has to carry that line
        // and not its replacement.
        next = keptQuote(config)
      }
      if window == nil {
        show(config, phrase: next, in: appWindow ?? hostWindow, forSnapshot: true)
      } else {
        refill(config, phrase: next)
      }
    } else if window == nil {
      // Reachable only on a COLD relay: a warm one always finds the cover the
      // last backgrounding left standing. See `restoreOrRoll`.
      // A cold relay proves any earlier return went uncollected: `pendingReturn`
      // is memory-only, so a killed process took the evidence with it. Marked
      // rather than rolled, because this relay still has to show the line the
      // dead process painted into the snapshot.
      rollOwed = true
      let drawn = QuoteCatalog.restoreOrRoll(config)
      relayPhrase = drawn?.text
      show(config, phrase: drawn, in: appWindow ?? hostWindow, forSnapshot: false)
      QuoteCatalog.countAsShown(relayPhrase, config: config)
    } else {
      // The cover being KEPT is the one the last backgrounding painted, and
      // `roll` recorded that line as `current` when it painted it. Reading it
      // HERE and not in `beginRelay` is the difference between the card showing
      // the phrase the user saw and showing the one before it: on a cold relay
      // the branch above draws a fresh line, and a capture taken before this
      // call would already be stale.
      relayPhrase = QuoteCatalog.loadStats().current
      QuoteCatalog.countAsShown(relayPhrase, config: config)
    }
    // Anything else: the cover already on screen is KEPT exactly as it is, and
    // this call reads nothing but the config it already needed.

    // Gated on `enabled` like every other branch above. Without it, turning
    // Phrases OFF while a duration longer than instant was selected left the
    // relay holding for that long on a blank themed rectangle -- the setting
    // still costing its time after being switched off, which is the one thing
    // an off switch must never do.
    return config.enabled ? config.holdSeconds : 0
  }

  /// Torn down when the app comes back to the foreground, which is the moment
  /// the user returns from the target app. Leaving it up would show a stale
  /// phrase over the list.
  static func dismiss() {
    guard !relayInFlight else { return }
    // Before anything else: the cover is going away, so a handoff still owed to
    // a finger that is no longer there must not fire into an app the user has
    // already come back from.
    gate.reset()
    clearCoverGestures()
    fingerLeft()
    cardPhrase = nil
    resumeTarget = nil
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
    // Nothing was missed: the app never left, and the user is about to be
    // looking at an alert rather than at the phrase.
    pendingReturn.clear()
    dismiss()
  }

  // MARK: - The phrase you missed

  /// Turns the cover already on screen into something you can read at leisure.
  ///
  /// Not a new screen and deliberately so. The cover has been up since the last
  /// backgrounding, so it is what the system was already replaying while the
  /// app animated back in: the line simply stays instead of being torn down,
  /// and gains a count and a way out. Nothing flashes and nothing moves.
  private static func presentCard(_ missed: RelayReturn.Missed) {
    let text = missed.phrase
    resumeTarget = missed.target
    guard let overlay = window, let root = overlay.rootViewController?.view else { return }
    // A touch on the card is not a touch on a relay. Without this the press
    // that dismisses it would leave the gate holding, and the NEXT relay would
    // inherit a finger that is not there.
    gate.reset()
    // The pinned cover leaves a tap and a pan behind, and this adds its own.
    // Without stripping first they stack on the same view, and the card's
    // recogniser would be competing with a tap that means "carry on" for a
    // cover that no longer exists.
    clearCoverGestures()

    let config = QuoteCatalog.loadConfig()
    let author = config.items.first { $0.text == text }?.author
    let count = QuoteCatalog.loadStats().counts[text] ?? 0

    root.subviews.forEach { $0.removeFromSuperview() }
    let phrase = QuoteCatalog.Quote(text: text, author: author)
    cardPhrase = phrase
    let stack = CoverChrome.fill(root, config: config, phrase: phrase)
    tallyLabel = CoverChrome.addCardChrome(
      to: root, below: stack, config: config, count: count,
      target: Proxy.shared, copy: #selector(Proxy.copyCard),
      share: #selector(Proxy.shareCard), open: #selector(Proxy.dismissCard))
    shade?.removeFromSuperview()
    shade = nil

    // Swiping right means the same thing it means on a pinned cover: take me
    // where I was going. Here that is the app the user just came BACK from,
    // which is why the destination had to be remembered alongside the line.
    //
    // Swipe only, and no tap. On a pinned cover a tap is someone mid-launch
    // carrying on; on this card it would be someone who deliberately came back
    // being thrown out again by a stray touch.
    // A PAN and not a swipe. `UISwipeGestureRecognizer` wants a flick: a
    // deliberate, unhurried drag to the right never reaches its velocity
    // threshold and is silently ignored, which is exactly what a person doing
    // what the feature describes would do.
    let drag = UIPanGestureRecognizer(target: Proxy.shared, action: #selector(Proxy.resume(_:)))
    drag.cancelsTouchesInView = false
    root.addGestureRecognizer(drag)

    root.layoutIfNeeded()
  }

  /// Far enough sideways, either way, to mean "take me there" rather than a
  /// finger settling.
  ///
  /// Direction is deliberately not checked: asking for one only tests whether
  /// the user guessed the same convention as the author. Read on `.ended`, so a
  /// threshold crossed mid-drag cannot fire under a thumb still deciding.
  private static func draggedSideways(_ recognizer: UIGestureRecognizer) -> Bool {
    guard let pan = recognizer as? UIPanGestureRecognizer, pan.state == .ended else { return false }
    let moved = pan.translation(in: pan.view)
    return abs(moved.x) > 60 && abs(moved.x) > abs(moved.y)
  }

  /// Where the user was going when the phrase got away from them.
  private static var resumeTarget: URL?

  /// Back to the app they came from, from the card.
  ///
  /// A plain open rather than a fresh relay: the cover is already on screen, so
  /// nothing is exposed, and re-entering the relay would roll a different line
  /// under someone who came back to read this one. If the open fails the card
  /// simply stays, which is a fair way to say nothing happened.
  fileprivate static func resumeJourney(_ recognizer: UIGestureRecognizer) {
    guard draggedSideways(recognizer), let target = resumeTarget else { return }
    resumeTarget = nil
    UIApplication.shared.open(target, options: [:]) { ok in
      // RE-ARM, and this is the part that was missing. Resuming opens the
      // target directly instead of going through the relay, so nothing
      // recorded that a phrase was owed again: the second time the user came
      // back, the cover found nothing pending and fell through to the list.
      //
      // If a line is worth coming back to once it is worth coming back to
      // twice. Bouncing keeps working for as long as the user keeps bouncing,
      // and the two minute window still ends it once they settle into the
      // other app.
      guard ok, let phrase = cardPhrase?.text else { return }
      pendingReturn.handedOff(phrase: phrase, target: target,
                              at: Date().timeIntervalSince1970)
    }
  }

  // MARK: - Pinning the cover on purpose

  /// How long a finger has to stay down before the cover is pinned.
  ///
  /// Long enough that nobody trips it while reaching for the screen, short
  /// enough that it does not feel like a punishment. Being able to WATCH it
  /// fill is what makes the number tolerable.
  private static let lockDuration: TimeInterval = 1.2

  private static var lockWork: DispatchWorkItem?

  /// A finger arrived on the cover, at `point`.
  ///
  /// Also the honest signal that the touch was SEEN. iOS delivers nothing to
  /// this app for the first ~420ms of a relay, so a press that draws no ring is
  /// a press that never reached us: lift, press again, and the ring appears.
  /// That is worth more than any hint text, because it is the truth rather than
  /// a description of it.
  /// A finger arrived on the cover: start the clock that pins it.
  ///
  /// No drawn ring any more. An earlier version filled a dial under the thumb
  /// and never once appeared on a device, so it carried no information while
  /// costing a layer tree per touch. The haptic at the moment of pinning is the
  /// feedback.
  fileprivate static func fingerLanded() {
    guard relayInFlight, !gate.locked, lockWork == nil,
          let root = window?.rootViewController?.view,
          !(root.subviews.compactMap { $0 as? UIStackView }.isEmpty)
    else { return }

    let work = DispatchWorkItem { engageLock() }
    lockWork = work
    DispatchQueue.main.asyncAfter(deadline: .now() + lockDuration, execute: work)
  }

  /// The finger left before it had been down long enough.
  private static func fingerLeft() {
    lockWork?.cancel()
    lockWork = nil
  }

  /// The finger held long enough. From here nothing leaves on its own.
  private static func engageLock() {
    guard relayInFlight, !gate.locked, let root = window?.rootViewController?.view else { return }
    gate.lock()
    // Copy and Share read this; on the return card it is set by `presentCard`.
    if let text = relayPhrase {
      cardPhrase = QuoteCatalog.Quote(text: text, author: QuoteCatalog.loadConfig().items.first { $0.text == text }?.author)
    }
    lockWork = nil

    UIImpactFeedbackGenerator(style: .medium).impactOccurred()

    let config = QuoteCatalog.loadConfig()
    let count = relayPhrase.map { QuoteCatalog.loadStats().counts[$0] ?? 0 } ?? 0
    let stack = root.subviews.compactMap { $0 as? UIStackView }.first
    tallyLabel = CoverChrome.addCardChrome(
      to: root, below: stack, config: config, count: count,
      target: Proxy.shared, copy: #selector(Proxy.copyCard),
      share: #selector(Proxy.shareCard), open: #selector(Proxy.dismissCard))
    CoverChrome.addPadlock(to: root, config: config)

    let tap = UITapGestureRecognizer(target: Proxy.shared, action: #selector(Proxy.proceedFromLock))
    tap.cancelsTouchesInView = false
    root.addGestureRecognizer(tap)
    let drag = UIPanGestureRecognizer(target: Proxy.shared,
                                      action: #selector(Proxy.proceedFromLock(_:)))
    drag.cancelsTouchesInView = false
    root.addGestureRecognizer(drag)
  }


  /// The user chose THIS app over the one the row pointed at.
  ///
  /// `dismiss` alone is not enough and that is not obvious: it refuses to do
  /// anything while a relay is in flight, and a pinned cover is a relay still
  /// in flight, because nothing was ever handed off. On the return card the
  /// relay is long over and the plain dismiss works, which is exactly why this
  /// path went unnoticed until a locked cover met the button.
  ///
  /// Ending the relay here is honest rather than a workaround: the target is
  /// not going to open, so there is nothing left to guard.
  fileprivate static func openHostApp() {
    relayInFlight = false
    pendingReturn.clear()
    dismiss()
  }

  /// A tap on the pinned cover, or a drag to the right: go where the widget row
  /// was pointing all along.
  ///
  /// A tap that lands on one of the controls is not this. `copy`, `share` and
  /// the button all sit in front and would otherwise be unreachable, since the
  /// recogniser is on the view behind them.
  fileprivate static func proceedFromLock(_ recognizer: UIGestureRecognizer) {
    guard gate.locked, let root = window?.rootViewController?.view else { return }
    if recognizer is UITapGestureRecognizer {
      if root.hitTest(recognizer.location(in: root), with: nil) is UIControl { return }
    } else if !draggedSideways(recognizer) {
      return
    }
    gate.proceed()
    // The handoff `proceed` fires records the return like any other, and it is
    // LEFT ALONE on purpose.
    //
    // This used to clear it, reasoning that a line read deliberately has
    // nothing left to recover. That was backwards. Pinning the cover is the
    // strongest signal a phrase matters to this person, so clearing it took the
    // card away from precisely the user who cared most, and cost them the
    // flash-free return as well: with nothing pending, the exit rolls a new
    // line into the snapshot and they watch it change on the way back.
  }

  // MARK: - Taking the line with you



  fileprivate static func copyCard() {
    guard let phrase = cardPhrase else { return }
    UIPasteboard.general.string = CoverChrome.cardText(phrase)
    flashConfirmation()
  }

  fileprivate static func shareCard() {
    guard let phrase = cardPhrase, let presenter = window?.rootViewController else { return }
    var items: [Any] = [CoverChrome.cardText(phrase)]
    let size = window?.bounds.size ?? UIScreen.main.bounds.size
    if let image = CoverChrome.cardImage(config: QuoteCatalog.loadConfig(), phrase: phrase,
                                         size: size) {
      items.insert(image, at: 0)
    }
    let sheet = UIActivityViewController(activityItems: items, applicationActivities: nil)
    presenter.present(sheet, animated: true)
  }

  /// A word where the count was, for a moment. Cheaper than an alert and it
  /// does not take the card away from under the user.
  private static func flashConfirmation() {
    guard let label = tallyLabel else { return }
    let previous = label.text
    label.text = QuoteCatalog.relayStrings(language: QuoteCatalog.loadConfig().language)["copied"] ?? "Copied"
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
      guard tallyLabel === label else { return }
      label.text = previous
    }
  }

  /// The line the card is showing, so copy and share do not have to find it
  /// again, and the count label, so the copy confirmation has somewhere to go.
  private static var cardPhrase: QuoteCatalog.Quote?
  private static weak var tallyLabel: UILabel?



  /// Where the failure alert should be presented from. The cover is normally
  /// gone by then (`dismissForFailure`), so this is the app's own root; the
  /// cover's own controller is the fallback for the cold path, where React
  /// Native's root view may not be in a hierarchy yet.
  static func failurePresenter() -> UIViewController? {
    hostWindow?.rootViewController ?? window?.rootViewController
  }

  // MARK: - Presentation

  private static func show(_ config: QuoteCatalog.Config, phrase: QuoteCatalog.Quote?, in appWindow: UIWindow?, forSnapshot: Bool) {
    if let appWindow {
      hostWindow = appWindow
    }

    let overlay: UIWindow
    if let scene = windowScene(preferring: appWindow) {
      overlay = CoverWindow(windowScene: scene)
    } else {
      // No scene yet. This app has no `UIApplicationSceneManifest`, so it runs
      // the legacy app-delegate lifecycle and this initialiser is valid -- it
      // is the same one the app's own window uses in AppDelegate. Never return
      // without a cover just because the scene set was not populated yet.
      overlay = CoverWindow(frame: UIScreen.main.bounds)
    }
    // Above the app's own window (.normal, 0) and above React Native's debug
    // chrome in a Debug build (RCTDevLoadingView sits at .statusBar + 1), while
    // staying well below .alert so system alerts still reach the user.
    overlay.windowLevel = .statusBar + 2

    let controller = UIViewController()
    // ALWAYS, including the snapshot path. A warm relay does not build a new
    // cover: it keeps the one the last backgrounding left standing, so the
    // window created with `forSnapshot: true` is the very one the user's finger
    // lands on in the common case. Only the `shade` copy below stays inert.
    controller.view = CoverView(frame: overlay.bounds)
    CoverChrome.fill(controller.view, config: config, phrase: phrase)
    overlay.backgroundColor = controller.view.backgroundColor
    overlay.rootViewController = controller
    overlay.makeKeyAndVisible()

    if let host = appWindow ?? hostWindow, host !== overlay {
      let copy = UIView(frame: host.bounds)
      copy.autoresizingMask = [.flexibleWidth, .flexibleHeight]
      CoverChrome.fill(copy, config: config, phrase: phrase)
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
  private static func refill(_ config: QuoteCatalog.Config, phrase: QuoteCatalog.Quote?) {
    guard let overlay = window else { return }

    if let root = overlay.rootViewController {
      root.view.subviews.forEach { $0.removeFromSuperview() }
      CoverChrome.fill(root.view, config: config, phrase: phrase)
      overlay.backgroundColor = root.view.backgroundColor
      root.view.layoutIfNeeded()
    }
    if let shade = shade {
      shade.subviews.forEach { $0.removeFromSuperview() }
      CoverChrome.fill(shade, config: config, phrase: phrase)
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
  @discardableResult

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

  // MARK: - Holding the cover under a finger

  /// Hands off after `seconds`, unless a finger is on the cover.
  ///
  /// Replaces a bare `asyncAfter(open)` at the call site, and the difference is
  /// the whole feature: the wait still runs on a timer, but the decision to
  /// leave is taken by the gate at the moment the timer lands, so a touch that
  /// arrived in the meantime is seen.
  ///
  /// ZERO IS NOT A SPECIAL CASE, and that is the point. "Instant" still shows
  /// the phrase, because the cover is what the user is looking at during the
  /// app-switch animation whatever the duration says. Ticking synchronously
  /// keeps that path exactly as fast as it was while still asking the gate,
  /// which is what lets a finger that landed during the animation freeze it.
  ///
  /// The timer is never cancelled, it is STAMPED. A press and release can hand
  /// off long before the timer lands, and the tick left over from that relay
  /// would otherwise satisfy the NEXT one and cut its cover short. Carrying the
  /// token the gate handed out is what makes the stale tick a no-op, and it
  /// beats a `DispatchWorkItem` because there is nothing to hold, cancel or
  /// leak.
  ///
  /// The instant path takes one runloop hop rather than ticking inline. That is
  /// not a delay anyone can perceive, and it is the only thing standing between
  /// this feature and being unreachable at zero: touch delivery happens between
  /// runloop turns, so ticking synchronously guarantees no finger is ever seen.
  /// It still costs nothing when nobody is touching, which is the rule about an
  /// off switch never charging for itself.
  static func scheduleOpen(after seconds: TimeInterval, target: URL,
                           _ open: @escaping () -> Void) {
    let token = gate.arm {
      recordHandoff(target: target)
      open()
    }
    guard seconds > 0 else {
      DispatchQueue.main.async { gate.durationElapsed(token) }
      return
    }
    countDown(seconds, token: token)
  }

  /// Starts the hold only once the app is ACTIVE, which is the difference
  /// between a duration you can touch and one you can only watch.
  ///
  /// A warm relay arrives during the open animation, and for the whole of that
  /// animation iOS is replaying a snapshot image while the app is not
  /// interactive. `application(_:open:options:)` runs inside that window, so
  /// counting from there spent the user's 0.8 seconds on a picture: by the time
  /// a finger could be delivered anywhere, the target had been asked to open.
  /// The phrase looked right and the hold was unreachable.
  ///
  /// The number in the Phrases screen is therefore seconds of LIVE cover, which
  /// is what it always claimed to be and what the header of this file says the
  /// frame wait exists to guarantee.
  /// How long after the app becomes active before a touch is actually
  /// delivered to it. Measured, not guessed: `docs/native-notes.md`, "The dead
  /// 420 milliseconds".
  ///
  /// Without it the chosen duration is partly spent on a picture the user
  /// cannot touch, and the number in the Phrases screen stops meaning what it
  /// says.
  private static let touchSettleDelay: TimeInterval = 0.25

  private static func countDown(_ seconds: TimeInterval, token: Int) {
    guard UIApplication.shared.applicationState != .active else {
      DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { gate.durationElapsed(token) }
      return
    }

    if let waiter = activationWaiter {
      NotificationCenter.default.removeObserver(waiter)
    }
    activationWaiter = NotificationCenter.default.addObserver(
      forName: UIApplication.didBecomeActiveNotification,
      object: nil,
      queue: .main
    ) { _ in
      if let waiter = activationWaiter {
        NotificationCenter.default.removeObserver(waiter)
        activationWaiter = nil
      }
      DispatchQueue.main.asyncAfter(deadline: .now() + touchSettleDelay + seconds) {
        gate.durationElapsed(token)
      }
    }

    // A launcher that never launches is the worst failure this code has, and an
    // activation that never arrives would be exactly that. Generous, because it
    // only ever runs when the notification did not: normal foregrounding is
    // well under a second.
    DispatchQueue.main.asyncAfter(deadline: .now() + seconds + 3) { gate.durationElapsed(token) }
  }

  private static var activationWaiter: NSObjectProtocol?

  /// The cover itself, listening for a finger.
  ///
  /// Raw touch callbacks rather than a `UILongPressGestureRecognizer` with a
  /// zero minimum duration: a recognizer has to decide it has recognised
  /// something, and on the instant path there is no time to spare for that.
  /// `touchesBegan` arrives with the event.
  ///
  /// Nothing in `fill` takes touches (labels and stacks do not by default), so
  /// every touch on the cover reaches this.
  /// The cover's own window, listening at the lowest level UIKit offers.
  ///
  /// `CoverView` covers the ordinary case and misses two. A touch that
  /// hit-tests to something other than the root view never reaches its
  /// callbacks. And a finger that lands during the app-switch animation and
  /// then STAYS PUT produces no `touchesBegan` here (it began while the home
  /// screen still owned it) and no `touchesMoved` either, because nothing
  /// moved: measured on a real relay, not one event arrived in the whole
  /// second and a half while a thumb sat on the glass.
  ///
  /// `sendEvent` sees every event routed to this window before any of that
  /// dispatch happens, and `allTouches` carries touches in the `.stationary`
  /// phase, which is precisely the finger nothing else can see.
  private final class CoverWindow: UIWindow {
    override func sendEvent(_ event: UIEvent) {
      super.sendEvent(event)
      // Only while a handoff is actually pending. Once the relay is over this
      // same window carries the return card, and a tap on its Share button is
      // not a statement about any launch.
      guard QuoteScreen.relayInFlight, !QuoteScreen.gate.locked else { return }
      guard let touches = event.allTouches, !touches.isEmpty else { return }
      // Down if ANY touch is still on the glass. The gate collapses repeats,
      // so calling this on every event is free.
      let down = touches.contains { $0.phase != .ended && $0.phase != .cancelled }
      if down {
        QuoteScreen.gate.press()
        // Also here, because this is the ONLY place a finger that landed during
        // the app-switch animation is seen: it produces no `touchesBegan` on
        // the view, having begun while the home screen still owned it.
        QuoteScreen.fingerLanded()
      } else {
        QuoteScreen.gate.release()
      }
    }
  }

  private final class CoverView: UIView {
    /// The window resizes its root view for us, but the shade copy in `show`
    /// relies on this and a rotation should never leave a dead strip that eats
    /// nothing and hands off nothing.
    override init(frame: CGRect) {
      super.init(frame: frame)
      autoresizingMask = [.flexibleWidth, .flexibleHeight]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not from a nib") }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
      super.touchesBegan(touches, with: event)
      QuoteScreen.gate.press()
      QuoteScreen.fingerLanded()
    }

    /// A finger that was ALREADY DOWN when the cover became touchable.
    ///
    /// The relay arrives during the app-switch animation, and for the first
    /// stretch of it the touch belongs to the home screen: a measured 0.42s
    /// before this app sees anything at all. Someone who taps a row and puts
    /// their thumb straight back down is inside that window, so `touchesBegan`
    /// for their press never arrives here.
    ///
    /// A resting finger is never still, though. If UIKit hands the ongoing
    /// touch over once delivery starts, it arrives as movement rather than as
    /// a beginning, and that is the only signal this case leaves behind.
    /// Treating it as a press costs nothing when a normal `touchesBegan` came
    /// first, because holding is idempotent.
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
      super.touchesMoved(touches, with: event)
      QuoteScreen.gate.press()
      // The finger that landed during the animation has no `began` here.
      // `fingerLanded` ignores repeats.
      QuoteScreen.fingerLanded()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
      super.touchesEnded(touches, with: event)
      QuoteScreen.gate.release()
      QuoteScreen.fingerLeft()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
      super.touchesCancelled(touches, with: event)
      QuoteScreen.gate.cancelPress()
      QuoteScreen.fingerLeft()
    }
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

  /// CADisplayLink retains its target, so the enum cannot be one. The host
  /// window's recogniser needs an NSObject target and a delegate too, and this
  /// is already the file's one long-lived object.
  private final class Proxy: NSObject, UIGestureRecognizerDelegate {
    static let shared = Proxy()

    @objc func tick() { QuoteScreen.tick() }

    @objc func proceedFromLock(_ recognizer: UIGestureRecognizer) {
      QuoteScreen.proceedFromLock(recognizer)
    }

    @objc func resume(_ recognizer: UIGestureRecognizer) {
      QuoteScreen.resumeJourney(recognizer)
    }

    @objc func copyCard() { QuoteScreen.copyCard() }
    @objc func shareCard() { QuoteScreen.shareCard() }

    /// The way out of the card, and the only one that matters: after this the
    /// cover is gone and the user is in the app they asked for.
    @objc func dismissCard() {
      QuoteScreen.openHostApp()
    }

    @objc func hostTouch(_ recognizer: UILongPressGestureRecognizer) {
      // Only while a cover is actually up. Outside a relay this window is the
      // ordinary app and a tap on it means nothing to the gate.
      guard QuoteScreen.window != nil else { return }
      switch recognizer.state {
      case .began, .changed:
        QuoteScreen.gate.press()
      case .ended, .cancelled, .failed:
        QuoteScreen.gate.release()
      default:
        break
      }
    }

    /// Never take a touch away from anything else. React Native's own
    /// recognisers, the scroll views and every button in the app keep working
    /// exactly as before; this one only listens.
    func gestureRecognizer(_ recognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
      true
    }
  }

  // MARK: - Type

}

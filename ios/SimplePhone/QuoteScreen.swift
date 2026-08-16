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

  /// Whether the last relay was interrupted rather than finished, and what to
  /// put back if so.
  private static var suspension = RelaySuspension()

  /// What the current relay does when it hands off. Kept so an interrupted one
  /// can be armed again with the same destination on the way back in, without
  /// the suspension having to carry a URL and stop being a Foundation type.
  private static var armedWork: (() -> Void)?

  /// When the visible countdown runs out, and how long it was to begin with.
  /// Read only at the moment a relay is interrupted, to work out what is left.
  private static var countdownDeadline: CFTimeInterval?
  private static var countdownTotal: TimeInterval = 0

  /// No deadline means the clock never started -- a finger landed inside the
  /// dead window before the cover was touchable -- so the whole of it is left,
  /// not none of it. Returning zero there handed off the moment the finger
  /// lifted, which is the exact behaviour a press is no longer allowed to have.
  private static func remainingCountdown() -> TimeInterval {
    guard let countdownDeadline else { return countdownTotal }
    return max(countdownDeadline - CACurrentMediaTime(), 0)
  }

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
    // A hold belongs to the cover it was made on. See `forgetHold`.
    forgetHold()
    // Launching something supersedes whatever the last relay was interrupted
    // in the middle of: this IS the user choosing, and they chose this instead.
    suspension.clear()
    isShowingCard = false
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
    // The off switch, honoured here as everywhere else. `roll`, `restoreOrRoll`
    // and `countAsShown` all refuse when Phrases is off; keeping a line that was
    // already on screen was the one path that did not, so switching it off left
    // the last phrase painted into every snapshot after it.
    guard config.enabled else { return nil }
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
    // AND THE CONTROLS THEY BELONGED TO. A pinned cover walked away from is
    // left standing on purpose -- `cover(forSnapshot:)` steps aside for it --
    // and a warm relay reuses whatever cover it finds. Without this, the next
    // launch inherited that pin's Copy, Share and "Open The Simple Phone", and
    // the last of those silently cancels the relay the user just asked for.
    CoverChrome.removeCardChrome(from: root)
    tallyLabel = nil
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
    let now = Date().timeIntervalSince1970
    // Before the card, because they answer different questions and only one can
    // be true: a card is owed when something DID open, a suspension when nothing
    // did.
    if let resumed = suspension.resume(at: now), window != nil, let work = armedWork {
      resumeRelay(resumed, work)
      return
    }
    if let missed = pendingReturn.consume(at: now), window != nil {
      presentCard(missed)
      return
    }
    dismiss()
  }

  /// Puts the user back in the relay they were taken out of.
  ///
  /// Nothing is repainted, and that is the whole trick: `cover(forSnapshot:)`
  /// left this cover alone on the way out, so the phrase, the pin's controls and
  /// the badge are all still on screen exactly as they were, and were what the
  /// system snapshotted. There is nothing to restore, only a clock to restart.
  private static func resumeRelay(_ resumed: RelaySuspension.Resumed,
                                  _ work: @escaping () -> Void) {
    relayInFlight = true
    let token = gate.arm(work)

    guard !resumed.pinned else {
      // The drag `engageLock` left on the view is still attached, along with
      // the controls, because `cover(forSnapshot:)` left this cover alone. So
      // locking again is the entire restoration.
      gate.lock()
      return
    }
    guard !resumed.held else {
      // A cover that was merely HELD has none of that. `engageLock` locks the
      // gate AND builds the controls and the way out, which is exactly what is
      // missing, so it is the whole answer rather than half of one.
      //
      // Locking without it produced a full-screen phrase with no countdown, no
      // controls and no working gesture, which survived being relaunched: every
      // touch route is gated on `!gate.locked`, `dismiss` refuses to run for
      // the length of a relay, and a pinned cover is a relay still in flight.
      engageLock()
      return
    }

    // Known before the settle, because a finger can land inside it and
    // `remainingCountdown` would otherwise read the deadline from BEFORE the
    // interruption -- long past by then, so worth zero, so lifting hands off at
    // once. `startCountdown` replaces both with the exact values.
    countdownTotal = resumed.total
    countdownDeadline = CACurrentMediaTime() + touchSettleDelay + resumed.secondsLeft

    // The same settle as a fresh relay. Unlocking has its own stretch where the
    // app is drawing but not yet being handed touches, so a countdown started
    // at this instant would again be partly unreachable.
    DispatchQueue.main.asyncAfter(deadline: .now() + touchSettleDelay) {
      startCountdown(resumed.secondsLeft, of: resumed.total, token: token)
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + touchSettleDelay + resumed.secondsLeft) {
      gate.durationElapsed(token)
    }
  }

  /// The relay is over when the app has left, not when `open` was called.
  /// Releasing at the call site left the handoff itself -- the exact interval
  /// the phrase exists to cover -- unguarded.
  static func endRelay() {
    // A relay that ends with NOTHING HANDED OFF did not finish, it was
    // interrupted: the screen locked itself, a call came in, the user left
    // mid-read. iOS reports every one of those as the same backgrounding as a
    // successful handoff, and the only thing that tells them apart is whether
    // anything was ever opened.
    //
    // Read before `gate.reset` and `forgetHold` clear the two things it needs.
    // A finger still down counts as a pin: holding means "I am still reading",
    // and nobody keeps a finger on the glass through a locked screen.
    if relayInFlight, !pendingReturn.isPending, armedWork != nil {
      suspension.interrupted(pinned: gate.locked, held: isHolding,
                             secondsLeft: remainingCountdown(),
                             total: countdownTotal,
                             at: Date().timeIntervalSince1970)
    } else if isShowingCard, let phrase = cardPhrase?.text {
      // THE CARD NEEDS THE SAME MERCY, by the same reasoning and against the
      // same interruptions. Putting it up consumed the offer, so a backgrounding
      // from a card looked exactly like one from the app list: the exit rolled
      // a new phrase and the next activation found nothing owed and tore the
      // card down. The user locked their phone reading a line and came back to
      // a different one.
      //
      // Owed again rather than suspended, because the card already has a
      // mechanism for being owed and `activate` already knows how to serve it.
      pendingReturn.handedOff(phrase: phrase, target: resumeTarget,
                              at: Date().timeIntervalSince1970)
    }
    relayInFlight = false
    // Every route that reports a finger stops at `relayInFlight`, so a finger
    // still down when the relay ends has no way left to report its own lift:
    // the gate would keep holding for a hand that is no longer there, and
    // `arm` only inherits-and-clears a finger that came with a pin. Nothing
    // else covers a cover walked away from mid-hold.
    gate.reset()
    forgetHold()
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
      // AN INTERRUPTED RELAY IS COMING BACK TO THIS EXACT COVER, so this is the
      // one backgrounding that must not touch it. The snapshot IS what the user
      // sees on the way back in, and repainting would roll a different line into
      // it -- which is the flash-then-swap the user reported -- while wiping the
      // pin, its controls and the badge along with it.
      if suspension.isPending { return 0 }

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
    isShowingCard = false
    // The cover this relay belonged to is gone, so there is nothing left to put
    // anyone back into. `activate` has already consumed the offer by now; this
    // is what stops one surviving any OTHER way the cover comes down.
    suspension.clear()
    armedWork = nil
    countdownDeadline = nil
    countdownTotal = 0
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
    isShowingCard = true
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
    // Switched off between the handoff and the return. Offering the line back
    // now would be the off switch failing to be off, on the one screen whose
    // whole purpose is to show a phrase.
    guard config.enabled else {
      isShowingCard = false
      dismiss()
      return
    }
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
    // A PAN and not a swipe. `UISwipeGestureRecognizer` wants a flick: a
    // deliberate, unhurried drag never reaches its velocity threshold and is
    // silently ignored, which is exactly what a person doing what the feature
    // describes would do. It is also the only kind that can drive a ring.
    // Only when there is somewhere to go. A badge that answers a drag leading
    // nowhere is an offer the card cannot keep.
    if resumeTarget != nil {
      badge = CoverChrome.addBadge(to: root, config: config, showsPause: false)
      badge?.quiet()
    }

    let drag = UIPanGestureRecognizer(target: Proxy.shared, action: #selector(Proxy.resume(_:)))
    drag.cancelsTouchesInView = false
    root.addGestureRecognizer(drag)

    root.layoutIfNeeded()
  }

  /// Where the user was going when the phrase got away from them.
  private static var resumeTarget: URL?

  /// The return card is what is on screen right now. Consuming the offer is
  /// what puts it up, so without this nothing downstream can tell a card from
  /// the app list.
  private static var isShowingCard = false

  /// Back to the app they came from, from the card.
  ///
  /// A plain open rather than a fresh relay: the cover is already on screen, so
  /// nothing is exposed, and re-entering the relay would roll a different line
  /// under someone who came back to read this one. If the open fails the card
  /// simply stays, which is a fair way to say nothing happened.
  fileprivate static func resumeJourney(_ recognizer: UIGestureRecognizer) {
    guard let pan = recognizer as? UIPanGestureRecognizer, resumeTarget != nil,
          let badge else { return }
    let moved = pan.translation(in: pan.view)

    switch pan.state {
    case .began:
      exitDrag.began(x: 0, y: 0)
      return
    case .changed:
      // The same arrow over the same sixty points as everywhere else. There is
      // nothing to count down here, so the badge is invisible until a finger
      // starts moving and the ring is the only thing it ever draws.
      show(exitDrag.moved(x: moved.x, y: moved.y), on: badge)
      return
    case .ended:
      let promised = exitDrag.promise
      exitDrag.end()
      // Whatever the drag asked for, it is over: the badge goes back to being
      // invisible. Leaving it whole on the way out left a card sitting behind a
      // full ring and a forward arrow describing a gesture nothing would answer.
      badge.quiet()
      guard promised == .skipping else { return }
    default:
      exitDrag.end()
      badge.quiet()
      return
    }

    guard let target = resumeTarget else { return }
    resumeTarget = nil

    // RE-ARMED BEFORE THE OPEN, not in its completion. Resuming goes straight
    // to the target instead of through the relay, so nothing else records that
    // a phrase is owed again -- and the second time the user came back, the
    // cover found nothing pending and fell through to the list.
    //
    // If a line is worth coming back to once it is worth coming back to twice.
    // Bouncing keeps working for as long as the user keeps bouncing, and the
    // two minute window still ends it once they settle into the other app.
    //
    // The ORDER is the part that took an audit to see. `didEnterBackground`
    // reads `pendingReturn.isPending` to decide whether the exit keeps this
    // line or rolls a new one, and the open's completion is asynchronous: on a
    // target that cold-starts slowly the backgrounding won that race, painted a
    // different phrase into the snapshot, and the user watched the line change
    // under them on the way back. Every other handoff records first for the
    // same reason -- see `scheduleOpen`.
    if let phrase = cardPhrase?.text {
      pendingReturn.handedOff(phrase: phrase, target: target,
                              at: Date().timeIntervalSince1970)
    }

    UIApplication.shared.open(target, options: [:]) { ok in
      guard !ok else { return }
      // Nothing happened, so nothing may be left changed. Without putting the
      // target back, the guard at the top of this function rejected every later
      // drag: one refusal and the card's only way out was gone for good, with
      // no alert and no explanation.
      pendingReturn.clear()
      resumeTarget = target
    }
  }

  // MARK: - Pinning the cover on purpose

  /// A ruler and not a clock, and the difference is worth the change. A timed
  /// hold makes the user commit before they know whether they were heard: iOS
  /// delivers nothing to this app for the first ~420ms of a relay, so a press
  /// that never arrived cost them the whole wait before they found out. A drag
  /// answers in the first millimetre, because the ring is following the thumb.
  ///
  /// It also splits the two intentions cleanly. Resting a finger PAUSES, for as
  /// long as you like, and commits to nothing. Dragging KEEPS, or leaves.
  /// Neither is a timeout on the other.
  ///
  /// The distances and the rule that reads them are in `CoverDrag`.

  /// What the finger on the cover is asking for. The rule itself, and every
  /// number in it, lives in `CoverDrag` where it can be tested.
  private static var drag = CoverDrag()

  /// The same reading, for the drag that LEAVES a cover already pinned.
  ///
  /// A second one rather than sharing, because `CoverView.touchesEnded` calls
  /// `forgetHold` on a pinned cover too, and UIKit gives no order between that
  /// callback and a recogniser's `.ended`. One shared reading made the exit work
  /// or not depending on which arrived first.
  private static var exitDrag = CoverDrag(canPin: false)

  /// What was left on the clock when a finger stopped it.
  private static var pausedLeft: TimeInterval = 0

  /// The badge on the live cover.
  ///
  /// Weak on purpose: the view hierarchy owns it, and every path that rebuilds
  /// the cover -- `refill`, `presentCard`, `dismiss` -- takes it down with the
  /// rest of the subviews without having to know it exists.
  private static weak var badge: CoverChrome.Badge?

  /// A finger is on the cover right now. Not the same question as `gate.locked`:
  /// this one is about the badge, which has a state for held that is not the
  /// state for pinned.
  private static var isHolding = false

  /// WHICH finger the origin belongs to. Weak, because UIKit owns the touch and
  /// recycles it once the gesture is over.
  private static weak var holdTouch: UITouch?

  /// The phrase's own clock, started at the moment the cover becomes touchable
  /// rather than at the moment the relay began. Why they are different, and why
  /// this is the honest one: `docs/native-notes.md`, "A countdown that cannot
  /// lie".
  /// `total` is what the countdown was to begin with, which differs from
  /// `seconds` only when a relay is being resumed: the ring then picks the sweep
  /// up part way through instead of starting it over.
  private static func startCountdown(_ seconds: TimeInterval, of total: TimeInterval,
                                     token: Int) {
    // A drain left over from the relay before this one would sweep the badge of
    // a cover it knows nothing about. Same staleness as the tick, same answer.
    guard gate.isCurrent(token), relayInFlight, !gate.locked, !isHolding else { return }
    countdownDeadline = CACurrentMediaTime() + seconds
    countdownTotal = total
    badge?.drain(over: seconds, of: total)
  }

  /// A finger arrived on the cover: freeze the countdown, buzz, and start the
  /// clock that pins the cover when the ring closes.
  ///
  /// The buzz and the badge together are the honest signal that the touch was
  /// SEEN. iOS delivers nothing to this app for the first ~420ms of a widget
  /// tap, so a press that does not buzz is a press that never arrived: lift and
  /// press again.
  ///
  /// No badge means no phrase on the cover -- Phrases switched off, or an empty
  /// list -- and there is nothing to hold a blank rectangle for.
  fileprivate static func fingerLanded(_ touch: UITouch?, at point: CGPoint) {
    guard relayInFlight, !gate.locked, !isHolding, let badge else { return }
    isHolding = true
    holdTouch = touch
    drag.began(x: point.x, y: point.y)

    // STOP THE CLOCK, rather than merely refusing to act on it. The gate holds
    // the handoff back on its own, but the time would carry on being spent
    // underneath, so a finger rested through the whole duration used to leave
    // nothing to go back to. Restamping makes the tick already in flight a
    // no-op; `fingerLeft` schedules a fresh one for what is left.
    pausedLeft = remainingCountdown()
    countdownDeadline = nil
    gate.restamp()

    UIImpactFeedbackGenerator(style: .light).impactOccurred()
    badge.hold()
  }

  /// The finger is dragging. `CoverDrag` says what that means; this puts the
  /// badge where the answer points and buzzes when a ring closes.
  ///
  /// Ignores any finger but the one that anchored the origin. `UIEvent`
  /// delivers touches in an unordered `Set`, so a second finger resting on the
  /// glass would otherwise have its position measured against the FIRST
  /// finger's origin: the distance between two thumbs, read as a drag nobody
  /// made, pinning the cover with no travel at all.
  fileprivate static func fingerMoved(_ touch: UITouch?, to point: CGPoint) {
    guard isHolding, touch === holdTouch, !gate.locked, let badge else { return }
    show(drag.moved(x: point.x, y: point.y), on: badge)
  }

  /// One reading, drawn. Shared by the hold and by the drag that leaves a cover
  /// already pinned, which is the whole point of them being the same gesture.
  private static func show(_ reading: CoverDrag.Reading, on badge: CoverChrome.Badge) {
    if reading.changed { badge.showSkip(reading.gesture == .skipping) }
    badge.pinProgress(reading.closed)
    guard reading.justArmed else { return }
    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
  }

  /// The finger left before the ring closed.
  ///
  /// A `touch` names which one lifted; nil means every finger is off the glass,
  /// or that the caller is tearing the cover down rather than reporting a
  /// gesture. Lifting a finger that was not driving the hold is not this finger
  /// lifting: with two down, letting go of the passenger used to wipe the origin
  /// and unwind the ring under a thumb that had not moved.
  private static func fingerLeft(_ touch: UITouch? = nil, cancelled: Bool = false) {
    if let touch, let holdTouch, touch !== holdTouch { return }
    let wasHolding = isHolding
    // What the finger had promised, if anything. An open ring promises nothing,
    // and NEITHER DOES A TOUCH THE SYSTEM TOOK AWAY. A call arriving, or a
    // system gesture claiming the touch, is not the user deciding: acting on
    // the armed gesture there pinned the cover, or launched the app, on an
    // interruption they had no part in.
    let promised = cancelled ? CoverDrag.Gesture.none : drag.promise
    forgetHold()
    // A pin outlives the finger that made it. Without this, lifting off a cover
    // that has just been pinned would wind the badge back to counting.
    guard wasHolding, !gate.locked else { return }

    switch promised {
    case .pinning:
      // No `releaseHold` first: `engageLock` puts the badge straight into its
      // pinned state, and winding it back to a countdown on the way there is a
      // frame of the cover claiming it is about to leave.
      engageLock()
    case .skipping:
      badge?.releaseHold()
      gate.proceed()
    case .none:
      badge?.releaseHold()
      resumeAfterHold()
    }
  }

  /// The finger came off with nothing asked for, so the relay goes back to
  /// being a relay: the clock picks up where the press stopped it.
  ///
  /// The tick from before the hold is still in flight and is deliberately not
  /// cancelled, only out-stamped. See `RelayGate.restamp`.
  private static func resumeAfterHold() {
    guard relayInFlight, !gate.locked, armedWork != nil else { return }
    let token = gate.restamp()
    guard pausedLeft > 0 else {
      DispatchQueue.main.async { gate.durationElapsed(token) }
      return
    }
    startCountdown(pausedLeft, of: countdownTotal, token: token)
    DispatchQueue.main.asyncAfter(deadline: .now() + pausedLeft) {
      gate.durationElapsed(token)
    }
  }

  /// Everything the hold owns, put back to nothing, with no view involved.
  ///
  /// Separate from `fingerLeft` because A RELAY BOUNDARY IS NOT A FINGER
  /// LIFTING: there may be no finger left to lift. Pin the cover, then swipe
  /// home. `dismiss` refuses to run for the whole length of a relay and a pinned
  /// cover is a relay still in flight, so nothing tears anything down; and the
  /// finger that made the pin can lift without `CoverView` ever hearing it,
  /// because a touch that began during the app-switch animation is delivered to
  /// this app through `sendEvent` alone and never gets a `began` on the view to
  /// be the end of.
  ///
  /// `isHolding` would then stay true for the life of the process, and it is a
  /// guard on both `fingerLanded` and `startCountdown`: no buzz, no pause, no
  /// pin and no countdown, ever again.
  ///
  /// This is `RelayGate.arm` refusing to inherit the previous cover's pin and
  /// finger, which is the same rule and was learned the same way. The gate can
  /// only clear its own state; this clears the half that lives up here.
  private static func forgetHold() {
    isHolding = false
    holdTouch = nil
    drag.end()
  }

  /// The drag went the distance. From here nothing leaves on its own.
  private static func engageLock() {
    guard relayInFlight, !gate.locked, let root = window?.rootViewController?.view else { return }
    gate.lock()
    // Copy and Share read this; on the return card it is set by `presentCard`.
    if let text = relayPhrase {
      cardPhrase = QuoteCatalog.Quote(text: text, author: QuoteCatalog.loadConfig().items.first { $0.text == text }?.author)
    }

    UIImpactFeedbackGenerator(style: .medium).impactOccurred()

    let config = QuoteCatalog.loadConfig()
    let count = relayPhrase.map { QuoteCatalog.loadStats().counts[$0] ?? 0 } ?? 0
    let stack = root.subviews.compactMap { $0 as? UIStackView }.first
    tallyLabel = CoverChrome.addCardChrome(
      to: root, below: stack, config: config, count: count,
      target: Proxy.shared, copy: #selector(Proxy.copyCard),
      share: #selector(Proxy.shareCard), open: #selector(Proxy.dismissCard))

    // The rings have said what they had to say. The pause stays, and it is the
    // only thing left saying the cover is pinned rather than merely slow.
    badge?.pinned()

    // A DRAG AND NOTHING ELSE. There used to be a tap here as well, and it was
    // the one way out of this cover that cost nothing: pinning is a deliberate
    // act, taken to stop the screen moving, and a stray thumb undoing it threw
    // the user into the app they had just refused. It is also the only gesture
    // in the whole cover that acted with no ring behind it. The button at the
    // bottom is still there for anyone who wants a target to aim at.
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

  /// A sideways drag on the pinned cover: go where the widget row was pointing
  /// all along.
  ///
  /// The tap that used to do this as well is gone. See `engageLock`.
  fileprivate static func proceedFromLock(_ recognizer: UIGestureRecognizer) {
    guard gate.locked, let pan = recognizer as? UIPanGestureRecognizer,
          let badge else { return }
    let moved = pan.translation(in: pan.view)

    switch pan.state {
    case .began:
      exitDrag.began(x: 0, y: 0)
      return
    case .changed:
      // The rings were retired when the cover pinned; `pinProgress` brings them
      // back. THE WAY OUT HAS THE SHAPE OF THE WAY IN, which is the only reason
      // anyone would guess it exists: the same arrow, the same ring, the same
      // distance as skipping ahead from a cover that was merely held.
      show(exitDrag.moved(x: moved.x, y: moved.y), on: badge)
      return

    case .ended:
      let promised = exitDrag.promise
      exitDrag.end()
      guard promised == .skipping else {
        // Not far enough. Back to being pinned, exactly as it was.
        badge.pinned()
        return
      }

    default:
      exitDrag.end()
      badge.pinned()
      return
    }

    gate.proceed()
    // `proceed` unlocks, and the touches that drove this drag are still on
    // their way to `touchesEnded`. Without forgetting the hold first, that
    // trailing lift finds the gate unlocked and winds the badge back to a full
    // countdown as the app leaves.
    forgetHold()
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
    // No stack means no phrase -- Phrases off, or an empty list -- and a badge
    // counting down to nothing over a blank rectangle would be furniture.
    if CoverChrome.fill(controller.view, config: config, phrase: phrase) != nil {
      badge = CoverChrome.addBadge(to: controller.view, config: config)
    }
    overlay.backgroundColor = controller.view.backgroundColor
    overlay.rootViewController = controller
    overlay.makeKeyAndVisible()

    if let host = appWindow ?? hostWindow, host !== overlay {
      let copy = UIView(frame: host.bounds)
      copy.autoresizingMask = [.flexibleWidth, .flexibleHeight]
      // The shade exists only to be snapshotted, so its badge is never animated
      // and stays whole. That is the right picture: the snapshot is the stretch
      // before the countdown has started.
      if CoverChrome.fill(copy, config: config, phrase: phrase) != nil {
        CoverChrome.addBadge(to: copy, config: config)
      }
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
      if CoverChrome.fill(root.view, config: config, phrase: phrase) != nil {
        badge = CoverChrome.addBadge(to: root.view, config: config)
      }
      overlay.backgroundColor = root.view.backgroundColor
      root.view.layoutIfNeeded()
    }
    if let shade = shade {
      shade.subviews.forEach { $0.removeFromSuperview() }
      if CoverChrome.fill(shade, config: config, phrase: phrase) != nil {
        CoverChrome.addBadge(to: shade, config: config)
      }
      shade.layoutIfNeeded()
    }
    CATransaction.flush()

    // Same reasoning as the tail of `show`: the render server goes through this
    // frame before the app is suspended, so the next warm relay still opens
    // with no frame wait at all.
    isComposited = true
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
    let work = {
      recordHandoff(target: target)
      open()
    }
    armedWork = work
    // Known from here rather than from where the clock starts, because a finger
    // can land before the clock does and `remainingCountdown` has to be able to
    // say how much is owed even then.
    countdownTotal = seconds
    countdownDeadline = nil
    let token = gate.arm(work)
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
      startCountdown(seconds, of: seconds, token: token)
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
      // The ring starts where the timer starts, which is also where touch
      // delivery starts. That alignment is the feature: a ring that is moving
      // is a cover that can be caught.
      DispatchQueue.main.asyncAfter(deadline: .now() + touchSettleDelay) {
        startCountdown(seconds, of: seconds, token: token)
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
        // the view, having begun while the home screen still owned it. Its DRAG
        // is invisible to the view for the same reason, so the pin has to be
        // driven from here too.
        //
        // Every live touch is offered rather than an arbitrary one picked out
        // of the Set. The guards inside decide: the first one through anchors
        // the origin, and after that only the finger holding it is listened to.
        for touch in touches where touch.phase != .ended && touch.phase != .cancelled {
          let point = touch.location(in: rootViewController?.view)
          QuoteScreen.fingerLanded(touch, at: point)
          QuoteScreen.fingerMoved(touch, to: point)
        }
      } else {
        QuoteScreen.gate.release()
        // Symmetrically, and for the same reason: the finger this route exists
        // to hear is one `CoverView` never gets a `touchesEnded` for either.
        // Nil, because this branch means every finger is off the glass.
        //
        // And it is the ONE route that can see a finger the view cannot, so a
        // cancellation reaching only here would otherwise be read as a decision:
        // a call arriving mid-drag pinned the cover or launched the target.
        let taken = touches.contains { $0.phase == .cancelled }
        QuoteScreen.fingerLeft(cancelled: taken)
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
      for touch in touches { QuoteScreen.fingerLanded(touch, at: touch.location(in: self)) }
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
      // `fingerLanded` ignores repeats, so this both adopts that finger and
      // reports the ordinary drag.
      for touch in touches {
        let point = touch.location(in: self)
        QuoteScreen.fingerLanded(touch, at: point)
        QuoteScreen.fingerMoved(touch, to: point)
      }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
      super.touchesEnded(touches, with: event)
      // Only a lift when it is the LAST lift. `touchesEnded` carries the ended
      // subset, so with two fingers down this fires for the one that let go
      // while the other is still holding the cover back.
      guard !stillDown(besides: touches, in: event) else {
        touches.forEach { QuoteScreen.fingerLeft($0) }
        return
      }
      QuoteScreen.gate.release()
      touches.forEach { QuoteScreen.fingerLeft($0) }
    }

    private func stillDown(besides ended: Set<UITouch>, in event: UIEvent?) -> Bool {
      guard let all = event?.allTouches else { return false }
      return all.contains { !ended.contains($0) && $0.phase != .ended && $0.phase != .cancelled }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
      super.touchesCancelled(touches, with: event)
      guard !stillDown(besides: touches, in: event) else {
        touches.forEach { QuoteScreen.fingerLeft($0, cancelled: true) }
        return
      }
      QuoteScreen.gate.cancelPress()
      touches.forEach { QuoteScreen.fingerLeft($0, cancelled: true) }
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
      // The badge hears this route too. It is the only one that used to speak
      // to the gate and to nothing else, and the countdown made that asymmetry
      // visible: a finger seen only here held the handoff back while the ring
      // carried on emptying, so the cover sat past zero with nothing leaving
      // and nothing on screen admitting why.
      switch recognizer.state {
      case .began, .changed:
        QuoteScreen.gate.press()
        // Nil, because a recogniser hands over no `UITouch` to name. It reads
        // as its own identity: this route can anchor a hold nobody else has,
        // and can then only drive that one, because any hold anchored by a real
        // touch has a non-nil owner that nil will never match.
        let point = recognizer.location(in: recognizer.view)
        QuoteScreen.fingerLanded(nil, at: point)
        QuoteScreen.fingerMoved(nil, to: point)
      case .ended:
        QuoteScreen.gate.release()
        QuoteScreen.fingerLeft()
      case .cancelled, .failed:
        // Taken away rather than lifted, so it decides nothing.
        QuoteScreen.gate.release()
        QuoteScreen.fingerLeft(cancelled: true)
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

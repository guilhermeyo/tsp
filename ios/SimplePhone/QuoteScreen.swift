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
  private static var rolledThisLaunch = false

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
  }

  /// Strips the recognisers a pinned cover or a return card left behind.
  ///
  /// The window outlives any one relay: it is only torn down when the user
  /// comes back with nothing pending. So without this, every lock and every
  /// card stacked another recogniser on the same view, and a pan among them
  /// would CANCEL the touches the view was using to detect a hold. A thumb's
  /// natural drift was enough to start the pan, which read as the finger
  /// leaving: the ring vanished and the target opened. Holding got worse the
  /// more the feature was used, which is the shape of a leak rather than a bug
  /// in the hold itself.
  ///
  /// `cancelsTouchesInView = false` on each recogniser is the other half. Both
  /// are here because either one alone would have hidden the other.
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
    let config = loadConfig()

    if forSnapshot {
      // A BACKGROUNDING THAT ENDS A RELAY DOES NOT ROLL.
      //
      // Rolling here is normally right: it is the one moment nobody is looking,
      // so it is where a new line can appear without swapping under anyone. But
      // when the app is leaving BECAUSE it handed off, the next foreground is
      // most likely the user coming back for the line they missed, and rolling
      // costs twice.
      //
      // It flashes: the snapshot iOS replays carries the new line, and the card
      // then repaints with the old one, so the user watches a phrase they never
      // asked for turn into the one they did.
      //
      // And it lies: rolling is what counts a line as shown. A phrase that only
      // ever existed as a picture during someone's return would collect a tally
      // for a reading that never happened.
      //
      // The line still changes. This only defers the roll until a backgrounding
      // that is not part of a relay the user may still come back to.
      let next = pendingReturn.isPending ? keptQuote(config) : roll(config)
      if window == nil {
        show(config, phrase: next, in: appWindow ?? hostWindow, forSnapshot: true)
      } else {
        refill(config, phrase: next)
      }
    } else if window == nil {
      // Reachable only on a COLD relay: a warm one always finds the cover the
      // last backgrounding left standing. See `restoreOrRoll`.
      let drawn = restoreOrRoll(config)
      relayPhrase = drawn?.text
      show(config, phrase: drawn, in: appWindow ?? hostWindow, forSnapshot: false)
    } else {
      // The cover being KEPT is the one the last backgrounding painted, and
      // `roll` recorded that line as `current` when it painted it. Reading it
      // HERE and not in `beginRelay` is the difference between the card showing
      // the phrase the user saw and showing the one before it: on a cold relay
      // the branch above draws a fresh line, and a capture taken before this
      // call would already be stale.
      relayPhrase = loadStats().current
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

    let config = loadConfig()
    let author = config.items.first { $0.text == text }?.author
    let count = loadStats().counts[text] ?? 0

    root.subviews.forEach { $0.removeFromSuperview() }
    let phrase = Quote(text: text, author: author)
    cardPhrase = phrase
    let stack = fill(root, config: config, phrase: phrase)
    addCardChrome(to: root, below: stack, config: config, count: count)
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

  /// Far enough sideways, EITHER WAY, to count as "take me there" rather than
  /// as a finger settling.
  ///
  /// Direction is deliberately not checked, and that came from watching eight
  /// real attempts: every one of them went LEFT, by 143 to 341 points, while
  /// the code was demanding right. Asking for a specific direction only tests
  /// whether the user guessed the same convention as the author. Going onward
  /// to the app reads as advancing, which is leftward like turning a page,
  /// while rightward is what iOS itself uses for going back. Both are defensible
  /// and neither is worth losing a gesture over.
  ///
  /// Read on `.ended` rather than while moving: a threshold crossed mid-drag
  /// would fire under a thumb that was still deciding. Diagonal is fine, since
  /// real drags are never straight; it just has to be more sideways than not.
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

  private static var ring: CALayer?
  private static var lockWork: DispatchWorkItem?

  /// A finger arrived on the cover, at `point`.
  ///
  /// Also the honest signal that the touch was SEEN. iOS delivers nothing to
  /// this app for the first ~420ms of a relay, so a press that draws no ring is
  /// a press that never reached us: lift, press again, and the ring appears.
  /// That is worth more than any hint text, because it is the truth rather than
  /// a description of it.
  private static func fingerArrived(at point: CGPoint) {
    guard relayInFlight, !gate.locked, ring == nil,
          let root = window?.rootViewController?.view,
          !(root.subviews.compactMap { $0 as? UIStackView }.isEmpty)
    else { return }

    let config = loadConfig()
    let colour: UIColor = config.isDark ? .white : .black
    let radius: CGFloat = 32

    // One container for the whole dial, so retiring it later is a single
    // animation on a single layer rather than three that have to agree.
    let dial = CALayer()
    let side = (radius + 6) * 2
    dial.frame = CGRect(x: point.x - side / 2, y: point.y - side / 2, width: side, height: side)
    root.layer.addSublayer(dial)

    let centre = CGPoint(x: side / 2, y: side / 2)
    let circle = UIBezierPath(arcCenter: centre, radius: radius,
                              startAngle: -.pi / 2, endAngle: 1.5 * .pi, clockwise: true).cgPath

    let track = CAShapeLayer()
    track.frame = dial.bounds
    track.path = circle
    track.fillColor = UIColor.clear.cgColor
    track.strokeColor = colour.withAlphaComponent(0.12).cgColor
    track.lineWidth = 3
    dial.addSublayer(track)

    // The padlock sits INSIDE the dial while it fills, so the ring reads as a
    // countdown to locking rather than as a countdown to something unnamed.
    // It is the same glyph that ends up at the top, which is what makes the
    // two moments feel like one gesture.
    let glyphConfig = UIImage.SymbolConfiguration(pointSize: 15, weight: .regular)
    if let glyph = UIImage(systemName: "lock.fill", withConfiguration: glyphConfig)?
        .withTintColor(colour.withAlphaComponent(0.45), renderingMode: .alwaysOriginal) {
      let mark = CALayer()
      mark.contents = glyph.cgImage
      mark.contentsScale = UIScreen.main.scale
      mark.bounds = CGRect(origin: .zero, size: glyph.size)
      mark.position = centre
      dial.addSublayer(mark)
    }

    let progress = CAShapeLayer()
    progress.frame = dial.bounds
    progress.path = circle
    progress.fillColor = UIColor.clear.cgColor
    progress.strokeColor = colour.withAlphaComponent(0.55).cgColor
    progress.lineWidth = 3
    progress.lineCap = .round
    progress.strokeEnd = 0
    dial.addSublayer(progress)

    let fill = CABasicAnimation(keyPath: "strokeEnd")
    fill.fromValue = 0
    fill.toValue = 1
    fill.duration = lockDuration
    fill.fillMode = .forwards
    fill.isRemovedOnCompletion = false
    progress.add(fill, forKey: "fill")
    ring = dial

    // The animation is the picture; this is the fact. Kept separate so a
    // dropped frame cannot decide whether the cover is pinned.
    let work = DispatchWorkItem { engageLock() }
    lockWork = work
    DispatchQueue.main.asyncAfter(deadline: .now() + lockDuration, execute: work)
  }

  /// The finger left before the ring closed.
  private static func fingerLeft() {
    lockWork?.cancel()
    lockWork = nil
    ring?.removeFromSuperlayer()
    ring = nil
  }

  /// The ring closed. From here nothing leaves on its own.
  private static func engageLock() {
    guard relayInFlight, !gate.locked, let root = window?.rootViewController?.view else { return }
    gate.lock()
    // Copy and Share read this; on the return card it is set by `presentCard`.
    if let text = relayPhrase {
      cardPhrase = Quote(text: text, author: loadConfig().items.first { $0.text == text }?.author)
    }
    lockWork = nil

    UIImpactFeedbackGenerator(style: .medium).impactOccurred()

    let config = loadConfig()
    let count = relayPhrase.map { loadStats().counts[$0] ?? 0 } ?? 0
    let stack = root.subviews.compactMap { $0 as? UIStackView }.first
    addCardChrome(to: root, below: stack, config: config, count: count)
    addPadlock(to: root, config: config)

    // The ring has said what it had to say. It shrinks away where it stood
    // while the padlock fades in at the top, so the eye follows one thing
    // becoming another rather than two unrelated changes.
    if let ring {
      let shrink = CABasicAnimation(keyPath: "transform.scale")
      shrink.toValue = 0.4
      let fade = CABasicAnimation(keyPath: "opacity")
      fade.toValue = 0
      let group = CAAnimationGroup()
      group.animations = [shrink, fade]
      group.duration = 0.28
      group.fillMode = .forwards
      group.isRemovedOnCompletion = false
      ring.add(group, forKey: "retire")
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
        ring.removeFromSuperlayer()
      }
      self.ring = nil
    }

    let tap = UITapGestureRecognizer(target: Proxy.shared, action: #selector(Proxy.proceedFromLock))
    tap.cancelsTouchesInView = false
    root.addGestureRecognizer(tap)
    let drag = UIPanGestureRecognizer(target: Proxy.shared,
                                      action: #selector(Proxy.proceedFromLock(_:)))
    drag.cancelsTouchesInView = false
    root.addGestureRecognizer(drag)
  }

  /// The padlock, opposite the copy and share controls, saying the cover is
  /// pinned rather than merely slow.
  private static func addPadlock(to container: UIView, config: Config) {
    let colour: UIColor = config.isDark ? .white : .black
    let symbol = UIImage.SymbolConfiguration(pointSize: 14, weight: .regular)
    // COLOURED INTO THE IMAGE, not left to `tintColor`.
    //
    // A UIImageView only honours `tintColor` for a template image, and
    // `UIImage(systemName:)` hands back `.automatic`, which a plain image view
    // renders as the symbol's own colour: black. A black padlock on a black
    // cover is a padlock nobody can see, and the lock looked broken when the
    // only thing missing was its colour. UIButton resolves this on its own,
    // which is why Copy and Share showed up and this did not.
    let glyph = UIImage(systemName: "lock.fill", withConfiguration: symbol)?
      .withTintColor(colour.withAlphaComponent(0.4), renderingMode: .alwaysOriginal)
    let lock = UIImageView(image: glyph)
    lock.alpha = 0
    lock.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(lock)
    NSLayoutConstraint.activate([
      lock.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 30),
      lock.topAnchor.constraint(equalTo: container.safeAreaLayoutGuide.topAnchor, constant: 22),
    ])
    UIView.animate(withDuration: 0.28) { lock.alpha = 1 }
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

  /// The line as a picture, without any of the card's furniture.
  ///
  /// What the card needs on screen and what belongs in something you post are
  /// different things. A count of how many times a phrase has come up is a fact
  /// about YOUR phone, and a button labelled "Open The Simple Phone" is a
  /// control, not content. Both are dropped here, and what replaces them is a
  /// small wordmark, so the image says where it came from without asking
  /// anything of whoever sees it.
  ///
  /// Rendered from a view that was never on screen, through `layer.render`
  /// rather than `drawHierarchy`, because the latter needs the view to be in a
  /// window and this one deliberately is not.
  private static func cardImage(config: Config, phrase: Quote) -> UIImage? {
    let size = window?.bounds.size ?? UIScreen.main.bounds.size
    guard size.width > 0, size.height > 0 else { return nil }

    let canvas = UIView(frame: CGRect(origin: .zero, size: size))
    fill(canvas, config: config, phrase: phrase)

    let mark = UILabel()
    mark.text = "The Simple Phone"
    // Fainter than the attribution on the card, which is already secondary.
    // A signature, not a caption.
    mark.textColor = (config.isDark ? UIColor.white : .black).withAlphaComponent(0.3)
    mark.font = font(for: config, size: 13)
    mark.textAlignment = .center
    mark.translatesAutoresizingMaskIntoConstraints = false
    canvas.addSubview(mark)
    NSLayoutConstraint.activate([
      mark.centerXAnchor.constraint(equalTo: canvas.centerXAnchor),
      mark.bottomAnchor.constraint(equalTo: canvas.bottomAnchor, constant: -56),
    ])

    canvas.setNeedsLayout()
    canvas.layoutIfNeeded()

    let renderer = UIGraphicsImageRenderer(bounds: canvas.bounds)
    return renderer.image { context in canvas.layer.render(in: context.cgContext) }
  }

  /// The phrase as text, the way a person would write it down.
  private static func cardText(_ phrase: Quote) -> String {
    guard let author = phrase.author, !author.isEmpty else { return phrase.text }
    return "\(phrase.text)\n\u{2014}\u{2009}\(author)"
  }

  fileprivate static func copyCard() {
    guard let phrase = cardPhrase else { return }
    UIPasteboard.general.string = cardText(phrase)
    flashConfirmation()
  }

  fileprivate static func shareCard() {
    guard let phrase = cardPhrase, let presenter = window?.rootViewController else { return }
    var items: [Any] = [cardText(phrase)]
    if let image = cardImage(config: loadConfig(), phrase: phrase) {
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
    label.text = relayStrings(language: loadConfig().language)["copied"] ?? "Copied"
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
      guard tallyLabel === label else { return }
      label.text = previous
    }
  }

  /// The line the card is showing, so copy and share do not have to find it
  /// again, and the count label, so the copy confirmation has somewhere to go.
  private static var cardPhrase: Quote?
  private static weak var tallyLabel: UILabel?

  /// A glyph you can find but not trip over: dimmed to the same weight as the
  /// attribution, with a touch target far larger than the icon it draws.
  private static func chromeButton(symbol: String, label: String,
                                   action: Selector, tint: UIColor) -> UIButton {
    let button = UIButton(type: .system)
    let config = UIImage.SymbolConfiguration(pointSize: 15, weight: .regular)
    button.setImage(UIImage(systemName: symbol, withConfiguration: config), for: .normal)
    button.tintColor = tint.withAlphaComponent(0.45)
    button.accessibilityLabel = label
    button.addTarget(Proxy.shared, action: action, for: .touchUpInside)
    button.translatesAutoresizingMaskIntoConstraints = false
    button.widthAnchor.constraint(equalToConstant: 44).isActive = true
    button.heightAnchor.constraint(equalToConstant: 44).isActive = true
    return button
  }

  /// The count and the way back, under the line.
  private static func addCardChrome(to container: UIView, below stack: UIStackView?,
                                    config: Config, count: Int) {
    let foreground: UIColor = config.isDark ? .white : .black
    let strings = relayStrings(language: config.language)

    let tally = UILabel()
    tally.text = count == 1
      ? (strings["shownOnce"] ?? "shown once")
      : String(format: strings["shownTimes"] ?? "shown %@ times", "\(count)")
    // Dimmer than the attribution, which is already secondary. This is a
    // footnote about a phrase, not part of it.
    tally.textColor = foreground.withAlphaComponent(0.35)
    tally.font = font(for: config, size: 13)
    tally.textAlignment = .center
    tally.translatesAutoresizingMaskIntoConstraints = false
    tallyLabel = tally

    let back = UIButton(type: .system)
    back.setTitle(strings["openApp"] ?? "Open The Simple Phone", for: .normal)
    back.setTitleColor(foreground.withAlphaComponent(0.5), for: .normal)
    back.titleLabel?.font = font(for: config, size: 15)
    back.addTarget(Proxy.shared, action: #selector(Proxy.dismissCard), for: .touchUpInside)
    back.translatesAutoresizingMaskIntoConstraints = false

    let copy = chromeButton(symbol: "doc.on.doc", label: strings["copy"] ?? "Copy",
                            action: #selector(Proxy.copyCard), tint: foreground)
    let share = chromeButton(symbol: "square.and.arrow.up", label: strings["share"] ?? "Share",
                             action: #selector(Proxy.shareCard), tint: foreground)

    container.addSubview(tally)
    container.addSubview(back)
    container.addSubview(copy)
    container.addSubview(share)
    NSLayoutConstraint.activate([
      share.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
      share.topAnchor.constraint(equalTo: container.safeAreaLayoutGuide.topAnchor, constant: 8),
      copy.trailingAnchor.constraint(equalTo: share.leadingAnchor, constant: -4),
      copy.centerYAnchor.constraint(equalTo: share.centerYAnchor),
    ])
    NSLayoutConstraint.activate([
      tally.centerXAnchor.constraint(equalTo: container.centerXAnchor),
      // Under the LINE, not under the middle of the screen. A four line phrase
      // reaches well past centre, and anchoring to the centre printed the count
      // straight through the attribution.
      tally.topAnchor.constraint(equalTo: stack?.bottomAnchor ?? container.centerYAnchor,
                                 constant: 28),
      back.centerXAnchor.constraint(equalTo: container.centerXAnchor),
      back.bottomAnchor.constraint(equalTo: container.safeAreaLayoutGuide.bottomAnchor, constant: -28),
    ])
  }

  /// Where the failure alert should be presented from. The cover is normally
  /// gone by then (`dismissForFailure`), so this is the app's own root; the
  /// cover's own controller is the fallback for the cold path, where React
  /// Native's root view may not be in a hierarchy yet.
  static func failurePresenter() -> UIViewController? {
    hostWindow?.rootViewController ?? window?.rootViewController
  }

  // MARK: - Presentation

  private static func show(_ config: Config, phrase: Quote?, in appWindow: UIWindow?, forSnapshot: Bool) {
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
  private static func refill(_ config: Config, phrase: Quote?) {
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
  @discardableResult
  private static func fill(_ container: UIView, config: Config, phrase: Quote?) -> UIStackView? {
    let background: UIColor = config.isDark ? .black : .white
    container.backgroundColor = background
    container.isOpaque = true
    guard let phrase, !phrase.text.isEmpty else { return nil }

    let foreground: UIColor = config.isDark ? .white : .black

    let label = UILabel()
    label.text = phrase.text
    label.textColor = foreground
    label.font = font(for: config)
    label.numberOfLines = 0
    label.textAlignment = .center
    label.adjustsFontSizeToFitWidth = true
    label.minimumScaleFactor = 0.6

    // A STACK, not a second free-floating label, so the pair stays optically
    // centred: with no author the line sits exactly where it always did, and
    // with one the two centre together rather than the phrase shifting up by
    // however tall the credit happens to be.
    let stack = UIStackView(arrangedSubviews: [label])
    stack.axis = .vertical
    stack.alignment = .fill
    stack.spacing = 10
    stack.translatesAutoresizingMaskIntoConstraints = false

    if let author = phrase.author, !author.isEmpty {
      let credit = UILabel()
      // An en dash and a thin space, which is how a printed attribution is set.
      credit.text = "\u{2013}\u{2009}\(author)"
      // Dimmed as well as smaller. At 55 percent it reads as secondary at a
      // glance, which matters when the whole thing is on screen for under a
      // second and the phrase is what should be read first.
      credit.textColor = foreground.withAlphaComponent(0.55)
      credit.font = font(for: config, size: 15)
      credit.numberOfLines = 1
      credit.textAlignment = .center
      credit.adjustsFontSizeToFitWidth = true
      credit.minimumScaleFactor = 0.6
      stack.addArrangedSubview(credit)
    }

    container.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.centerYAnchor.constraint(equalTo: container.centerYAnchor),
      stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 32),
      stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -32),
    ])
    return stack
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
  /// delivered to it.
  ///
  /// MEASURED, not guessed. A trace of eleven real widget taps on an iPhone 17
  /// Pro: the relay starts at 0, `didBecomeActive` lands at 0.21 to 0.23, and
  /// the earliest touch the app ever saw was 0.42. Never once earlier, and not
  /// on the host window either, which listens precisely to catch that case.
  /// For that first stretch the finger belongs to the home screen and iOS does
  /// not hand it over.
  ///
  /// Without this the duration was being spent on a picture: the phrase is
  /// visible from 0 because the system is replaying the snapshot, so a "1.5
  /// second" cover offered 1.36 seconds you could touch and 0.4 you could only
  /// look at. Adding it back is what makes the number in the Phrases screen
  /// mean what it says.
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
      if let point = touches.first?.location(in: self) { QuoteScreen.fingerArrived(at: point) }
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
      // The finger that landed during the animation has no `began` here, so
      // this is where its ring starts. `fingerArrived` ignores repeats.
      if let point = touches.first?.location(in: self) { QuoteScreen.fingerArrived(at: point) }
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
  private static func roll(_ config: Config) -> Quote? {
    rolledThisLaunch = true
    guard config.enabled else { return nil }

    var stats = loadStats()
    guard let next = pick(from: config.items, counts: stats.counts, excluding: stats.current) else {
      return nil
    }
    stats.counts[next.text, default: 0] += 1
    stats.current = next.text
    saveStats(stats, items: config.items)
    return next
  }

  /// The line already on the cover, neither re-drawn nor counted.
  ///
  /// Falls back to the stored `current` because `relayPhrase` lives only as
  /// long as the process: a relay that began before a restart has none, and
  /// repainting the cover blank would be worse than repainting it the same.
  private static func keptQuote(_ config: Config) -> Quote? {
    guard let text = relayPhrase ?? loadStats().current else { return nil }
    return config.items.first { $0.text == text }
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
  private static func restoreOrRoll(_ config: Config) -> Quote? {
    guard config.enabled else { return nil }
    // Matched on TEXT, so re-attributing a line does not lose the snapshot it
    // is already carrying; the restored Quote is the CURRENT one, so an author
    // edited since the snapshot was taken shows up on the first live frame.
    if !rolledThisLaunch,
       let current = loadStats().current,
       let restored = config.items.first(where: { $0.text == current }) {
      rolledThisLaunch = true
      return restored
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
  private static func pick(from items: [Quote], counts: [String: Int], excluding current: String?) -> Quote? {
    guard items.count > 1 else { return items.first }

    // The fallback covers a config that somehow holds nothing but duplicates of
    // the current line; the contract is the cover, so this may not return nil
    // for a list that has items in it.
    let pool = items.filter { $0.text != current }
    let candidates = pool.isEmpty ? items : pool

    // Sorting 101 strings, on the backgrounding path, with no frame deadline
    // and nobody watching. The deterministic tie-break keeps the ranking stable
    // between draws; the randomness comes from the pick within the tier.
    let ranked = candidates.sorted { lhs, rhs in
      let left = counts[lhs.text] ?? 0
      let right = counts[rhs.text] ?? 0
      return left == right ? lhs.text < rhs.text : left < right
    }
    guard let first = ranked.first else { return nil }

    let lowest = counts[first.text] ?? 0
    let floor = min(ranked.count, max(5, items.count / 8))
    var tier = ranked.prefix { (counts[$0.text] ?? 0) == lowest }
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
  /// line's history, and the Phrases screen DOES edit: `updateQuote` renames a
  /// line in place, which orphans its count and the `current` restore key. The
  /// orphan is pruned on the next write and the restore falls through to a
  /// fresh roll, so the cost is one forgotten counter, not a broken screen.
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

  private static func saveStats(_ stats: Stats, items: [Quote]) {
    var counts = stats.counts
    // Keys for lines no longer in rotation are KEPT on purpose. It is what
    // makes a language round trip non-destructive (the four catalogs are
    // disjoint, so pruning would zero the others permanently), and a count is
    // only ever looked up for an item that is in the list right now, so a stale
    // key cannot reach the draw. The bound exists only so that pasting in a very
    // large list cannot grow a blob that is rewritten on every backgrounding.
    //
    // It has to clear the sum of every bundled catalog for the guarantee above
    // to hold: four languages at 101 lines each is 404 keys that all have to fit
    // alongside whatever the user wrote themselves.
    if counts.count > 1200 {
      let live = Set(items.map(\.text))
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
  private static func font(for config: Config, size: CGFloat = 30) -> UIFont {
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

  /// One line and, optionally, who said it.
  ///
  /// Decoded from BOTH wire shapes: a bare string when there is no author, an
  /// object when there is. `text` alone is the identity everywhere else --
  /// stats keys, the "not the one just shown" exclusion, the restore lookup --
  /// so attribution can be edited without orphaning a counter.
  struct Quote: Equatable {
    let text: String
    let author: String?
  }

  struct Config {
    let enabled: Bool
    let items: [Quote]
    let isDark: Bool
    let font: String
    /// The interface language the user settled on, as a stored BCP-47 tag, or
    /// nil when nothing has ever been written. Carried here so the relay's
    /// failure alert can be worded in it -- it is the only string this process
    /// writes that the user reads.
    let language: String?
    /// Resolved by the app from its named durations, so this side never carries
    /// the label table. Clamped on read: a corrupt payload must not be able to
    /// freeze the launcher on a phrase.
    let holdSeconds: TimeInterval
  }

  /// The stored language, for the one caller outside this file: AppDelegate's
  /// failure alert. Re-reads the config rather than caching it, which is free on
  /// a path that has already given up on opening anything.
  static func configuredLanguage() -> String? {
    loadConfig().language
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

    // Top-level `language` is authoritative. `quotes.language` is read only as
    // a fallback, for a config written by a build that still mirrored it there.
    let language = (root?["language"] as? String) ?? (quotes?["language"] as? String)
    let stored = ((quotes?["items"] as? [Any]) ?? []).compactMap(Self.decodeQuote)

    return Config(
      enabled: quotes?["enabled"] as? Bool ?? true,
      // An empty or absent list is "never seeded", not "the user deleted every
      // line". Deleting the last phrase is what the `enabled` switch is for.
      items: stored.isEmpty ? bundledItems(language: language) : stored,
      isDark: theme?["isDark"] as? Bool ?? true,
      font: theme?["font"] as? String ?? "monospaced",
      language: language,
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

  /// A bare string is an unattributed line; an object carries `text` and an
  /// optional `author`. An author that trims to nothing becomes nil, so the
  /// renderer never has to distinguish absent from empty.
  private static func decodeQuote(_ raw: Any) -> Quote? {
    if let text = raw as? String {
      let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
      return trimmed.isEmpty ? nil : Quote(text: trimmed, author: nil)
    }
    guard let object = raw as? [String: Any],
          let text = object["text"] as? String
    else { return nil }
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty { return nil }
    let author = (object["author"] as? String)?
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return Quote(text: trimmed, author: (author?.isEmpty ?? true) ? nil : author)
  }

  private static func bundledItems(language: String?) -> [Quote] {
    if let language, let items = catalogPhrases(matching: language) {
      return items
    }

    // THE SYSTEM STEP, and it is not a second resolver competing with the app's.
    // It is reachable ONLY while the shared container holds no phrase list at
    // all -- a fresh install whose first ever action was a widget tap, before
    // JavaScript has run once. The moment the app writes a config, the stored
    // `language` above wins unconditionally and this line is dead. Without it a
    // brand-new install would show its very first cover in whatever
    // `defaultLanguage` happens to say, regardless of the phone.
    if let system = Locale.preferredLanguages.first, let items = catalogPhrases(matching: system) {
      return items
    }

    // The default language lives in the catalog rather than being re-decided
    // here, so Swift cannot drift from the TypeScript side.
    let fallback = bundledCatalog["defaultLanguage"] as? String ?? "en"
    return ((bundledCatalog[fallback] as? [Any]) ?? []).compactMap(decodeQuote)
  }

  /// A BCP-47 tag to one of the catalog's phrase arrays: exact key first, then
  /// the two-letter primary subtag, mirroring `matchLanguage` on the TypeScript
  /// side. Underscores are normalised because `Locale` spells regions with one
  /// ("pt_BR") while the catalog keys use hyphens.
  ///
  /// The `as? [Any]` cast is also the guard against the catalog's non-phrase
  /// keys: `relay` is a dictionary and `defaultLanguage` is a string, so neither
  /// can ever be returned as a phrase list even when a tag prefix-matches their
  /// name. Keys are sorted so a tie between two candidates is at least stable.
  private static func catalogPhrases(matching tag: String) -> [Quote]? {
    let normalized = tag.replacingOccurrences(of: "_", with: "-").lowercased()
    guard !normalized.isEmpty else { return nil }
    let prefix = String(normalized.prefix(2))
    let keys = bundledCatalog.keys.sorted()
    let key = keys.first { $0.lowercased() == normalized }
      ?? keys.first { $0.lowercased().hasPrefix(prefix) }
    guard let key, let raw = bundledCatalog[key] as? [Any] else { return nil }
    let items = raw.compactMap(decodeQuote)
    return items.isEmpty ? nil : items
  }

  /// The relay's failure alert, in the user's language, from the same
  /// `quotes.json` the app imports. `AppDelegate` is the only caller.
  ///
  /// This is technically a SECOND matcher, and it is safe only because it
  /// matches the STORED tag and never the system locale: `config.language` is
  /// always one of the four exact keys in the relay table, so it cannot disagree
  /// with the JavaScript resolver about which language the user is in. If a
  /// future build ever stores a tag the table lacks, the worst case is English.
  ///
  /// The English table is the base and the matched one is merged over it, so a
  /// half-finished translation renders its finished keys and English for the
  /// rest rather than nothing at all.
  static func relayStrings(language: String?) -> [String: String] {
    let table = bundledCatalog["relay"] as? [String: Any] ?? [:]
    let english = table["en"] as? [String: String] ?? [:]
    guard let language else { return english }

    let normalized = language.replacingOccurrences(of: "_", with: "-").lowercased()
    guard !normalized.isEmpty else { return english }
    let prefix = String(normalized.prefix(2))
    let keys = table.keys.sorted()
    let key = keys.first { $0.lowercased() == normalized }
      ?? keys.first { $0.lowercased().hasPrefix(prefix) }
    guard let key, let localized = table[key] as? [String: String] else { return english }
    return english.merging(localized) { _, new in new }
  }
}

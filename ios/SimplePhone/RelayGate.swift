import Foundation

/// Decides WHEN the relay is allowed to hand off to the target app.
///
/// One rule: the target opens once the chosen duration has run out AND nothing
/// is holding the cover. A finger on the screen holds it.
///
/// NO UIKit AND NO TIMER, on purpose, and both are load-bearing.
///
/// No UIKit is what lets `scripts/test-relay-gate` compile this exact file and
/// drive every case by hand. The app target has no XCTest bundle, so that
/// script is the only executable test the native half of this repo has, and it
/// only stays possible while this file imports nothing but Foundation.
///
/// No timer is what makes those cases deterministic. Time enters through
/// `durationElapsed(_:)`, which the caller schedules however it likes; the gate
/// itself has no idea how long anything took.
///
/// THE ORDER OF EVENTS IS NOT GUARANTEED, which is the whole reason this is a
/// state machine rather than a cancelled `DispatchWorkItem`. At the "instant"
/// duration there is no timer to cancel at all, and a finger that landed during
/// the app-switch animation has already pressed before the relay is even armed.
/// Asking "is anything holding this?" at fire time answers both for free.
///
/// It also means a release can arrive before the duration ever runs out. That
/// hands off immediately: the finger REPLACES the wait rather than queueing
/// behind it, because a person who read the line and lifted their thumb is done
/// reading, whatever number is set in the Phrases screen.
final class RelayGate {
  /// Set while a touch is down on the cover. Multiple downs collapse into one:
  /// the first release hands off, which is what a person means by letting go.
  private var isHeld = false

  /// True once the chosen duration has run out, or once a finger has landed.
  ///
  /// A press implies it. Holding the cover to read is a statement that the wait
  /// is over and the handoff is now the thumb's business, so a release must not
  /// then sit out the remainder of a four second setting.
  private var isDue = false

  /// What to run to leave. Cleared the moment it runs, which is what makes
  /// every "does it open twice" case below a no-op rather than a guard.
  private var open: (() -> Void)?

  /// Which relay is on screen right now.
  ///
  /// The gate is a singleton and its caller schedules a timer it never cancels,
  /// so a tick can outlive the relay that asked for it. That is harmless while
  /// nothing else is owed, and NOT harmless the moment a second relay has armed:
  /// without an identity, relay one's stale tick satisfies relay two and cuts
  /// its cover short, which is precisely the wait this feature exists to
  /// protect. A counter is enough, and it keeps the timer out here where the
  /// tests can stay honest about time.
  private var cycle = 0

  /// The cover is on screen and this relay owes the user a handoff.
  ///
  /// Returns the token its tick must carry back. `@discardableResult` for the
  /// caller that has no timer to schedule, on the instant path.
  ///
  /// `isDue` starts at whatever the finger is doing rather than at false. A
  /// press can land BEFORE this: the cover is already up from the last
  /// backgrounding, so the touch belongs to the relay being armed even though
  /// it arrived first. Clearing the flag here threw that press away and left
  /// the user's release handing off nothing.
  @discardableResult
  func arm(_ work: @escaping () -> Void) -> Int {
    cycle &+= 1
    open = work
    // A NEW COVER CANNOT INHERIT THE OLD ONE'S PIN, NOR ITS FINGER.
    //
    // Nothing else clears it on the one path that matters: a pinned cover the
    // user walks away from. Swiping home ends the relay through `endRelay`,
    // which only drops `relayInFlight`, and `dismiss` refuses to run while a
    // relay is in flight, so `reset` is never reached. The pin then outlives
    // its cover, and the next relay arms behind a lock with no ring, no
    // controls and no gestures left on screen: a full-screen phrase with no way
    // out and no way through.
    //
    // The finger has to go with it, and the lock is what tells the two cases
    // apart. `isHeld` is normally PRESERVED across arming, because a press can
    // legitimately land before the relay is armed and throwing it away costs
    // the user their hold. But a press that was still down when the cover was
    // pinned belongs to that cover, not to this one: nobody holds a phone
    // through someone else's launch.
    //
    // Here rather than in the caller because arming IS the start of a cover,
    // and a rule this expensive to get wrong should not depend on every future
    // caller remembering it.
    if isLocked {
      isLocked = false
      isHeld = false
    }
    isDue = isHeld
    return cycle
  }

  /// The chosen duration ran out, for the relay identified by `token`.
  ///
  /// A tick from an older cycle is dropped on the floor. Harmless after the
  /// fact in the other direction too: a tick for the CURRENT cycle that lands
  /// once the target has already been asked to open finds nothing to run.
  func durationElapsed(_ token: Int) {
    guard token == cycle else { return }
    isDue = true
    fire()
  }

  /// Set once a finger has held long enough to pin the cover deliberately.
  ///
  /// After this NOTHING leaves on its own. Not the duration, not lifting the
  /// finger, not a tick left over from before. The user asked for the line to
  /// stay, and the only thing that may take it away is the user asking again.
  ///
  /// It is the most dangerous state in this file for exactly that reason: a
  /// lock with no way out is a launcher that never launches. `proceed` and
  /// `reset` are the two ways out and both are covered by cases in
  /// `scripts/relay-gate-tests.swift`.
  private var isLocked = false

  var locked: Bool { isLocked }

  /// A finger landed on the cover.
  func press() {
    isHeld = true
    isDue = true
  }

  /// The finger held long enough to mean it.
  func lock() {
    isLocked = true
  }

  /// The user asked to go, from a locked cover: a tap, or a drag to the right.
  /// The only thing that hands off once locked.
  func proceed() {
    isLocked = false
    isHeld = false
    isDue = true
    fire()
  }

  /// The finger lifted.
  ///
  /// Inert while locked, and NOT by a guard of its own: `fire` is the single
  /// place the lock is enforced. A second guard here read as defence in depth
  /// and was the opposite, because the two masked each other. Removing either
  /// one left every case green, which is a test suite describing a rule that
  /// nothing actually implements.
  ///
  /// Letting go of a cover you just pinned means you are done pressing, not
  /// that you are done reading.
  func release() {
    isHeld = false
    fire()
  }

  /// The touch was cancelled by the system rather than lifted: a call arrived,
  /// or the user swiped away mid-press.
  ///
  /// Identical to a release, deliberately. A launcher that launches nothing is
  /// a worse failure than one that shows its list, so there is no path where a
  /// touch the user cannot end leaves the handoff owed forever.
  func cancelPress() {
    release()
  }

  /// The cover came down for good, so anything still owed is stale. Called from
  /// `QuoteScreen.dismiss()`, which runs when the user is back in the app and
  /// the target they picked is no longer wanted.
  ///
  /// Lifting `isHeld` is the part that matters most. If a cover came down with
  /// a finger still on it and no cancellation ever arrived, every relay after
  /// this one would be held back by a thumb that is not there: a launcher that
  /// never launches, which is worse than any wrong phrase.
  func reset() {
    cycle &+= 1
    isHeld = false
    isDue = false
    isLocked = false
    open = nil
  }

  private func fire() {
    guard !isLocked, isDue, !isHeld, let work = open else { return }
    open = nil
    work()
  }
}

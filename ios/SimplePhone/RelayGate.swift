import Foundation

/// Decides WHEN the relay may hand off to the target app.
///
/// The target opens once the chosen duration has run out and nothing is holding
/// the cover. A finger holds it; holding long enough pins it, and a pinned cover
/// only ever leaves through `proceed` or `reset`.
///
/// Two invariants, both load-bearing:
///
/// - **Foundation only.** `scripts/test-relay-gate` compiles this exact file.
///   The app target has no XCTest bundle, so that script is the only executable
///   test the native half has, and a single `import UIKit` deletes it silently.
/// - **No timer.** Time arrives as `durationElapsed(_:)`, scheduled by the
///   caller, which is what keeps the cases deterministic.
///
/// Why it is a state machine rather than a cancellable timer, and why the pin
/// exists at all: `docs/native-notes.md`, "The relay cover".
final class RelayGate {
  /// A touch is down. Repeated presses collapse into one.
  private var isHeld = false

  /// The wait is over, either because the duration elapsed or because a finger
  /// landed. A press implies it, so releasing hands off without serving out the
  /// remainder of a four second setting.
  private var isDue = false

  /// What to run to leave, cleared the moment it runs.
  private var open: (() -> Void)?

  /// Which cover is on screen. The caller's timer is never cancelled, so a tick
  /// can outlive the relay that scheduled it; without an identity that stale
  /// tick satisfies the NEXT relay and cuts its cover short.
  private var cycle = 0

  /// The cover was pinned deliberately. Nothing leaves on its own after this.
  ///
  /// The most dangerous state here: a pin with no way out is a launcher that
  /// never launches. `proceed` and `reset` are the two exits and both are
  /// covered in `scripts/relay-gate-tests.swift`.
  private var isLocked = false

  var locked: Bool { isLocked }

  /// This cover owes a handoff. Returns the token its tick must carry back.
  ///
  /// `isDue` inherits the finger rather than starting false, because a press can
  /// land before the relay is armed and discarding it costs the user their hold.
  ///
  /// A pin, though, is never inherited, and the finger goes with it: a press
  /// still down when the cover was pinned belongs to that cover. Nothing else
  /// clears either one when a pinned cover is simply walked away from.
  @discardableResult
  func arm(_ work: @escaping () -> Void) -> Int {
    cycle &+= 1
    open = work
    if isLocked {
      isLocked = false
      isHeld = false
    }
    isDue = isHeld
    return cycle
  }

  /// Whether `token` still names the cover on screen.
  ///
  /// The tick is not the only thing the caller schedules against a cover: the
  /// countdown ring is animated from here too, and it needs the same answer for
  /// the same reason.
  func isCurrent(_ token: Int) -> Bool { token == cycle }

  /// The duration ran out for the relay identified by `token`. A tick from an
  /// older cycle is dropped.
  func durationElapsed(_ token: Int) {
    guard token == cycle else { return }
    isDue = true
    fire()
  }

  /// A finger landed on the cover.
  func press() {
    isHeld = true
    isDue = true
  }

  /// The finger held long enough to mean it.
  func lock() {
    isLocked = true
  }

  /// A tap or a sideways drag on a pinned cover. The only thing that hands off
  /// once locked.
  func proceed() {
    isLocked = false
    isHeld = false
    isDue = true
    fire()
  }

  /// The finger lifted. Inert while pinned, and deliberately without a guard of
  /// its own: `fire` is the single place the pin is enforced.
  func release() {
    isHeld = false
    fire()
  }

  /// The system took the touch away rather than the user lifting it. Identical
  /// to a release: no path may leave a handoff owed forever.
  func cancelPress() {
    release()
  }

  /// The cover came down for good. Lifting `isHeld` is the part that matters:
  /// a cover dismissed with a finger still on it would hold back every relay
  /// after it.
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

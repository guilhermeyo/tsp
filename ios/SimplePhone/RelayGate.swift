import Foundation

/// Decides WHAT a finger on the cover is asking for, from where it landed and
/// where it is now.
///
/// The cover offers two gestures and neither of them acts while the finger is
/// down. Closing a ring is a PROMISE about what lifting will do, which is what
/// makes both retractable: drag back, the ring opens, the promise goes with it.
///
/// - **Down** closes the pin over `pinTravel`. Lifting keeps the cover.
/// - **Sideways**, either way, closes the skip over the shorter `skipTravel`.
///   Lifting goes to the app.
///
/// ONE AT A TIME, decided by whichever axis has travelled further. Letting both
/// run put a forward arrow on a cover that had just been pinned: the ring
/// answered the drag down while the glyph still answered the drag sideways, and
/// neither was wrong on its own, which is the tell that the model was missing
/// rather than the drawing.
///
/// Foundation only and no view, for the same reason as `RelayGate` below:
/// `scripts/test-relay-gate` compiles this file, and it is the only way any of
/// this is tested at all. Points arrive as plain numbers so the caller can hand
/// over a touch location or a recogniser's translation without either one
/// leaking in here.
struct CoverDrag {
  /// Far enough down to keep the cover. More than the skip, because pinning
  /// takes the launch away entirely while skipping only brings forward what the
  /// cover was going to do on its own.
  static let pinTravel = 120.0
  static let skipTravel = 60.0

  /// How far a finger must move before either axis owns the drag. Below it a
  /// resting thumb's own tremor decides which is larger, and the glyph flickers
  /// between pause and forward on a hand that is holding still.
  static let slack = 8.0

  enum Gesture { case none, pinning, skipping }

  struct Reading {
    let gesture: Gesture
    /// How much of the ring is drawn, 0 to 1.
    let closed: Double
    /// The ring is whole, so lifting will do what the glyph says.
    let armed: Bool
    /// Armed on THIS reading and not the one before it, so the caller buzzes
    /// once rather than on every event a resting thumb produces.
    let justArmed: Bool
    /// The gesture is not the one the last reading gave, so the caller swaps
    /// the glyph.
    let changed: Bool
  }

  /// False for the drag that leaves a cover already pinned: down has nothing
  /// left to ask for there, since it is already the thing that happened.
  private let canPin: Bool
  private var origin: (x: Double, y: Double)?
  private var gesture: Gesture = .none
  private var armed = false

  init(canPin: Bool = true) {
    self.canPin = canPin
  }

  /// Where the finger was first SEEN, which on a warm relay is not where it
  /// landed: the first stretch of the touch belonged to the home screen. Seen
  /// is the honest baseline and the one the user's eye agrees with, because the
  /// ring starts moving from that same instant.
  mutating func began(x: Double, y: Double) {
    origin = (x, y)
    gesture = .none
    armed = false
  }

  mutating func moved(x: Double, y: Double) -> Reading {
    guard let origin else { return settle(.none, closed: 0) }
    // Down only. Coming back up unwinds the ring rather than closing it from
    // the other side, which is what makes backing out feel like backing out.
    let down = canPin ? max(y - origin.y, 0) : 0
    let sideways = abs(x - origin.x)

    guard max(down, sideways) >= Self.slack else { return settle(.none, closed: 0) }
    if sideways > down {
      return settle(.skipping, closed: min(sideways / Self.skipTravel, 1))
    }
    return settle(.pinning, closed: min(down / Self.pinTravel, 1))
  }

  /// The finger is gone. Nothing is promised and there is no origin to measure
  /// the next one against.
  mutating func end() {
    origin = nil
    gesture = .none
    armed = false
  }

  /// What lifting right now would do. An open ring promises nothing.
  var promise: Gesture { armed ? gesture : .none }

  private mutating func settle(_ next: Gesture, closed: Double) -> Reading {
    let changed = next != gesture
    if changed {
      gesture = next
      // A promise made by one gesture is not carried across to another.
      armed = false
    }
    let closing = closed >= 1 && next != .none
    let justArmed = closing && !armed
    armed = closing
    return Reading(gesture: next, closed: closed, armed: armed,
                   justArmed: justArmed, changed: changed)
  }
}

/// Decides WHEN the relay may hand off to the target app.
///
/// The target opens once the chosen duration has run out and nothing is holding
/// the cover. A finger holds it, and dragging that finger far enough pins it --
/// distance, not duration, and the caller owns that measurement. A pinned cover
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

  /// The duration has run out. ONLY the duration sets this.
  ///
  /// A press used to imply it, so lifting handed off without serving out the
  /// rest of the wait. That made a touch a commitment: rest a finger to read a
  /// line, think better of it, and lifting threw you into the app anyway. A
  /// press now pauses and nothing more, and the caller stops its own clock to
  /// match, so lifting simply returns the user to where they were.
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
  /// A press that landed before the relay was armed keeps holding: `isHeld`
  /// survives, so the finger is not discarded. What it no longer does is arrive
  /// already due, because nothing but the duration makes a relay due.
  ///
  /// A pin is never inherited, and the finger goes with it: a press still down
  /// when the cover was pinned belongs to that cover. Nothing else clears
  /// either one when a pinned cover is simply walked away from.
  @discardableResult
  func arm(_ work: @escaping () -> Void) -> Int {
    cycle &+= 1
    open = work
    if isLocked {
      isLocked = false
      isHeld = false
    }
    isDue = false
    return cycle
  }

  /// A new token for the SAME cover, without re-arming it.
  ///
  /// The caller's clock is paused and restarted while a finger is down, and the
  /// tick it scheduled before the pause is still out there. Stamping a fresh
  /// cycle is what makes that one a no-op, exactly as it does for a tick left
  /// over from a previous relay: the gate never cancels anything, it only stops
  /// recognising it.
  @discardableResult
  func restamp() -> Int {
    cycle &+= 1
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

  /// A finger landed on the cover. It pauses and commits to nothing.
  func press() {
    isHeld = true
  }

  /// The finger travelled far enough to mean it.
  func lock() {
    isLocked = true
  }

  /// GO NOW, whatever the clock says. A tap or a sideways drag on a pinned
  /// cover, and a sideways drag on one that is merely held. The only thing that
  /// hands off once locked, and the only thing that hands off early at all.
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

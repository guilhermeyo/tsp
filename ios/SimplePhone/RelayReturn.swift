import Foundation

/// Decides whether coming back to the app should show the phrase you just left
/// on, and where you were going when you left it.
///
/// Holding the cover to read is a race the platform does not always let you
/// win, so a missed line is recoverable instead. Only a return that follows a
/// HANDOFF earns the card: the cover goes up on every backgrounding, including
/// a plain swipe home, so anything looser would put a card in front of the list
/// every time the app is opened.
///
/// Foundation only and no clock, for the same reasons as `RelayGate`: it is
/// what lets `scripts/test-relay-gate` compile this file and drive every case.
/// Why the race exists at all is in `docs/native-notes.md`, "The relay cover".
struct RelayReturn {
  /// How long a miss stays worth recovering. A judgement call: long enough for
  /// "the app opened, the line was gone, I want it back", short enough not to
  /// ambush someone coming back to launch something else.
  static let window: TimeInterval = 120

  /// The line, and the place the user was headed.
  struct Missed {
    let phrase: String
    /// Nil when the relay had no usable target, which the widget cannot produce
    /// but a hand-typed URL can.
    let target: URL?
  }

  private var handoffAt: TimeInterval?
  private var phrase: String?
  private var target: URL?

  /// The target was asked to open, with this line on screen. Recorded rather
  /// than read back later, because the exit paints the next phrase into the
  /// snapshot and the stored `current` moves on.
  mutating func handedOff(phrase: String?, target: URL?, at now: TimeInterval) {
    handoffAt = now
    self.phrase = phrase
    self.target = target
  }

  /// The app is activating. Returns what to show, or nil to tear the cover down
  /// as usual. Consuming is the point: a second activation is someone opening
  /// the app to use it.
  mutating func consume(at now: TimeInterval) -> Missed? {
    guard let at = handoffAt else { return nil }
    let line = phrase
    let destination = target
    handoffAt = nil
    phrase = nil
    target = nil
    guard now >= at, now - at <= Self.window, let line else { return nil }
    return Missed(phrase: line, target: destination)
  }

  /// The relay ended without the app leaving: the target refused to open.
  /// Nothing was missed, so nothing is owed.
  mutating func clear() {
    handoffAt = nil
    phrase = nil
    target = nil
  }

  /// Whether a card is still owed. Also the signal the roll reads on the way
  /// out, which is why it is not private.
  var isPending: Bool { handoffAt != nil }
}

/// Decides whether coming back should put the user where the relay was, rather
/// than tearing the cover down as if it had finished.
///
/// A relay that ends without handing off did not finish, it was INTERRUPTED:
/// the phone locked its own screen, a call arrived, the user left mid-read. The
/// app cannot tell those apart, because iOS reports all of them as the same
/// backgrounding, so the rule has to be good enough for all of them at once.
///
/// Two things are being resumed and they carry different risk, which is the
/// whole of why this type exists rather than a bool:
///
/// - **A pin is inert.** It never leaves on its own, so offering it back a day
///   later costs nothing but a tap. It is also the user having said, in as many
///   words, that they want this line. No window.
/// - **A countdown is not inert.** Resuming it hands the user to another app.
///   Soon after the fact that is a courtesy; long after it is an ambush by a
///   launch they have forgotten choosing. Hence `window`.
///
/// Foundation only, no clock, same as `RelayGate` and `RelayReturn` above, and
/// for the same reason: `scripts/test-relay-gate` compiles this file.
struct RelaySuspension {
  /// How long an unfinished countdown is worth resuming. The same judgement and
  /// the same number as `RelayReturn.window`, because it is the same question
  /// asked from the other side.
  static let window: TimeInterval = 120

  struct Resumed {
    /// The cover was ALREADY pinned, so it still carries the pin's controls and
    /// the drag that leaves it. Locking again is the whole restoration.
    let pinned: Bool
    /// A finger was merely resting on it. Nothing leaves on its own either --
    /// nobody keeps a finger on the glass through a locked screen, and resuming
    /// a countdown that was being held back is the one reading the user
    /// certainly did not ask for -- but NONE of the pin's furniture was ever
    /// built, so the caller has to build it before locking.
    ///
    /// Collapsing this into `pinned` produced a full-screen cover with no
    /// countdown, no controls and no working gesture, which survived being
    /// relaunched. `docs/native-notes.md` calls that the worst failure this
    /// code can have.
    let held: Bool
    /// What was still on the clock when everything stopped.
    let secondsLeft: TimeInterval
    /// What it had been in total, so the ring can pick the sweep up part way
    /// through rather than starting it over.
    let total: TimeInterval
  }

  private var at: TimeInterval?
  private var pinned = false
  private var held = false
  private var secondsLeft: TimeInterval = 0
  private var total: TimeInterval = 0

  /// The relay stopped without ever handing off.
  ///
  /// A finger down at this moment is worth remembering, and that is a decision
  /// rather than a shortcut. Holding means "I am still reading"; nobody can
  /// keep a finger on the glass through a locked screen, and resuming a
  /// countdown that was being held back is the one reading of the situation the
  /// user certainly did not ask for. It is kept SEPARATE from a pin because the
  /// two come back to different covers: see `Resumed.held`.
  mutating func interrupted(pinned: Bool, held: Bool, secondsLeft: TimeInterval,
                            total: TimeInterval, at now: TimeInterval) {
    self.at = now
    self.pinned = pinned
    self.held = held && !pinned
    self.secondsLeft = max(secondsLeft, 0)
    self.total = max(total, 0)
  }

  /// The app is activating. Returns what to put back, or nil to carry on as
  /// usual. Consuming either way: a stale offer left in place would simply fire
  /// on the next activation instead.
  mutating func resume(at now: TimeInterval) -> Resumed? {
    guard let at else { return nil }
    let taken = Resumed(pinned: pinned, held: held, secondsLeft: secondsLeft, total: total)
    clear()
    guard now >= at else { return nil }
    // Only a countdown expires. Neither of the other two leaves on its own, so
    // neither can ambush anyone by being offered back late.
    guard taken.pinned || taken.held || now - at <= Self.window else { return nil }
    return taken
  }

  /// A new relay supersedes an interrupted one: the user chose something else.
  mutating func clear() {
    at = nil
    pinned = false
    held = false
    secondsLeft = 0
    total = 0
  }

  var isPending: Bool { at != nil }
}

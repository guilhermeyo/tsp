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

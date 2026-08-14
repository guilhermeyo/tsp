import Foundation

/// Decides whether coming back to the app should show the phrase you just left
/// on, instead of dropping you straight into the list.
///
/// The point is the miss. Holding the cover to read a line is a race against a
/// window iOS does not open for the first 400ms of a relay, so sometimes the
/// app is gone before your thumb lands. Rather than keep fighting for those
/// milliseconds, the line is still there when you come back: tap the `TSP`
/// breadcrumb iOS puts in the status bar and the phrase is waiting, with how
/// many times it has come up and a way into the app.
///
/// NO UIKit, so `scripts/test-relay-gate` compiles this file and drives every
/// case, and no clock, so those cases are not timing-dependent. Time arrives as
/// an argument.
///
/// WHY IT IS NOT ENOUGH TO ASK "did we just relay". The cover goes up on EVERY
/// backgrounding, including a plain swipe to the home screen, because that is
/// what makes the system snapshot carry a phrase. Keeping it up on every return
/// would put a card in front of the list every single time the app is opened.
/// Only a return that follows a HANDOFF earns it.
struct RelayReturn {
  /// How long a miss stays worth recovering.
  ///
  /// A judgement call, and the one number here that is not derived from
  /// anything. Two minutes covers the actual case (the app opened, the line was
  /// gone, you want it back) without ambushing someone who spent a while in
  /// WhatsApp and came back to launch something else.
  static let window: TimeInterval = 120

  private var handoffAt: TimeInterval?
  private var phrase: String?

  /// The target was asked to open, and this is the line that was on screen when
  /// it happened. Recorded here rather than read back later because
  /// backgrounding rolls the NEXT phrase to paint into the snapshot, so by the
  /// time anyone comes back the stored `current` is a different line.
  mutating func handedOff(phrase: String?, at now: TimeInterval) {
    handoffAt = now
    self.phrase = phrase
  }

  /// The app is being activated. Returns the line to show, or nil to behave as
  /// before and tear the cover down.
  ///
  /// Consuming is the point: a second activation is someone opening the app to
  /// use it, not someone chasing a line they missed.
  mutating func consume(at now: TimeInterval) -> String? {
    guard let at = handoffAt else { return nil }
    let line = phrase
    handoffAt = nil
    phrase = nil
    guard now >= at, now - at <= Self.window else { return nil }
    return line
  }

  /// The relay ended without the app ever leaving: the target refused to open
  /// and the user is looking at an alert. Nothing was missed, so nothing is
  /// owed.
  mutating func clear() {
    handoffAt = nil
    phrase = nil
  }

  var isPending: Bool { handoffAt != nil }
}

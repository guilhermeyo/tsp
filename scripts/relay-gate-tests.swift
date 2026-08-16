// Tests for RelayGate, the rule that decides when the relay hands off.
//
// The native half of this repo has no XCTest target, and adding one means
// surgery on a committed pbxproj for a type with no UIKit in it. So this runs
// the real `ios/SimplePhone/RelayGate.swift` directly:
//
//     ./scripts/test-relay-gate
//
// Every case below is something a finger can actually do to the cover. Time is
// never real here: `durationElapsed(_:)` is the tick, called by hand, which is
// the whole reason the gate owns no timer.

import Foundation

@main
enum RelayGateTests {
  static var failures = 0

  static func check(_ condition: Bool, _ what: String) {
    if condition {
      print("  ok    \(what)")
    } else {
      print("  FAIL  \(what)")
      failures += 1
    }
  }

  /// The duration ran out and nobody was touching the screen. The ordinary relay.
  static func testOpensWhenDurationRunsOut() {
    let gate = RelayGate()
    var opened = 0
    let token = gate.arm { opened += 1 }
    check(opened == 0, "armed alone does not open")
    gate.durationElapsed(token)
    check(opened == 1, "the duration running out opens the target")
  }

  /// Instant, where the caller ticks on the very next runloop turn.
  ///
  /// Honest about what this proves and what it does not. It proves the GATE
  /// holds when a press has already been delivered, which is the whole of its
  /// job. It cannot prove UIKit delivers that press in time, because the window
  /// at zero is the app-switch animation and the app is barely interactive
  /// through it. Short or Medium is where holding is actually comfortable; this
  /// case exists so that zero is not additionally broken on top of being tight.
  static func testInstantStillFreezesUnderAFinger() {
    let gate = RelayGate()
    var opened = 0
    gate.press()
    let token = gate.arm { opened += 1 }
    gate.durationElapsed(token)
    check(opened == 0, "a finger already down holds the target back at zero duration")
    gate.release()
    check(opened == 1, "lifting it hands off")
  }

  /// A press partway through the chosen duration.
  static func testPressDuringTheDurationHolds() {
    let gate = RelayGate()
    var opened = 0
    let token = gate.arm { opened += 1 }
    gate.press()
    check(opened == 0, "pressing during the duration does not open")
    gate.durationElapsed(token)
    check(opened == 0, "the duration running out while held does not open")
    gate.release()
    check(opened == 1, "releasing after the duration opens")
  }

  /// Holding then letting go hands off at once rather than serving out the rest
  /// of a four second wait: the finger replaces the timer, it does not queue
  /// behind it.
  static func testReleaseBeatsTheClock() {
    let gate = RelayGate()
    var opened = 0
    let token = gate.arm { opened += 1 }
    gate.press()
    gate.release()
    check(opened == 1, "releasing opens before the duration has run out")
    gate.durationElapsed(token)
    check(opened == 1, "the late tick does not open a second time")
  }

  /// The touch was cancelled rather than lifted: a call arrived, or the user
  /// swiped away mid-press. A launcher that launches nothing is worse than one
  /// that shows its list, so cancellation has to hand off like a release.
  static func testCancelledTouchStillHandsOff() {
    let gate = RelayGate()
    var opened = 0
    gate.arm { opened += 1 }
    gate.press()
    gate.cancelPress()
    check(opened == 1, "a cancelled touch hands off like a release")
  }

  /// Fingers do not always come in pairs.
  static func testUnbalancedTouches() {
    let gate = RelayGate()
    var opened = 0
    let token = gate.arm { opened += 1 }
    gate.press()
    gate.press()
    gate.durationElapsed(token)
    gate.release()
    check(opened == 1, "a repeated press still opens on the first release")
  }

  /// A `touchesEnded` with no `touchesBegan` behind it. The gate is a singleton
  /// that outlives any one cover, so a release belonging to nothing must not
  /// leave the next relay primed to hand off on sight.
  static func testStrayReleaseDoesNotPrimeTheNextRelay() {
    let gate = RelayGate()
    gate.release()

    var opened = 0
    let token = gate.arm { opened += 1 }
    check(opened == 0, "a stray release does not open the relay that follows it")
    gate.durationElapsed(token)
    check(opened == 1, "and that relay still opens exactly once on its own tick")
  }

  /// THE ORPHAN TICK, and the reason a cycle has an identity at all.
  ///
  /// Relay 1 hands off early because a thumb let go, so the timer it scheduled
  /// is still out there with nothing to do. Relay 2 arms while that tick is in
  /// flight. Without a token the stale tick satisfies the NEW relay and cuts its
  /// cover short, which is the exact opposite of what holding is for.
  static func testOrphanTickCannotOpenTheNextRelay() {
    let gate = RelayGate()
    var first = 0, second = 0

    let firstToken = gate.arm { first += 1 }
    gate.press()
    gate.release()
    check(first == 1, "relay one handed off on the release")

    let secondToken = gate.arm { second += 1 }
    gate.durationElapsed(firstToken)
    check(second == 0, "relay one's stale tick does not open relay two")

    gate.durationElapsed(secondToken)
    check(second == 1, "relay two opens on its own tick")
  }

  /// A press that lands BEFORE the relay is armed.
  ///
  /// `arm` used to clear the due flag unconditionally, which threw that press
  /// away: releasing then handed off nothing and the user sat through the whole
  /// duration with their thumb off the glass. A finger already on the cover is
  /// a statement that the wait is over, and arming must not forget it.
  static func testPressBeforeArmSurvivesTheArm() {
    let gate = RelayGate()
    var opened = 0
    gate.press()
    gate.arm { opened += 1 }
    check(opened == 0, "still held after arming")
    gate.release()
    check(opened == 1, "releasing hands off without waiting for the tick")
  }

  /// The cover came down with a finger still on it and no cancellation ever
  /// arrived. If `reset` forgot to lift that finger, every relay afterwards
  /// would be held by a thumb that is not there: a launcher that never
  /// launches, which is the worst failure this code has.
  static func testResetLiftsAStuckFinger() {
    let gate = RelayGate()
    gate.arm {}
    gate.press()
    gate.reset()

    var opened = 0
    let token = gate.arm { opened += 1 }
    gate.durationElapsed(token)
    check(opened == 1, "a relay after a reset opens with no extra touch")
  }

  /// Touching after the target was already asked to open changes nothing. The
  /// open is not cancellable once requested, and the gate must not pretend so.
  static func testPressAfterHandoffDoesNothing() {
    let gate = RelayGate()
    var opened = 0
    let token = gate.arm { opened += 1 }
    gate.durationElapsed(token)
    check(opened == 1, "opened on time")
    gate.press()
    gate.release()
    check(opened == 1, "a press after the handoff does not open again")
  }

  /// The cover came down for good, so anything still owed is stale: the user is
  /// back in the app and the target they picked is no longer wanted.
  static func testResetForgetsAHeldOpen() {
    let gate = RelayGate()
    var opened = 0
    let token = gate.arm { opened += 1 }
    gate.press()
    gate.reset()
    gate.release()
    gate.durationElapsed(token)
    check(opened == 0, "reset forgets a held open")
  }

  /// A second relay after a reset works from scratch.
  static func testRelayAfterResetOpens() {
    let gate = RelayGate()
    var first = 0
    let firstToken = gate.arm { first += 1 }
    gate.durationElapsed(firstToken)
    gate.reset()
    var second = 0
    let secondToken = gate.arm { second += 1 }
    gate.durationElapsed(secondToken)
    check(first == 1 && second == 1, "a fresh relay after a reset opens")
  }

  // MARK: - RelayReturn: the phrase waiting for you when you come back

  /// The ordinary miss. The app handed off, you tapped the breadcrumb, and the
  /// line you did not get to read is what you come back to.
  static func testReturnAfterHandoffOffersThePhrase() {
    var ret = RelayReturn()
    ret.handedOff(phrase: "the obstacle is the way", target: URL(string: "whatsapp://"), at: 1000)
    check(ret.consume(at: 1002)?.phrase == "the obstacle is the way", "a quick return offers the line")
  }

  /// Opening the app without a relay behind it is someone going to use it. The
  /// cover comes down as it always did.
  static func testPlainActivationOffersNothing() {
    var ret = RelayReturn()
    check(ret.consume(at: 1000) == nil, "an activation with no handoff behind it offers nothing")
  }

  /// The card is for a miss, not a bookmark. Come back much later and you are
  /// opening the app to do something, not chasing a line.
  static func testStaleReturnOffersNothing() {
    var ret = RelayReturn()
    ret.handedOff(phrase: "seneca", target: URL(string: "whatsapp://"), at: 1000)
    check(ret.consume(at: 1000 + RelayReturn.window + 1) == nil, "a late return offers nothing")
  }

  /// Exactly on the boundary still counts. An off-by-one here is a card that
  /// vanishes for no reason a user could ever describe.
  static func testReturnOnTheBoundaryStillOffers() {
    var ret = RelayReturn()
    ret.handedOff(phrase: "marcus", target: URL(string: "whatsapp://"), at: 1000)
    check(ret.consume(at: 1000 + RelayReturn.window)?.phrase == "marcus", "the boundary is inclusive")
  }

  /// Consuming is once. The second activation is the user opening the app.
  static func testTheOfferIsConsumed() {
    var ret = RelayReturn()
    ret.handedOff(phrase: "epictetus", target: URL(string: "whatsapp://"), at: 1000)
    _ = ret.consume(at: 1001)
    check(ret.consume(at: 1002) == nil, "the offer is not made twice")
  }

  /// A stale offer is consumed even though it shows nothing, so it cannot
  /// surface later on an unrelated activation.
  static func testAStaleOfferIsAlsoConsumed() {
    var ret = RelayReturn()
    ret.handedOff(phrase: "seneca", target: URL(string: "whatsapp://"), at: 1000)
    _ = ret.consume(at: 1000 + RelayReturn.window + 1)
    check(!ret.isPending, "a stale offer does not linger")
  }

  /// The target refused to open, so the app never left and nothing was missed.
  static func testFailedOpenOwesNothing() {
    var ret = RelayReturn()
    ret.handedOff(phrase: "marcus", target: URL(string: "whatsapp://"), at: 1000)
    ret.clear()
    check(ret.consume(at: 1001) == nil, "a relay that never left owes no card")
  }

  /// A phrase-less cover (phrases switched off, or an empty list) still hands
  /// off, and must not offer an empty card on the way back.
  static func testHandoffWithNoPhraseOffersNothing() {
    var ret = RelayReturn()
    ret.handedOff(phrase: nil, target: URL(string: "whatsapp://"), at: 1000)
    check(ret.consume(at: 1001) == nil, "no phrase means no card")
  }

  /// A second relay replaces the first. You come back to the line you actually
  /// just missed, not to one from two launches ago.
  static func testTheLatestHandoffWins() {
    var ret = RelayReturn()
    ret.handedOff(phrase: "first", target: URL(string: "whatsapp://"), at: 1000)
    ret.handedOff(phrase: "second", target: URL(string: "whatsapp://"), at: 1010)
    check(ret.consume(at: 1011)?.phrase == "second", "the most recent line is the one waiting")
  }


  // MARK: - The lock: a cover pinned on purpose

  /// Holding long enough pins the cover. The chosen duration stops mattering.
  static func testLockSurvivesTheDuration() {
    let gate = RelayGate()
    var opened = 0
    let token = gate.arm { opened += 1 }
    gate.press()
    gate.lock()
    gate.durationElapsed(token)
    check(opened == 0, "a locked cover ignores its own duration")
  }

  /// Letting go of a cover you pinned means you are done PRESSING, not done
  /// reading. This is the whole difference between holding and locking.
  static func testReleaseDoesNothingWhileLocked() {
    let gate = RelayGate()
    var opened = 0
    gate.arm { opened += 1 }
    gate.press()
    gate.lock()
    gate.release()
    check(opened == 0, "lifting the finger off a locked cover does not hand off")
  }

  /// A cancelled touch must not sneak past the lock either. It is a release by
  /// another name and the same reasoning applies.
  static func testCancelDoesNothingWhileLocked() {
    let gate = RelayGate()
    var opened = 0
    gate.arm { opened += 1 }
    gate.press()
    gate.lock()
    gate.cancelPress()
    check(opened == 0, "a cancelled touch does not break the lock")
  }

  /// The tap, or the drag to the right. The one way out that goes where the
  /// user was originally headed.
  static func testProceedHandsOffFromALock() {
    let gate = RelayGate()
    var opened = 0
    gate.arm { opened += 1 }
    gate.press()
    gate.lock()
    gate.proceed()
    check(opened == 1, "proceeding from a lock opens the target")
  }

  /// Twice is once. A double tap on a locked cover is one instruction.
  static func testProceedOnlyFiresOnce() {
    let gate = RelayGate()
    var opened = 0
    gate.arm { opened += 1 }
    gate.press()
    gate.lock()
    gate.proceed()
    gate.proceed()
    check(opened == 1, "proceeding twice opens once")
  }

  /// THE WORST FAILURE THIS FILE CAN HAVE. A lock that outlives its cover would
  /// hold every relay afterwards behind a pin nobody can see: a launcher that
  /// never launches. `reset` is the other way out and it has to be total.
  static func testResetUnlocks() {
    let gate = RelayGate()
    gate.arm {}
    gate.press()
    gate.lock()
    gate.reset()

    var opened = 0
    let token = gate.arm { opened += 1 }
    gate.durationElapsed(token)
    check(opened == 1, "a relay after a locked one opens on its own duration")
  }

  /// A tick left over from before the lock is still owed to nobody afterwards.
  static func testStaleTickCannotOpenAfterProceed() {
    let gate = RelayGate()
    var opened = 0
    let token = gate.arm { opened += 1 }
    gate.press()
    gate.lock()
    gate.proceed()
    gate.durationElapsed(token)
    check(opened == 1, "the old tick does not open a second time after proceeding")
  }

  /// Locking without a finger is not a thing the UI can do, but the gate must
  /// not invent a handoff if it happens.
  static func testLockWithoutPressStillBlocks() {
    let gate = RelayGate()
    var opened = 0
    let token = gate.arm { opened += 1 }
    gate.lock()
    gate.durationElapsed(token)
    check(opened == 0, "a lock blocks even with no finger recorded")
    gate.proceed()
    check(opened == 1, "and proceeding still works")
  }

  /// The flag the UI reads to know whether to draw a padlock.
  static func testLockedIsVisible() {
    let gate = RelayGate()
    gate.arm {}
    check(!gate.locked, "not locked to begin with")
    gate.lock()
    check(gate.locked, "locked after locking")
    gate.proceed()
    check(!gate.locked, "not locked after proceeding")
  }


  /// Swiping right on the card puts you back where you were going, so the card
  /// has to remember the destination and not only the line.
  static func testTheCardRemembersWhereYouWereGoing() {
    var ret = RelayReturn()
    ret.handedOff(phrase: "seneca", target: URL(string: "whatsapp-consumer://"), at: 1000)
    check(ret.consume(at: 1001)?.target?.absoluteString == "whatsapp-consumer://",
          "the destination comes back with the line")
  }

  /// A relay with no usable destination still owes the line. The card shows,
  /// and the swipe simply has nowhere to go.
  static func testACardWithoutADestinationStillShows() {
    var ret = RelayReturn()
    ret.handedOff(phrase: "marcus", target: nil, at: 1000)
    let missed = ret.consume(at: 1001)
    check(missed?.phrase == "marcus", "the line survives a missing destination")
    check(missed?.target == nil, "and the destination is honestly absent")
  }

  /// The destination is consumed with everything else, so a later activation
  /// cannot swipe you into an app you left minutes ago.
  static func testTheDestinationIsConsumedToo() {
    var ret = RelayReturn()
    ret.handedOff(phrase: "epictetus", target: URL(string: "waze://"), at: 1000)
    _ = ret.consume(at: 1001)
    check(ret.consume(at: 1002) == nil, "the destination does not linger either")
  }


  /// THE DEAD COVER, and the reason `arm` cannot be trusted to inherit state.
  ///
  /// A pinned cover that the user walks away from instead of dismissing:
  /// they swipe home. The relay ends without `proceed` and without `reset`,
  /// because `endRelay` only clears `relayInFlight` and `dismiss` refuses to
  /// run while a relay is in flight. The pin outlives its cover.
  ///
  /// The next relay then arms behind a lock nobody can see, with no ring, no
  /// chrome and no gestures left on screen: a full-screen phrase above
  /// everything, with no way out and no way through. A launcher that never
  /// launches, which the header of this file calls the worst failure it has.
  static func testAnAbandonedLockDoesNotPoisonTheNextRelay() {
    let gate = RelayGate()
    gate.arm {}
    gate.press()
    gate.lock()
    // The user swipes home. Nothing else happens: no proceed, no reset.

    var opened = 0
    let token = gate.arm { opened += 1 }
    gate.durationElapsed(token)
    check(opened == 1, "a relay after an abandoned lock still opens")
  }

  static func main() {
    testOpensWhenDurationRunsOut()
    testInstantStillFreezesUnderAFinger()
    testPressDuringTheDurationHolds()
    testReleaseBeatsTheClock()
    testCancelledTouchStillHandsOff()
    testUnbalancedTouches()
    testStrayReleaseDoesNotPrimeTheNextRelay()
    testOrphanTickCannotOpenTheNextRelay()
    testPressBeforeArmSurvivesTheArm()
    testResetLiftsAStuckFinger()
    testPressAfterHandoffDoesNothing()
    testResetForgetsAHeldOpen()
    testRelayAfterResetOpens()

    testReturnAfterHandoffOffersThePhrase()
    testPlainActivationOffersNothing()
    testStaleReturnOffersNothing()
    testReturnOnTheBoundaryStillOffers()
    testTheOfferIsConsumed()
    testAStaleOfferIsAlsoConsumed()
    testFailedOpenOwesNothing()
    testHandoffWithNoPhraseOffersNothing()
    testTheLatestHandoffWins()
    testTheCardRemembersWhereYouWereGoing()
    testACardWithoutADestinationStillShows()
    testTheDestinationIsConsumedToo()

    testLockSurvivesTheDuration()
    testReleaseDoesNothingWhileLocked()
    testCancelDoesNothingWhileLocked()
    testProceedHandsOffFromALock()
    testProceedOnlyFiresOnce()
    testResetUnlocks()
    testStaleTickCannotOpenAfterProceed()
    testLockWithoutPressStillBlocks()
    testLockedIsVisible()
    testAnAbandonedLockDoesNotPoisonTheNextRelay()

    print("")
    if failures == 0 {
      print("relay gate: all cases pass")
      exit(0)
    }
    print("relay gate: \(failures) failing")
    exit(1)
  }
}

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

  /// Resting a finger and lifting it again is not a decision.
  ///
  /// This used to hand off, on the reasoning that a press meant the user was
  /// ready. It made a touch a commitment instead of a pause: reach for the
  /// screen to read a line, change your mind, and lifting threw you into the app
  /// regardless. Nothing but the clock and an explicit gesture opens anything
  /// now, and the caller stops its own clock while the finger is down so the
  /// time is genuinely held rather than merely ignored.
  static func testReleasingWithoutAGestureLeavesTheClockOwing() {
    let gate = RelayGate()
    var opened = 0
    let token = gate.arm { opened += 1 }
    gate.press()
    gate.release()
    check(opened == 0, "lifting without a gesture does not open anything")
    gate.durationElapsed(token)
    check(opened == 1, "and the duration it went back to still opens it")
  }

  /// Sideways on a cover that is merely held, rather than pinned: go now.
  static func testASidewaysDragOpensEarly() {
    let gate = RelayGate()
    var opened = 0
    let token = gate.arm { opened += 1 }
    gate.press()
    gate.proceed()
    check(opened == 1, "asking to go opens without waiting for the duration")
    gate.durationElapsed(token)
    check(opened == 1, "and the tick it beat does not open a second time")
  }

  /// The clock is restarted whenever a hold ends, and the tick scheduled before
  /// the hold is still out there. Without a fresh stamp it lands early and cuts
  /// the resumed countdown short.
  static func testRestampingDropsTheTickFromBeforeAHold() {
    let gate = RelayGate()
    var opened = 0
    let stale = gate.arm { opened += 1 }
    gate.press()
    let live = gate.restamp()
    gate.release()
    gate.durationElapsed(stale)
    check(opened == 0, "the tick from before the hold is not recognised")
    gate.durationElapsed(live)
    check(opened == 1, "the one scheduled for what was left of it is")
  }

  /// The system took the touch away rather than the user lifting it. Identical
  /// to a release, which now means the relay goes back to its clock rather than
  /// handing off: no path may leave a handoff owed forever, and the duration is
  /// what redeems it.
  static func testCancelledTouchGoesBackToTheClock() {
    let gate = RelayGate()
    var opened = 0
    let token = gate.arm { opened += 1 }
    gate.press()
    gate.cancelPress()
    check(opened == 0, "a cancelled touch opens nothing, exactly like a release")
    gate.durationElapsed(token)
    check(opened == 1, "and the relay is still owed to its own duration")
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
    gate.proceed()
    check(first == 1, "relay one handed off early on a sideways drag")

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
    let token = gate.arm { opened += 1 }
    check(opened == 0, "still held after arming")
    gate.durationElapsed(token)
    check(opened == 0, "the finger that arrived before the arm still holds the tick back")
    gate.release()
    check(opened == 1, "and lifting it lets that tick through")
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

  /// Dragging far enough pins the cover. The chosen duration stops mattering.
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

  /// The flag the UI reads to know the cover is pinned rather than merely slow.
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

  /// The countdown ring is animated by the caller, not by the gate, so it needs
  /// the same staleness check the tick has: a drain scheduled for the relay
  /// before this one must not start sweeping the badge of the current cover.
  static func testATokenKnowsWhichRelayItBelongsTo() {
    let gate = RelayGate()
    let first = gate.arm {}
    check(gate.isCurrent(first), "the token just handed out is the current one")
    let second = gate.arm {}
    check(!gate.isCurrent(first), "the previous relay's token has gone stale")
    check(gate.isCurrent(second), "the new one is current")
  }

  /// Tearing the cover down invalidates everything, the same way it invalidates
  /// a pending tick. A drain that fired after a dismiss would animate a badge
  /// that is no longer on screen at best, and the NEXT cover's at worst.
  static func testResetStalesEveryToken() {
    let gate = RelayGate()
    let token = gate.arm {}
    gate.reset()
    check(!gate.isCurrent(token), "reset stales the token it had handed out")
  }

  // MARK: - The relay that was interrupted rather than finished

  /// The ordinary end of a relay. The app left because the target opened, so
  /// there is nothing to come back to.
  static func testNothingInterruptedResumesNothing() {
    var suspension = RelaySuspension()
    check(!suspension.isPending, "a relay that was never interrupted owes nothing")
    check(suspension.resume(at: 0) == nil, "and resuming it yields nothing")
  }

  /// The phone locked itself while the cover was counting down. Coming back
  /// should carry on from where the clock stopped, not start over and not skip.
  static func testAnUnfinishedCountdownResumesWithWhatWasLeft() {
    var suspension = RelaySuspension()
    suspension.interrupted(pinned: false, held: false, secondsLeft: 0.9, total: 1.5, at: 100)
    check(suspension.isPending, "an interrupted countdown is owed")
    let resumed = suspension.resume(at: 130)
    check(resumed?.secondsLeft == 0.9, "it resumes with the time that was left")
    check(resumed?.total == 1.5, "and remembers how long it was, so the ring can pick up mid-sweep")
    check(resumed?.pinned == false, "still counting, not pinned")
  }

  /// A pinned cover is inert: it never leaves on its own, so there is no reason
  /// to stop offering it back. Pinning is the user saying they want this line.
  static func testAPinnedCoverResumesHoweverLongItTakes() {
    var suspension = RelaySuspension()
    suspension.interrupted(pinned: true, held: false, secondsLeft: 0, total: 1.5, at: 0)
    let resumed = suspension.resume(at: 60 * 60 * 24)
    check(resumed?.pinned == true, "a pin is still owed a day later")
    check(resumed?.held == false, "and it was not merely a finger resting")
  }

  /// A FINGER RESTING IS NOT A PIN, and the difference is the whole reason
  /// these are two flags rather than one.
  ///
  /// Both come back rather than counting down, because nobody keeps a finger on
  /// the glass through a locked screen and resuming a countdown that was being
  /// held back is the one reading the user certainly did not ask for. But a
  /// cover that was PINNED already carries the pin's controls and the drag that
  /// leaves it, and one that was merely held carries none of them. Collapsing
  /// the two locked a cover with no way off it at all.
  static func testARestingFingerIsRememberedAsHeldRatherThanPinned() {
    var suspension = RelaySuspension()
    suspension.interrupted(pinned: false, held: true, secondsLeft: 0.9, total: 1.5, at: 0)
    let resumed = suspension.resume(at: 10)
    check(resumed?.held == true, "a finger that was down is remembered as held")
    check(resumed?.pinned == false, "and NOT as a pin, which would promise controls it never built")
  }

  /// A held cover is as inert as a pinned one once it comes back, so it gets
  /// the same absence of a deadline.
  static func testAHeldCoverAlsoResumesHoweverLongItTakes() {
    var suspension = RelaySuspension()
    suspension.interrupted(pinned: false, held: true, secondsLeft: 0.9, total: 1.5, at: 0)
    check(suspension.resume(at: 60 * 60 * 24)?.held == true,
          "a hold is still owed a day later, because it will not leave on its own either")
  }

  /// An unfinished countdown is NOT inert: resuming it hands the user to another
  /// app. Long enough after the fact, that is an ambush rather than a courtesy.
  static func testAStaleCountdownIsDroppedRatherThanResumed() {
    var suspension = RelaySuspension()
    suspension.interrupted(pinned: false, held: false, secondsLeft: 0.9, total: 1.5, at: 0)
    check(suspension.resume(at: RelaySuspension.window + 1) == nil,
          "a countdown nobody came back for does not open anything")
  }

  /// Dropped and CONSUMED. A stale offer left in place would fire on the next
  /// activation instead, which is the same ambush one foregrounding later.
  static func testAStaleCountdownIsConsumedToo() {
    var suspension = RelaySuspension()
    suspension.interrupted(pinned: false, held: false, secondsLeft: 0.9, total: 1.5, at: 0)
    _ = suspension.resume(at: RelaySuspension.window + 1)
    check(!suspension.isPending, "the stale offer is gone rather than pending")
  }

  /// Coming back is a single event. A second activation is someone opening the
  /// app to use it, not someone still returning from the relay.
  static func testResumingConsumesTheOffer() {
    var suspension = RelaySuspension()
    suspension.interrupted(pinned: true, held: false, secondsLeft: 0, total: 1.5, at: 0)
    _ = suspension.resume(at: 1)
    check(suspension.resume(at: 2) == nil, "the offer is taken only once")
  }

  /// A new relay supersedes an interrupted one: the user chose something else.
  static func testClearDropsTheOffer() {
    var suspension = RelaySuspension()
    suspension.interrupted(pinned: true, held: false, secondsLeft: 0, total: 1.5, at: 0)
    suspension.clear()
    check(!suspension.isPending, "clearing drops it")
    check(suspension.resume(at: 1) == nil, "and nothing comes back")
  }

  /// A clock that ran backwards must not read as an offer from the future that
  /// is somehow always fresh. Same rule the return card follows.
  static func testACountdownFromTheFutureIsRefused() {
    var suspension = RelaySuspension()
    suspension.interrupted(pinned: false, held: false, secondsLeft: 0.9, total: 1.5, at: 500)
    check(suspension.resume(at: 100) == nil, "a suspension in the future is not resumed")
  }

  // MARK: - What a finger on the cover is asking for

  /// A thumb that has not gone anywhere is asking for nothing. It still pauses,
  /// but pausing is what a press does; this is about what LIFTING will do.
  static func testAStillFingerPromisesNothing() {
    var drag = CoverDrag()
    drag.began(x: 200, y: 400)
    let reading = drag.moved(x: 200, y: 400)
    check(reading.gesture == .none, "no travel is no gesture")
    check(reading.closed == 0, "and nothing is closed")
    check(drag.promise == .none, "so lifting does nothing")
  }

  /// Below the slack the two axes are decided by tremor, and the glyph flickers
  /// between pause and forward on a hand that is holding still.
  static func testTremorIsNotAGesture() {
    var drag = CoverDrag()
    drag.began(x: 200, y: 400)
    check(drag.moved(x: 204, y: 403).gesture == .none, "a few points either way is still nothing")
    check(drag.moved(x: 200, y: 407).gesture == .none, "just under the slack, still nothing")
    check(drag.moved(x: 200, y: 409).gesture == .pinning, "past it, the larger axis takes over")
  }

  static func testDraggingDownClosesThePinInProportion() {
    var drag = CoverDrag()
    drag.began(x: 200, y: 400)
    check(drag.moved(x: 200, y: 460).closed == 0.5, "half the travel closes half the ring")
    let full = drag.moved(x: 200, y: 520)
    check(full.closed == 1, "the whole travel closes it")
    check(full.armed, "and arms it")
    check(drag.promise == .pinning, "lifting now pins")
  }

  /// The buzz is a transition, not a state. A thumb resting at the far end of
  /// the travel would otherwise buzz on every touch event it produces.
  static func testTheRingArmsOnceNoMatterHowLongYouSitThere() {
    var drag = CoverDrag()
    drag.began(x: 200, y: 400)
    check(drag.moved(x: 200, y: 530).justArmed, "closing the ring says so")
    check(!drag.moved(x: 200, y: 540).justArmed, "staying closed does not say it again")
    check(!drag.moved(x: 200, y: 600).justArmed, "nor does going further")
  }

  /// Backing out. The whole reason nothing acts until the finger lifts.
  static func testDraggingBackOpensTheRingAndTakesThePromiseBack() {
    var drag = CoverDrag()
    drag.began(x: 200, y: 400)
    _ = drag.moved(x: 200, y: 530)
    check(drag.promise == .pinning, "closed, so lifting would pin")
    let backedOut = drag.moved(x: 200, y: 440)
    check(!backedOut.armed, "coming back up disarms it")
    check(drag.promise == .none, "and lifting now does nothing")
    check(drag.moved(x: 200, y: 530).justArmed, "going back out arms it again, and says so")
  }

  /// Up is not a shorter way to pin. Coming back toward the origin has to mean
  /// backing out, or there is no way to change your mind.
  static func testDraggingUpClosesNothing() {
    var drag = CoverDrag()
    drag.began(x: 200, y: 400)
    let up = drag.moved(x: 200, y: 200)
    check(up.gesture == .none, "two hundred points up is not a gesture")
    check(up.closed == 0, "and closes nothing")
  }

  static func testDraggingSidewaysClosesTheShorterRing() {
    var drag = CoverDrag()
    drag.began(x: 200, y: 400)
    check(drag.moved(x: 230, y: 400).closed == 0.5, "half of sixty is half the ring")
    check(drag.moved(x: 260, y: 400).armed, "sixty arms it")
    check(drag.promise == .skipping, "lifting now goes to the app")
  }

  /// Either way sideways. There is no convention to guess here, only a thumb.
  static func testSidewaysCountsInBothDirections() {
    var drag = CoverDrag()
    drag.began(x: 200, y: 400)
    check(drag.moved(x: 140, y: 400).armed, "sixty to the left arms it too")
  }

  /// The bug the screenshot caught: the ring answering one axis while the glyph
  /// answered the other. One gesture at a time, and the larger axis owns it.
  static func testTheLargerAxisOwnsTheDrag() {
    var drag = CoverDrag()
    drag.began(x: 200, y: 400)
    check(drag.moved(x: 260, y: 420).gesture == .skipping, "sideways leads, sideways owns it")
    let turned = drag.moved(x: 260, y: 500)
    check(turned.gesture == .pinning, "going further down hands it over")
    check(turned.changed, "and says the gesture changed, so the glyph can follow")
    check(!turned.armed, "the promise made by the other gesture does not carry across")
  }

  /// Diagonals are decided, not refused.
  static func testAPerfectDiagonalGoesToThePin() {
    var drag = CoverDrag()
    drag.began(x: 200, y: 400)
    check(drag.moved(x: 250, y: 450).gesture == .pinning,
          "with neither axis ahead, the one that asks for more wins")
  }

  /// The drag that leaves a cover already pinned: sideways is the only question
  /// worth asking, because it is already doing what pinning would ask for.
  static func testTheExitDragNeverPins() {
    var drag = CoverDrag(canPin: false)
    drag.began(x: 0, y: 0)
    check(drag.moved(x: 0, y: 300).gesture == .none, "dragging down a pinned cover asks for nothing")
    check(drag.moved(x: 70, y: 300).gesture == .skipping,
          "and sideways still leaves, even against more vertical travel")
  }

  /// A gesture belongs to the touch that started it.
  static func testAReadingBeforeAnyOriginIsNothing() {
    var drag = CoverDrag()
    check(drag.moved(x: 200, y: 900).gesture == .none, "no origin, no gesture")
    check(drag.promise == .none, "and nothing promised")
  }

  static func testEndingForgetsEverything() {
    var drag = CoverDrag()
    drag.began(x: 200, y: 400)
    _ = drag.moved(x: 200, y: 530)
    drag.end()
    check(drag.promise == .none, "ending drops the promise")
    check(drag.moved(x: 200, y: 530).gesture == .none, "and the origin with it")
  }

  static func main() {
    testOpensWhenDurationRunsOut()
    testInstantStillFreezesUnderAFinger()
    testPressDuringTheDurationHolds()
    testReleasingWithoutAGestureLeavesTheClockOwing()
    testASidewaysDragOpensEarly()
    testRestampingDropsTheTickFromBeforeAHold()
    testCancelledTouchGoesBackToTheClock()
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
    testATokenKnowsWhichRelayItBelongsTo()
    testResetStalesEveryToken()

    testNothingInterruptedResumesNothing()
    testAnUnfinishedCountdownResumesWithWhatWasLeft()
    testAPinnedCoverResumesHoweverLongItTakes()
    testARestingFingerIsRememberedAsHeldRatherThanPinned()
    testAHeldCoverAlsoResumesHoweverLongItTakes()
    testAStaleCountdownIsDroppedRatherThanResumed()
    testAStaleCountdownIsConsumedToo()
    testResumingConsumesTheOffer()
    testClearDropsTheOffer()
    testACountdownFromTheFutureIsRefused()

    testAStillFingerPromisesNothing()
    testTremorIsNotAGesture()
    testDraggingDownClosesThePinInProportion()
    testTheRingArmsOnceNoMatterHowLongYouSitThere()
    testDraggingBackOpensTheRingAndTakesThePromiseBack()
    testDraggingUpClosesNothing()
    testDraggingSidewaysClosesTheShorterRing()
    testSidewaysCountsInBothDirections()
    testTheLargerAxisOwnsTheDrag()
    testAPerfectDiagonalGoesToThePin()
    testTheExitDragNeverPins()
    testAReadingBeforeAnyOriginIsNothing()
    testEndingForgetsEverything()

    print("")
    if failures == 0 {
      print("relay gate: all cases pass")
      exit(0)
    }
    print("relay gate: \(failures) failing")
    exit(1)
  }
}

import Foundation
import Testing
@testable import DodoLicense

@MainActor
@Suite("Trial")
struct TrialTests {
    let store = InMemoryStore()
    let clock = TestClock()

    func trial() -> Trial {
        Trial(length: .seconds(7 * 86_400), store: store, now: { clock.now })
    }

    @Test func aFreshTrialHasSevenDays() {
        #expect(trial().daysLeft == 7)
    }

    @Test func daysRoundUp_soATrialStartedThisMorningStillReadsSeven() {
        let trial = trial()
        clock.advance(hours: 10)

        #expect(trial.daysLeft == 7)
    }

    @Test func itsEndingSoonWithTwoDaysOrFewerLeft() {
        let trial = trial()
        clock.advance(days: 4.5)
        #expect(!trial.isEndingSoon)

        clock.advance(days: 1)
        #expect(trial.daysLeft == 2)
        #expect(trial.isEndingSoon)
    }

    @Test func afterSevenDaysItHasEnded() {
        let trial = trial()
        clock.advance(days: 7)

        #expect(trial.daysLeft == 0)
        #expect(trial.hasEnded)
        #expect(!trial.isEndingSoon)
    }

    @Test func reinstallingDoesntRestartIt() {
        _ = trial()
        clock.advance(days: 3)

        // A reinstall finds the same Keychain item.
        let reinstalled = trial()

        #expect(reinstalled.daysLeft == 4)
    }

    @Test func settingTheClockBackDoesntAddDays() {
        let trial = trial()
        clock.advance(days: 6)
        #expect(trial.daysLeft == 1)

        clock.advance(days: -5)

        #expect(trial.daysLeft == 1)
    }

    @Test func aStartDateThatCantBeReadIsntSavedOver() {
        _ = trial()
        let saved = store.items["trial-start"]
        clock.advance(days: 3)

        store.failsReads = true
        _ = trial()

        #expect(store.items["trial-start"] == saved)
    }

    @Test func settingTheClockBackDoesntHelpAfterARelaunchEither() {
        let first = trial()
        clock.advance(days: 6)
        _ = first.daysLeft  // seen, and saved

        clock.advance(days: -5)
        let relaunched = trial()

        #expect(relaunched.daysLeft == 1)
    }
}

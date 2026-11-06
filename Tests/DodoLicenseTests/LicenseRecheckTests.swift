import Foundation
import Testing
@testable import DodoLicense

@MainActor
@Suite("Daily rechecks")
struct LicenseRecheckTests {
    let provider = StubProvider()
    let clock = TestClock()

    /// An active license, last checked at the clock's current time.
    func activeLicense() async throws -> License {
        let license = License.testing(provider: provider, clock: clock)
        try await license.activate("KEY-1")
        return license
    }

    @Test func noRecheckUntilADayHasPassed() async throws {
        let license = try await activeLicense()
        clock.advance(hours: 23)

        await license.refreshIfDue()

        #expect(await provider.validateCount == 0)
    }

    @Test func aRecheckOnceADayHasPassed() async throws {
        let license = try await activeLicense()
        clock.advance(days: 1)

        await license.refreshIfDue()

        #expect(await provider.validateCount == 1)
        #expect(license.isActive)
    }

    @Test func aGoodRecheckPutsTheNextOneADayLater() async throws {
        let license = try await activeLicense()
        clock.advance(days: 1)
        await license.refreshIfDue()

        clock.advance(hours: 12)
        await license.refreshIfDue()

        #expect(await provider.validateCount == 1)
    }

    @Test func aLastCheckInTheFutureCountsAsDue() async throws {
        // Activated while the clock was a year ahead, then the clock was fixed.
        clock.advance(days: 365)
        let license = try await activeLicense()
        clock.advance(days: -365)

        await license.refreshIfDue()

        #expect(await provider.validateCount == 1)
    }

    @Test func aRevokedLicenseTurnsOffAndTellsTheApp() async throws {
        let license = try await activeLicense()
        var wasTold = false
        license.onRevoke = { wasTold = true }
        await provider.set(validate: .success(.revoked))
        clock.advance(days: 1)

        await license.refreshIfDue()

        #expect(license.state == .unlicensed)
        #expect(wasTold)
    }

    @Test(arguments: [ProviderError.unreachable, .server(status: 500, message: nil), .server(status: 429, message: nil)])
    func answersThatSayNothingAboutTheKeyKeepItActive(error: ProviderError) async throws {
        let license = try await activeLicense()
        await provider.set(validate: .failure(error))
        clock.advance(days: 30)

        await license.refreshIfDue()

        #expect(license.isActive)
    }

    @Test func afterAFailedRecheckItTriesAgainNextTime() async throws {
        let license = try await activeLicense()
        await provider.set(validate: .failure(.unreachable))
        clock.advance(days: 1)
        await license.refreshIfDue()

        clock.advance(hours: 1)
        await license.refreshIfDue()

        #expect(await provider.validateCount == 2)
    }

    @Test func deactivatingDoesntCallOnRevoke() async throws {
        let license = try await activeLicense()
        var wasTold = false
        license.onRevoke = { wasTold = true }

        try await license.deactivate()

        #expect(!wasTold)
    }
}

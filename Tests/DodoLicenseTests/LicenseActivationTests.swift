import Foundation
import Testing
@testable import DodoLicense

@MainActor
@Suite("Activating and deactivating")
struct LicenseActivationTests {
    @Test func aValidKeyIsStoredAndTheLicenseBecomesActive() async throws {
        let store = InMemoryStore()
        let license = License.testing(store: store)

        try await license.activate("KEY-1")

        #expect(license.state == .active(key: "KEY-1"))
        #expect(store.items["license"] != nil)
    }

    @Test func pastedKeysAreCleanedBeforeTheyReachTheStore() async throws {
        let provider = StubProvider()
        let license = License.testing(provider: provider)

        try await license.activate("  KEY\u{2013}1\u{200B}\n")

        #expect(await provider.activatedKeys == ["KEY-1"])
    }

    @Test func anEmptyKeyIsRejectedWithoutAsking() async {
        let provider = StubProvider()
        let license = License.testing(provider: provider)

        await #expect(throws: LicenseError.notFound) { try await license.activate(" \n ") }
        #expect(await provider.activatedKeys.isEmpty)
    }

    @Test(arguments: [
        (ProviderError.keyNotFound, LicenseError.notFound),
        (.keyInactive, .inactive),
        (.activationLimitReached, .inUseElsewhere),
        (.wrongProduct, .wrongProduct),
        (.unreachable, .offline),
        (.server(status: 500, message: "Boom"), .server(status: 500, message: "Boom")),
    ])
    func storeErrorsBecomeErrorsForTheUser(providerError: ProviderError, expected: LicenseError) async {
        let provider = StubProvider()
        await provider.set(activate: .failure(providerError))
        let license = License.testing(provider: provider)

        await #expect(throws: expected) { try await license.activate("KEY-1") }
        #expect(license.state == .unlicensed)
    }

    @Test func whenTheKeychainWontSave_theActivationIsGivenBackAndNothingIsKept() async {
        let provider = StubProvider()
        let store = InMemoryStore()
        store.failsWrites = true
        let license = License.testing(provider: provider, store: store)

        await #expect(throws: LicenseError.keychainFailed) { try await license.activate("KEY-1") }

        #expect(await provider.deactivated == [Activation(key: "KEY-1", instanceID: "lki_1")])
        #expect(store.items.isEmpty)
        #expect(license.state == .unlicensed)
    }

    @Test func aStoredLicenseIsActiveOnTheNextLaunch() async throws {
        let store = InMemoryStore()
        try await License.testing(store: store).activate("KEY-1")

        let relaunched = License.testing(store: store)

        #expect(relaunched.state == .active(key: "KEY-1"))
    }

    @Test func deactivatingFreesTheActivationAndForgetsTheKey() async throws {
        let provider = StubProvider()
        let store = InMemoryStore()
        let license = License.testing(provider: provider, store: store)
        try await license.activate("KEY-1")

        try await license.deactivate()

        #expect(await provider.deactivated == [Activation(key: "KEY-1", instanceID: "lki_1")])
        #expect(license.state == .unlicensed)
        #expect(store.items.isEmpty)
    }

    @Test func deactivatingOffline_keepsTheLicense() async throws {
        let provider = StubProvider()
        let license = License.testing(provider: provider)
        try await license.activate("KEY-1")
        await provider.set(deactivate: .failure(.unreachable))

        await #expect(throws: LicenseError.offline) { try await license.deactivate() }

        #expect(license.state == .active(key: "KEY-1"))
    }

    @Test func activatingTheKeyThatsAlreadyActiveDoesNothing() async throws {
        let provider = StubProvider()
        let license = License.testing(provider: provider)
        try await license.activate("KEY-1")

        try await license.activate("KEY-1")

        #expect(await provider.activatedKeys == ["KEY-1"])
    }

    @Test func aSecondActivationWhileOneIsRunningThrowsBusy() async throws {
        let provider = StubProvider()
        await provider.holdActivations()
        let license = License.testing(provider: provider)
        let first = Task { try await license.activate("KEY-1") }
        while await !provider.isHoldingActivation { await Task.yield() }

        await #expect(throws: LicenseError.busy) { try await license.activate("KEY-2") }
        await provider.releaseActivation()
        try await first.value
    }

    /// Otherwise the Deactivate button does nothing, with no word why.
    @Test func deactivatingWhenTheKeychainCantBeReadSaysSo() async throws {
        let store = InMemoryStore()
        let provider = StubProvider()
        let license = License.testing(provider: provider, store: store)
        try await license.activate("KEY-1")
        store.failsReads = true

        await #expect(throws: LicenseError.keychainFailed) { try await license.deactivate() }
        #expect(await provider.deactivated.isEmpty)
        #expect(store.items["license"] != nil)
    }

    /// A Keychain locked at launch, or a denied access prompt, isn't "no license".
    @Test func aKeychainThatCantBeReadDoesntLookLikeNoLicense() async throws {
        let store = InMemoryStore()
        try await License.testing(store: store).activate("KEY-1")
        store.failsReads = true

        let launchedLocked = License.testing(store: store)
        #expect(launchedLocked.state == .unlicensed)  // nothing to show yet, but nothing was deleted
        #expect(store.items["license"] != nil)

        store.failsReads = false
        await launchedLocked.refreshIfDue()
        #expect(launchedLocked.state == .active(key: "KEY-1"))
    }

    @Test func everyErrorHasASentenceForTheUser() {
        let errors: [LicenseError] = [.notFound, .inactive, .inUseElsewhere, .wrongProduct, .keychainFailed, .offline, .server(status: 500, message: nil), .busy]
        for error in errors {
            #expect(error.errorDescription?.isEmpty == false)
        }
    }
}

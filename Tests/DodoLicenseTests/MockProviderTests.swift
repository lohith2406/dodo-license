import Testing
@testable import DodoLicense

@Suite("Mock provider")
struct MockProviderTests {
    let mock = MockProvider(latency: .zero)

    @Test func validKeysActivateAndStayValid() async throws {
        let activation = try await mock.activate(key: "valid-1234", deviceName: "Mac")

        #expect(try await mock.validate(activation) == .valid)
    }

    @Test func refundedKeysActivateThenRevoke() async throws {
        let activation = try await mock.activate(key: "REFUNDED-1", deviceName: "Mac")

        #expect(try await mock.validate(activation) == .revoked)
    }

    @Test(arguments: [
        ("USED-1", ProviderError.activationLimitReached),
        ("INACTIVE-1", .keyInactive),
        ("OTHER-1", .wrongProduct),
        ("NOPE-1", .keyNotFound),
    ])
    func otherKeysFailTheWayTheirNameSays(key: String, expected: ProviderError) async {
        await #expect(throws: expected) { try await mock.activate(key: key, deviceName: "Mac") }
    }

    @Test func offlineEverythingIsUnreachable() async {
        await mock.setOffline(true)

        await #expect(throws: ProviderError.unreachable) { try await mock.activate(key: "VALID-1", deviceName: "Mac") }
    }
}

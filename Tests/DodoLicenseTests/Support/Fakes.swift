import Foundation
@testable import DodoLicense

/// A Keychain in memory. `failsReads` and `failsWrites` act like a locked Keychain, or one
/// whose access prompt the user denied.
@MainActor
final class InMemoryStore: SecretStore {
    var items: [String: Data] = [:]
    var failsReads = false
    var failsWrites = false

    func read(_ account: String) -> Stored<Data> {
        if failsReads { return .unreadable }
        return items[account].map(Stored.found) ?? .missing
    }

    func write(_ data: Data, for account: String) -> Bool {
        guard !failsWrites else { return false }
        items[account] = data
        return true
    }

    func delete(_ account: String) { items[account] = nil }
}

/// A clock the test moves by hand.
@MainActor
final class TestClock {
    var now = Date(timeIntervalSince1970: 1_800_000_000)

    func advance(days: Double) { now.addTimeInterval(days * 86_400) }
    func advance(hours: Double) { now.addTimeInterval(hours * 3600) }
}

/// A provider whose answers each test sets, and which records what it was asked.
actor StubProvider: LicenseProvider {
    nonisolated let storageScope = "stub"

    var activateResult: Result<Activation, ProviderError> = .success(Activation(key: "KEY-1", instanceID: "lki_1"))
    var validateResult: Result<Validity, ProviderError> = .success(.valid)
    var deactivateResult: Result<Void, ProviderError> = .success(())

    private(set) var activatedKeys: [String] = []
    private(set) var validateCount = 0
    private(set) var deactivated: [Activation] = []

    func set(activate: Result<Activation, ProviderError>) { activateResult = activate }
    func set(validate: Result<Validity, ProviderError>) { validateResult = validate }
    func set(deactivate: Result<Void, ProviderError>) { deactivateResult = deactivate }

    /// When set, `activate` waits for `releaseActivation()`, so a test can act mid-activation.
    private var holdsActivations = false
    private var heldActivation: CheckedContinuation<Void, Never>?
    var isHoldingActivation: Bool { heldActivation != nil }

    func holdActivations() { holdsActivations = true }

    func releaseActivation() {
        heldActivation?.resume()
        heldActivation = nil
    }

    func activate(key: String, deviceName: String) async throws(ProviderError) -> Activation {
        activatedKeys.append(key)
        if holdsActivations {
            await withCheckedContinuation { heldActivation = $0 }
        }
        return try activateResult.get()
    }

    func validate(_ activation: Activation) async throws(ProviderError) -> Validity {
        validateCount += 1
        return try validateResult.get()
    }

    func deactivate(_ activation: Activation) async throws(ProviderError) {
        deactivated.append(activation)
        try deactivateResult.get()
    }
}

/// Replays recorded Dodo answers, one per endpoint, and keeps every request it was sent.
actor FakeTransport: HTTPTransport {
    struct Request: Sendable {
        var url: URL
        var body: [String: String]
    }

    private var responses: [String: HTTPResponse] = [:]
    private var isOffline = false
    private(set) var requests: [Request] = []

    /// Answers requests to `/licenses/<action>` with `status` and `json`.
    func respond(to action: String, status: Int, json: String = "{}") {
        responses[action] = HTTPResponse(status: status, body: Data(json.utf8))
    }

    func goOffline() { isOffline = true }

    func post(_ url: URL, body: Data) async throws -> HTTPResponse {
        requests.append(Request(url: url, body: (try? JSONDecoder().decode([String: String].self, from: body)) ?? [:]))
        if isOffline { throw URLError(.notConnectedToInternet) }
        guard let response = responses[url.lastPathComponent] else { throw URLError(.badURL) }
        return response
    }
}

extension License {
    /// A license on a stub provider, an in-memory Keychain and a test clock.
    static func testing(
        provider: StubProvider = StubProvider(),
        store: InMemoryStore = InMemoryStore(),
        clock: TestClock = TestClock()
    ) -> License {
        License(provider: provider, store: store, checkInterval: .seconds(86_400), deviceName: { "Test Mac" }, now: { clock.now })
    }
}

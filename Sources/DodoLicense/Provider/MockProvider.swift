import Foundation

/// A pretend store, for building and previewing your license screens without buying a key.
/// No network is involved. What a key does depends on how it starts:
///
/// | Key starts with | Activate | Recheck |
/// |---|---|---|
/// | `VALID-` | works | valid |
/// | `REFUNDED-` | works | revoked, so the license turns off |
/// | `USED-` | activation limit reached | |
/// | `INACTIVE-` | key inactive | |
/// | `OTHER-` | key for another product | |
/// | anything else | key not found | |
///
/// Turn on `isOffline` to see how your app behaves with no connection.
public actor MockProvider: LicenseProvider {
    public nonisolated let storageScope = "mock"
    private let latency: Duration
    private var isOffline: Bool

    /// - Parameters:
    ///   - latency: How long each request pretends to take, so spinners show. `.zero` in tests.
    ///   - isOffline: Every request fails as if there were no connection.
    public init(latency: Duration = .milliseconds(400), isOffline: Bool = false) {
        self.latency = latency
        self.isOffline = isOffline
    }

    /// Switches the pretend connection off or back on.
    public func setOffline(_ isOffline: Bool) {
        self.isOffline = isOffline
    }

    public func activate(key: String, deviceName: String) async throws(ProviderError) -> Activation {
        try await respond()
        switch Self.kind(of: key) {
        case "VALID", "REFUNDED": return Activation(key: key, instanceID: "mock_\(UUID().uuidString)")
        case "USED": throw .activationLimitReached
        case "INACTIVE": throw .keyInactive
        case "OTHER": throw .wrongProduct
        default: throw .keyNotFound
        }
    }

    public func validate(_ activation: Activation) async throws(ProviderError) -> Validity {
        try await respond()
        return Self.kind(of: activation.key) == "REFUNDED" ? .revoked : .valid
    }

    public func deactivate(_ activation: Activation) async throws(ProviderError) {
        try await respond()
    }

    /// Waits like a real request would, then fails if offline.
    private func respond() async throws(ProviderError) {
        if latency > .zero {
            try? await Task.sleep(for: latency)
        }
        if isOffline {
            throw .unreachable
        }
    }

    /// The part before the first dash, upper-cased: "valid-1234" is "VALID".
    private static func kind(of key: String) -> String {
        String(key.prefix(while: { $0 != "-" })).uppercased()
    }
}

/// The part of licensing that talks to a store: activate a key on this Mac, check it, free it.
///
/// `License` does everything else (storage, daily rechecks, offline handling, errors), so a
/// provider only maps its store's HTTP answers onto these few results. The package ships
/// `DodoProvider` for Dodo Payments and `MockProvider` for trying things out without a key.
public protocol LicenseProvider: Sendable {
    /// Keeps this provider's stored license apart from others', so a test-mode key never
    /// shows up in a live build. Becomes part of the default Keychain service name.
    var storageScope: String { get }

    /// Activates `key` on this Mac, after checking it belongs to this app's product.
    func activate(key: String, deviceName: String) async throws(ProviderError) -> Activation

    /// Whether the activation is still good.
    ///
    /// Return `.revoked` only for a clear "not valid" or "not found" from the store. Anything
    /// that says nothing about the key (no connection, a server error, a rate limit) must
    /// throw instead, because `License` turns itself off on `.revoked` alone.
    func validate(_ activation: Activation) async throws(ProviderError) -> Validity

    /// Frees this Mac's activation so the key can be used on another Mac. An activation that
    /// is already gone counts as success.
    func deactivate(_ activation: Activation) async throws(ProviderError)
}

/// A key activated on this Mac, and what's needed to check or free it later.
public struct Activation: Codable, Sendable, Equatable {
    public var key: String
    /// The store's ID for this Mac's activation (Dodo's `lki_…`).
    public var instanceID: String

    public init(key: String, instanceID: String) {
        self.key = key
        self.instanceID = instanceID
    }
}

/// The answer to a recheck.
public enum Validity: Sendable, Equatable {
    case valid
    /// Refunded, expired, or deactivated from the store's side.
    case revoked
}

/// What can go wrong talking to a store, before it's turned into words for the user.
public enum ProviderError: Error, Sendable, Equatable {
    /// The store doesn't know this key.
    case keyNotFound
    /// The key exists but isn't active: refunded, expired or disabled.
    case keyInactive
    /// The key's activation limit is used up.
    case activationLimitReached
    /// The key is real but for another product.
    case wrongProduct
    /// No answer arrived: offline, a timeout, DNS. Says nothing about the key.
    case unreachable
    /// An answer this package didn't expect, with the store's own message if it sent one.
    case server(status: Int, message: String?)
}

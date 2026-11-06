import Foundation

/// Why activating or deactivating failed. `errorDescription` is a sentence you can show as is.
public enum LicenseError: Error, Equatable, Sendable, LocalizedError {
    /// No such key, or the field was empty. Usually a copying mistake.
    case notFound
    /// The key exists but was refunded, expired or disabled.
    case inactive
    /// The key's activation limit is used up, by another Mac or a lost one.
    case inUseElsewhere
    /// The key is for another product.
    case wrongProduct
    /// The Keychain wouldn't save the key (its activation was given back), or couldn't be
    /// read to deactivate it.
    case keychainFailed
    /// No answer from the license server: offline, a timeout, DNS.
    case offline
    /// An answer this package didn't expect, with the server's message if it sent one.
    case server(status: Int, message: String?)
    /// Another activation or deactivation is still running.
    case busy

    init(_ error: ProviderError) {
        switch error {
        case .keyNotFound: self = .notFound
        case .keyInactive: self = .inactive
        case .activationLimitReached: self = .inUseElsewhere
        case .wrongProduct: self = .wrongProduct
        case .unreachable: self = .offline
        case .server(let status, let message): self = .server(status: status, message: message)
        }
    }

    public var errorDescription: String? {
        switch self {
        case .notFound:
            "That key wasn't found. Copy it again from your purchase email."
        case .inactive:
            "That key is no longer active. It may have been refunded or expired."
        case .inUseElsewhere:
            "That key is already in use on another Mac. Deactivate it there, then try again. If you no longer have that Mac, contact support to free the key."
        case .wrongProduct:
            "That key is for a different app."
        case .keychainFailed:
            "Your Keychain couldn't be used. Unlock Keychain Access or allow access when asked, then try again."
        case .offline:
            "Couldn't reach the license server. Check your connection and try again."
        case .server(let status, let message):
            message ?? "The license server had a problem (error \(status)). Try again in a moment."
        case .busy:
            "Still working on the last request. Try again in a moment."
        }
    }
}

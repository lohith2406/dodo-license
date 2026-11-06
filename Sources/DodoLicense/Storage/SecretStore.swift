import Foundation
import Security

/// Where the license and the trial dates are kept. The real one is the Keychain; the tests
/// use an in-memory one, so they can also make reading or saving fail.
@MainActor
protocol SecretStore {
    func read(_ account: String) -> Stored<Data>
    /// Returns false when the value couldn't be saved.
    func write(_ data: Data, for account: String) -> Bool
    func delete(_ account: String)
}

/// The result of reading the store. "Nothing saved" and "couldn't read" are kept apart:
/// treating a locked Keychain as "no license" would lock out a paying user.
enum Stored<Value> {
    case found(Value)
    case missing
    case unreadable
}

/// Generic passwords in the user's login Keychain, one item per account under `service`.
struct KeychainStore: SecretStore {
    let service: String

    func read(_ account: String) -> Stored<Data> {
        var query = baseQuery(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        switch SecItemCopyMatching(query as CFDictionary, &result) {
        case errSecSuccess: return (result as? Data).map(Stored.found) ?? .unreadable
        case errSecItemNotFound: return .missing
        default: return .unreadable
        }
    }

    /// Updates the item in place and only adds one if there's none. Deleting first and then
    /// adding would lose the old value whenever the add fails.
    func write(_ data: Data, for account: String) -> Bool {
        let update = SecItemUpdate(baseQuery(account) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if update == errSecSuccess { return true }
        guard update == errSecItemNotFound else { return false }
        var query = baseQuery(account)
        query[kSecValueData as String] = data
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    func delete(_ account: String) {
        SecItemDelete(baseQuery(account) as CFDictionary)
    }

    private func baseQuery(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}

extension SecretStore {
    /// Reads and decodes a value. Data that no longer decodes counts as missing.
    func lookUp<Value: Decodable>(_ type: Value.Type, at account: String) -> Stored<Value> {
        switch read(account) {
        case .found(let data):
            guard let value = try? JSONDecoder().decode(Value.self, from: data) else { return .missing }
            return .found(value)
        case .missing: return .missing
        case .unreadable: return .unreadable
        }
    }

    func write(_ value: some Encodable, for account: String) -> Bool {
        guard let data = try? JSONEncoder().encode(value) else { return false }
        return write(data, for: account)
    }
}

/// The app's bundle ID, for default Keychain service names.
let appIdentifier = Bundle.main.bundleIdentifier ?? "DodoLicense"

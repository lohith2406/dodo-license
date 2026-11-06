import Foundation
import SystemConfiguration

/// A license key activated on this Mac.
///
/// ```swift
/// let license = License(productID: "pdt_…", environment: .live)
/// license.start()
/// try await license.activate(keyFromTextField)
/// ```
///
/// The key and this Mac's activation are kept in the Keychain, so the app stays licensed
/// offline, for as long as it needs to. Once a day has passed since the last good check, it
/// asks the store whether the key is still good, and only a clear "no" (a refund, an expired
/// key, a deactivation on the web) turns it off. No connection, a server error or a rate
/// limit change nothing.
@MainActor
@Observable
public final class License {
    /// Whether this Mac has a license.
    public enum State: Equatable, Sendable {
        case unlicensed
        /// Activated on this Mac with `key`.
        case active(key: String)
    }

    public private(set) var state: State
    /// True while an activation or deactivation is running, for a spinner.
    public private(set) var isWorking = false

    /// Whether the app should unlock. The same as `state` being `.active`.
    public var isActive: Bool {
        if case .active = state { true } else { false }
    }

    /// Called when a recheck finds the license revoked and turns it off, so the app can tell
    /// the user. Not called when the user deactivates.
    @ObservationIgnored public var onRevoke: (@MainActor () -> Void)?

    private let provider: any LicenseProvider
    private let store: any SecretStore
    private let checkInterval: TimeInterval
    private let deviceName: @MainActor () -> String
    private let now: @MainActor () -> Date
    @ObservationIgnored private var recheckTask: Task<Void, Never>?
    @ObservationIgnored private var isChecking = false

    private static let account = "license"

    /// A license sold through Dodo Payments.
    ///
    /// - Parameters:
    ///   - productID: Your product's ID in Dodo (`pdt_…`). Keys for other products are refused.
    ///   - environment: `.test` for test-mode keys while developing, `.live` for real ones.
    ///   - keychainService: Where the license is kept. Defaults to
    ///     `<bundle ID>.license.dodo.<environment>`, so test and live keys never mix.
    public convenience init(productID: String, environment: DodoEnvironment, keychainService: String? = nil) {
        self.init(productIDs: [productID], environment: environment, keychainService: keychainService)
    }

    /// A license sold through Dodo Payments as any of several products, such as a lifetime
    /// plan and a discounted one that both carry the same license key entitlement.
    public convenience init(productIDs: Set<String>, environment: DodoEnvironment, keychainService: String? = nil) {
        self.init(provider: DodoProvider(productIDs: productIDs, environment: environment), keychainService: keychainService)
    }

    /// A license from any provider, such as `MockProvider` while you build your screens.
    ///
    /// - Parameter checkInterval: How long a good check lasts before the next one. A day by default.
    public convenience init(
        provider: some LicenseProvider,
        keychainService: String? = nil,
        checkInterval: Duration = .seconds(24 * 3600)
    ) {
        self.init(
            provider: provider,
            store: KeychainStore(service: keychainService ?? "\(appIdentifier).license.\(provider.storageScope)"),
            checkInterval: checkInterval,
            deviceName: Self.computerName,
            now: { Date() }
        )
    }

    init(
        provider: any LicenseProvider,
        store: any SecretStore,
        checkInterval: Duration,
        deviceName: @escaping @MainActor () -> String,
        now: @escaping @MainActor () -> Date
    ) {
        self.provider = provider
        self.store = store
        self.checkInterval = checkInterval.timeInterval
        self.deviceName = deviceName
        self.now = now
        state = .unlicensed
        reloadState()
    }

    // MARK: Activating

    /// Activates a key on this Mac and keeps it. The key is cleaned first (see `LicenseKey.clean`).
    ///
    /// Activating the key that's already active does nothing. Activating a different key
    /// replaces the license without freeing the old activation; deactivate first if that
    /// matters. Throws `.busy` while another activation or deactivation is running.
    public func activate(_ input: String) async throws(LicenseError) {
        let key = LicenseKey.clean(input)
        guard !key.isEmpty else { throw .notFound }
        guard !isWorking else { throw .busy }
        guard state != .active(key: key) else { return }
        isWorking = true
        defer { isWorking = false }

        let activation: Activation
        do {
            activation = try await provider.activate(key: key, deviceName: deviceName())
        } catch {
            throw LicenseError(error)
        }

        // If the Keychain won't keep it, give the activation back. Otherwise the key stays
        // used up on the store with nothing on this Mac to free it.
        guard store.write(StoredLicense(activation: activation, lastChecked: now()), for: Self.account) else {
            store.delete(Self.account)
            try? await provider.deactivate(activation)
            throw .keychainFailed
        }
        state = .active(key: key)
    }

    /// Frees this Mac's activation, so the key can be used on another Mac, and forgets the key.
    /// Offline, it throws and the license stays as it was. Does nothing when there's no license.
    /// Throws `.keychainFailed` when the Keychain can't be read (locked since launch, say), as
    /// there's then no activation to free and doing nothing would look like a broken button.
    public func deactivate() async throws(LicenseError) {
        guard !isWorking else { throw .busy }
        let stored: StoredLicense
        switch storedLicense {
        case .found(let found): stored = found
        case .missing: return
        case .unreadable: throw .keychainFailed
        }
        isWorking = true
        defer { isWorking = false }

        do {
            try await provider.deactivate(stored.activation)
        } catch {
            throw LicenseError(error)
        }
        forget()
    }

    // MARK: Rechecking

    /// Call once at launch. Looks every hour while the app runs, and asks the store once a
    /// day has passed since the last good check (straight away, if it already has).
    public func start() {
        guard recheckTask == nil else { return }
        recheckTask = Task { [weak self] in
            while !Task.isCancelled {
                // Holds the license only for the check, not across the hour's sleep.
                do {
                    guard let self else { return }
                    await self.refreshIfDue()
                }
                try? await Task.sleep(for: .seconds(3600))
            }
        }
    }

    /// Stops the hourly look that `start()` began.
    public func stop() {
        recheckTask?.cancel()
        recheckTask = nil
    }

    /// Asks the store about the license if a day has passed since the last good check.
    /// `start()` calls this for you; call it yourself if you'd rather schedule checks.
    public func refreshIfDue() async {
        // Picks up a Keychain that was locked at launch and has since been unlocked.
        reloadState()
        guard case .found(let stored) = storedLicense, isDue(stored.lastChecked), !isChecking else { return }
        isChecking = true
        defer { isChecking = false }

        let validity: Validity
        do {
            validity = try await provider.validate(stored.activation)
        } catch {
            return  // No answer, or one that says nothing about the key: carry on as before.
        }
        // The user may have deactivated or entered another key while this was waiting.
        guard case .found(let current) = storedLicense, current.activation == stored.activation else { return }

        switch validity {
        case .valid:
            _ = store.write(StoredLicense(activation: stored.activation, lastChecked: now()), for: Self.account)
        case .revoked:
            forget()
            onRevoke?()
        }
    }

    /// Due once the interval has passed, or when the last check is in the future, which
    /// means the clock was set ahead at the time and its date can't be trusted.
    private func isDue(_ lastChecked: Date) -> Bool {
        let current = now()
        return lastChecked > current || current.timeIntervalSince(lastChecked) >= checkInterval
    }

    // MARK: Storage

    private var storedLicense: Stored<StoredLicense> {
        store.lookUp(StoredLicense.self, at: Self.account)
    }

    /// Matches `state` to what's stored. A Keychain that can't be read right now (locked, or
    /// access denied) leaves `state` alone rather than calling a paying user unlicensed.
    private func reloadState() {
        switch storedLicense {
        case .found(let stored): state = .active(key: stored.activation.key)
        case .missing: state = .unlicensed
        case .unreadable: break
        }
    }

    private func forget() {
        store.delete(Self.account)
        state = .unlicensed
    }

    /// The Mac's name from System Settings, such as "Lohith's MacBook Pro", to label the
    /// activation in Dodo's dashboard. `Host.current()` can stall on name lookups; this doesn't.
    private static func computerName() -> String {
        (SCDynamicStoreCopyComputerName(nil, nil) as String?) ?? "Mac"
    }
}

/// What's kept in the Keychain: the activation, and when the store last said it was good.
struct StoredLicense: Codable, Equatable {
    var activation: Activation
    var lastChecked: Date
}

extension Duration {
    var timeInterval: TimeInterval {
        Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}

import Foundation

/// A free trial that starts on first launch. Optional, and separate from `License`; combine
/// them yourself:
///
/// ```swift
/// let trial = Trial()                    // 7 days
/// var canUseApp: Bool { license.isActive || !trial.hasEnded }
/// ```
///
/// The start date is kept in the Keychain, so deleting and reinstalling the app doesn't
/// restart the trial, and setting the Mac's clock back doesn't add days. It stops casual
/// restarts, not determined people: deleting the Keychain item resets it.
///
/// The values come from the clock each time you read them, so read them when you show the
/// trial (at launch, or when a window opens) rather than expecting a view to redraw itself.
@MainActor
public final class Trial {
    /// How long the trial lasts.
    public let length: Duration
    /// When the trial started: the first time it was created on this Mac.
    public let startDate: Date

    private let store: any SecretStore
    private let now: @MainActor () -> Date
    /// The latest time seen, so the clock going back never counts.
    private var latestSeen: Date

    private static let startAccount = "trial-start"
    private static let seenAccount = "trial-seen"
    /// The latest time seen is saved at most this often, not on every read.
    private static let seenSaveInterval: TimeInterval = 3600

    /// - Parameters:
    ///   - length: Seven days by default.
    ///   - keychainService: Where the dates are kept. Defaults to `<bundle ID>.trial`.
    public convenience init(length: Duration = .seconds(7 * 86_400), keychainService: String? = nil) {
        self.init(length: length, store: KeychainStore(service: keychainService ?? "\(appIdentifier).trial"), now: { Date() })
    }

    init(length: Duration, store: any SecretStore, now: @escaping @MainActor () -> Date) {
        self.length = length
        self.store = store
        self.now = now
        let current = now()
        switch store.lookUp(Date.self, at: Self.startAccount) {
        case .found(let saved):
            startDate = saved
        case .missing:
            startDate = current
            _ = store.write(current, for: Self.startAccount)
        case .unreadable:
            // Don't save over a start date that's there but can't be read right now.
            startDate = current
        }
        if case .found(let seen) = store.lookUp(Date.self, at: Self.seenAccount) {
            latestSeen = seen
        } else {
            latestSeen = .distantPast
        }
    }

    /// When the trial ends.
    public var endDate: Date { startDate.addingTimeInterval(length.timeInterval) }

    /// Whole days left, rounded up, so a trial started this morning still reads 7. 0 once it's over.
    public var daysLeft: Int {
        let left = endDate.timeIntervalSince(currentTime())
        return max(0, Int((left / 86_400).rounded(.up)))
    }

    /// Whether the trial is over.
    public var hasEnded: Bool { daysLeft == 0 }

    /// One or two days left: a good time to remind the user, once.
    public var isEndingSoon: Bool { (1...2).contains(daysLeft) }

    /// The clock, but never earlier than the latest time seen.
    private func currentTime() -> Date {
        let current = now()
        guard current > latestSeen else { return latestSeen }
        if current.timeIntervalSince(latestSeen) >= Self.seenSaveInterval {
            _ = store.write(current, for: Self.seenAccount)
        }
        latestSeen = current
        return current
    }
}

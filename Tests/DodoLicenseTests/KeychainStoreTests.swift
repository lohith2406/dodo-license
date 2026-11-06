import Foundation
import Testing
@testable import DodoLicense

/// The real Keychain, under a throwaway service name that's removed afterwards.
@MainActor
@Suite("Keychain")
struct KeychainStoreTests {
    let store = KeychainStore(service: "DodoLicenseTests.\(UUID().uuidString)")

    @Test func savingTwiceUpdatesTheItemInPlace() {
        defer { store.delete("item") }

        #expect(store.write(Data("first".utf8), for: "item"))
        #expect(store.write(Data("second".utf8), for: "item"))

        guard case .found(let data) = store.read("item") else {
            Issue.record("The item wasn't found")
            return
        }
        #expect(data == Data("second".utf8))
    }

    @Test func anItemNeverSavedIsMissingNotUnreadable() {
        guard case .missing = store.read("never-saved") else {
            Issue.record("Expected .missing")
            return
        }
    }

    @Test func deletedItemsAreMissing() {
        _ = store.write(Data("value".utf8), for: "item")

        store.delete("item")

        guard case .missing = store.read("item") else {
            Issue.record("Expected .missing")
            return
        }
    }
}

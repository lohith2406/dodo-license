import Foundation
import Testing
@testable import DodoLicense

/// DodoProvider against recorded answers in the shapes Dodo's docs give.
@Suite("Dodo Payments")
struct DodoProviderTests {
    let transport = FakeTransport()
    let activation = Activation(key: "KEY-1", instanceID: "lki_123")

    func provider(environment: DodoEnvironment = .test) -> DodoProvider {
        DodoProvider(productIDs: ["pdt_app", "pdt_app_discount"], environment: environment, transport: transport)
    }

    /// What Dodo's edge sends for a blocked or unknown request: a 403 with an HTML page, not
    /// Dodo's JSON. Recorded from test.dodopayments.com on 2026-11-06.
    static let edgeBlock = #"<!DOCTYPE html><html lang=en><meta charset=utf-8><title>403 Forbidden - Dodo Payments</title></html>"#

    /// Recorded from test.dodopayments.com on 2026-11-06 with a made-up key.
    static let notFound = #"{"code":"NOT_FOUND","message":"The requested resource could not be found. This might be because the ID doesn't exist or the resource has been deleted. Please verify your request parameters and try again."}"#

    /// A 201 from activate, recorded from test.dodopayments.com on 2026-11-06 (IDs shortened).
    static let activated = #"{"id":"lki_123","business_id":"bus_1","name":"Test’s MacBook Air","license_key_id":"lic_1","created_at":"2026-11-06T16:04:25.928642Z","product":{"product_id":"pdt_app","name":"Test App"},"customer":{"customer_id":"cus_1","name":"Test Buyer","email":"buyer@example.com","phone_number":null,"metadata":{}}}"#

    /// The rest recorded from test.dodopayments.com on 2026-11-06 with a test-mode key.
    /// Activating a key that was disabled on Dodo:
    static let inactive = #"{"code":"INACTIVE_LICENSE_KEY","message":"License key is not active"}"#
    /// Activating a key whose one activation is in use:
    static let limitReached = #"{"code":"LICENSE_KEY_LIMIT_REACHED","message":"License key activation limit reached"}"#
    /// Deactivating an instance that was already deactivated:
    static let instanceGone = #"{"code":"LICENSE_KEY_NOT_FOUND","message":"License key instance not found or does not belong to this license key"}"#

    // MARK: Activate

    @Test(arguments: [(DodoEnvironment.test, "https://test.dodopayments.com/licenses/activate"), (.live, "https://live.dodopayments.com/licenses/activate")])
    func activateSendsTheKeyAndMacNameToTheRightServer(environment: DodoEnvironment, url: String) async throws {
        await transport.respond(to: "activate", status: 201, json: Self.activated)

        _ = try await provider(environment: environment).activate(key: "KEY-1", deviceName: "Lohith's Mac")

        let request = try #require(await transport.requests.first)
        #expect(request.url.absoluteString == url)
        #expect(request.body == ["license_key": "KEY-1", "name": "Lohith's Mac"])
    }

    @Test func activateReturnsThisMacsInstance() async throws {
        await transport.respond(to: "activate", status: 201, json: Self.activated)

        let result = try await provider().activate(key: "KEY-1", deviceName: "Mac")

        #expect(result == activation)
    }

    @Test func aKeyForAnotherProductIsGivenBackAndRefused() async throws {
        await transport.respond(to: "activate", status: 201, json: Self.activated.replacingOccurrences(of: "pdt_app", with: "pdt_other"))
        await transport.respond(to: "deactivate", status: 200)

        await #expect(throws: ProviderError.wrongProduct) { try await provider().activate(key: "KEY-1", deviceName: "Mac") }

        let last = try #require(await transport.requests.last)
        #expect(last.url.lastPathComponent == "deactivate")
        #expect(last.body == ["license_key": "KEY-1", "license_key_instance_id": "lki_123"])
    }

    @Test func keysForAnyOfTheAppsProductsAreAccepted() async throws {
        await transport.respond(to: "activate", status: 201, json: Self.activated.replacingOccurrences(of: "pdt_app", with: "pdt_app_discount"))

        let result = try await provider().activate(key: "KEY-1", deviceName: "Mac")

        #expect(result == activation)
    }

    @Test(arguments: [
        (403, inactive, ProviderError.keyInactive),
        (403, edgeBlock, .server(status: 403, message: nil)),   // a firewall block isn't a refund
        (404, notFound, .keyNotFound),
        (422, limitReached, .activationLimitReached),
        (422, "{}", .activationLimitReached),
        (500, #"{"message": "Something went wrong"}"#, .server(status: 500, message: "Something went wrong")),
        (201, "not json", .server(status: 201, message: nil)),
    ])
    func activateMapsDodosAnswers(status: Int, json: String, expected: ProviderError) async {
        await transport.respond(to: "activate", status: status, json: json)

        await #expect(throws: expected) { try await provider().activate(key: "KEY-1", deviceName: "Mac") }
    }

    @Test func activateOfflineIsUnreachable() async {
        await transport.goOffline()

        await #expect(throws: ProviderError.unreachable) { try await provider().activate(key: "KEY-1", deviceName: "Mac") }
    }

    // MARK: Validate

    @Test func validateSendsTheKeyAndInstance() async throws {
        await transport.respond(to: "validate", status: 200, json: #"{"valid": true}"#)

        _ = try await provider().validate(activation)

        let request = try #require(await transport.requests.first)
        #expect(request.body == ["license_key": "KEY-1", "license_key_instance_id": "lki_123"])
    }

    @Test(arguments: [
        (200, #"{"valid": true}"#, Validity.valid),
        // Dodo's answer for a key that doesn't exist, a key disabled on Dodo, and an
        // instance that was deactivated (all recorded on 2026-11-06).
        (200, #"{"valid":false}"#, .revoked),
        (404, notFound, .revoked),
        (404, #"{"code": "LICENSE_KEY_NOT_FOUND", "message": "Not found"}"#, .revoked),
        (404, #"{"code": "LICENSE_KEY_INSTANCE_NOT_FOUND", "message": "Not found"}"#, .revoked),
    ])
    func validateReadsClearAnswers(status: Int, json: String, expected: Validity) async throws {
        await transport.respond(to: "validate", status: status, json: json)

        #expect(try await provider().validate(activation) == expected)
    }

    @Test(arguments: [(404, ""), (500, "{}"), (429, "{}"), (502, "<html>Bad gateway</html>")])
    func validateNeverRevokesOnAnswersThatSayNothingAboutTheKey(status: Int, body: String) async {
        await transport.respond(to: "validate", status: status, json: body)

        await #expect(throws: ProviderError.self) { try await provider().validate(activation) }
    }

    @Test func validateOfflineIsUnreachable() async {
        await transport.goOffline()

        await #expect(throws: ProviderError.unreachable) { try await provider().validate(activation) }
    }

    // MARK: Deactivate

    @Test(arguments: [
        (200, ""),   // what Dodo sends
        (200, "{}"),
        (403, instanceGone),
        (404, notFound),
    ])
    func deactivateSucceedsWhenTheActivationIsFreedOrAlreadyGone(status: Int, json: String) async throws {
        await transport.respond(to: "deactivate", status: status, json: json)

        try await provider().deactivate(activation)
    }

    /// Otherwise the key is wiped on this Mac while Dodo still counts the activation, and the
    /// user can't free it from the next Mac.
    @Test func aBlockedDeactivateIsAnErrorNotAlreadyGone() async {
        await transport.respond(to: "deactivate", status: 403, json: Self.edgeBlock)

        await #expect(throws: ProviderError.server(status: 403, message: nil)) { try await provider().deactivate(activation) }
    }

    @Test func deactivateFailsOnAServerError() async {
        await transport.respond(to: "deactivate", status: 500)

        await #expect(throws: ProviderError.server(status: 500, message: nil)) { try await provider().deactivate(activation) }
    }

    @Test func testAndLiveAreStoredApart() {
        #expect(provider(environment: .test).storageScope != provider(environment: .live).storageScope)
    }
}

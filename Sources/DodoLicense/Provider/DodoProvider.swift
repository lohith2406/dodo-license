import Foundation

/// Which Dodo Payments server to talk to. Test-mode keys only work against `.test`.
public enum DodoEnvironment: String, Sendable {
    /// test.dodopayments.com, for test-mode products while developing.
    case test
    /// live.dodopayments.com, for real purchases.
    case live

    var baseURL: URL {
        switch self {
        case .test: URL(string: "https://test.dodopayments.com")!
        case .live: URL(string: "https://live.dodopayments.com")!
        }
    }
}

/// Dodo Payments' public license endpoints (`/licenses/activate`, `validate`, `deactivate`).
/// They need no API key, so nothing secret ships in the app.
///
/// Those endpoints accept a key for any product on Dodo, so activation also checks the key
/// is for one of `productIDs` and gives the activation straight back if it isn't.
///
/// Status codes only count when Dodo's own JSON error comes with them. Dodo's edge answers
/// blocked requests (a firewall rule, a bot check) with a 403 HTML page, and reading that
/// as "already deactivated" would wipe the key here while Dodo still counts it.
public struct DodoProvider: LicenseProvider {
    /// The products whose keys this app accepts, such as a lifetime plan and a discounted one.
    public let productIDs: Set<String>
    public let environment: DodoEnvironment
    private let transport: any HTTPTransport

    /// - Parameters:
    ///   - productIDs: Your products' IDs in Dodo (`pdt_…`). Keys for any other product are refused.
    ///   - environment: `.test` for test-mode keys, `.live` for real ones.
    public init(productIDs: Set<String>, environment: DodoEnvironment) {
        self.init(productIDs: productIDs, environment: environment, transport: URLSessionTransport())
    }

    init(productIDs: Set<String>, environment: DodoEnvironment, transport: any HTTPTransport) {
        self.productIDs = productIDs
        self.environment = environment
        self.transport = transport
    }

    public var storageScope: String { "dodo.\(environment.rawValue)" }

    public func activate(key: String, deviceName: String) async throws(ProviderError) -> Activation {
        let response = try await post("activate", ["license_key": key, "name": deviceName])
        let error = response.dodoError
        switch response.status {
        case 200..<300:
            guard let body = try? JSONDecoder().decode(ActivateResponse.self, from: response.body) else {
                throw .server(status: response.status, message: nil)
            }
            let activation = Activation(key: key, instanceID: body.id)
            guard let product = body.product?.productID, productIDs.contains(product) else {
                // Give back the activation this just used up, then refuse the key.
                try? await deactivate(activation)
                throw .wrongProduct
            }
            return activation
        case 403 where error != nil:
            throw .keyInactive
        case 404 where error != nil:
            throw .keyNotFound
        case 422:
            // Dodo's docs give 422 on activate one meaning, whatever the body says.
            throw .activationLimitReached
        default:
            throw .server(status: response.status, message: error?.message)
        }
    }

    public func validate(_ activation: Activation) async throws(ProviderError) -> Validity {
        let response = try await post("validate", [
            "license_key": activation.key,
            "license_key_instance_id": activation.instanceID,
        ])
        if (200..<300).contains(response.status) {
            guard let body = try? JSONDecoder().decode(ValidateResponse.self, from: response.body) else {
                throw .server(status: response.status, message: nil)
            }
            return body.valid ? .valid : .revoked
        }
        // The key or this Mac's activation is gone. A bare 404 without Dodo's error code
        // could be anything (a proxy, a moved URL), so it doesn't count.
        let error = response.dodoError
        if error?.code?.hasSuffix("NOT_FOUND") == true {
            return .revoked
        }
        throw .server(status: response.status, message: error?.message)
    }

    public func deactivate(_ activation: Activation) async throws(ProviderError) {
        let response = try await post("deactivate", [
            "license_key": activation.key,
            "license_key_instance_id": activation.instanceID,
        ])
        // Dodo's 403 is "instance not found or not for this key" and its 404 is "key not
        // found": either way nothing is left to free, which is what deactivating wants.
        let error = response.dodoError
        let isAlreadyGone = error != nil && (response.status == 403 || error?.code?.hasSuffix("NOT_FOUND") == true)
        guard (200..<300).contains(response.status) || isAlreadyGone else {
            throw .server(status: response.status, message: error?.message)
        }
    }

    private func post(_ action: String, _ body: [String: String]) async throws(ProviderError) -> HTTPResponse {
        let url = environment.baseURL.appending(path: "licenses/\(action)")
        do {
            return try await transport.post(url, body: JSONEncoder().encode(body))
        } catch {
            throw .unreachable
        }
    }
}

// MARK: - Dodo's JSON

private struct ActivateResponse: Decodable {
    struct Product: Decodable {
        let productID: String

        enum CodingKeys: String, CodingKey {
            case productID = "product_id"
        }
    }

    /// This Mac's activation, `lki_…`.
    let id: String
    let product: Product?
}

private struct ValidateResponse: Decodable {
    let valid: Bool
}

/// Dodo's error body, such as `{"code": "LICENSE_KEY_LIMIT_REACHED", "message": "…"}`.
private struct ErrorBody: Decodable {
    let code: String?
    let message: String?
}

private extension HTTPResponse {
    /// Dodo's JSON error, or nil for anything else: an HTML page from the edge or a proxy,
    /// or an empty body.
    var dodoError: ErrorBody? {
        guard let error = try? JSONDecoder().decode(ErrorBody.self, from: body),
              error.code != nil || error.message != nil
        else { return nil }
        return error
    }
}

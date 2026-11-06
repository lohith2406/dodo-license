import Foundation

/// Sends one JSON POST and hands back whatever came back. It sits between `DodoProvider` and
/// the network so the tests can replay recorded answers instead of calling Dodo.
protocol HTTPTransport: Sendable {
    /// Throws only when no answer arrived at all. Every HTTP status, 500s included, is an answer.
    func post(_ url: URL, body: Data) async throws -> HTTPResponse
}

struct HTTPResponse: Sendable, Equatable {
    var status: Int
    var body: Data
}

struct URLSessionTransport: HTTPTransport {
    var session: URLSession = .shared
    var timeout: TimeInterval = 20

    func post(_ url: URL, body: Data) async throws -> HTTPResponse {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return HTTPResponse(status: http.statusCode, body: data)
    }
}

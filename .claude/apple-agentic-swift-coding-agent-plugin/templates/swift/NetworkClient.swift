import Foundation

public struct NetworkClient: Sendable {
    private let session: URLSession
    private let allowedHosts: Set<String>

    public init(session: URLSession = .shared, allowedHosts: Set<String>) {
        self.session = session
        self.allowedHosts = allowedHosts
    }

    public func get<T: Decodable & Sendable>(_ type: T.Type, from url: URL) async throws -> T {
        guard let host = url.host, allowedHosts.contains(host) else {
            throw URLError(.appTransportSecurityRequiresSecureConnection)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}

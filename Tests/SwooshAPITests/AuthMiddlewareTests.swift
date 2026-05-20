import Testing
@testable import SwooshAPI

@Suite("Bearer auth")
struct AuthMiddlewareTests {
    @Test("Accepts exact bearer token")
    func acceptsExactBearer() {
        #expect(swooshBearerTokenMatches(authorizationHeader: "Bearer token-123", token: "token-123"))
    }

    @Test("Rejects missing bearer prefix")
    func rejectsMissingBearerPrefix() {
        #expect(!swooshBearerTokenMatches(authorizationHeader: "token-123", token: "token-123"))
    }

    @Test("Rejects wrong token")
    func rejectsWrongToken() {
        #expect(!swooshBearerTokenMatches(authorizationHeader: "Bearer token-124", token: "token-123"))
    }

    @Test("Rejects absent authorization header")
    func rejectsAbsentHeader() {
        #expect(!swooshBearerTokenMatches(authorizationHeader: nil, token: "token-123"))
    }
}

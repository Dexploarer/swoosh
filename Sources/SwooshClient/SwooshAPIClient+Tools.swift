// SwooshClient/SwooshAPIClient+Tools.swift — 0.4A Tool execution endpoint
//
// Wire method for `POST /api/tools/{name}/execute`. The server routes
// the call through `ToolRegistry.execute` so the firewall + approval +
// audit pipeline runs unchanged — the wire never carries permission state.

import Foundation

extension SwooshAPIClient {
    public func executeTool(name: String, body: ToolExecuteRequest = ToolExecuteRequest()) async throws -> ToolExecuteResponse {
        let encodedName = try pathComponent(name)
        let encoded = try encoder.encode(body)
        let request = try makeRequest(method: "POST", path: "api/tools/\(encodedName)/execute", body: encoded)
        return try await execute(request, as: ToolExecuteResponse.self)
    }
}

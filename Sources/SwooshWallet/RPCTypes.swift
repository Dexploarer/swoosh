// SwooshWallet/RPCTypes.swift — JSON-RPC envelope + error types — 0.9A
//
// Wire shape for `RPCClient` and `MultiEndpointRPC`. The single-endpoint
// client and the multi-endpoint orchestrator both encode requests through
// `JSONRPCRequest` and decode responses through `JSONRPCResponse<T>`. The
// envelope is private to the module — callers see the public typed result
// or one of the four `RPCError` cases.

import Foundation

public enum RPCError: Error, Sendable, Equatable {
    case transport(String)
    case decode(String)
    case rpc(code: Int, message: String)
    case unexpectedResponse(String)
    case httpStatus(Int, body: String)
}

struct JSONRPCRequest: Encodable {
    let jsonrpc = "2.0"
    let id: Int
    let method: String
    let params: [JSONValue]
}

struct JSONRPCResponse<T: Decodable>: Decodable {
    let jsonrpc: String?
    let id: Int?
    let result: T?
    let error: JSONRPCError?
}

struct JSONRPCError: Decodable {
    let code: Int
    let message: String
}

/// Minimal JSON value type for encoding heterogeneous RPC params.
public enum JSONValue: Encodable, Sendable {
    case string(String)
    case int(Int)
    case bool(Bool)
    case array([JSONValue])
    case object([String: JSONValue])

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let str):    try container.encode(str)
        case .int(let intValue):  try container.encode(intValue)
        case .bool(let boolean):  try container.encode(boolean)
        case .array(let array):   try container.encode(array)
        case .object(let object): try container.encode(object)
        }
    }
}

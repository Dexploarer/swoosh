// SwooshToolsets/URLSessionEVMRPCClient.swift — Concrete EVM JSON-RPC client — 0.9R
//
// Implements `EVMRPCClient` over real Ethereum JSON-RPC 2.0. The URL is
// resolved per-call from `EVMRPCConfig` (Keychain ref → env override →
// public fallback). The `URLSession` is injectable for tests.
//
// Hard rule: this client is read/broadcast only — it never holds, sees,
// or transmits private-key material. `sendRawTransaction` only accepts
// an already-signed transaction hex.

import Foundation
import SwooshTools
import BigInt

public struct URLSessionEVMRPCClient: EVMRPCClient {
    private let transport: JSONRPCTransport
    private let secrets: any SecretResolving
    private let environment: [String: String]

    public init(
        session: URLSession = .shared,
        secrets: any SecretResolving,
        requestTimeout: TimeInterval = 20,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.transport = JSONRPCTransport(session: session, requestTimeout: requestTimeout)
        self.secrets = secrets
        self.environment = environment
    }

    // ── Helpers ───────────────────────────────────────────────────────

    private func endpoint(_ config: EVMRPCConfig) async throws -> URL {
        try await RPCEndpointResolver.resolveEVM(config: config, secrets: secrets, environment: environment)
    }

    /// Encode a block parameter for JSON-RPC (`latest`, `0x..`, etc.).
    private static func blockParam(_ block: EVMBlockParameter) -> String {
        switch block {
        case .tag(let tag): return tag.rawValue
        case .number(let qty): return qty.hexString
        }
    }

    private static func quantity(from result: Any) throws -> EVMQuantity {
        guard let hex = result as? String else {
            throw ToolError.executionFailed("Expected a hex quantity, got \(type(of: result))")
        }
        return EVMQuantity(hex)
    }

    private static func hexData(from result: Any) throws -> EVMHexData {
        guard let hex = result as? String else {
            throw ToolError.executionFailed("Expected hex data, got \(type(of: result))")
        }
        return EVMHexData(hex)
    }

    // ── EVMRPCClient conformance ──────────────────────────────────────

    public func chainID(config: EVMRPCConfig) async throws -> EVMChainID {
        let url = try await endpoint(config)
        let result = try await transport.call(url: url, method: "eth_chainId", params: [])
        guard let hex = result as? String, let value = Int(hex.dropFirst(2), radix: 16) else {
            throw ToolError.executionFailed("eth_chainId returned an unparseable value")
        }
        return EVMChainID(value)
    }

    public func blockNumber(config: EVMRPCConfig) async throws -> EVMQuantity {
        let url = try await endpoint(config)
        let result = try await transport.call(url: url, method: "eth_blockNumber", params: [])
        return try Self.quantity(from: result)
    }

    public func getBalance(config: EVMRPCConfig, address: EVMAddress, block: EVMBlockParameter) async throws -> EVMQuantity {
        let url = try await endpoint(config)
        let result = try await transport.call(
            url: url, method: "eth_getBalance",
            params: [address.hex, Self.blockParam(block)])
        return try Self.quantity(from: result)
    }

    public func getTransactionCount(config: EVMRPCConfig, address: EVMAddress, block: EVMBlockParameter) async throws -> EVMQuantity {
        let url = try await endpoint(config)
        let result = try await transport.call(
            url: url, method: "eth_getTransactionCount",
            params: [address.hex, Self.blockParam(block)])
        return try Self.quantity(from: result)
    }

    public func getCode(config: EVMRPCConfig, address: EVMAddress, block: EVMBlockParameter) async throws -> EVMHexData {
        let url = try await endpoint(config)
        let result = try await transport.call(
            url: url, method: "eth_getCode",
            params: [address.hex, Self.blockParam(block)])
        return try Self.hexData(from: result)
    }

    public func call(config: EVMRPCConfig, call: EVMContractCallInput) async throws -> EVMHexData {
        let url = try await endpoint(config)
        var callObject: [String: Any] = [
            "to": call.to.hex,
            "data": call.data.hex,
        ]
        if let from = call.from { callObject["from"] = from.hex }
        if let value = call.valueWei { callObject["value"] = value.hexString }
        let result = try await transport.call(
            url: url, method: "eth_call",
            params: [callObject, Self.blockParam(call.block)])
        return try Self.hexData(from: result)
    }

    public func estimateGas(config: EVMRPCConfig, tx: EVMTxEstimateGasInput) async throws -> EVMQuantity {
        let url = try await endpoint(config)
        var callObject: [String: Any] = [:]
        if let from = tx.from { callObject["from"] = from.hex }
        if let to = tx.to { callObject["to"] = to.hex }
        if let data = tx.data { callObject["data"] = data.hex }
        if let value = tx.valueWei { callObject["value"] = value.hexString }
        let result = try await transport.call(
            url: url, method: "eth_estimateGas", params: [callObject])
        return try Self.quantity(from: result)
    }

    public func getLogs(config: EVMRPCConfig, filter: EVMGetLogsInput) async throws -> [EVMLog] {
        let url = try await endpoint(config)
        var filterObject: [String: Any] = [:]
        if let fromBlock = filter.fromBlock { filterObject["fromBlock"] = Self.blockParam(fromBlock) }
        if let toBlock = filter.toBlock { filterObject["toBlock"] = Self.blockParam(toBlock) }
        if let address = filter.address { filterObject["address"] = address.hex }
        if !filter.topics.isEmpty {
            filterObject["topics"] = filter.topics.map { $0?.hex as Any? ?? NSNull() }
        }
        let result = try await transport.call(
            url: url, method: "eth_getLogs", params: [filterObject])
        guard let entries = result as? [[String: Any]] else {
            // Empty result arrays decode as [], anything else is unexpected.
            if result is [Any] { return [] }
            throw ToolError.executionFailed("eth_getLogs returned an unexpected shape")
        }
        return entries.map { entry in
            let topics = (entry["topics"] as? [String] ?? []).map { EVMHexData($0) }
            let blockNumber = (entry["blockNumber"] as? String).map { EVMQuantity($0) }
            let txHash = (entry["transactionHash"] as? String).map { EVMHexData($0) }
            return EVMLog(
                address: EVMAddress((entry["address"] as? String) ?? "0x"),
                topics: topics,
                data: EVMHexData((entry["data"] as? String) ?? "0x"),
                blockNumber: blockNumber,
                transactionHash: txHash
            )
        }
    }

    public func sendRawTransaction(config: EVMRPCConfig, signedTransaction: EVMHexData) async throws -> EVMHexData {
        let url = try await endpoint(config)
        let result = try await transport.call(
            url: url, method: "eth_sendRawTransaction", params: [signedTransaction.hex])
        return try Self.hexData(from: result)
    }

    public func getTransactionReceipt(config: EVMRPCConfig, transactionHash: EVMHexData) async throws -> EVMTransactionReceipt? {
        let url = try await endpoint(config)
        let result = try await transport.call(
            url: url, method: "eth_getTransactionReceipt", params: [transactionHash.hex])
        if result is NSNull { return nil }
        guard let object = result as? [String: Any] else { return nil }
        let logs = (object["logs"] as? [[String: Any]] ?? []).map { entry -> EVMLog in
            let topics = (entry["topics"] as? [String] ?? []).map { EVMHexData($0) }
            return EVMLog(
                address: EVMAddress((entry["address"] as? String) ?? "0x"),
                topics: topics,
                data: EVMHexData((entry["data"] as? String) ?? "0x"),
                blockNumber: (entry["blockNumber"] as? String).map { EVMQuantity($0) },
                transactionHash: (entry["transactionHash"] as? String).map { EVMHexData($0) }
            )
        }
        return EVMTransactionReceipt(
            transactionHash: EVMHexData((object["transactionHash"] as? String) ?? transactionHash.hex),
            blockNumber: (object["blockNumber"] as? String).map { EVMQuantity($0) },
            status: (object["status"] as? String).map { EVMQuantity($0) },
            gasUsed: (object["gasUsed"] as? String).map { EVMQuantity($0) },
            contractAddress: (object["contractAddress"] as? String).map { EVMAddress($0) },
            logs: logs
        )
    }

    public func getTransactionByHash(config: EVMRPCConfig, transactionHash: EVMHexData) async throws -> String? {
        let url = try await endpoint(config)
        let result = try await transport.call(
            url: url, method: "eth_getTransactionByHash", params: [transactionHash.hex])
        if result is NSNull { return nil }
        guard JSONSerialization.isValidJSONObject(result),
              let data = try? JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]),
              let json = String(data: data, encoding: .utf8) else {
            return nil
        }
        return json
    }
}

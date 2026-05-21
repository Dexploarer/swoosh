// SwooshToolsets/URLSessionSolanaRPCClient.swift — Concrete Solana JSON-RPC client — 0.9R
//
// Implements `SolanaRPCClient` over real Solana JSON-RPC 2.0. The URL
// is resolved per-call from `SolanaCluster` (Keychain ref → env override
// → public fallback). The `URLSession` is injectable for tests.
//
// Hard rule: this client is read/broadcast only — it never holds, sees,
// or transmits private-key material. `sendTransaction` only accepts an
// already-signed base64 transaction.

import Foundation
import SwooshTools
import BigInt

public struct URLSessionSolanaRPCClient: SolanaRPCClient {
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

    private func endpoint(_ cluster: SolanaCluster) async throws -> URL {
        try await RPCEndpointResolver.resolveSolana(cluster: cluster, secrets: secrets, environment: environment)
    }

    /// The Solana RPC commitment config object.
    private static func commitmentObject(_ commitment: SolanaCommitment) -> [String: Any] {
        ["commitment": commitment.rawValue]
    }

    /// Solana wraps most results in `{ context, value }`. Extract `value`.
    private static func value(from result: Any) -> Any {
        if let object = result as? [String: Any], object.keys.contains("value") {
            return object["value"] ?? NSNull()
        }
        return result
    }

    // ── SolanaRPCClient conformance ───────────────────────────────────

    public func getBalance(cluster: SolanaCluster, pubkey: SolanaPubkey, commitment: SolanaCommitment) async throws -> Lamports {
        let url = try await endpoint(cluster)
        let result = try await transport.call(
            url: url, method: "getBalance",
            params: [pubkey.base58, Self.commitmentObject(commitment)])
        let value = Self.value(from: result)
        if let lamports = value as? UInt64 { return Lamports(lamports) }
        if let lamports = value as? Int { return Lamports(BigInt(lamports)) }
        if let number = value as? NSNumber { return Lamports(BigInt(number.uint64Value)) }
        throw ToolError.executionFailed("getBalance returned an unparseable value")
    }

    public func getAccountInfo(cluster: SolanaCluster, input: SolanaAccountInfoInput) async throws -> SolanaAccountInfoOutput {
        let url = try await endpoint(cluster)
        var config = Self.commitmentObject(input.commitment)
        config["encoding"] = "base64"
        let result = try await transport.call(
            url: url, method: "getAccountInfo",
            params: [input.pubkey.base58, config])
        let value = Self.value(from: result)
        guard let object = value as? [String: Any] else {
            throw ToolError.executionFailed("Account \(input.pubkey.base58) not found")
        }
        // `data` comes back as [base64String, "base64"].
        let dataString: String = {
            if let array = object["data"] as? [Any], let first = array.first as? String { return first }
            if let raw = object["data"] as? String { return raw }
            return ""
        }()
        return SolanaAccountInfoOutput(
            lamports: ((object["lamports"] as? NSNumber)?.uint64Value) ?? 0,
            owner: (object["owner"] as? String) ?? "",
            data: dataString,
            executable: (object["executable"] as? Bool) ?? false
        )
    }

    public func getTokenAccountBalance(cluster: SolanaCluster, tokenAccount: SolanaPubkey, commitment: SolanaCommitment) async throws -> SolanaTokenAmount {
        let url = try await endpoint(cluster)
        let result = try await transport.call(
            url: url, method: "getTokenAccountBalance",
            params: [tokenAccount.base58, Self.commitmentObject(commitment)])
        let value = Self.value(from: result)
        guard let object = value as? [String: Any] else {
            throw ToolError.executionFailed("getTokenAccountBalance returned an unexpected shape")
        }
        return Self.tokenAmount(from: object)
    }

    private static func tokenAmount(from object: [String: Any]) -> SolanaTokenAmount {
        SolanaTokenAmount(
            amount: (object["amount"] as? String) ?? "0",
            decimals: (object["decimals"] as? Int) ?? 0,
            uiAmountString: object["uiAmountString"] as? String
        )
    }

    public func getTokenAccountsByOwner(cluster: SolanaCluster, input: SolanaTokenAccountsByOwnerInput) async throws -> [SolanaTokenAccountEntry] {
        let url = try await endpoint(cluster)
        // Filter object: either by mint or by program id (default SPL Token program).
        var filter: [String: Any] = [:]
        if let mint = input.mint {
            filter["mint"] = mint.base58
        } else if let programId = input.programId {
            filter["programId"] = programId.base58
        } else {
            filter["programId"] = "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA"
        }
        let result = try await transport.call(
            url: url, method: "getTokenAccountsByOwner",
            params: [input.owner.base58, filter, ["encoding": "jsonParsed"]])
        let value = Self.value(from: result)
        guard let entries = value as? [[String: Any]] else { return [] }
        return entries.compactMap { entry -> SolanaTokenAccountEntry? in
            guard let pubkey = entry["pubkey"] as? String,
                  let account = entry["account"] as? [String: Any],
                  let data = account["data"] as? [String: Any],
                  let parsed = data["parsed"] as? [String: Any],
                  let info = parsed["info"] as? [String: Any],
                  let mint = info["mint"] as? String,
                  let tokenAmount = info["tokenAmount"] as? [String: Any] else {
                return nil
            }
            return SolanaTokenAccountEntry(
                pubkey: SolanaPubkey(pubkey),
                mint: SolanaPubkey(mint),
                amount: Self.tokenAmount(from: tokenAmount)
            )
        }
    }

    public func getSignaturesForAddress(cluster: SolanaCluster, input: SolanaSignaturesForAddressInput) async throws -> [SolanaSignatureInfo] {
        let url = try await endpoint(cluster)
        var config: [String: Any] = ["limit": input.limit]
        if let before = input.before { config["before"] = before.base58 }
        let result = try await transport.call(
            url: url, method: "getSignaturesForAddress",
            params: [input.address.base58, config])
        guard let entries = result as? [[String: Any]] else { return [] }
        return entries.map { entry in
            let errJSON: String? = {
                guard let err = entry["err"], !(err is NSNull) else { return nil }
                guard let data = try? JSONSerialization.data(withJSONObject: err, options: []) else { return nil }
                return String(data: data, encoding: .utf8)
            }()
            return SolanaSignatureInfo(
                signature: SolanaSignature((entry["signature"] as? String) ?? ""),
                slot: ((entry["slot"] as? NSNumber)?.uint64Value) ?? 0,
                blockTime: (entry["blockTime"] as? NSNumber)?.int64Value,
                confirmationStatus: entry["confirmationStatus"] as? String,
                errJSON: errJSON
            )
        }
    }

    public func getTransaction(cluster: SolanaCluster, input: SolanaGetTransactionInput) async throws -> SolanaGetTransactionOutput {
        let url = try await endpoint(cluster)
        let config: [String: Any] = [
            "commitment": input.commitment.rawValue,
            "maxSupportedTransactionVersion": 0,
        ]
        let result = try await transport.call(
            url: url, method: "getTransaction",
            params: [input.signature.base58, config])
        guard let object = result as? [String: Any] else {
            throw ToolError.executionFailed("Transaction \(input.signature.base58) not found")
        }
        let slot = ((object["slot"] as? NSNumber)?.uint64Value) ?? 0
        var meta: SolanaGetTransactionOutput.SolanaTransactionMeta?
        if let metaObject = object["meta"] as? [String: Any] {
            let errString: String? = {
                guard let err = metaObject["err"], !(err is NSNull) else { return nil }
                guard let data = try? JSONSerialization.data(withJSONObject: err, options: []) else { return nil }
                return String(data: data, encoding: .utf8)
            }()
            meta = SolanaGetTransactionOutput.SolanaTransactionMeta(
                fee: ((metaObject["fee"] as? NSNumber)?.uint64Value) ?? 0,
                err: errString
            )
        }
        return SolanaGetTransactionOutput(slot: slot, meta: meta)
    }

    public func getSignatureStatuses(cluster: SolanaCluster, signatures: [SolanaSignature], searchTransactionHistory: Bool) async throws -> [SolanaSignatureStatus] {
        let url = try await endpoint(cluster)
        let result = try await transport.call(
            url: url, method: "getSignatureStatuses",
            params: [signatures.map(\.base58), ["searchTransactionHistory": searchTransactionHistory]])
        let value = Self.value(from: result)
        guard let entries = value as? [Any] else { return [] }
        return zip(signatures, entries).map { signature, raw in
            guard let object = raw as? [String: Any] else {
                return SolanaSignatureStatus(signature: signature)
            }
            let errJSON: String? = {
                guard let err = object["err"], !(err is NSNull) else { return nil }
                guard let data = try? JSONSerialization.data(withJSONObject: err, options: []) else { return nil }
                return String(data: data, encoding: .utf8)
            }()
            return SolanaSignatureStatus(
                signature: signature,
                slot: (object["slot"] as? NSNumber)?.uint64Value,
                confirmationStatus: object["confirmationStatus"] as? String,
                errJSON: errJSON
            )
        }
    }

    public func getLatestBlockhash(cluster: SolanaCluster, commitment: SolanaCommitment) async throws -> SolanaGetLatestBlockhashOutput {
        let url = try await endpoint(cluster)
        let result = try await transport.call(
            url: url, method: "getLatestBlockhash",
            params: [Self.commitmentObject(commitment)])
        let value = Self.value(from: result)
        guard let object = value as? [String: Any],
              let blockhash = object["blockhash"] as? String else {
            throw ToolError.executionFailed("getLatestBlockhash returned an unexpected shape")
        }
        return SolanaGetLatestBlockhashOutput(
            blockhash: blockhash,
            lastValidBlockHeight: ((object["lastValidBlockHeight"] as? NSNumber)?.uint64Value) ?? 0
        )
    }

    public func simulateTransaction(cluster: SolanaCluster, input: SolanaTxSimulateInput) async throws -> SolanaTxSimulateOutput {
        let url = try await endpoint(cluster)
        let config: [String: Any] = [
            "commitment": input.commitment.rawValue,
            "encoding": "base64",
        ]
        let result = try await transport.call(
            url: url, method: "simulateTransaction",
            params: [input.transaction, config])
        let value = Self.value(from: result)
        guard let object = value as? [String: Any] else {
            throw ToolError.executionFailed("simulateTransaction returned an unexpected shape")
        }
        let errString: String? = {
            guard let err = object["err"], !(err is NSNull) else { return nil }
            guard let data = try? JSONSerialization.data(withJSONObject: err, options: []) else { return nil }
            return String(data: data, encoding: .utf8)
        }()
        return SolanaTxSimulateOutput(
            err: errString,
            logs: (object["logs"] as? [String]) ?? [],
            unitsConsumed: (object["unitsConsumed"] as? NSNumber)?.uint64Value
        )
    }

    public func sendTransaction(cluster: SolanaCluster, input: SolanaTxSendSignedInput) async throws -> SolanaSignature {
        let url = try await endpoint(cluster)
        let config: [String: Any] = [
            "encoding": "base64",
            "skipPreflight": input.skipPreflight,
        ]
        let result = try await transport.call(
            url: url, method: "sendTransaction",
            params: [input.signedTransaction, config])
        guard let signature = result as? String else {
            throw ToolError.executionFailed("sendTransaction returned an unparseable signature")
        }
        return SolanaSignature(signature)
    }

    public func requestAirdrop(cluster: SolanaCluster, pubkey: SolanaPubkey, lamports: Lamports) async throws -> SolanaSignature {
        let url = try await endpoint(cluster)
        // RPC expects lamports as a u64 integer.
        guard let lamportsUInt = UInt64(lamports.value.description) else {
            throw ToolError.invalidInput("Airdrop amount exceeds UInt64 range")
        }
        let result = try await transport.call(
            url: url, method: "requestAirdrop",
            params: [pubkey.base58, lamportsUInt])
        guard let signature = result as? String else {
            throw ToolError.executionFailed("requestAirdrop returned an unparseable signature")
        }
        return SolanaSignature(signature)
    }
}

// Tests/SwooshToolsetsTests/RPCClientTests.swift
//
// Verifies JSON-RPC 2.0 request construction and response/error parsing
// for the concrete EVM and Solana RPC clients. All HTTP is intercepted
// by MockURLProtocol — no live network calls are made.

import Testing
import Foundation
@testable import SwooshToolsets
@testable import SwooshTools

// MARK: - Test secret resolver

/// A `SecretResolving` stub. RPC tests use the "default" ref path, so
/// `resolve` is never reached; it throws to prove that.
private struct ThrowingSecretResolver: SecretResolving {
    func resolve(ref: String) async throws -> String {
        throw ToolError.executionFailed("ThrowingSecretResolver: \(ref)")
    }
}

private func jsonResult(_ body: String) -> (Int, [String: String], Data) {
    (200, ["Content-Type": "application/json"], Data(body.utf8))
}

// MARK: - EVM RPC client

@Suite("URLSessionEVMRPCClient")
struct URLSessionEVMRPCClientTests {

    @Test("blockNumber sends a well-formed JSON-RPC request and parses the result")
    func blockNumber() async throws {
        let result = try await MockURLProtocol.with({ request in
            // The request body is JSON-RPC 2.0 with the expected method.
            let body = try! JSONSerialization.jsonObject(with: request.bodyData()) as! [String: Any]
            #expect(body["jsonrpc"] as? String == "2.0")
            #expect(body["method"] as? String == "eth_blockNumber")
            #expect(body["params"] as? [Any] != nil)
            return jsonResult(#"{"jsonrpc":"2.0","id":1,"result":"0x10d4f"}"#)
        }) {
            let client = URLSessionEVMRPCClient(
                session: MockURLProtocol.makeSession(),
                secrets: ThrowingSecretResolver())
            let config = EVMRPCConfig(chainID: .mainnet, rpcURLSecretRef: "default")
            return try await client.blockNumber(config: config)
        }
        #expect(result.value == 68943)  // 0x10d4f
    }

    @Test("getBalance forwards the address + block params")
    func getBalance() async throws {
        let balance = try await MockURLProtocol.with({ request in
            let body = try! JSONSerialization.jsonObject(with: request.bodyData()) as! [String: Any]
            #expect(body["method"] as? String == "eth_getBalance")
            let params = body["params"] as! [Any]
            #expect((params.first as? String) == "0x000000000000000000000000000000000000dead")
            #expect((params.last as? String) == "latest")
            return jsonResult(#"{"jsonrpc":"2.0","id":1,"result":"0xde0b6b3a7640000"}"#)
        }) {
            let client = URLSessionEVMRPCClient(
                session: MockURLProtocol.makeSession(),
                secrets: ThrowingSecretResolver())
            let config = EVMRPCConfig(chainID: .mainnet, rpcURLSecretRef: "default")
            return try await client.getBalance(
                config: config,
                address: EVMAddress("0x000000000000000000000000000000000000dEaD"),
                block: .tag(.latest))
        }
        #expect(balance.asETH == 1.0)  // 0xde0b6b3a7640000 wei = 1 ETH
    }

    @Test("a JSON-RPC error object surfaces as JSONRPCError")
    func rpcError() async throws {
        await #expect(throws: JSONRPCError.self) {
            try await MockURLProtocol.with({ _ in
                jsonResult(#"{"jsonrpc":"2.0","id":1,"error":{"code":-32000,"message":"boom"}}"#)
            }) {
                let client = URLSessionEVMRPCClient(
                    session: MockURLProtocol.makeSession(),
                    secrets: ThrowingSecretResolver())
                let config = EVMRPCConfig(chainID: .mainnet, rpcURLSecretRef: "default")
                _ = try await client.blockNumber(config: config)
            }
        }
    }

    @Test("getTransactionReceipt returns nil for a null result")
    func receiptNull() async throws {
        let receipt = try await MockURLProtocol.with({ _ in
            jsonResult(#"{"jsonrpc":"2.0","id":1,"result":null}"#)
        }) {
            let client = URLSessionEVMRPCClient(
                session: MockURLProtocol.makeSession(),
                secrets: ThrowingSecretResolver())
            let config = EVMRPCConfig(chainID: .mainnet, rpcURLSecretRef: "default")
            return try await client.getTransactionReceipt(
                config: config,
                transactionHash: EVMHexData("0xabc"))
        }
        #expect(receipt == nil)
    }

    @Test("getTransactionReceipt parses status and logs")
    func receiptParsed() async throws {
        let receipt = try await MockURLProtocol.with({ _ in
            jsonResult(#"""
            {"jsonrpc":"2.0","id":1,"result":{
              "transactionHash":"0xfeed","blockNumber":"0x1","status":"0x1","gasUsed":"0x5208",
              "logs":[{"address":"0xcafe","topics":["0xaa"],"data":"0xbb"}]}}
            """#)
        }) {
            let client = URLSessionEVMRPCClient(
                session: MockURLProtocol.makeSession(),
                secrets: ThrowingSecretResolver())
            let config = EVMRPCConfig(chainID: .mainnet, rpcURLSecretRef: "default")
            return try await client.getTransactionReceipt(
                config: config,
                transactionHash: EVMHexData("0xfeed"))
        }
        #expect(receipt?.status?.value == 1)
        #expect(receipt?.gasUsed?.value == 21000)
        #expect(receipt?.logs.count == 1)
    }
}

// MARK: - Solana RPC client

@Suite("URLSessionSolanaRPCClient")
struct URLSessionSolanaRPCClientTests {

    @Test("getBalance parses the lamports value out of the context wrapper")
    func getBalance() async throws {
        let lamports = try await MockURLProtocol.with({ request in
            let body = try! JSONSerialization.jsonObject(with: request.bodyData()) as! [String: Any]
            #expect(body["jsonrpc"] as? String == "2.0")
            #expect(body["method"] as? String == "getBalance")
            return jsonResult(#"{"jsonrpc":"2.0","id":1,"result":{"context":{"slot":1},"value":2500000000}}"#)
        }) {
            let client = URLSessionSolanaRPCClient(
                session: MockURLProtocol.makeSession(),
                secrets: ThrowingSecretResolver())
            return try await client.getBalance(
                cluster: SolanaCluster(id: "mainnet-beta", rpcURLSecretRef: "default"),
                pubkey: SolanaPubkey("So11111111111111111111111111111111111111112"),
                commitment: .confirmed)
        }
        #expect(lamports.asSOL == 2.5)
    }

    @Test("getLatestBlockhash parses blockhash + lastValidBlockHeight")
    func latestBlockhash() async throws {
        let output = try await MockURLProtocol.with({ request in
            let body = try! JSONSerialization.jsonObject(with: request.bodyData()) as! [String: Any]
            #expect(body["method"] as? String == "getLatestBlockhash")
            return jsonResult(#"""
            {"jsonrpc":"2.0","id":1,"result":{"context":{"slot":99},
             "value":{"blockhash":"Hxyz","lastValidBlockHeight":12345}}}
            """#)
        }) {
            let client = URLSessionSolanaRPCClient(
                session: MockURLProtocol.makeSession(),
                secrets: ThrowingSecretResolver())
            return try await client.getLatestBlockhash(
                cluster: SolanaCluster(id: "devnet", rpcURLSecretRef: "default"),
                commitment: .confirmed)
        }
        #expect(output.blockhash == "Hxyz")
        #expect(output.lastValidBlockHeight == 12345)
    }

    @Test("a Solana JSON-RPC error surfaces as JSONRPCError")
    func rpcError() async throws {
        await #expect(throws: JSONRPCError.self) {
            try await MockURLProtocol.with({ _ in
                jsonResult(#"{"jsonrpc":"2.0","id":1,"error":{"code":-32602,"message":"bad params"}}"#)
            }) {
                let client = URLSessionSolanaRPCClient(
                    session: MockURLProtocol.makeSession(),
                    secrets: ThrowingSecretResolver())
                _ = try await client.getBalance(
                    cluster: SolanaCluster(id: "devnet", rpcURLSecretRef: "default"),
                    pubkey: SolanaPubkey("bad"),
                    commitment: .confirmed)
            }
        }
    }

    @Test("sendTransaction returns the broadcast signature")
    func sendTransaction() async throws {
        let signature = try await MockURLProtocol.with({ request in
            let body = try! JSONSerialization.jsonObject(with: request.bodyData()) as! [String: Any]
            #expect(body["method"] as? String == "sendTransaction")
            return jsonResult(#"{"jsonrpc":"2.0","id":1,"result":"5xSig"}"#)
        }) {
            let client = URLSessionSolanaRPCClient(
                session: MockURLProtocol.makeSession(),
                secrets: ThrowingSecretResolver())
            return try await client.sendTransaction(
                cluster: SolanaCluster(id: "devnet", rpcURLSecretRef: "default"),
                input: SolanaTxSendSignedInput(signedTransaction: "AQAB", clusterID: "devnet"))
        }
        #expect(signature.base58 == "5xSig")
    }
}

// MARK: - Endpoint resolution

@Suite("RPCEndpointResolver")
struct RPCEndpointResolverTests {

    @Test("EVM default ref falls back to a public RPC for known chains")
    func evmDefaultFallback() async throws {
        let url = try await RPCEndpointResolver.resolveEVM(
            config: EVMRPCConfig(chainID: .mainnet, rpcURLSecretRef: "default"),
            secrets: ThrowingSecretResolver(),
            environment: [:])
        #expect(url.scheme == "https")
        #expect(url.host?.isEmpty == false)
    }

    @Test("EVM env override wins over the public fallback")
    func evmEnvOverride() async throws {
        let url = try await RPCEndpointResolver.resolveEVM(
            config: EVMRPCConfig(chainID: .mainnet, rpcURLSecretRef: "default"),
            secrets: ThrowingSecretResolver(),
            environment: ["SWOOSH_EVM_RPC_1": "https://my-private-rpc.example/eth"])
        #expect(url.absoluteString == "https://my-private-rpc.example/eth")
    }

    @Test("Solana default ref falls back to the public cluster RPC")
    func solanaDefaultFallback() async throws {
        let url = try await RPCEndpointResolver.resolveSolana(
            cluster: SolanaCluster(id: "mainnet-beta", rpcURLSecretRef: "default"),
            secrets: ThrowingSecretResolver(),
            environment: [:])
        #expect(url.absoluteString == "https://api.mainnet-beta.solana.com")
    }

    @Test("an unknown EVM chain with no override throws")
    func evmUnknownChain() async throws {
        await #expect(throws: ToolError.self) {
            _ = try await RPCEndpointResolver.resolveEVM(
                config: EVMRPCConfig(chainID: EVMChainID(999_999), rpcURLSecretRef: "default"),
                secrets: ThrowingSecretResolver(),
                environment: [:])
        }
    }
}

// MARK: - EVM ABI encoding

@Suite("EVMABI")
struct EVMABITests {

    @Test("encodeTransfer produces the canonical ERC-20 transfer calldata")
    func encodeTransfer() {
        // transfer(0x...dEaD, 1)
        let data = EVMABI.encodeTransfer(
            to: EVMAddress("0x000000000000000000000000000000000000dEaD"),
            amount: 1)
        #expect(data.hex == "0xa9059cbb"
            + "000000000000000000000000000000000000000000000000000000000000dead"
            + "0000000000000000000000000000000000000000000000000000000000000001")
    }

    @Test("encodeApprove uses the approve selector 0x095ea7b3")
    func encodeApprove() {
        let data = EVMABI.encodeApprove(
            spender: EVMAddress("0x0000000000000000000000000000000000000001"),
            amount: 255)
        #expect(data.hex.hasPrefix("0x095ea7b3"))
        #expect(data.hex.hasSuffix("00ff"))
    }

    @Test("decodeUint reads the first 32-byte word")
    func decodeUint() {
        let value = EVMABI.decodeUint(EVMHexData(
            "0x0000000000000000000000000000000000000000000000000000000000000064"))
        #expect(value == 100)
    }

    @Test("functionSelector matches the known transfer selector")
    func functionSelector() {
        #expect(EVMABI.functionSelector("transfer(address,uint256)") == "a9059cbb")
        #expect(EVMABI.functionSelector("approve(address,uint256)") == "095ea7b3")
        #expect(EVMABI.functionSelector("balanceOf(address)") == "70a08231")
    }

    @Test("encodeArgument rejects unsupported Solidity types")
    func encodeArgumentRejectsUnsupported() {
        #expect(throws: ToolError.self) {
            _ = try EVMABI.encodeArgument(type: "bytes", value: "0x00")
        }
    }
}

// SwooshDaemon/LocalWalletBridge.swift - SwooshWallet-backed tool bridge
import Foundation
import BigInt
import CryptoKit
import secp256k1
import SwooshTools
import SwooshWallet

actor LocalWalletBridge: WalletBridge {
    private let store: WalletStore
    private let keychain: KeychainKeyStore
    private let evmSessionID = "local-swoosh-wallet-evm"
    private let solanaSessionID = "local-swoosh-wallet-solana"

    init(store: WalletStore = WalletStore(), keychain: KeychainKeyStore = KeychainKeyStore()) {
        self.store = store
        self.keychain = keychain
    }

    func connectEVM() async throws -> String {
        evmSessionID
    }

    func evmAccounts(sessionID: String) async throws -> [EVMAddress] {
        try requireSession(sessionID, expected: evmSessionID, chain: "EVM")
        return await store.accounts()
            .filter { $0.chain.isEVM }
            .map { EVMAddress($0.address) }
    }

    func requestEVMSignature(
        transaction: EVMUnsignedTransaction,
        sessionID: String,
        confirmationText: String
    ) async throws -> EVMHexData {
        try requireSession(sessionID, expected: evmSessionID, chain: "EVM")
        guard let chain = walletChain(for: transaction.chainID) else {
            throw ToolError.executionFailed("Unsupported EVM chain ID \(transaction.chainID.value)")
        }
        let account = try await account(chain: chain, address: transaction.from.hex)
        let secret = try await keychain.load(
            account: account,
            prompt: confirmationText.isEmpty ? "Sign EVM transaction with Swoosh wallet." : confirmationText
        )
        return EVMHexData(try Self.signEIP1559(transaction: transaction, secret: secret))
    }

    func connectSolana() async throws -> String {
        solanaSessionID
    }

    func solanaAccounts(sessionID: String) async throws -> [SolanaPubkey] {
        try requireSession(sessionID, expected: solanaSessionID, chain: "Solana")
        return await store.accounts()
            .filter { $0.chain == .solana }
            .map { SolanaPubkey($0.address) }
    }

    func requestSolanaSignature(
        transaction: SolanaUnsignedTransaction,
        sessionID: String,
        confirmationText: String
    ) async throws -> String {
        try requireSession(sessionID, expected: solanaSessionID, chain: "Solana")
        let account = try await account(chain: .solana, address: transaction.feePayer.base58)
        let secret = try await keychain.load(
            account: account,
            prompt: confirmationText.isEmpty ? "Sign Solana transaction with Swoosh wallet." : confirmationText
        )
        return try Self.signSolanaTransaction(transaction, secret: secret)
    }

    private func requireSession(_ sessionID: String, expected: String, chain: String) throws {
        guard sessionID == expected else {
            throw ToolError.executionFailed("Unknown \(chain) wallet session \(sessionID)")
        }
    }

    private func account(chain: WalletChain, address: String) async throws -> WalletAccount {
        let normalized = address.lowercased()
        guard let account = await store.accounts().first(where: {
            $0.chain == chain && $0.address.lowercased() == normalized
        }) else {
            throw ToolError.executionFailed("No local \(chain.displayName) wallet account for \(address)")
        }
        return account
    }

    private func walletChain(for chainID: EVMChainID) -> WalletChain? {
        switch chainID.value {
        case 1: .ethereum
        case 8453: .base
        case 56: .bnb
        default: nil
        }
    }

    private static func signSolanaTransaction(_ transaction: SolanaUnsignedTransaction, secret: Data) throws -> String {
        guard let encoded = transaction.serializedMessageBase64,
              var serialized = Data(base64Encoded: encoded) else {
            throw ToolError.executionFailed("Solana signing requires a serialized transaction")
        }
        let signatureCount = try shortVectorLength(serialized)
        guard signatureCount.value > 0 else {
            throw ToolError.executionFailed("Solana transaction has no signature slots")
        }
        let signatureOffset = signatureCount.bytesRead
        let messageOffset = signatureOffset + signatureCount.value * 64
        guard serialized.count > messageOffset else {
            throw ToolError.executionFailed("Solana transaction is shorter than its signature header")
        }
        let pair = try WalletKeyFactory.load(chain: .solana, secret: secret)
        let seed = pair.secret.prefix(32)
        let privateKey = try Curve25519.Signing.PrivateKey(rawRepresentation: seed)
        let signature = try privateKey.signature(for: serialized[messageOffset...])
        serialized.replaceSubrange(signatureOffset..<(signatureOffset + 64), with: signature)
        return serialized.base64EncodedString()
    }

    private static func shortVectorLength(_ data: Data) throws -> (value: Int, bytesRead: Int) {
        var value = 0
        var shift = 0
        for (index, byte) in data.prefix(4).enumerated() {
            value |= Int(byte & 0x7f) << shift
            if byte & 0x80 == 0 {
                return (value, index + 1)
            }
            shift += 7
        }
        throw ToolError.executionFailed("Invalid Solana short vector length")
    }

    private static func signEIP1559(transaction: EVMUnsignedTransaction, secret: Data) throws -> String {
        guard let nonce = transaction.nonce else {
            throw ToolError.executionFailed("EVM signing requires nonce")
        }
        guard let gasLimit = transaction.gasLimit else {
            throw ToolError.executionFailed("EVM signing requires gasLimit")
        }
        guard let maxFeePerGas = transaction.maxFeePerGas else {
            throw ToolError.executionFailed("EVM signing requires maxFeePerGas")
        }
        guard let maxPriorityFeePerGas = transaction.maxPriorityFeePerGas else {
            throw ToolError.executionFailed("EVM signing requires maxPriorityFeePerGas")
        }

        let accessList = RLP.list([])
        let fields = try [
            RLP.integer(BigUInt(transaction.chainID.value)),
            RLP.bytes(quantityBytes(nonce, field: "nonce")),
            RLP.bytes(quantityBytes(maxPriorityFeePerGas, field: "maxPriorityFeePerGas")),
            RLP.bytes(quantityBytes(maxFeePerGas, field: "maxFeePerGas")),
            RLP.bytes(quantityBytes(gasLimit, field: "gasLimit")),
            RLP.bytes(hexBytes(transaction.to?.hex, field: "to")),
            RLP.bytes(quantityBytes(transaction.valueWei ?? EVMQuantity(0), field: "valueWei")),
            RLP.bytes(hexBytes(transaction.data?.hex, field: "data")),
            accessList,
        ]
        let signingPayload = Data([UInt8(0x02)] + RLP.list(fields))
        let digest = HashDigest(Keccak.hash256(Array(signingPayload)))
        let key = try secp256k1.Recovery.PrivateKey(dataRepresentation: secret, format: .uncompressed)
        let signature = try key.signature(for: digest).compactRepresentation
        let recoveryID = signature.recoveryId >= 27 ? signature.recoveryId - 27 : signature.recoveryId
        guard recoveryID == 0 || recoveryID == 1 else {
            throw ToolError.executionFailed("Invalid EVM recovery ID \(signature.recoveryId)")
        }
        let compact = [UInt8](signature.signature)
        let r = Array(compact.prefix(32))
        let s = Array(compact.suffix(32))
        let signedFields = fields + [
            RLP.integer(BigUInt(Int(recoveryID))),
            RLP.bytes(trimLeadingZeros(r)),
            RLP.bytes(trimLeadingZeros(s)),
        ]
        return Hex.encode([UInt8(0x02)] + RLP.list(signedFields))
    }

    private static func quantityBytes(_ quantity: EVMQuantity, field: String) throws -> [UInt8] {
        guard quantity.value >= BigInt(0),
              let unsigned = BigUInt(quantity.value.description) else {
            throw ToolError.executionFailed("Invalid non-negative EVM quantity for \(field)")
        }
        return bigUIntBytes(unsigned)
    }

    private static func hexBytes(_ hex: String?, field: String) throws -> [UInt8] {
        guard let hex, !hex.isEmpty else { return [] }
        guard let bytes = Hex.decode(hex) else {
            throw ToolError.executionFailed("Invalid EVM hex field \(field)")
        }
        return bytes
    }

    fileprivate static func bigUIntBytes(_ value: BigUInt) -> [UInt8] {
        if value == BigUInt(0) { return [] }
        return Hex.decode(String(value, radix: 16))!
    }

    private static func trimLeadingZeros(_ bytes: [UInt8]) -> [UInt8] {
        Array(bytes.drop(while: { $0 == 0 }))
    }
}

private enum RLP {
    static func integer(_ value: BigUInt) -> [UInt8] {
        bytes(LocalWalletBridge.bigUIntBytes(value))
    }

    static func bytes(_ bytes: [UInt8]) -> [UInt8] {
        if bytes.count == 1, let first = bytes.first, first < 0x80 {
            return bytes
        }
        return prefix(offset: 0x80, count: bytes.count) + bytes
    }

    static func list(_ elements: [[UInt8]]) -> [UInt8] {
        let payload = elements.flatMap { $0 }
        return prefix(offset: 0xc0, count: payload.count) + payload
    }

    private static func prefix(offset: UInt8, count: Int) -> [UInt8] {
        if count < 56 {
            return [offset + UInt8(count)]
        }
        let countBytes = lengthBytes(count)
        return [offset + 55 + UInt8(countBytes.count)] + countBytes
    }

    private static func lengthBytes(_ value: Int) -> [UInt8] {
        var value = value
        var bytes: [UInt8] = []
        while value > 0 {
            bytes.insert(UInt8(value & 0xff), at: 0)
            value >>= 8
        }
        return bytes
    }
}

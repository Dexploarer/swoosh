// SwooshWallet/WalletKeyPair.swift — Per-chain keypair generation + EIP-55 checksum — 0.9A
//
// Solana: ed25519 via CryptoKit `Curve25519.Signing.PrivateKey`. The 32-byte
// private key plus 32-byte public key matches Solana's canonical 64-byte
// secret representation (priv ‖ pub). Addresses are bare base58 of the
// public key.
//
// EVM (Ethereum, Base, BNB): secp256k1 via the GigaBitcoin SPM package. We
// generate uncompressed-format private keys, derive the 64-byte X‖Y pubkey
// (everything after the leading 0x04), and the address is the last 20
// bytes of keccak256(pubkey) prefixed with "0x".

import Foundation
import CryptoKit
import secp256k1

public struct WalletKeyPair: Sendable {
    public let chain: WalletChain
    public let address: String
    /// Canonical secret representation. For Solana this is 64 bytes (priv ‖ pub),
    /// matching what `solana-keygen` / `@solana/web3.js` emit. For EVM it's
    /// the 32-byte private scalar.
    public let secret: Data
    /// Public key bytes — base58-decoded for Solana, uncompressed-no-prefix
    /// X‖Y for EVM.
    public let publicKey: Data

    public init(chain: WalletChain, address: String, secret: Data, publicKey: Data) {
        self.chain = chain
        self.address = address
        self.secret = secret
        self.publicKey = publicKey
    }
}

public enum WalletKeyError: Error, Sendable, Equatable {
    case invalidSecretLength(expected: Int, got: Int)
    case secp256k1Failed(String)
}

public enum WalletKeyFactory {
    public static func generate(chain: WalletChain) throws -> WalletKeyPair {
        switch chain {
        case .solana:
            return try generateSolana()
        case .ethereum, .base, .bnb:
            return try generateEVM(chain: chain)
        }
    }

    /// Re-derive a public key + address from a saved secret blob. Used when
    /// reading keys back out of the Keychain.
    public static func load(chain: WalletChain, secret: Data) throws -> WalletKeyPair {
        switch chain {
        case .solana:
            return try loadSolana(secret: secret)
        case .ethereum, .base, .bnb:
            return try loadEVM(chain: chain, secret: secret)
        }
    }

    // MARK: - Solana

    private static func generateSolana() throws -> WalletKeyPair {
        let priv = Curve25519.Signing.PrivateKey()
        return try assembleSolana(privateKey: priv)
    }

    private static func loadSolana(secret: Data) throws -> WalletKeyPair {
        // Accept either bare 32-byte seed or the canonical 64-byte priv‖pub blob.
        let seed: Data
        switch secret.count {
        case 32: seed = secret
        case 64: seed = secret.prefix(32)
        default: throw WalletKeyError.invalidSecretLength(expected: 32, got: secret.count)
        }
        let priv = try Curve25519.Signing.PrivateKey(rawRepresentation: seed)
        return try assembleSolana(privateKey: priv)
    }

    private static func assembleSolana(privateKey: Curve25519.Signing.PrivateKey) throws -> WalletKeyPair {
        let priv = privateKey.rawRepresentation
        let pub = privateKey.publicKey.rawRepresentation
        var combined = Data(capacity: 64)
        combined.append(priv)
        combined.append(pub)
        let address = Base58.encode([UInt8](pub))
        return WalletKeyPair(chain: .solana, address: address, secret: combined, publicKey: pub)
    }

    // MARK: - EVM

    private static func generateEVM(chain: WalletChain) throws -> WalletKeyPair {
        do {
            let priv = try secp256k1.Signing.PrivateKey(format: .uncompressed)
            return try assembleEVM(chain: chain, privateKey: priv)
        } catch let error as WalletKeyError {
            throw error
        } catch {
            throw WalletKeyError.secp256k1Failed(String(describing: error))
        }
    }

    private static func loadEVM(chain: WalletChain, secret: Data) throws -> WalletKeyPair {
        guard secret.count == 32 else {
            throw WalletKeyError.invalidSecretLength(expected: 32, got: secret.count)
        }
        do {
            let priv = try secp256k1.Signing.PrivateKey(
                dataRepresentation: secret,
                format: .uncompressed
            )
            return try assembleEVM(chain: chain, privateKey: priv)
        } catch let error as WalletKeyError {
            throw error
        } catch {
            throw WalletKeyError.secp256k1Failed(String(describing: error))
        }
    }

    private static func assembleEVM(
        chain: WalletChain,
        privateKey: secp256k1.Signing.PrivateKey
    ) throws -> WalletKeyPair {
        let privBytes = Data(privateKey.dataRepresentation)
        // Uncompressed pubkey is 65 bytes: 0x04 || X(32) || Y(32). Strip the 0x04.
        let uncompressed = privateKey.publicKey.dataRepresentation
        guard uncompressed.count == 65, uncompressed.first == 0x04 else {
            throw WalletKeyError.secp256k1Failed(
                "expected 65-byte uncompressed pubkey, got \(uncompressed.count) bytes"
            )
        }
        let pubXY = uncompressed.dropFirst()
        let hash = Keccak.hash256([UInt8](pubXY))
        let addressBytes = Array(hash.suffix(20))
        let address = checksumAddress(bytes: addressBytes)
        return WalletKeyPair(chain: chain, address: address, secret: privBytes, publicKey: Data(pubXY))
    }

    /// EIP-55 mixed-case checksum address. Exposed so consumers outside
    /// the wallet module (e.g. transaction display in the iOS app, daemon
    /// log formatters) can render addresses with checksum casing without
    /// reimplementing the keccak-of-lowercase-hex routine. Input is the
    /// raw 20-byte address bytes; output is `0x` followed by 40 hex
    /// characters with EIP-55 casing applied.
    public static func checksumAddress(bytes: [UInt8]) -> String {
        let lower = Hex.encode(bytes, prefix: false)
        let hashOfLower = Keccak.hash256(Array(lower.utf8))
        var out = "0x"
        out.reserveCapacity(42)
        for (i, char) in lower.enumerated() {
            let nibble = hashOfLower[i / 2]
            let highNibble = i % 2 == 0
            let nibbleValue = highNibble ? (nibble >> 4) : (nibble & 0x0F)
            if char.isLetter, nibbleValue >= 8 {
                out.append(Character(char.uppercased()))
            } else {
                out.append(char)
            }
        }
        return out
    }
}

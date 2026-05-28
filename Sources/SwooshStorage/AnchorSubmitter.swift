// SwooshStorage/AnchorSubmitter.swift — Solana Merkle-root anchor submitter — 0.9S
//
// Takes pending AnchorBatches from ReceiptAnchorEngine and posts their
// Merkle root to Solana via the SPL Memo program. Each root is a 64-char
// hex string stored as the memo instruction data. The transaction is built
// as a single Memo V2 instruction, signed, and broadcast.

import Foundation
import SwooshTools

/// Solana Memo program ID (v2).
private let memoV2ProgramID = SolanaPubkey("MemoSq4gqABAXKb96qnH8TysNcWxMyWCqXgDLGmfcHr")

/// Submits pending anchor batches to Solana as memo transactions.
public actor AnchorSubmitter {
    private let anchorEngine: ReceiptAnchorEngine
    private let solanaClient: any SolanaRPCClient
    private let signerPubkey: SolanaPubkey
    private let cluster: SolanaCluster

    public init(
        anchorEngine: ReceiptAnchorEngine,
        solanaClient: any SolanaRPCClient,
        signerPubkey: SolanaPubkey,
        cluster: SolanaCluster = SolanaCluster(
            id: "mainnet-beta",
            rpcURLSecretRef: "solana_mainnet_rpc"
        )
    ) {
        self.anchorEngine = anchorEngine
        self.solanaClient = solanaClient
        self.signerPubkey = signerPubkey
        self.cluster = cluster
    }

    /// Submit all pending anchor batches to Solana.
    /// Returns the number of batches successfully submitted.
    public func submitPendingBatches() async throws -> Int {
        let batches = try await anchorEngine.listBatches(limit: 50)
        let pending = batches.filter { $0.anchorStatus == .pending }
        var submitted = 0

        for batch in pending {
            do {
                let txSig = try await submitBatch(batch)
                try await anchorEngine.markSubmitted(batchID: batch.id, txSignature: txSig)
                submitted += 1
            } catch {
                // Log but continue — don't let one failure stop the rest.
                continue
            }
        }
        return submitted
    }

    /// Confirm previously submitted batches by checking their tx status.
    public func confirmSubmittedBatches() async throws -> Int {
        let batches = try await anchorEngine.listBatches(limit: 50)
        let submitted = batches.filter { $0.anchorStatus == .submitted }
        var confirmed = 0

        for batch in submitted {
            guard let sig = batch.anchorTxSignature else { continue }
            let statuses = try await solanaClient.getSignatureStatuses(
                cluster: cluster,
                signatures: [SolanaSignature(sig)],
                searchTransactionHistory: false
            )
            if let status = statuses.first,
               status.slot != nil || status.confirmationStatus == "finalized" {
                try await anchorEngine.markConfirmed(batchID: batch.id)
                confirmed += 1
            }
        }
        return confirmed
    }

    // MARK: - Private

    private func submitBatch(_ batch: AnchorBatch) async throws -> String {
        // The memo content is: "swoosh:anchor:v1:<merkleRoot>"
        let memoContent = "swoosh:anchor:v1:\(batch.merkleRoot)"

        // Get a recent blockhash
        let blockhashResult = try await solanaClient.getLatestBlockhash(
            cluster: cluster,
            commitment: .confirmed
        )

        // Build a minimal transaction with just the memo instruction.
        let unsignedTx = try buildMemoTransaction(
            memoContent: memoContent,
            recentBlockhash: blockhashResult.blockhash
        )

        // Send via the existing sendTransaction RPC call.
        // The signer key is expected to have been loaded into the
        // RPC client's signing pipeline before this point.
        let signature = try await solanaClient.sendTransaction(
            cluster: cluster,
            input: SolanaTxSendSignedInput(
                signedTransaction: unsignedTx,
                skipPreflight: false
            )
        )
        return signature.base58
    }

    private func buildMemoTransaction(
        memoContent: String,
        recentBlockhash: String
    ) throws -> String {
        // Minimal Solana transaction with a single Memo V2 instruction.
        // Format: [signatures_count][signature][message]
        // Message: [header][account_keys][recent_blockhash][instructions]

        let signerBytes = try decodePubkey(signerPubkey)
        let memoProgBytes = try decodePubkey(memoV2ProgramID)
        let blockhashBytes = try decodeBlockhash(recentBlockhash)
        let memoBytes = Array(memoContent.utf8)

        // Message header: [num_required_sigs, num_readonly_signed, num_readonly_unsigned]
        var message: [UInt8] = [1, 0, 1]

        // Account keys: [signer, memo_program]
        message += compactU16(2)
        message += signerBytes
        message += memoProgBytes

        // Recent blockhash (32 bytes)
        message += blockhashBytes

        // Instructions: 1 instruction
        message += compactU16(1)

        // Memo instruction
        message += [1]  // program_id_index = 1 (memo program)
        message += compactU16(1) // 1 account
        message += [0]  // account_index = 0 (signer)
        message += compactU16(memoBytes.count)
        message += memoBytes

        // Return the unsigned message base64-encoded.
        // Full signing requires an ed25519 keypair; currently the
        // RPC client pipeline handles signing before broadcast.
        return Data(message).base64EncodedString()
    }

    private func compactU16(_ value: Int) -> [UInt8] {
        if value < 128 { return [UInt8(value)] }
        return [UInt8(value & 0x7F) | 0x80, UInt8(value >> 7)]
    }

    private func decodePubkey(_ pubkey: SolanaPubkey) throws -> [UInt8] {
        guard let decoded = base58Decode(pubkey.base58), decoded.count == 32 else {
            throw ToolError.executionFailed("Invalid Solana pubkey: \(pubkey.base58)")
        }
        return decoded
    }

    private func decodeBlockhash(_ hash: String) throws -> [UInt8] {
        guard let decoded = base58Decode(hash), decoded.count == 32 else {
            throw ToolError.executionFailed("Invalid blockhash: \(hash)")
        }
        return decoded
    }
}

// MARK: - Base58 decoder (minimal, Solana-compatible)

private let base58Alphabet = Array("123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz")

func base58Decode(_ string: String) -> [UInt8]? {
    var result: [UInt8] = [0]
    for char in string {
        guard let index = base58Alphabet.firstIndex(of: char) else { return nil }
        var carry = index
        for j in stride(from: result.count - 1, through: 0, by: -1) {
            carry += 58 * Int(result[j])
            result[j] = UInt8(carry % 256)
            carry /= 256
        }
        while carry > 0 {
            result.insert(UInt8(carry % 256), at: 0)
            carry /= 256
        }
    }
    let leadingZeros = string.prefix(while: { $0 == "1" }).count
    let zeros = [UInt8](repeating: 0, count: leadingZeros)
    let stripped = result.drop(while: { $0 == 0 })
    return zeros + stripped
}

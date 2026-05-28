// SwooshStorage/MerkleTree.swift — SHA-256 Merkle tree for receipt anchoring — 0.9S
//
// Pure-Swift Merkle tree builder using CryptoKit. Supports root computation,
// inclusion proof generation, and proof verification for the on-chain
// receipt anchoring system.

import Foundation
import CryptoKit

// MARK: - Proof node

/// A single node in a Merkle inclusion proof.
public struct MerkleProofNode: Codable, Sendable, Equatable {
    /// The sibling hash at this tree level.
    public let hash: Data
    /// Whether this sibling is on the left side.
    public let isLeft: Bool

    public init(hash: Data, isLeft: Bool) {
        self.hash = hash
        self.isLeft = isLeft
    }
}

// MARK: - Merkle tree

/// Stateless Merkle tree operations using SHA-256.
public enum MerkleTree {

    // MARK: - Root computation

    /// Build a Merkle root from leaf hashes.
    /// - Returns: The 32-byte root hash. Empty input returns 32 zero bytes.
    public static func root(from leaves: [Data]) -> Data {
        guard !leaves.isEmpty else {
            return Data(repeating: 0, count: 32)
        }
        var level = leaves
        // Ensure even count by duplicating last leaf if odd
        if level.count % 2 != 0 {
            level.append(level.last!)
        }
        while level.count > 1 {
            var nextLevel: [Data] = []
            for i in stride(from: 0, to: level.count, by: 2) {
                let combined = level[i] + level[i + 1]
                let digest = SHA256.hash(data: combined)
                nextLevel.append(Data(digest))
            }
            level = nextLevel
            if level.count > 1 && level.count % 2 != 0 {
                level.append(level.last!)
            }
        }
        return level[0]
    }

    // MARK: - Proof generation

    /// Generate an inclusion proof for a specific leaf.
    /// - Parameters:
    ///   - leafIndex: Index of the leaf in the original array.
    ///   - leaves: All leaf hashes.
    /// - Returns: Array of proof nodes from leaf to root.
    public static func proof(for leafIndex: Int, leaves: [Data]) -> [MerkleProofNode] {
        guard !leaves.isEmpty, leafIndex >= 0, leafIndex < leaves.count else {
            return []
        }
        var level = leaves
        if level.count % 2 != 0 {
            level.append(level.last!)
        }
        var idx = leafIndex
        var proofNodes: [MerkleProofNode] = []

        while level.count > 1 {
            let siblingIdx = idx % 2 == 0 ? idx + 1 : idx - 1
            let isLeft = idx % 2 != 0  // sibling is on the left if current is odd
            proofNodes.append(MerkleProofNode(hash: level[siblingIdx], isLeft: isLeft))

            // Compute next level
            var nextLevel: [Data] = []
            for i in stride(from: 0, to: level.count, by: 2) {
                let combined = level[i] + level[i + 1]
                nextLevel.append(Data(SHA256.hash(data: combined)))
            }
            level = nextLevel
            if level.count > 1 && level.count % 2 != 0 {
                level.append(level.last!)
            }
            idx = idx / 2
        }
        return proofNodes
    }

    // MARK: - Verification

    /// Verify a leaf against a root using its inclusion proof.
    public static func verify(leaf: Data, proof: [MerkleProofNode], root: Data) -> Bool {
        var current = leaf
        for node in proof {
            let combined: Data
            if node.isLeft {
                combined = node.hash + current
            } else {
                combined = current + node.hash
            }
            current = Data(SHA256.hash(data: combined))
        }
        return current == root
    }

    // MARK: - Leaf hash helper

    /// Compute the SHA-256 hash of arbitrary data for use as a leaf.
    public static func leafHash(_ data: Data) -> Data {
        Data(SHA256.hash(data: data))
    }
}
